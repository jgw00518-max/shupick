"""Account restoration must preserve existing business profiles and permissions."""

from contextlib import contextmanager
from datetime import date
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException

import app.auth as auth_module
from app.auth import FirebaseIdentity, sync_customer_profile
from app.schemas import CustomerProfileSyncRequest


def profile(**changes):
    return {
        "customer_id": 42,
        "firebase_uid": "test-uid",
        "email": "shupicktest01@example.com",
        "customer_name": "Saved name",
        "phone": "010-1234-5678",
        "birth_date": date(1995, 1, 2),
        "deleted_at": None,
        **changes,
    }


def database(monkeypatch, rows):
    cursor = MagicMock()
    cursor.__enter__.return_value = cursor
    cursor.fetchone.side_effect = rows
    cursor.lastrowid = 42
    connection = MagicMock()
    connection.cursor.return_value = cursor

    @contextmanager
    def connect():
        yield connection

    monkeypatch.setattr(auth_module, "mysql_connection", connect)
    return cursor, connection


def identity(verified=True):
    return FirebaseIdentity("test-uid", "shupicktest01@example.com", verified)


def test_ensure_existing_profile_keeps_name_phone_birth_date(monkeypatch):
    cursor, connection = database(monkeypatch, [profile(), profile()])
    result = sync_customer_profile(
        CustomerProfileSyncRequest(customerName="Email-derived name", ensureOnly=True),
        identity(),
    )
    assert result.customerId == 42
    assert result.customerName == "Saved name"
    assert result.phone == "010-1234-5678"
    assert result.birthDate == "1995-01-02"
    assert all(call.args[0].strip().startswith("SELECT") for call in cursor.execute.call_args_list)
    connection.commit.assert_called_once()


def test_ensure_links_verified_legacy_profile_without_overwriting_details(monkeypatch):
    cursor, _ = database(monkeypatch, [None, profile(firebase_uid="legacy-customer-42"), profile()])
    sync_customer_profile(
        CustomerProfileSyncRequest(customerName="Email-derived name", ensureOnly=True),
        identity(),
    )
    updates = [call for call in cursor.execute.call_args_list if call.args[0].strip().startswith("UPDATE")]
    assert len(updates) == 1
    assert updates[0].args[1] == ("test-uid", "Saved name", "010-1234-5678", date(1995, 1, 2), 42)


def test_ensure_new_customer_creates_zero_balance_wallet(monkeypatch):
    cursor, connection = database(monkeypatch, [None, None, profile()])
    sync_customer_profile(
        CustomerProfileSyncRequest(customerName="Test user", ensureOnly=True), identity(),
    )
    inserts = [call for call in cursor.execute.call_args_list if call.args[0].strip().startswith("INSERT")]
    assert len(inserts) == 2
    assert "customers" in inserts[0].args[0]
    assert "point_wallets" in inserts[1].args[0]
    assert inserts[1].args[1] == (42,)
    connection.commit.assert_called_once()


@pytest.mark.parametrize("row,verified", [
    (profile(firebase_uid="legacy-customer-42"), False),
    (profile(firebase_uid="another-firebase-uid"), True),
    (profile(firebase_uid="legacy-customer-42", deleted_at="2026-01-01"), True),
])
def test_ensure_cannot_take_over_or_restore_another_profile(monkeypatch, row, verified):
    cursor, connection = database(monkeypatch, [None, row])
    with pytest.raises(HTTPException) as error:
        sync_customer_profile(
            CustomerProfileSyncRequest(customerName="Test user", ensureOnly=True), identity(verified),
        )
    assert error.value.status_code == 409
    assert not any(call.args[0].strip().startswith(("UPDATE", "INSERT")) for call in cursor.execute.call_args_list)
    connection.commit.assert_not_called()
    connection.rollback.assert_called_once()


def test_ensure_does_not_restore_deleted_uid_profile(monkeypatch):
    cursor, connection = database(monkeypatch, [profile(deleted_at="2026-01-01")])
    with pytest.raises(HTTPException) as error:
        sync_customer_profile(
            CustomerProfileSyncRequest(customerName="Test user", ensureOnly=True), identity(),
        )
    assert error.value.status_code == 409
    assert cursor.execute.call_count == 1
    connection.commit.assert_not_called()


def test_explicit_profile_update_still_updates_requested_fields(monkeypatch):
    cursor, _ = database(monkeypatch, [profile(), profile(customer_name="New name", phone=None, birth_date=None)])
    result = sync_customer_profile(CustomerProfileSyncRequest(customerName="New name"), identity())
    assert result.customerName == "New name"
    assert any(call.args[0].strip().startswith("UPDATE") for call in cursor.execute.call_args_list)
