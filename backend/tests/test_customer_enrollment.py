from contextlib import contextmanager
from datetime import date, timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from pydantic import SecretStr, ValidationError
from pymysql import MySQLError

import app.customer_enrollment as enrollment
from app.auth import CurrentCustomer


CURRENT = CurrentCustomer(42, "primary-shopper-uid", "synthetic@example.com")


def database(monkeypatch, rows=()):
    cursor = MagicMock()
    cursor.__enter__.return_value = cursor
    cursor.fetchone.side_effect = rows
    connection = MagicMock()
    connection.cursor.return_value = cursor

    @contextmanager
    def connect():
        yield connection

    monkeypatch.setattr(enrollment, "mysql_connection", connect)
    return cursor, connection


def token_backend(monkeypatch, **changes):
    claims = {"uid": "auxiliary-phone-uid", "phone_number": "+821012345678",
              "auth_time": 1000, "firebase": {"sign_in_provider": "phone"}, **changes}
    monkeypatch.setattr(enrollment.time, "time", lambda: 1000)
    monkeypatch.setattr(enrollment, "get_firebase_app", lambda: "configured-project")
    verify = MagicMock(return_value=claims)
    user = MagicMock(return_value=SimpleNamespace(disabled=False, phone_number="+821012345678"))
    monkeypatch.setattr(enrollment.auth, "verify_id_token", verify)
    monkeypatch.setattr(enrollment.auth, "get_user", user)
    return verify, user


def test_phone_proof_requires_project_signature_revocation_and_freshness(monkeypatch):
    verify, _ = token_backend(monkeypatch)
    proof = enrollment.verify_phone_token(SecretStr("synthetic-secret"))
    assert proof.uid == "auxiliary-phone-uid"
    assert proof.phone == "+821012345678"
    verify.assert_called_once_with("synthetic-secret", app="configured-project", check_revoked=True, clock_skew_seconds=30)
    assert "12345678" not in repr(proof)


@pytest.mark.parametrize("changes", [
    {"auth_time": 699}, {"auth_time": 1031}, {"auth_time": True},
    {"auth_time": "1000"}, {"auth_time": float("nan")},
    {"phone_number": None}, {"phone_number": "01012345678"},
    {"phone_number": "+15555555555"}, {"uid": ""},
    {"firebase": {"sign_in_provider": "password"}}, {"firebase": None},
])
def test_invalid_phone_claims_rejected(monkeypatch, changes):
    token_backend(monkeypatch, **changes)
    with pytest.raises(HTTPException) as error:
        enrollment.verify_phone_token(SecretStr("synthetic-secret"))
    assert error.value.status_code == 401
    assert "synthetic-secret" not in error.value.detail


@pytest.mark.parametrize("disabled,phone", [(True, "+821012345678"), (False, "+821087654321")])
def test_phone_changed_or_disabled_rejected(monkeypatch, disabled, phone):
    _, user = token_backend(monkeypatch)
    user.return_value = SimpleNamespace(disabled=disabled, phone_number=phone)
    with pytest.raises(HTTPException):
        enrollment.verify_phone_token(SecretStr("synthetic-secret"))


def test_revoked_or_wrong_project_token_is_not_exposed(monkeypatch, caplog):
    verify, _ = token_backend(monkeypatch)
    verify.side_effect = ValueError("wrong project: synthetic-secret")
    with pytest.raises(HTTPException) as error:
        enrollment.verify_phone_token(SecretStr("synthetic-secret"))
    assert error.value.status_code == 401
    assert "synthetic-secret" not in caplog.text + error.value.detail


@pytest.mark.parametrize("token", [None, SecretStr(""), SecretStr("x" * 10001)])
def test_missing_or_oversized_proof_rejected(token):
    with pytest.raises(HTTPException) as error:
        enrollment.verify_phone_token(token)
    assert error.value.status_code == 401


@pytest.mark.parametrize("birthday", [date(1899, 12, 31), date.today() + timedelta(days=1)])
def test_birthday_range(birthday):
    with pytest.raises(ValidationError):
        enrollment.EnrollmentRequest(birthDate=birthday)


@pytest.mark.parametrize("payload", [
    enrollment.EnrollmentRequest(phoneToken="synthetic-secret"),
    enrollment.EnrollmentRequest(birthDate=date(2000, 1, 1)),
])
def test_explicit_consents_required(payload):
    with pytest.raises(HTTPException) as error:
        enrollment.validate_consents(payload)
    assert error.value.status_code == 422


def test_new_enrollment_saves_phone_and_optional_birthday_for_primary_uid(monkeypatch):
    token_backend(monkeypatch)
    cursor, connection = database(monkeypatch, [{"customer_id": 42}, None])
    result = enrollment.save_enrollment(enrollment.EnrollmentRequest(phoneToken="synthetic-secret", phoneConsent=True), CURRENT)
    assert result == {"saved": True}
    calls = cursor.execute.call_args_list
    assert calls[0].args[1] == (42, "primary-shopper-uid")
    assert calls[2].args[1] == (42, "+821012345678", "auxiliary-phone-uid", False)
    assert calls[3].args[1] == (None, 42)
    assert "firebase_uid=" not in calls[3].args[0]
    assert "customers.phone" not in " ".join(call.args[0] for call in calls)
    connection.commit.assert_called_once()
    connection.rollback.assert_not_called()


def test_existing_verified_number_preserved_on_birthday_update(monkeypatch):
    cursor, connection = database(monkeypatch, [{"customer_id": 42}, {"verified_phone": "+821012345678"}])
    birthday = date(2000, 1, 2)
    enrollment.save_enrollment(enrollment.EnrollmentRequest(birthDate=birthday, birthdayConsent=True), CURRENT)
    calls = cursor.execute.call_args_list
    assert not any("INSERT" in call.args[0] for call in calls)
    assert calls[-1].args[1] == (birthday, 42)
    assert "verified_phone=" not in calls[-2].args[0]
    connection.commit.assert_called_once()


def test_unverified_contact_phone_does_not_count_as_enrollment(monkeypatch):
    _, connection = database(monkeypatch, [{"customer_id": 42}, None])
    with pytest.raises(HTTPException) as error:
        enrollment.save_enrollment(enrollment.EnrollmentRequest(), CURRENT)
    assert error.value.status_code == 422
    connection.rollback.assert_called_once()
    connection.commit.assert_not_called()


def test_missing_primary_customer_cannot_be_overwritten(monkeypatch):
    token_backend(monkeypatch)
    cursor, connection = database(monkeypatch, [None])
    with pytest.raises(HTTPException) as error:
        enrollment.save_enrollment(enrollment.EnrollmentRequest(phoneToken="synthetic-secret", phoneConsent=True), CURRENT)
    assert error.value.status_code == 404
    assert cursor.execute.call_count == 1
    connection.commit.assert_not_called()


def test_storage_failure_rolls_back_phone_and_birthday_together(monkeypatch):
    token_backend(monkeypatch)
    cursor, connection = database(monkeypatch, [{"customer_id": 42}, None])
    cursor.execute.side_effect = [None, None, None, MySQLError("synthetic private data")]
    with pytest.raises(HTTPException) as error:
        enrollment.save_enrollment(enrollment.EnrollmentRequest(phoneToken="synthetic-secret", phoneConsent=True), CURRENT)
    assert error.value.status_code == 503
    assert "private" not in error.value.detail
    connection.rollback.assert_called_once()
    connection.commit.assert_not_called()


def test_get_only_returns_masked_number_with_primary_uid_scope(monkeypatch):
    cursor, _ = database(monkeypatch, [{"birth_date": date(2000, 1, 2), "verified_phone": "+821012345678"}])
    result = enrollment.get_enrollment(CURRENT)
    assert result == {"phoneVerified": True, "maskedPhone": "010-****-5678", "birthDate": "2000-01-02"}
    assert cursor.execute.call_args.args[1] == (42, "primary-shopper-uid")


def client(authenticated=False):
    app = FastAPI()
    app.include_router(enrollment.router)
    if authenticated:
        app.dependency_overrides[enrollment.get_current_customer] = lambda: CURRENT
    return TestClient(app)


def test_unauthenticated_storage_endpoint_rejects_guest():
    assert client().post("/auth/customer/enrollment", json={}).status_code == 401


@pytest.mark.parametrize("extra", [{"customerId": 99}, {"firebase_uid": "another-user"}, {"birthDate": "invalid"}, {"phoneToken": {"nested": "synthetic-secret"}}])
def test_invalid_body_never_echoes_token_or_accepts_another_customer(extra):
    response = client(True).post("/auth/customer/enrollment", json={"phoneToken": "synthetic-secret", **extra})
    assert response.status_code == 422
    assert "synthetic-secret" not in response.text


def test_signup_preflight_verifies_proof_and_checks_schema_without_writing(monkeypatch):
    token_backend(monkeypatch)
    cursor, connection = database(monkeypatch)
    assert enrollment.validate_phone_before_signup(enrollment.EnrollmentRequest(phoneToken="synthetic-secret", phoneConsent=True)) == {"verified": True}
    assert "LIMIT 0" in cursor.execute.call_args.args[0]
    connection.commit.assert_not_called()
