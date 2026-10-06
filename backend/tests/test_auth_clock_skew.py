"""Exercise bounded clock skew with real SDK signature and claim checks.

All keys, certificates, and tokens in this module are synthetic and ephemeral.
The certificate request is replaced locally; Firebase credentials and network
access are never used.
"""

from datetime import datetime, timedelta, timezone
import json
from types import SimpleNamespace

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from firebase_admin import _token_gen, auth
from google.auth import _helpers, crypt, jwt
import pytest

import app.auth as auth_module


TEST_PROJECT_ID = "synthetic-clock-skew-project"
TEST_KEY_ID = "synthetic-clock-skew-key"
TEST_NOW = datetime(2026, 10, 5, 0, 0, 0, tzinfo=timezone.utc)
TEST_NOW_SECONDS = int(TEST_NOW.timestamp())


@pytest.fixture(scope="module")
def signing_material():
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    wrong_private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Synthetic test certificate")])
    certificate = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(private_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(TEST_NOW - timedelta(days=1))
        .not_valid_after(TEST_NOW + timedelta(days=1))
        .sign(private_key, hashes.SHA256())
    )
    return SimpleNamespace(
        signer=crypt.RSASigner(private_key, key_id=TEST_KEY_ID),
        wrong_signer=crypt.RSASigner(wrong_private_key, key_id=TEST_KEY_ID),
        certificate_pem=certificate.public_bytes(serialization.Encoding.PEM).decode("ascii"),
    )


@pytest.fixture
def sdk_verifier(monkeypatch, signing_material):
    monkeypatch.delenv("FIREBASE_AUTH_EMULATOR_HOST", raising=False)
    monkeypatch.setattr(_helpers, "utcnow", lambda: TEST_NOW.replace(tzinfo=None))
    verifier = _token_gen.TokenVerifier(
        SimpleNamespace(project_id=TEST_PROJECT_ID, options={})
    )

    def fetch_synthetic_certificate(url, method="GET", **kwargs):
        assert url == _token_gen.ID_TOKEN_CERT_URI
        assert method == "GET"
        return SimpleNamespace(
            status=200,
            data=json.dumps({TEST_KEY_ID: signing_material.certificate_pem}).encode("utf-8"),
        )

    verifier.request = fetch_synthetic_certificate
    return verifier


def make_token(signing_material, *, issued_in=0, expires_in=3600, audience=None, wrong_signature=False):
    payload = {
        "iss": f"https://securetoken.google.com/{TEST_PROJECT_ID}",
        "aud": TEST_PROJECT_ID if audience is None else audience,
        "sub": "synthetic-test-user",
        "iat": TEST_NOW_SECONDS + issued_in,
        "exp": TEST_NOW_SECONDS + expires_in,
        "auth_time": TEST_NOW_SECONDS,
    }
    signer = signing_material.wrong_signer if wrong_signature else signing_material.signer
    return jwt.encode(signer, payload)


@pytest.mark.parametrize("issued_in", [5, 30])
def test_sdk_accepts_signed_same_project_token_within_clock_skew(
    sdk_verifier, signing_material, issued_in
):
    decoded = sdk_verifier.verify_id_token(
        make_token(signing_material, issued_in=issued_in),
        clock_skew_seconds=auth_module.FIREBASE_CLOCK_SKEW_SECONDS,
    )
    assert decoded["uid"] == "synthetic-test-user"


@pytest.mark.parametrize("issued_in", [31, 120])
def test_sdk_rejects_signed_token_issued_beyond_clock_skew(
    sdk_verifier, signing_material, issued_in
):
    with pytest.raises(auth.InvalidIdTokenError, match="Token used too early"):
        sdk_verifier.verify_id_token(
            make_token(signing_material, issued_in=issued_in),
            clock_skew_seconds=auth_module.FIREBASE_CLOCK_SKEW_SECONDS,
        )


def test_sdk_accepts_token_at_expiration_clock_skew_boundary(sdk_verifier, signing_material):
    decoded = sdk_verifier.verify_id_token(
        make_token(signing_material, issued_in=-3600, expires_in=-30),
        clock_skew_seconds=auth_module.FIREBASE_CLOCK_SKEW_SECONDS,
    )
    assert decoded["uid"] == "synthetic-test-user"


@pytest.mark.parametrize("expires_in", [-31, -120])
def test_sdk_rejects_token_expired_beyond_clock_skew(
    sdk_verifier, signing_material, expires_in
):
    with pytest.raises(auth.ExpiredIdTokenError, match="Token expired"):
        sdk_verifier.verify_id_token(
            make_token(signing_material, issued_in=-3600, expires_in=expires_in),
            clock_skew_seconds=auth_module.FIREBASE_CLOCK_SKEW_SECONDS,
        )


def test_clock_skew_does_not_accept_token_for_another_project(sdk_verifier, signing_material):
    with pytest.raises(auth.InvalidIdTokenError, match='incorrect "aud"'):
        sdk_verifier.verify_id_token(
            make_token(signing_material, issued_in=5, audience="another-project"),
            clock_skew_seconds=auth_module.FIREBASE_CLOCK_SKEW_SECONDS,
        )


def test_clock_skew_does_not_accept_invalid_signature(sdk_verifier, signing_material):
    with pytest.raises(auth.InvalidIdTokenError, match="signature"):
        sdk_verifier.verify_id_token(
            make_token(signing_material, issued_in=5, wrong_signature=True),
            clock_skew_seconds=auth_module.FIREBASE_CLOCK_SKEW_SECONDS,
        )


def test_app_requests_bounded_skew_and_keeps_revocation_check(monkeypatch):
    assert auth_module.FIREBASE_CLOCK_SKEW_SECONDS == 30
    synthetic_app = object()
    monkeypatch.setattr(auth_module, "get_firebase_app", lambda: synthetic_app)

    def verify(token, *, app, check_revoked, clock_skew_seconds):
        assert token == "synthetic-token"
        assert app is synthetic_app
        assert check_revoked is True
        assert clock_skew_seconds == 30
        return {"uid": "synthetic-test-user", "email": "synthetic@example.test"}

    monkeypatch.setattr(auth_module.auth, "verify_id_token", verify)
    identity = auth_module.verify_firebase_identity(
        HTTPAuthorizationCredentials(scheme="Bearer", credentials="synthetic-token")
    )
    assert identity.uid == "synthetic-test-user"


@pytest.mark.parametrize("error_class", [auth.RevokedIdTokenError, auth.UserDisabledError])
def test_app_still_rejects_revoked_tokens_and_disabled_users(monkeypatch, error_class):
    monkeypatch.setattr(auth_module, "get_firebase_app", lambda: None)

    def reject(token, *, app, check_revoked, clock_skew_seconds):
        assert check_revoked is True
        assert clock_skew_seconds == 30
        raise error_class("Synthetic verification failure")

    monkeypatch.setattr(auth_module.auth, "verify_id_token", reject)
    with pytest.raises(HTTPException) as error:
        auth_module.verify_firebase_identity(
            HTTPAuthorizationCredentials(scheme="Bearer", credentials="synthetic-token")
        )
    assert error.value.status_code == 401
