import pytest
from fastapi import HTTPException

from app.auth import verify_firebase_identity


def test_firebase_identity_requires_bearer_token() -> None:
    with pytest.raises(HTTPException) as error:
        verify_firebase_identity(None)

    assert error.value.status_code == 401
    assert error.value.detail == "Firebase ID token is required"
