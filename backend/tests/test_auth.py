import pytest
from fastapi import HTTPException

from app.auth import verify_firebase_identity
from fastapi.security import HTTPAuthorizationCredentials
import app.auth as auth_module


def test_firebase_identity_requires_bearer_token() -> None:
    with pytest.raises(HTTPException) as error:
        verify_firebase_identity(None)

    assert error.value.status_code == 401
    assert error.value.detail == "Firebase ID token is required"


@pytest.mark.parametrize("message,reason", [
    ('Token used too early; secret-token', 'token_issued_in_future'),
    ('Firebase ID token has incorrect "aud"; secret-token', 'project_mismatch'),
    ('Could not verify signature; secret-token', 'invalid_signature'),
    ('Unknown failure; secret-token', 'invalid_token'),
])
def test_verification_diagnostic_does_not_log_token_or_exception_text(monkeypatch, caplog, message, reason):
    monkeypatch.setattr(auth_module, 'get_firebase_app', lambda: None)

    def reject(*args, **kwargs):
        assert kwargs['check_revoked'] is True
        assert kwargs['clock_skew_seconds'] == 30
        raise ValueError(message)

    monkeypatch.setattr(auth_module.auth, 'verify_id_token', reject)
    with pytest.raises(HTTPException) as error:
        verify_firebase_identity(HTTPAuthorizationCredentials(scheme='Bearer', credentials='secret-token'))
    assert error.value.status_code == 401
    assert f'reason={reason}' in caplog.text
    assert 'secret-token' not in caplog.text
    assert message not in caplog.text


def test_large_clock_mismatch_logs_only_numeric_offset(monkeypatch, caplog):
    monkeypatch.setattr(auth_module, 'get_firebase_app', lambda: None)

    def reject(*args, **kwargs):
        raise ValueError('Token used too early, 1000 < 1090. secret-token')

    monkeypatch.setattr(auth_module.auth, 'verify_id_token', reject)
    with pytest.raises(HTTPException) as error:
        verify_firebase_identity(HTTPAuthorizationCredentials(scheme='Bearer', credentials='secret-token'))
    assert error.value.status_code == 401
    assert 'token_ahead_seconds=90 allowed_seconds=30' in caplog.text
    assert 'secret-token' not in caplog.text
