"""Social authentication regression tests; all provider/Firebase/DB I/O is mocked."""

import base64
from contextlib import contextmanager
from concurrent.futures import ThreadPoolExecutor
import hashlib
import logging
import time
from types import SimpleNamespace
from unittest.mock import MagicMock
from urllib.parse import parse_qs, urlsplit

from cryptography.hazmat.primitives.asymmetric import rsa
import jwt
import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

import app.social_auth as social

_REAL_PROVIDER_JSON = social._provider_json


@pytest.fixture(autouse=True)
def no_external_accounts_or_database(monkeypatch):
    def forbidden(*args, **kwargs):
        pytest.fail("A test attempted unmocked provider, Firebase, or MySQL I/O")

    monkeypatch.setattr(social, "get_firebase_app", lambda: "mock-firebase-app")
    monkeypatch.setattr(social, "mysql_connection", forbidden)
    monkeypatch.setattr(social, "_provider_json", forbidden)
    monkeypatch.setattr(social._naver_keys, "get_signing_key_from_jwt", forbidden)
    monkeypatch.setattr(social.requests, "get", forbidden)
    monkeypatch.setattr(social.requests, "post", forbidden)
    for method in ("get_user", "get_user_by_email", "create_user", "update_user", "create_custom_token"):
        monkeypatch.setattr(social.auth, method, forbidden)
    with social._flows_lock:
        social._flows.clear()
    yield
    with social._flows_lock:
        social._flows.clear()


@pytest.fixture
def configured(monkeypatch):
    # Entirely synthetic values: pytest can display fixture reprs on failure.
    # Never copy .env-backed settings (including database passwords) into tests.
    value = SimpleNamespace(
        firebase_project_id="mock-firebase-project",
        firebase_credentials_path="mock-not-a-real-credentials-file.json",
        kakao_app_id=1234,
        naver_client_id="mock-naver-client",
        naver_client_secret="mock-server-only-secret",
        naver_redirect_uri="https://server.example/auth/social/naver/callback",
    )
    monkeypatch.setattr(social, "settings", value)
    return value


def pkce_challenge(verifier: str) -> str:
    return base64.urlsafe_b64encode(hashlib.sha256(verifier.encode("ascii")).digest()).decode("ascii").rstrip("=")


def customer(**changes):
    return {
        "customer_id": 42,
        "firebase_uid": "provider:test-subject",
        "email": None,
        "customer_name": "Saved customer name",
        "phone": "010-1234-5678",
        "birth_date": None,
        "deleted_at": None,
        **changes,
    }


def mocked_database(monkeypatch, rows):
    cursor = MagicMock()
    cursor.__enter__.return_value = cursor
    cursor.fetchone.side_effect = rows
    cursor.lastrowid = 42
    connection = MagicMock()
    connection.cursor.return_value = cursor

    @contextmanager
    def connect():
        yield connection

    monkeypatch.setattr(social, "mysql_connection", connect)
    return cursor, connection


@pytest.fixture
def client():
    app = FastAPI()
    app.include_router(social.router)
    with TestClient(app, raise_server_exceptions=True) as result:
        yield result


def test_existing_provider_firebase_user_is_resolved_only_by_uid(monkeypatch):
    identity = social.ProviderIdentity("kakao:scoped-subject", "Provider name", "same@example.com", True)
    get_user = MagicMock(return_value=SimpleNamespace(disabled=False))
    create_user = MagicMock()
    monkeypatch.setattr(social.auth, "get_user", get_user)
    monkeypatch.setattr(social.auth, "create_user", create_user)

    social._provision_firebase_user(identity)

    assert get_user.call_args.args == (identity.uid,)
    assert get_user.call_args.kwargs["app"] == "mock-firebase-app"
    create_user.assert_not_called()


def test_new_provider_firebase_user_never_uses_email_to_merge_accounts(monkeypatch):
    identity = social.ProviderIdentity("naver:scoped-subject", "Provider name", "same@example.com", False)
    get_user = MagicMock(side_effect=social.auth.UserNotFoundError("Mock missing UID"))
    create_user = MagicMock(return_value=SimpleNamespace(disabled=False))
    monkeypatch.setattr(social.auth, "get_user", get_user)
    monkeypatch.setattr(social.auth, "create_user", create_user)

    social._provision_firebase_user(identity)

    assert get_user.call_args.args == (identity.uid,)
    assert create_user.call_args.kwargs["uid"] == identity.uid
    assert not create_user.call_args.kwargs.get("email_verified", False)


def nickname_identity(**changes):
    return social.ProviderIdentity(**{
        "uid": "naver:scoped-subject",
        "display_name": "Fetched Naver nickname",
        "email": "signed-contact@example.com",
        "refresh_default_display_name": True,
        **changes,
    })


def nickname_firebase(monkeypatch, *, saved_name="네이버 회원", disabled=False):
    user = SimpleNamespace(disabled=disabled, display_name=saved_name)
    get_user = MagicMock(return_value=user)
    update_user = MagicMock(return_value=user)
    mint = MagicMock(return_value=b"mock-firebase-custom-token")
    monkeypatch.setattr(social.auth, "get_user", get_user)
    monkeypatch.setattr(social.auth, "update_user", update_user)
    monkeypatch.setattr(social.auth, "create_custom_token", mint)
    return get_user, update_user, mint


def test_naver_new_nickname_creates_same_uid_firebase_customer_and_wallet(monkeypatch):
    identity = nickname_identity()
    get_user = MagicMock(side_effect=social.auth.UserNotFoundError("Mock missing UID"))
    create_user = MagicMock(return_value=SimpleNamespace(disabled=False, display_name=identity.display_name))
    update_user = MagicMock()
    mint = MagicMock(return_value=b"mock-firebase-custom-token")
    monkeypatch.setattr(social.auth, "get_user", get_user)
    monkeypatch.setattr(social.auth, "create_user", create_user)
    monkeypatch.setattr(social.auth, "update_user", update_user)
    monkeypatch.setattr(social.auth, "create_custom_token", mint)
    cursor, connection = mocked_database(monkeypatch, [None, None])

    assert social._custom_token(identity) == {"customToken": "mock-firebase-custom-token"}

    create_user.assert_called_once_with(
        uid=identity.uid, display_name=identity.display_name, app="mock-firebase-app",
    )
    update_user.assert_not_called()
    inserts = [item for item in cursor.execute.call_args_list if item.args[0].strip().startswith("INSERT")]
    assert len(inserts) == 2
    assert inserts[0].args[1] == (identity.uid, identity.email, identity.display_name)
    assert inserts[1].args[1] == (42,)
    connection.commit.assert_called_once()
    assert mint.call_args.args == (identity.uid,)


def test_naver_default_names_upgrade_only_after_customer_commit_and_before_token(monkeypatch):
    identity = nickname_identity()
    _, update_user, mint = nickname_firebase(monkeypatch)
    cursor, connection = mocked_database(monkeypatch, [customer(firebase_uid=identity.uid, customer_name="네이버 회원")])

    def update(uid, **kwargs):
        connection.commit.assert_called_once()
        mint.assert_not_called()
        assert uid == identity.uid
        assert kwargs == {"display_name": identity.display_name, "app": "mock-firebase-app"}
        return SimpleNamespace(disabled=False, display_name=identity.display_name)

    update_user.side_effect = update
    assert social._custom_token(identity) == {"customToken": "mock-firebase-custom-token"}

    update_user.assert_called_once_with(identity.uid, display_name=identity.display_name, app="mock-firebase-app")
    updates = [item for item in cursor.execute.call_args_list if item.args[0].strip().startswith("UPDATE")]
    assert len(updates) == 1
    statement, parameters = updates[0].args
    assert statement.split("WHERE", 1)[0].strip() == "UPDATE customers SET customer_name=%s"
    assert "firebase_uid=%s" in statement and "deleted_at IS NULL" in statement
    assert parameters == (identity.display_name, 42, identity.uid)
    assert all("INSERT" not in item.args[0] for item in cursor.execute.call_args_list)
    connection.rollback.assert_not_called()
    assert mint.call_args.args == (identity.uid,)


@pytest.mark.parametrize("uid,saved_name,new_name,refresh", [
    ("naver:scoped-subject", "User chosen nickname", "Fetched nickname", True),
    ("naver:scoped-subject", "네이버 회원 ", "Fetched nickname", True),
    ("naver:scoped-subject", " 네이버 회원", "Fetched nickname", True),
    ("naver:scoped-subject", "", "Fetched nickname", True),
    ("naver:scoped-subject", None, "Fetched nickname", True),
    ("naver:scoped-subject", "네이버 회원", "Signed-only name", False),
    ("naver:scoped-subject", "네이버 회원", "네이버 회원", True),
    ("kakao:scoped-subject", "네이버 회원", "Fetched nickname", True),
    ("provider:scoped-subject", "네이버 회원", "Fetched nickname", True),
    ("naver-other:scoped-subject", "네이버 회원", "Fetched nickname", True),
])
def test_nickname_upgrade_preserves_custom_names_other_providers_and_unflagged_identity(
    monkeypatch, uid, saved_name, new_name, refresh,
):
    identity = nickname_identity(uid=uid, display_name=new_name, refresh_default_display_name=refresh)
    _, update_user, mint = nickname_firebase(monkeypatch, saved_name=saved_name)
    cursor, connection = mocked_database(monkeypatch, [customer(firebase_uid=uid, customer_name=saved_name)])

    assert social._custom_token(identity) == {"customToken": "mock-firebase-custom-token"}

    update_user.assert_not_called()
    assert all(item.args[0].strip().startswith("SELECT") for item in cursor.execute.call_args_list)
    connection.commit.assert_called_once()
    assert mint.call_args.args == (uid,)


@pytest.mark.parametrize("firebase_name,mysql_name", [
    ("User's Firebase nickname", "네이버 회원"),
    ("네이버 회원", "User's customer nickname"),
])
def test_naver_default_upgrade_preserves_each_custom_name_independently(monkeypatch, firebase_name, mysql_name):
    identity = nickname_identity()
    _, update_user, _ = nickname_firebase(monkeypatch, saved_name=firebase_name)
    cursor, _ = mocked_database(monkeypatch, [customer(firebase_uid=identity.uid, customer_name=mysql_name)])

    social._custom_token(identity)

    assert update_user.call_count == int(firebase_name == "네이버 회원")
    updates = [item for item in cursor.execute.call_args_list if item.args[0].strip().startswith("UPDATE")]
    assert len(updates) == int(mysql_name == "네이버 회원")


@pytest.mark.parametrize("failure,expected", [("deleted", 409), ("database", 503)])
def test_naver_deleted_or_failed_customer_never_updates_firebase_or_mints_token(monkeypatch, failure, expected):
    identity = nickname_identity()
    _, update_user, mint = nickname_firebase(monkeypatch)
    cursor, connection = mocked_database(monkeypatch, [customer(
        firebase_uid=identity.uid, customer_name="네이버 회원", deleted_at="2026-01-01" if failure == "deleted" else None,
    )])
    if failure == "database":
        cursor.execute.side_effect = social.MySQLError("mock-private-provider-token")

    with pytest.raises(HTTPException) as error:
        social._custom_token(identity)

    assert error.value.status_code == expected
    assert "mock-private-provider-token" not in str(error.value.detail)
    update_user.assert_not_called()
    mint.assert_not_called()
    connection.commit.assert_not_called()
    connection.rollback.assert_called_once()
    assert all(not item.args[0].strip().startswith("UPDATE") for item in cursor.execute.call_args_list)


def test_naver_disabled_firebase_user_never_reaches_customer_or_name_updates(monkeypatch):
    _, update_user, mint = nickname_firebase(monkeypatch, disabled=True)
    with pytest.raises(HTTPException) as error:
        social._custom_token(nickname_identity())
    assert error.value.status_code == 403
    update_user.assert_not_called()
    mint.assert_not_called()


def test_naver_firebase_name_update_failure_is_sanitized_and_prevents_token_mint(monkeypatch, caplog):
    identity = nickname_identity()
    _, update_user, mint = nickname_firebase(monkeypatch)
    _, connection = mocked_database(monkeypatch, [customer(firebase_uid=identity.uid, customer_name="네이버 회원")])
    update_user.side_effect = ValueError("mock-private-provider-token")

    with pytest.raises(HTTPException) as error:
        social._custom_token(identity)

    assert error.value.status_code == 503
    assert "mock-private-provider-token" not in str(error.value.detail)
    assert "mock-private-provider-token" not in caplog.text
    connection.commit.assert_called_once()
    mint.assert_not_called()


def test_disabled_provider_firebase_user_is_rejected(monkeypatch):
    identity = social.ProviderIdentity("kakao:scoped-subject", "Provider name")
    monkeypatch.setattr(social.auth, "get_user", MagicMock(return_value=SimpleNamespace(disabled=True)))

    with pytest.raises(HTTPException) as error:
        social._provision_firebase_user(identity)

    assert error.value.status_code == 403


def test_existing_social_customer_is_read_only_and_queried_by_uid(monkeypatch):
    identity = social.ProviderIdentity("kakao:scoped-subject", "Replacement provider name", "same@example.com", True)
    cursor, connection = mocked_database(monkeypatch, [customer(firebase_uid=identity.uid)])

    social._provision_customer(identity)

    assert all(call.args[0].strip().startswith("SELECT") for call in cursor.execute.call_args_list)
    assert all("firebase_uid=%s" in call.args[0] for call in cursor.execute.call_args_list)
    assert cursor.execute.call_args_list[0].args[1] == (identity.uid,)
    connection.rollback.assert_not_called()


def test_new_email_less_social_customer_creates_zero_balance_wallet(monkeypatch):
    identity = social.ProviderIdentity("naver:scoped-subject", "Naver user")
    cursor, connection = mocked_database(monkeypatch, [None])

    social._provision_customer(identity)

    inserts = [call for call in cursor.execute.call_args_list if call.args[0].strip().startswith("INSERT")]
    assert len(inserts) == 2
    assert "customers" in inserts[0].args[0]
    assert identity.uid in inserts[0].args[1]
    assert None in inserts[0].args[1]
    assert "point_wallets" in inserts[1].args[0]
    assert inserts[1].args[1] == (42,)
    assert "0" in inserts[1].args[0]
    assert not any("WHERE email=" in call.args[0] for call in cursor.execute.call_args_list)
    connection.commit.assert_called_once()


def test_deleted_social_customer_cannot_be_restored(monkeypatch):
    identity = social.ProviderIdentity("kakao:scoped-subject", "Provider name")
    cursor, connection = mocked_database(monkeypatch, [customer(firebase_uid=identity.uid, deleted_at="2026-01-01")])

    with pytest.raises(HTTPException) as error:
        social._provision_customer(identity)

    assert error.value.status_code == 409
    assert cursor.execute.call_count == 1
    connection.commit.assert_not_called()
    connection.rollback.assert_called_once()


def test_social_email_collision_creates_separate_uid_without_taking_over_existing_customer(monkeypatch):
    identity = social.ProviderIdentity("kakao:scoped-subject", "New provider user", "same@example.com", True)
    cursor, connection = mocked_database(monkeypatch, [None, {"customer_id": 99}])

    customer_id = social._provision_customer(identity)

    assert customer_id == 42
    inserts = [call for call in cursor.execute.call_args_list if call.args[0].strip().startswith("INSERT")]
    assert inserts[0].args[1] == (identity.uid, None, identity.display_name)
    assert not any(call.args[0].strip().startswith("UPDATE") for call in cursor.execute.call_args_list)
    assert inserts[1].args[1] == (42,)
    connection.commit.assert_called_once()


def test_concurrent_social_customer_duplicate_uid_retries_lookup_without_second_wallet(monkeypatch):
    identity = social.ProviderIdentity("kakao:scoped-subject", "Provider user", "contact@example.com", True)
    cursor, connection = mocked_database(monkeypatch, [None, None, customer(firebase_uid=identity.uid)])
    cursor.execute.side_effect = [None, None, social.IntegrityError(1062, "Mock unique key collision"), None]

    assert social._provision_customer(identity) == 42

    assert sum("firebase_uid=%s" in call.args[0] for call in cursor.execute.call_args_list) == 2
    assert not any("point_wallets" in call.args[0] for call in cursor.execute.call_args_list)
    connection.rollback.assert_called_once()
    connection.commit.assert_called_once()


def test_social_wallet_failure_rolls_back_customer_before_token_can_be_minted(monkeypatch):
    identity = social.ProviderIdentity("naver:scoped-subject", "Naver user")
    cursor, connection = mocked_database(monkeypatch, [None])
    cursor.execute.side_effect = [None, None, social.MySQLError("Mock wallet failure")]

    with pytest.raises(HTTPException) as error:
        social._provision_customer(identity)

    assert error.value.status_code == 503
    connection.rollback.assert_called_once()
    connection.commit.assert_not_called()


def test_custom_token_mint_happens_only_after_firebase_and_business_profile_success(monkeypatch):
    identity = social.ProviderIdentity("naver:scoped-subject", "Naver user")
    order = []
    monkeypatch.setattr(social, "_provision_firebase_user", lambda value: order.append("firebase"))
    monkeypatch.setattr(social, "_provision_customer", lambda value: order.append("customer"))

    def mint(uid, **kwargs):
        assert uid == identity.uid
        assert order == ["firebase", "customer"]
        assert kwargs["developer_claims"] == {"social_provider": "naver"}
        order.append("token")
        return b"mock-firebase-custom-token"

    monkeypatch.setattr(social.auth, "create_custom_token", mint)
    assert social._custom_token(identity) == {"customToken": "mock-firebase-custom-token"}
    assert order == ["firebase", "customer", "token"]


@pytest.mark.parametrize("stage,status", [("firebase", 403), ("customer", 409)])
def test_failed_provisioning_never_mints_custom_token(monkeypatch, stage, status):
    identity = social.ProviderIdentity("naver:scoped-subject", "Naver user")
    firebase = MagicMock()
    database = MagicMock()
    failure = HTTPException(status, "Mock account rejected")
    (firebase if stage == "firebase" else database).side_effect = failure
    monkeypatch.setattr(social, "_provision_firebase_user", firebase)
    monkeypatch.setattr(social, "_provision_customer", database)

    with pytest.raises(HTTPException) as error:
        social._custom_token(identity)

    assert error.value.status_code == status
    if stage == "firebase":
        database.assert_not_called()


def kakao_responses(monkeypatch, *, app_id=1234, expires_in=3600, token_id=88, profile_id=88):
    calls = []

    def provider(method, url, *, headers=None, data=None):
        calls.append((method, url, headers, data))
        assert method == "GET"
        assert headers["Authorization"] == "Bearer mock-kakao-access-token"
        if url.endswith("/v1/user/access_token_info"):
            return {"id": token_id, "app_id": app_id, "expires_in": expires_in}
        assert url.endswith("/v2/user/me")
        return {
            "id": profile_id,
            "properties": {"nickname": "Kakao user"},
            "kakao_account": {
                "profile": {"nickname": "Kakao user"},
                "email": "same@example.com",
                "is_email_valid": True,
                "is_email_verified": True,
            },
        }

    monkeypatch.setattr(social, "_provider_json", provider)
    return calls


def test_kakao_validated_identity_is_stable_and_provider_app_scoped(monkeypatch, configured):
    calls = kakao_responses(monkeypatch)
    first = social._kakao_identity("mock-kakao-access-token")
    second = social._kakao_identity("mock-kakao-access-token")

    assert first.uid == second.uid
    assert first.uid.startswith("kakao:")
    assert len(first.uid) <= 128
    assert "/" not in first.uid
    assert first.display_name == "Kakao user"
    assert any(url.endswith("/v1/user/access_token_info") for _, url, _, _ in calls)

    configured.kakao_app_id = 4321
    kakao_responses(monkeypatch, app_id=4321)
    other_app = social._kakao_identity("mock-kakao-access-token")
    assert other_app.uid != first.uid


@pytest.mark.parametrize("changes", [
    {"app_id": 9999},
    {"app_id": "1234"},
    {"app_id": True},
    {"expires_in": 0},
    {"expires_in": -1},
    {"expires_in": "3600"},
    {"expires_in": True},
    {"expires_in": None},
    {"token_id": 88, "profile_id": 89},
    {"token_id": True},
    {"token_id": "88"},
    {"token_id": 0},
])
def test_kakao_rejects_wrong_app_expiry_and_subject_mismatch(monkeypatch, configured, changes):
    kakao_responses(monkeypatch, **changes)

    with pytest.raises(HTTPException) as error:
        social._kakao_identity("mock-kakao-access-token")

    assert error.value.status_code == 401
    assert "mock-kakao-access-token" not in str(error.value.detail)


def test_kakao_works_without_email_or_profile_optional_fields(monkeypatch, configured):
    def provider(method, url, **kwargs):
        if url.endswith("/v1/user/access_token_info"):
            return {"id": 88, "app_id": 1234, "expires_in": 60}
        return {"id": 88, "kakao_account": {}}

    monkeypatch.setattr(social, "_provider_json", provider)
    identity = social._kakao_identity("mock-kakao-access-token")
    assert identity.email is None
    assert not identity.email_verified
    assert identity.display_name


@pytest.fixture(scope="module")
def signing_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def oidc_hash(value: str) -> str:
    digest = hashlib.sha256(value.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest[: len(digest) // 2]).decode("ascii").rstrip("=")


def naver_claims(**changes):
    now = int(time.time())
    return {
        "iss": "https://nid.naver.com",
        "aud": "mock-naver-client",
        "sub": "pairwise-naver-subject",
        "iat": now,
        "exp": now + 600,
        "nonce": "mock-oauth-nonce",
        "at_hash": oidc_hash("mock-naver-access-token"),
        "c_hash": oidc_hash("mock-authorization-code"),
        **changes,
    }


def mock_jwks(monkeypatch, key):
    signing = SimpleNamespace(key=key.public_key())
    client = MagicMock()
    client.get_signing_key_from_jwt.return_value = signing
    monkeypatch.setattr(social, "_naver_keys", client)
    return client


def test_naver_oidc_verifies_signature_client_issuer_nonce_and_token_hashes(monkeypatch, configured, signing_key):
    mock_jwks(monkeypatch, signing_key)
    token = jwt.encode(
        naver_claims(), signing_key, algorithm="RS256",
        headers={"kid": "test-key", "jku": "https://untrusted.example/keys"},
    )

    result = social._verify_naver_id_token(
        token, "mock-oauth-nonce", "mock-naver-access-token", "mock-authorization-code",
    )

    assert result["sub"] == "pairwise-naver-subject"
    assert social.NAVER_JWKS_URL == "https://nid.naver.com/oauth2/jwks"


@pytest.mark.parametrize("changes", [
    {"aud": "another-naver-client"},
    {"iss": "https://untrusted.example"},
    {"nonce": "another-transaction"},
    {"exp": 1},
    {"at_hash": oidc_hash("different-access-token")},
    {"c_hash": oidc_hash("different-code")},
])
def test_naver_oidc_rejects_wrong_claims(monkeypatch, configured, signing_key, changes):
    mock_jwks(monkeypatch, signing_key)
    token = jwt.encode(naver_claims(**changes), signing_key, algorithm="RS256", headers={"kid": "test-key"})

    with pytest.raises(HTTPException) as error:
        social._verify_naver_id_token(
            token, "mock-oauth-nonce", "mock-naver-access-token", "mock-authorization-code",
        )

    assert error.value.status_code == 401
    assert token not in str(error.value.detail)


def test_naver_oidc_rejects_bad_signature(monkeypatch, configured, signing_key):
    mock_jwks(monkeypatch, signing_key)
    different_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    token = jwt.encode(naver_claims(), different_key, algorithm="RS256", headers={"kid": "test-key"})

    with pytest.raises(HTTPException) as error:
        social._verify_naver_id_token(
            token, "mock-oauth-nonce", "mock-naver-access-token", "mock-authorization-code",
        )

    assert error.value.status_code == 401


def test_naver_oidc_rejects_non_rs256_algorithm(monkeypatch, configured, signing_key):
    mock_jwks(monkeypatch, signing_key)
    token = jwt.encode(naver_claims(), "mock-unrelated-hmac-key-at-least-thirty-two-chars", algorithm="HS256")

    with pytest.raises(HTTPException) as error:
        social._verify_naver_id_token(
            token, "mock-oauth-nonce", "mock-naver-access-token", "mock-authorization-code",
        )

    assert error.value.status_code == 401


def test_naver_oidc_missing_optional_nonce_accepts_pkce_bound_code_exchange(monkeypatch, configured, signing_key):
    mock_jwks(monkeypatch, signing_key)
    claims = naver_claims()
    del claims["nonce"]
    token = jwt.encode(claims, signing_key, algorithm="RS256", headers={"kid": "test-key"})
    result = social._verify_naver_id_token(
        token, "mock-oauth-nonce", "mock-naver-access-token", "mock-authorization-code",
    )
    assert result["sub"] == "pairwise-naver-subject"


@pytest.mark.parametrize("missing", ["iss", "aud", "sub", "iat", "exp"])
def test_naver_oidc_requires_signed_identity_and_time_claims(monkeypatch, configured, signing_key, missing):
    mock_jwks(monkeypatch, signing_key)
    claims = naver_claims()
    del claims[missing]
    token = jwt.encode(claims, signing_key, algorithm="RS256", headers={"kid": "test-key"})
    with pytest.raises(HTTPException) as error:
        social._verify_naver_id_token(
            token, "mock-oauth-nonce", "mock-naver-access-token", "mock-authorization-code",
        )
    assert error.value.status_code == 401


@pytest.mark.parametrize("changes", [
    {"azp": "another-client"},
    {"aud": ["mock-naver-client", "another-client"]},
    {"nonce": False},
    {"iat": int(time.time()) + 120},
])
def test_naver_oidc_rejects_ambiguous_authorized_party_or_invalid_time_nonce(monkeypatch, configured, signing_key, changes):
    mock_jwks(monkeypatch, signing_key)
    token = jwt.encode(naver_claims(**changes), signing_key, algorithm="RS256", headers={"kid": "test-key"})
    with pytest.raises(HTTPException) as error:
        social._verify_naver_id_token(
            token, "mock-oauth-nonce", "mock-naver-access-token", "mock-authorization-code",
        )
    assert error.value.status_code == 401


def start_flow(client, verifier="a" * 64):
    response = client.post("/auth/social/naver/start", json={"challenge": pkce_challenge(verifier)})
    assert response.status_code == 200
    return response.json()["state"], verifier, response


def make_ready_flow(monkeypatch, client):
    state, verifier, _ = start_flow(client)
    identity = social.ProviderIdentity("naver:scoped-subject", "Naver user")
    resolve = MagicMock(return_value=identity)
    issue = MagicMock(return_value={"customToken": "mock-firebase-custom-token"})
    monkeypatch.setattr(social, "_naver_identity", resolve)
    monkeypatch.setattr(social, "_custom_token", issue)
    callback = client.get(
        "/auth/social/naver/callback", params={"state": state, "code": "mock-authorization-code"},
        follow_redirects=False,
    )
    assert callback.status_code == 302
    return state, verifier, identity, resolve, issue, callback


def test_naver_start_is_short_lived_bounded_pkce_nonce_and_no_secret_response(monkeypatch, configured, client):
    monkeypatch.setattr(social.time, "monotonic", lambda: 1000.0)
    state, verifier, response = start_flow(client)
    flow = social._flows[state]
    query = parse_qs(urlsplit(response.json()["authorizationUrl"]).query)

    assert set(response.json()) == {"state", "authorizationUrl"}
    assert response.headers["cache-control"] == "no-store"
    assert social.FLOW_TTL_SECONDS == 300
    assert social.MAX_PENDING_FLOWS == 128
    assert flow.expires_at == 1300.0
    assert flow.app_challenge == pkce_challenge(verifier)
    assert flow.oauth_verifier != verifier
    assert flow.oauth_verifier not in response.text
    assert configured.naver_client_secret not in response.text
    assert query["state"] == [state]
    assert query["nonce"] == [flow.nonce]
    assert query["client_id"] == [configured.naver_client_id]
    assert query["redirect_uri"] == [configured.naver_redirect_uri]
    assert query["code_challenge_method"] == ["S256"]
    assert query["code_challenge"] == [pkce_challenge(flow.oauth_verifier)]
    assert query["scope"][0].split() == ["openid", "profile"]
    assert query["auth_type"] == ["reauthenticate"]


def test_each_naver_sign_in_requests_fresh_authentication_and_independent_handoff(configured, client):
    first_state, _, first_response = start_flow(client)
    second_state, _, second_response = start_flow(client)
    first_flow = social._flows[first_state]
    second_flow = social._flows[second_state]

    assert first_state != second_state
    assert first_flow.nonce != second_flow.nonce
    assert first_flow.oauth_verifier != second_flow.oauth_verifier
    for state, response in ((first_state, first_response), (second_state, second_response)):
        url = urlsplit(response.json()["authorizationUrl"])
        query = parse_qs(url.query)
        assert f"{url.scheme}://{url.netloc}{url.path}" == social.NAVER_AUTH_URL
        assert query["auth_type"] == ["reauthenticate"]
        assert query["scope"][0].split() == ["openid", "profile"]
        assert query["state"] == [state]
        assert query["nonce"] == [social._flows[state].nonce]
        assert query["code_challenge"] == [pkce_challenge(social._flows[state].oauth_verifier)]
        assert query["code_challenge_method"] == ["S256"]
        assert "prompt" not in query
        assert "login_hint" not in query
        assert "client_secret" not in query
        assert configured.naver_client_secret not in response.text


@pytest.mark.parametrize("field,value,path,payload", [
    ("kakao_app_id", 0, "/auth/social/kakao", {"accessToken": "mock-kakao-access-token"}),
    ("naver_client_id", "", "/auth/social/naver/start", {"challenge": pkce_challenge("a" * 64)}),
    ("naver_client_secret", "", "/auth/social/naver/start", {"challenge": pkce_challenge("a" * 64)}),
    ("naver_redirect_uri", "", "/auth/social/naver/start", {"challenge": pkce_challenge("a" * 64)}),
    ("naver_redirect_uri", "http://public.example/auth/social/naver/callback", "/auth/social/naver/start", {"challenge": pkce_challenge("a" * 64)}),
    ("naver_redirect_uri", "https://user:password@server.example/auth/social/naver/callback", "/auth/social/naver/start", {"challenge": pkce_challenge("a" * 64)}),
    ("naver_redirect_uri", "https://server.example/auth/social/naver/callback?extra=true", "/auth/social/naver/start", {"challenge": pkce_challenge("a" * 64)}),
])
def test_social_unconfigured_or_unsafe_callback_gates_503_no_store(configured, client, field, value, path, payload):
    setattr(configured, field, value)
    response = client.post(path, json=payload)
    assert response.status_code == 503
    assert response.headers["cache-control"] == "no-store"
    assert not social._flows
    assert configured.naver_client_secret not in response.text or not configured.naver_client_secret


def test_naver_registry_capacity_and_expired_cleanup(monkeypatch, configured, client):
    now = [1000.0]
    monkeypatch.setattr(social.time, "monotonic", lambda: now[0])
    for _ in range(128):
        social.start_naver(social.NaverStartRequest(challenge=pkce_challenge("a" * 64)))
    assert len(social._flows) == 128

    blocked = client.post("/auth/social/naver/start", json={"challenge": pkce_challenge("a" * 64)})
    assert blocked.status_code == 429
    assert blocked.headers["cache-control"] == "no-store"
    assert len(social._flows) == 128

    now[0] = 1300.0
    start_flow(client)
    assert len(social._flows) == 1


def test_naver_handoff_url_has_only_state_no_provider_or_firebase_tokens(monkeypatch, configured, client):
    state, verifier, identity, resolve, issue, response = make_ready_flow(monkeypatch, client)
    location = urlsplit(response.headers["location"])
    assert location.scheme == "com.example.shupick.auth"
    assert location.netloc == "naver"
    assert parse_qs(location.query) == {"state": [state]}
    assert response.headers["cache-control"] == "no-store"
    assert "mock-authorization-code" not in response.headers["location"]
    assert "mock-firebase-custom-token" not in response.headers["location"]
    issue.assert_not_called()

    completed = client.post("/auth/social/naver/complete", json={"state": state, "verifier": verifier})
    assert completed.status_code == 200
    assert completed.json() == {"customToken": "mock-firebase-custom-token"}
    assert completed.headers["cache-control"] == "no-store"
    issue.assert_called_once_with(identity)
    resolve.assert_called_once()
    assert state not in social._flows


def test_naver_complete_requires_client_secret_verifier_and_is_one_use(monkeypatch, configured, client):
    state, verifier, _, resolve, issue, _ = make_ready_flow(monkeypatch, client)
    wrong = client.post("/auth/social/naver/complete", json={"state": state, "verifier": "b" * 64})
    assert wrong.status_code == 401
    assert state in social._flows
    issue.assert_not_called()

    replay_callback = client.get(
        "/auth/social/naver/callback", params={"state": state, "code": "mock-authorization-code"},
        follow_redirects=False,
    )
    assert replay_callback.status_code == 400
    assert resolve.call_count == 1

    good = client.post("/auth/social/naver/complete", json={"state": state, "verifier": verifier})
    replay = client.post("/auth/social/naver/complete", json={"state": state, "verifier": verifier})
    assert good.status_code == 200
    assert replay.status_code == 400
    assert issue.call_count == 1


def test_naver_early_complete_does_not_consume_pending_state(configured, client):
    state, verifier, _ = start_flow(client)
    response = client.post("/auth/social/naver/complete", json={"state": state, "verifier": verifier})
    assert response.status_code == 409
    assert social._flows[state].phase == "pending"


@pytest.mark.parametrize("params,expected_error", [
    ({"error": "access_denied"}, "cancelled"),
    ({"error": "cancelled"}, "cancelled"),
    ({"error": "canceled"}, "cancelled"),
    ({"error": "server_error"}, "login_failed"),
    ({"error": "invalid_request"}, "login_failed"),
    ({"error": "login_required"}, "login_failed"),
    ({"error": "private-provider-error"}, "login_failed"),
    ({}, "login_failed"),
])
def test_naver_cancel_and_missing_code_use_generic_handoff_and_consume_completion(configured, client, params, expected_error):
    state, verifier, _ = start_flow(client)
    response = client.get("/auth/social/naver/callback", params={"state": state, **params}, follow_redirects=False)
    assert response.status_code == 302
    query = parse_qs(urlsplit(response.headers["location"]).query)
    assert query == {"state": [state], "error": [expected_error]}
    assert "private-provider-error" not in response.headers["location"]
    assert social._flows[state].phase == "error"

    completed = client.post("/auth/social/naver/complete", json={"state": state, "verifier": verifier})
    assert completed.status_code == 400
    assert state not in social._flows


def test_naver_provider_failure_is_generic_not_leaked_in_url(monkeypatch, configured, client):
    state, verifier, _ = start_flow(client)
    monkeypatch.setattr(social, "_naver_identity", MagicMock(side_effect=HTTPException(401, "private-provider-token-error")))
    response = client.get(
        "/auth/social/naver/callback", params={"state": state, "code": "mock-authorization-code"},
        follow_redirects=False,
    )
    assert response.status_code == 302
    assert parse_qs(urlsplit(response.headers["location"]).query)["error"] == ["login_failed"]
    assert "private-provider-token-error" not in response.headers["location"]
    assert client.post("/auth/social/naver/complete", json={"state": state, "verifier": verifier}).status_code == 400


def test_naver_expired_state_cannot_be_completed_or_callback_reused(monkeypatch, configured, client):
    now = [1000.0]
    monkeypatch.setattr(social.time, "monotonic", lambda: now[0])
    state, verifier, _ = start_flow(client)
    now[0] = 1300.0
    complete = client.post("/auth/social/naver/complete", json={"state": state, "verifier": verifier})
    callback = client.get(
        "/auth/social/naver/callback", params={"state": state, "code": "mock-authorization-code"},
        follow_redirects=False,
    )
    assert complete.status_code == 400
    assert callback.status_code == 400
    assert state not in social._flows


def test_naver_concurrent_completion_issues_exactly_one_custom_token(monkeypatch, configured, client):
    state, verifier, _, _, issue, _ = make_ready_flow(monkeypatch, client)
    request = social.NaverCompleteRequest(state=state, verifier=verifier)

    def finish(_):
        try:
            return 200, social.complete_naver(request)
        except HTTPException as error:
            return error.status_code, None

    with ThreadPoolExecutor(max_workers=4) as executor:
        outcomes = list(executor.map(finish, range(4)))

    assert sorted(status for status, _ in outcomes) == [200, 400, 400, 400]
    issue.assert_called_once()


def test_naver_concurrent_callbacks_exchange_authorization_code_only_once(monkeypatch, configured, client):
    state, _, _ = start_flow(client)
    identity = social.ProviderIdentity("naver:scoped-subject", "Naver user")
    resolve = MagicMock(return_value=identity)
    monkeypatch.setattr(social, "_naver_identity", resolve)

    def callback(_):
        try:
            return social.callback_naver(code="mock-authorization-code", state=state).status_code
        except HTTPException as error:
            return error.status_code

    with ThreadPoolExecutor(max_workers=4) as executor:
        statuses = list(executor.map(callback, range(4)))

    assert sorted(statuses) == [302, 400, 400, 400]
    resolve.assert_called_once()
    assert social._flows[state].phase == "ready"


def test_naver_failed_mint_still_consumes_handoff_before_any_replay(monkeypatch, configured, client):
    state, verifier, _, _, issue, _ = make_ready_flow(monkeypatch, client)
    issue.side_effect = HTTPException(503, "Mock provisioning unavailable")
    first = client.post("/auth/social/naver/complete", json={"state": state, "verifier": verifier})
    replay = client.post("/auth/social/naver/complete", json={"state": state, "verifier": verifier})
    assert first.status_code == 503
    assert replay.status_code == 400
    assert state not in social._flows
    issue.assert_called_once()


def test_naver_expiry_during_exchange_never_creates_ready_handoff(monkeypatch, configured, client):
    now = [1000.0]
    monkeypatch.setattr(social.time, "monotonic", lambda: now[0])
    state, verifier, _ = start_flow(client)

    def resolve(code, flow):
        now[0] = 1300.0
        return social.ProviderIdentity("naver:scoped-subject", "Naver user")

    monkeypatch.setattr(social, "_naver_identity", resolve)
    callback = client.get(
        "/auth/social/naver/callback", params={"state": state, "code": "mock-authorization-code"},
        follow_redirects=False,
    )
    assert callback.status_code == 302
    assert parse_qs(urlsplit(callback.headers["location"]).query) == {"state": [state], "error": ["login_failed"]}
    assert state not in social._flows
    completed = client.post("/auth/social/naver/complete", json={"state": state, "verifier": verifier})
    assert completed.status_code == 400


def test_naver_code_exchange_uses_server_secret_pkce_and_signed_identity_only(monkeypatch, configured, client):
    state, _, _ = start_flow(client)
    flow = social._flows[state]
    calls = []

    def provider(method, url, *, headers=None, data=None):
        calls.append((method, url, headers, data))
        if method == "POST":
            assert url == social.NAVER_TOKEN_URL
            assert data["client_secret"] == configured.naver_client_secret
            assert data["client_id"] == configured.naver_client_id
            assert data["redirect_uri"] == configured.naver_redirect_uri
            assert data["state"] == state
            assert data["code"] == "mock-authorization-code"
            assert data["code_verifier"] == flow.oauth_verifier
            return {"access_token": "mock-naver-access-token", "id_token": "mock-naver-id-token", "token_type": "bearer"}
        assert method == "GET" and url == social.NAVER_USER_URL
        verify.assert_called_once()
        assert headers == {"Authorization": "Bearer mock-naver-access-token"}
        assert data is None
        return {"resultcode": "00", "response": {
            "id": "different-traditional-profile-id",
            "nickname": "  Consented Naver nickname  ",
            "name": "Ignored real name",
            "email": "ignored-profile-email@example.com",
        }}

    monkeypatch.setattr(social, "_provider_json", provider)
    verify = MagicMock(return_value={"sub": "pairwise-naver-subject", "name": "Signed Naver name", "email": "contact@example.com"})
    monkeypatch.setattr(social, "_verify_naver_id_token", verify)
    identity = social._naver_identity("mock-authorization-code", flow)

    verify.assert_called_once_with("mock-naver-id-token", flow.nonce, "mock-naver-access-token", "mock-authorization-code")
    assert identity.uid == social._provider_uid("naver", configured.naver_client_id, "pairwise-naver-subject")
    assert identity.display_name == "Consented Naver nickname"
    assert identity.refresh_default_display_name is True
    assert identity.email == "contact@example.com"
    assert identity.email_verified is False
    assert len(calls) == 2
    assert all("mock-authorization-code" not in url for _, url, _, _ in calls)
    assert all(configured.naver_client_secret not in url for _, url, _, _ in calls)


@pytest.mark.parametrize("token", [
    {"access_token": "mock-naver-access-token", "token_type": "bearer"},
    {"access_token": "mock-naver-access-token", "id_token": "mock-id-token", "token_type": "mac"},
    {"access_token": "bad token with spaces", "id_token": "mock-id-token", "token_type": "bearer"},
])
def test_naver_rejects_access_token_without_oidc_or_bad_type(monkeypatch, configured, client, token):
    state, _, _ = start_flow(client)
    provider = MagicMock(return_value=token)
    monkeypatch.setattr(social, "_provider_json", provider)

    with pytest.raises(HTTPException) as error:
        social._naver_identity("mock-authorization-code", social._flows[state])

    assert error.value.status_code == 401
    assert provider.call_count == 1


def test_naver_without_optional_profile_uses_signed_sub_not_unsigned_token_fields(monkeypatch, configured, client):
    state, _, _ = start_flow(client)
    provider = MagicMock(side_effect=[{
        "access_token": "mock-naver-access-token", "id_token": "mock-id-token", "token_type": "bearer",
        "sub": "unsigned-subject", "name": "Unsigned name", "email": "unsigned@example.com",
    }, {"resultcode": "00", "response": {
        "id": "unsigned-profile-id", "name": "Ignored profile name", "email": "ignored-profile@example.com",
    }}])
    monkeypatch.setattr(social, "_provider_json", provider)
    monkeypatch.setattr(social, "_verify_naver_id_token", MagicMock(return_value={"sub": "expected-provider-subject"}))

    identity = social._naver_identity("mock-authorization-code", social._flows[state])
    assert identity.uid == social._provider_uid("naver", configured.naver_client_id, "expected-provider-subject")
    assert identity.display_name == "네이버 회원"
    assert identity.display_name != "Unsigned name"
    assert identity.refresh_default_display_name is False
    assert identity.email is None
    assert identity.email_verified is False
    assert provider.call_count == 2


@pytest.mark.parametrize("profile", [
    {},
    {"resultcode": "01", "response": {"nickname": "Must not be used"}},
    {"resultcode": 0, "response": {"nickname": "Must not be used"}},
    {"resultcode": "00", "response": None},
    {"resultcode": "00", "response": []},
    {"resultcode": "00", "response": "invalid"},
    {"resultcode": "00", "response": {}},
    {"resultcode": "00", "response": {"nickname": None}},
    {"resultcode": "00", "response": {"nickname": 123}},
    {"resultcode": "00", "response": {"nickname": False}},
    {"resultcode": "00", "response": {"nickname": {"value": "invalid"}}},
    {"resultcode": "00", "response": {"nickname": []}},
    {"resultcode": "00", "response": {"nickname": ""}},
    {"resultcode": "00", "response": {"nickname": " \t\n "}},
    HTTPException(401, "mock-private-provider-token"),
    HTTPException(403, "mock-private-provider-token"),
    HTTPException(502, "mock-private-provider-token"),
])
def test_naver_optional_profile_failure_keeps_signed_name_and_identity(monkeypatch, configured, client, profile, caplog):
    state, _, _ = start_flow(client)
    provider = MagicMock(side_effect=[{
        "access_token": "mock-naver-access-token", "id_token": "mock-id-token", "token_type": "bearer",
    }, profile])
    monkeypatch.setattr(social, "_provider_json", provider)
    monkeypatch.setattr(social, "_verify_naver_id_token", MagicMock(return_value={
        "sub": "signed-subject", "name": "Preserved signed name", "email": "signed@example.com", "email_verified": True,
    }))

    identity = social._naver_identity("mock-authorization-code", social._flows[state])

    assert identity.uid == social._provider_uid("naver", configured.naver_client_id, "signed-subject")
    assert identity.display_name == "Preserved signed name"
    assert identity.email == "signed@example.com" and identity.email_verified is True
    assert identity.refresh_default_display_name is False
    assert provider.call_count == 2
    assert "mock-private-provider-token" not in caplog.text


@pytest.mark.parametrize("nickname,expected", [
    ("  닉네임  ", "닉네임"),
    ("a" * 101, "a" * 100),
    ("네이버 회원", "네이버 회원"),
    ("id***", "id***"),
])
def test_naver_nickname_is_trimmed_bounded_and_not_interpreted_as_identity(monkeypatch, nickname, expected, caplog):
    caplog.set_level(logging.INFO, logger="uvicorn.error")
    provider = MagicMock(return_value={"resultcode": "00", "response": {
        "nickname": nickname, "id": "unrelated-id", "name": "Ignored name", "email": "ignored@example.com",
    }})
    monkeypatch.setattr(social, "_provider_json", provider)

    assert social._naver_nickname("mock-naver-access-token") == expected
    assert "reason=nickname_present" in caplog.text
    assert "mock-naver-access-token" not in caplog.text
    assert "unrelated-id" not in caplog.text
    assert "ignored@example.com" not in caplog.text
    provider.assert_called_once_with(
        "GET", social.NAVER_USER_URL, headers={"Authorization": "Bearer mock-naver-access-token"},
    )


@pytest.mark.parametrize("profile,reason", [
    (HTTPException(401, "mock-private-provider-token"), "profile_rejected"),
    (HTTPException(403, "mock-private-provider-token"), "profile_rejected"),
    (HTTPException(502, "mock-private-provider-token"), "profile_unavailable"),
    ({"resultcode": "01", "response": {"nickname": "Private nickname"}}, "invalid_profile_response"),
    ({"resultcode": "00", "response": []}, "invalid_profile_response"),
    ({"resultcode": "00", "response": {}}, "nickname_missing"),
    ({"resultcode": "00", "response": {"nickname": "  "}}, "nickname_missing"),
])
def test_naver_nickname_logs_only_fixed_failure_reason(monkeypatch, profile, reason, caplog):
    if isinstance(profile, HTTPException):
        provider = MagicMock(side_effect=profile)
    else:
        provider = MagicMock(return_value=profile)
    monkeypatch.setattr(social, "_provider_json", provider)

    assert social._naver_nickname("mock-private-provider-token") is None
    assert f"reason={reason}" in caplog.text
    assert "mock-private-provider-token" not in caplog.text
    assert "Private nickname" not in caplog.text


@pytest.mark.parametrize("failure", ["denied", "outage", "redirect", "timeout", "invalid-json", "non-object-json"])
def test_naver_nickname_real_http_failures_fall_back_without_secret_logs(monkeypatch, failure, caplog):
    monkeypatch.setattr(social, "_provider_json", _REAL_PROVIDER_JSON)
    response = MagicMock(status_code={"denied": 403, "outage": 500, "redirect": 302}.get(failure, 200))
    response.json.return_value = [] if failure == "non-object-json" else {"private": "mock-private-provider-token"}
    if failure == "invalid-json":
        response.json.side_effect = ValueError("mock-private-provider-token")
    request = MagicMock(return_value=response)
    if failure == "timeout":
        request.side_effect = social.requests.Timeout("mock-private-provider-token")
    monkeypatch.setattr(social.requests, "get", request)

    assert social._naver_nickname("mock-naver-access-token") is None

    request.assert_called_once_with(
        social.NAVER_USER_URL, headers={"Authorization": "Bearer mock-naver-access-token"},
        timeout=10, allow_redirects=False,
    )
    assert "mock-private-provider-token" not in caplog.text


@pytest.mark.parametrize("changes", [
    {"aud": "other-client"},
    {"iss": "https://untrusted.example"},
    {"at_hash": oidc_hash("different-access-token")},
])
def test_naver_invalid_signed_identity_is_rejected_before_optional_profile(
    monkeypatch, configured, client, signing_key, changes,
):
    state, _, _ = start_flow(client)
    flow = social._flows[state]
    mock_jwks(monkeypatch, signing_key)
    token = jwt.encode(
        naver_claims(nonce=flow.nonce, **changes), signing_key, algorithm="RS256", headers={"kid": "test-key"},
    )
    provider = MagicMock(return_value={
        "access_token": "mock-naver-access-token", "id_token": token, "token_type": "bearer",
    })
    profile = MagicMock()
    monkeypatch.setattr(social, "_provider_json", provider)
    monkeypatch.setattr(social, "_naver_nickname", profile)

    with pytest.raises(HTTPException) as error:
        social._naver_identity("mock-authorization-code", flow)

    assert error.value.status_code == 401
    provider.assert_called_once()
    profile.assert_not_called()
    assert token not in str(error.value.detail)


def test_naver_profile_denial_still_completes_same_identity_without_private_handoff(monkeypatch, configured, client, caplog):
    state, verifier, _ = start_flow(client)
    provider = MagicMock(side_effect=[{
        "access_token": "mock-naver-access-token", "id_token": "mock-id-token", "token_type": "bearer",
    }, HTTPException(403, "mock-private-provider-token")])
    monkeypatch.setattr(social, "_provider_json", provider)
    monkeypatch.setattr(social, "_verify_naver_id_token", MagicMock(return_value={"sub": "signed-subject"}))
    issue = MagicMock(return_value={"customToken": "mock-firebase-custom-token"})
    monkeypatch.setattr(social, "_custom_token", issue)

    callback = client.get(
        "/auth/social/naver/callback", params={"state": state, "code": "mock-authorization-code"},
        follow_redirects=False,
    )
    assert callback.status_code == 302
    assert parse_qs(urlsplit(callback.headers["location"]).query) == {"state": [state]}
    completed = client.post("/auth/social/naver/complete", json={"state": state, "verifier": verifier})
    assert completed.status_code == 200
    identity = issue.call_args.args[0]
    assert identity.uid == social._provider_uid("naver", configured.naver_client_id, "signed-subject")
    assert identity.display_name == "네이버 회원" and not identity.refresh_default_display_name
    for secret in ("mock-private-provider-token", "mock-naver-access-token", "mock-authorization-code"):
        assert secret not in callback.headers["location"]
        assert secret not in completed.text
        assert secret not in caplog.text


@pytest.mark.parametrize("path,payload,secret", [
    ("/auth/social/kakao", {"accessToken": "secret token with spaces"}, "secret token with spaces"),
    ("/auth/social/kakao", {"accessToken": "비밀-토큰"}, "비밀-토큰"),
    ("/auth/social/kakao", {"accessToken": "mock-token", "uid": "client-chosen-identity"}, "client-chosen-identity"),
    ("/auth/social/naver/start", {"challenge": "invalid-private-challenge"}, "invalid-private-challenge"),
    ("/auth/social/naver/complete", {"state": "a" * 43, "verifier": "a" * 64, "accessToken": "private-naver-token"}, "private-naver-token"),
    ("/auth/social/naver/complete", {"state": "a" * 43, "verifier": "private-short-verifier"}, "private-short-verifier"),
])
def test_social_validation_rejects_client_identity_or_tokens_and_redacts_errors(configured, client, path, payload, secret):
    response = client.post(path, json=payload)
    assert response.status_code == 422
    assert response.json() == {"detail": "Invalid social login request"}
    assert response.headers["cache-control"] == "no-store"
    assert secret not in response.text


@pytest.mark.parametrize("method", ["GET", "POST"])
def test_provider_http_has_bounded_timeout_and_never_follows_redirects(monkeypatch, method):
    monkeypatch.setattr(social, "_provider_json", _REAL_PROVIDER_JSON)
    response = MagicMock(status_code=200)
    response.json.return_value = {"valid": True}
    request = MagicMock(return_value=response)
    monkeypatch.setattr(social.requests, method.lower(), request)

    assert social._provider_json(method, "https://provider.example/fixed", headers={"Authorization": "Bearer mock-token"}, data={"code": "mock-code"}) == {"valid": True}
    assert request.call_args.kwargs["timeout"] == 10
    assert request.call_args.kwargs["allow_redirects"] is False
    assert "mock-token" not in request.call_args.args[0]


@pytest.mark.parametrize("status,expected", [(400, 401), (401, 401), (403, 401), (302, 502), (500, 502)])
def test_provider_http_failures_are_sanitized(monkeypatch, status, expected):
    monkeypatch.setattr(social, "_provider_json", _REAL_PROVIDER_JSON)
    response = MagicMock(status_code=status)
    response.json.return_value = {"private": "provider-token-secret"}
    monkeypatch.setattr(social.requests, "get", MagicMock(return_value=response))
    with pytest.raises(HTTPException) as error:
        social._provider_json("GET", "https://provider.example/fixed")
    assert error.value.status_code == expected
    assert "provider-token-secret" not in str(error.value.detail)


def test_provider_network_error_does_not_expose_private_exception(monkeypatch):
    monkeypatch.setattr(social, "_provider_json", _REAL_PROVIDER_JSON)
    monkeypatch.setattr(social.requests, "get", MagicMock(side_effect=social.requests.Timeout("provider-token-secret")))
    with pytest.raises(HTTPException) as error:
        social._provider_json("GET", "https://provider.example/fixed")
    assert error.value.status_code == 502
    assert "provider-token-secret" not in str(error.value.detail)


@pytest.mark.parametrize("suffix", ["", "/"])
def test_oauth_callback_access_log_drops_all_query_secrets(suffix):
    record = logging.LogRecord(
        "uvicorn.access", logging.INFO, "", 0, '%s - "%s %s HTTP/1.1" %s',
        ("127.0.0.1", "GET", f"/auth/social/naver/callback{suffix}?code=private-code&state=private-state", 302), None,
    )
    social.OAuthCallbackAccessLogFilter().filter(record)
    message = record.getMessage()
    assert "private-code" not in message
    assert "private-state" not in message
    assert "?" not in message
