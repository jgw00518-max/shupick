from contextlib import contextmanager
from datetime import date
from unittest.mock import MagicMock
from app import auth
from app.auth import FirebaseIdentity
from app.schemas import CustomerProfileSyncRequest


def run_sync(monkeypatch, request, existing):
    row = {'customer_id': 7, 'firebase_uid': 'test-uid', 'email': 'test@example.com',
           'customer_name': 'Test', 'phone': '01012345678', 'birth_date': date(2000, 2, 29)}
    cursor = MagicMock()
    cursor.__enter__.return_value = cursor
    cursor.fetchone.side_effect = [row if existing else None] + ([] if existing else [None]) + [row]
    cursor.lastrowid = 7
    connection = MagicMock()
    connection.cursor.return_value = cursor

    @contextmanager
    def database():
        yield connection

    monkeypatch.setattr(auth, 'mysql_connection', database)
    identity = FirebaseIdentity(uid='test-uid', email='test@example.com', email_verified=True)
    auth.sync_customer_profile(request, identity)
    connection.commit.assert_called_once()
    return cursor


def test_signup_saves_phone_and_birth_date(monkeypatch):
    cursor = run_sync(monkeypatch, CustomerProfileSyncRequest(
        customerName='Test', phone='01012345678', birthDate='2000-02-29'), False)
    insertion = next(call for call in cursor.execute.call_args_list
                     if 'INSERT INTO customers' in call.args[0])
    assert insertion.args[1] == ('test-uid', 'test@example.com', 'Test', '01012345678', date(2000, 2, 29))


def test_login_sync_preserves_omitted_phone_and_birth_date(monkeypatch):
    cursor = run_sync(monkeypatch, CustomerProfileSyncRequest(customerName='Test'), True)
    update = next(call for call in cursor.execute.call_args_list if 'UPDATE customers' in call.args[0])
    assert update.args[1][2:4] == ('01012345678', date(2000, 2, 29))
