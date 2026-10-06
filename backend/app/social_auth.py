"""Provider-verified social sign-in, with UID-only Firebase/MySQL provisioning.

Provider credentials never become Firebase credentials directly. The server verifies
them, links the business profile, and only then issues a Firebase custom token.
NAVER uses a backend-owned OIDC flow; no client-supplied NAVER access token is trusted.
"""

from dataclasses import dataclass, field
from functools import wraps
import base64
import hashlib
import hmac
import logging
import re
import secrets
import threading
import time
from typing import Any
from urllib.parse import urlencode, urlsplit

import jwt
import requests
from fastapi import APIRouter, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.routing import APIRoute
from firebase_admin import auth
from firebase_admin.exceptions import FirebaseError
from pydantic import BaseModel, ConfigDict, Field, field_validator
from pymysql import IntegrityError, MySQLError

from .auth import get_firebase_app
from .config import settings
from .database import mysql_connection


KAKAO_TOKEN_INFO_URL = "https://kapi.kakao.com/v1/user/access_token_info"
KAKAO_USER_URL = "https://kapi.kakao.com/v2/user/me"
NAVER_ISSUER = "https://nid.naver.com"
NAVER_AUTH_URL = "https://nid.naver.com/oauth2/authorize"
NAVER_TOKEN_URL = "https://nid.naver.com/oauth2/token"
NAVER_JWKS_URL = "https://nid.naver.com/oauth2/jwks"
NAVER_USER_URL = "https://openapi.naver.com/v1/nid/me"
APP_HANDOFF_URL = "com.example.shupick.auth://naver"
FLOW_TTL_SECONDS = 300
MAX_PENDING_FLOWS = 128
_NO_STORE = {"Cache-Control": "no-store", "Pragma": "no-cache"}
_profile_logger = logging.getLogger("uvicorn.error")


class _NoStoreRoute(APIRoute):
    """Keep credentials out of caches and validation-error response bodies."""

    def get_route_handler(self):
        original = super().get_route_handler()

        @wraps(original)
        async def safe_handler(request):
            try:
                response = await original(request)
            except RequestValidationError:
                # Pydantic errors can contain the rejected access token/verifier.
                return JSONResponse(
                    status_code=422,
                    content={"detail": "Invalid social login request"},
                    headers=_NO_STORE,
                )
            except HTTPException as error:
                error.headers = {**(error.headers or {}), **_NO_STORE}
                raise
            response.headers.update(_NO_STORE)
            return response

        return safe_handler


router = APIRouter(prefix="/auth/social", tags=["social-auth"], route_class=_NoStoreRoute)


class KakaoRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    accessToken: str = Field(min_length=1, max_length=8192, strict=True, repr=False)

    @field_validator("accessToken")
    @classmethod
    def token_has_no_whitespace(cls, value: str) -> str:
        if any(character.isspace() or not 33 <= ord(character) <= 126 for character in value):
            raise ValueError("Invalid access token")
        return value


class NaverStartRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    challenge: str = Field(pattern=r"^[A-Za-z0-9_-]{43}$", strict=True, repr=False)


class NaverCompleteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    state: str = Field(pattern=r"^[A-Za-z0-9_-]{20,128}$", strict=True, repr=False)
    verifier: str = Field(pattern=r"^[A-Za-z0-9._~-]{43,128}$", strict=True, repr=False)


@dataclass(frozen=True)
class ProviderIdentity:
    uid: str
    display_name: str
    email: str | None = None
    email_verified: bool = False
    refresh_default_display_name: bool = False


@dataclass
class _PendingFlow:
    state: str
    app_challenge: str = field(repr=False)
    oauth_verifier: str = field(repr=False)
    nonce: str = field(repr=False)
    expires_at: float
    phase: str = "pending"
    identity: ProviderIdentity | None = field(default=None, repr=False)
    error: str | None = None


_flows: dict[str, _PendingFlow] = {}
_flows_lock = threading.RLock()
_naver_keys = jwt.PyJWKClient(
    NAVER_JWKS_URL, cache_keys=True, max_cached_keys=16, lifespan=300, timeout=10
)


def _pkce_challenge(verifier: str) -> str:
    return base64.urlsafe_b64encode(hashlib.sha256(verifier.encode("ascii")).digest()).decode("ascii").rstrip("=")


def _provider_uid(provider: str, application: str, subject: str) -> str:
    # Namespaced by provider application: a provider account ID is not globally unique.
    digest = hashlib.sha256(f"{application}\0{subject}".encode("utf-8")).hexdigest()
    return f"{provider}:{digest}"


def _display_name(value: Any, fallback: str) -> str:
    return value.strip()[:100] if isinstance(value, str) and value.strip() else fallback


def _contact_email(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    email = value.strip()
    if len(email) > 255 or re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email) is None:
        return None
    return email


def _provider_json(method: str, url: str, *, headers=None, data=None) -> dict[str, Any]:
    """Use fixed provider endpoints, bounded timeouts, and sanitized failures."""
    try:
        if method == "GET":
            response = requests.get(url, headers=headers, timeout=10, allow_redirects=False)
        else:
            response = requests.post(url, headers=headers, data=data, timeout=10, allow_redirects=False)
        if response.status_code in (400, 401, 403):
            raise HTTPException(status_code=401, detail="Social provider rejected sign-in")
        if not 200 <= response.status_code < 300:
            raise HTTPException(status_code=502, detail="Social provider is unavailable")
        result = response.json()
    except (requests.RequestException, ValueError):
        raise HTTPException(status_code=502, detail="Social provider is unavailable") from None
    if not isinstance(result, dict):
        raise HTTPException(status_code=502, detail="Invalid social provider response")
    return result


def _require_kakao_configuration() -> None:
    if settings.kakao_app_id <= 0:
        raise HTTPException(status_code=503, detail="Kakao sign-in is not configured")


def _require_naver_configuration() -> None:
    if not settings.naver_client_id or not settings.naver_client_secret or not settings.naver_redirect_uri:
        raise HTTPException(status_code=503, detail="Naver sign-in is not configured")
    redirect = urlsplit(settings.naver_redirect_uri)
    # HTTP is allowed only for local emulator development; production uses HTTPS.
    development_hosts = {"localhost", "127.0.0.1", "10.0.2.2", "::1"}
    if (
        redirect.scheme not in {"http", "https"}
        or not redirect.hostname
        or (redirect.scheme == "http" and redirect.hostname not in development_hosts)
        or redirect.username is not None
        or redirect.password is not None
        or redirect.path != "/auth/social/naver/callback"
        or redirect.query
        or redirect.fragment
    ):
        raise HTTPException(status_code=503, detail="Naver callback configuration is invalid")


def _kakao_identity(access_token: str) -> ProviderIdentity:
    _require_kakao_configuration()
    headers = {"Authorization": f"Bearer {access_token}"}
    token = _provider_json("GET", KAKAO_TOKEN_INFO_URL, headers=headers)
    subject, app_id, remaining = token.get("id"), token.get("app_id"), token.get("expires_in")
    if (
        type(subject) is not int
        or subject <= 0
        or type(app_id) is not int
        or app_id != settings.kakao_app_id
        or type(remaining) is not int
        or remaining <= 0
    ):
        raise HTTPException(status_code=401, detail="Invalid Kakao access token")
    user = _provider_json("GET", KAKAO_USER_URL, headers=headers)
    if type(user.get("id")) is not int or user["id"] != subject:
        raise HTTPException(status_code=401, detail="Kakao identity does not match the access token")
    account = user.get("kakao_account")
    account = account if isinstance(account, dict) else {}
    profile = account.get("profile")
    profile = profile if isinstance(profile, dict) else {}
    email_verified = account.get("is_email_valid") is True and account.get("is_email_verified") is True
    email = _contact_email(account.get("email")) if email_verified else None
    return ProviderIdentity(
        uid=_provider_uid("kakao", str(app_id), str(subject)),
        display_name=_display_name(profile.get("nickname"), "카카오 회원"),
        email=email,
        email_verified=bool(email and email_verified),
    )


def _verify_naver_id_token(id_token: str, nonce: str, access_token: str, code: str) -> dict[str, Any]:
    try:
        header = jwt.get_unverified_header(id_token)
        if header.get("alg") != "RS256" or not isinstance(header.get("kid"), str) or not header["kid"]:
            raise jwt.InvalidTokenError("Unsupported signing key")
        key = _naver_keys.get_signing_key_from_jwt(id_token)
        claims = jwt.decode(
            id_token,
            key.key,
            algorithms=["RS256"],
            audience=settings.naver_client_id,
            issuer=NAVER_ISSUER,
            leeway=30,
            options={"require": ["iss", "aud", "exp", "iat", "sub"]},
        )
        if not isinstance(claims.get("sub"), str) or not claims["sub"] or len(claims["sub"]) > 255:
            raise jwt.InvalidTokenError("Invalid subject")
        # NAVER documents state and PKCE, but does not promise nonce echo. The
        # token is obtained only by this server's state/PKCE-bound code exchange.
        # An echoed nonce must still match; absence must not break that flow.
        if "nonce" in claims and (
            not isinstance(claims["nonce"], str) or not hmac.compare_digest(claims["nonce"], nonce)
        ):
            raise jwt.InvalidTokenError("Invalid nonce")
        audience = claims["aud"]
        if "azp" in claims and claims["azp"] != settings.naver_client_id:
            raise jwt.InvalidTokenError("Invalid authorized party")
        if isinstance(audience, list) and len(audience) > 1 and claims.get("azp") != settings.naver_client_id:
            raise jwt.InvalidTokenError("Missing authorized party")
        for claim, value in (("at_hash", access_token), ("c_hash", code)):
            if claim in claims:
                expected = base64.urlsafe_b64encode(hashlib.sha256(value.encode("ascii")).digest()[:16]).decode("ascii").rstrip("=")
                if not isinstance(claims[claim], str) or not hmac.compare_digest(claims[claim], expected):
                    raise jwt.InvalidTokenError("Invalid token binding")
        return claims
    except jwt.PyJWKClientConnectionError:
        raise HTTPException(status_code=502, detail="Naver verification service is unavailable") from None
    except (jwt.PyJWTError, ValueError, TypeError, KeyError, UnicodeError):
        raise HTTPException(status_code=401, detail="Invalid Naver identity token") from None


def _naver_nickname(access_token: str) -> str | None:
    """Optional, consented metadata; never a source of account identity/email."""
    try:
        profile = _provider_json(
            "GET", NAVER_USER_URL, headers={"Authorization": f"Bearer {access_token}"}
        )
    except HTTPException as error:
        # Refusal, missing permission, or a provider outage must not prevent
        # sign-in after the separate signed OIDC identity has been verified.
        reason = "profile_rejected" if error.status_code in (401, 403) else "profile_unavailable"
        _profile_logger.warning("Naver nickname not received: reason=%s", reason)
        return None
    if (
        not isinstance(profile, dict)
        or profile.get("resultcode") != "00"
        or not isinstance(profile.get("response"), dict)
    ):
        _profile_logger.warning("Naver nickname not received: reason=invalid_profile_response")
        return None
    nickname = _display_name(profile["response"].get("nickname"), "") or None
    if nickname is None:
        _profile_logger.warning("Naver nickname not received: reason=nickname_missing")
    else:
        # Fixed outcomes only: never log names, provider IDs, tokens or bodies.
        _profile_logger.info("Naver nickname received: reason=nickname_present")
    return nickname


def _can_upgrade_naver_display_name(identity: ProviderIdentity, saved_name: Any) -> bool:
    return (
        identity.uid.startswith("naver:")
        and identity.refresh_default_display_name
        and identity.display_name != "네이버 회원"
        and saved_name == "네이버 회원"
    )


def _naver_identity(code: str, flow: _PendingFlow) -> ProviderIdentity:
    _require_naver_configuration()
    token = _provider_json(
        "POST",
        NAVER_TOKEN_URL,
        data={
            "grant_type": "authorization_code",
            "client_id": settings.naver_client_id,
            "client_secret": settings.naver_client_secret,
            "redirect_uri": settings.naver_redirect_uri,
            "code": code,
            "state": flow.state,
            "code_verifier": flow.oauth_verifier,
        },
    )
    access_token, id_token = token.get("access_token"), token.get("id_token")
    if (
        not isinstance(access_token, str)
        or not access_token
        or len(access_token) > 8192
        or any(character.isspace() or not 33 <= ord(character) <= 126 for character in access_token)
        or not isinstance(id_token, str)
        or not id_token
        or len(id_token) > 16384
        or str(token.get("token_type", "")).lower() != "bearer"
    ):
        raise HTTPException(status_code=401, detail="Naver did not return an OIDC identity")
    claims = _verify_naver_id_token(id_token, flow.nonce, access_token, code)
    # The profile's response.id is not documented to equal the OIDC pairwise
    # sub. Identity still comes ONLY from the verified signed sub. Fetch just
    # the consented nickname with this same server-owned exchange's token.
    # OIDC verification stays outside the optional-profile failure handling.
    nickname = _naver_nickname(access_token)
    email = _contact_email(claims.get("email"))
    return ProviderIdentity(
        uid=_provider_uid("naver", settings.naver_client_id, claims["sub"]),
        display_name=nickname or _display_name(claims.get("nickname") or claims.get("name") or claims.get("preferred_username"), "네이버 회원"),
        email=email,
        email_verified=bool(email and claims.get("email_verified") is True),
        refresh_default_display_name=nickname is not None,
    )


def _provision_firebase_user(identity: ProviderIdentity) -> auth.UserRecord:
    """Never find, merge, or register social accounts by a contact email."""
    try:
        app = get_firebase_app()
        try:
            user = auth.get_user(identity.uid, app=app)
        except auth.UserNotFoundError:
            try:
                user = auth.create_user(uid=identity.uid, display_name=identity.display_name, app=app)
            except auth.UidAlreadyExistsError:
                # Another request can safely create the same deterministic UID first.
                user = auth.get_user(identity.uid, app=app)
        if user.disabled:
            raise HTTPException(status_code=403, detail="This social account is disabled")
        return user
    except HTTPException:
        raise
    except (FirebaseError, ValueError):
        raise HTTPException(status_code=503, detail="Firebase sign-in is unavailable") from None


def _provision_customer(identity: ProviderIdentity) -> int:
    """Preserve UID-linked profiles; a colliding email is omitted, never merged."""
    contact_email = identity.email
    for attempt in range(2):
        try:
            with mysql_connection() as connection:
                try:
                    with connection.cursor() as cursor:
                        cursor.execute("SELECT * FROM customers WHERE firebase_uid=%s FOR UPDATE", (identity.uid,))
                        existing = cursor.fetchone()
                        if existing is not None:
                            if existing["deleted_at"] is not None:
                                raise HTTPException(status_code=409, detail="Customer profile is deleted")
                            customer_id = int(existing["customer_id"])
                            if _can_upgrade_naver_display_name(identity, existing["customer_name"]):
                                cursor.execute(
                                    "UPDATE customers SET customer_name=%s "
                                    "WHERE customer_id=%s AND firebase_uid=%s AND deleted_at IS NULL",
                                    (identity.display_name, customer_id, identity.uid),
                                )
                        else:
                            if contact_email is not None:
                                cursor.execute("SELECT customer_id FROM customers WHERE email=%s", (contact_email,))
                                if cursor.fetchone() is not None:
                                    contact_email = None
                            cursor.execute(
                                "INSERT INTO customers (firebase_uid,email,customer_name) VALUES (%s,%s,%s)",
                                (identity.uid, contact_email, identity.display_name),
                            )
                            customer_id = int(cursor.lastrowid)
                            cursor.execute("INSERT INTO point_wallets (customer_id,point_balance) VALUES (%s,0)", (customer_id,))
                    connection.commit()
                    return customer_id
                except Exception:
                    connection.rollback()
                    raise
        except HTTPException:
            raise
        except IntegrityError as error:
            if attempt == 0 and error.args and error.args[0] == 1062:
                # A concurrent UID/email insert: retry UID lookup, without contact email.
                contact_email = None
                continue
            raise HTTPException(status_code=503, detail="Social login database setup is unavailable") from None
        except MySQLError:
            raise HTTPException(status_code=503, detail="Social login database setup is unavailable") from None
    raise HTTPException(status_code=503, detail="Social login database setup is unavailable")


def _custom_token(identity: ProviderIdentity) -> dict[str, str]:
    user = _provision_firebase_user(identity)
    _provision_customer(identity)
    try:
        # Do not alter even a default Firebase name before the business profile
        # has passed the disabled/deleted-account checks. Preserve custom names.
        if _can_upgrade_naver_display_name(identity, getattr(user, "display_name", None)):
            auth.update_user(identity.uid, display_name=identity.display_name, app=get_firebase_app())
        token = auth.create_custom_token(
            identity.uid,
            developer_claims={"social_provider": identity.uid.split(":", 1)[0]},
            app=get_firebase_app(),
        )
        return {"customToken": token.decode("utf-8") if isinstance(token, bytes) else str(token)}
    except HTTPException:
        raise
    except (FirebaseError, ValueError):
        raise HTTPException(status_code=503, detail="Firebase sign-in is unavailable") from None


def _expire_flows() -> None:
    """Caller holds the registry lock; all phases retain the original short TTL."""
    now = time.monotonic()
    for state in [state for state, flow in _flows.items() if flow.expires_at <= now]:
        del _flows[state]


def _app_handoff(state: str, error: str | None = None) -> RedirectResponse:
    query = {"state": state}
    if error is not None:
        query["error"] = error
    return RedirectResponse(f"{APP_HANDOFF_URL}?{urlencode(query)}", status_code=302, headers=_NO_STORE)


@router.post("/kakao")
def kakao_login(request: KakaoRequest) -> dict[str, str]:
    return _custom_token(_kakao_identity(request.accessToken))


@router.post("/naver/start")
def start_naver(request: NaverStartRequest) -> dict[str, str]:
    _require_naver_configuration()
    flow = _PendingFlow(
        state=secrets.token_urlsafe(32),
        app_challenge=request.challenge,
        oauth_verifier=secrets.token_urlsafe(48),
        nonce=secrets.token_urlsafe(32),
        expires_at=time.monotonic() + FLOW_TTL_SECONDS,
    )
    with _flows_lock:
        _expire_flows()
        if len(_flows) >= MAX_PENDING_FLOWS:
            raise HTTPException(status_code=429, detail="Too many pending social sign-ins; try again later")
        _flows[flow.state] = flow
    parameters = {
        "response_type": "code",
        "client_id": settings.naver_client_id,
        "redirect_uri": settings.naver_redirect_uri,
        "scope": "openid profile",
        # App logout cannot clear NAVER's browser session. NAVER documents this
        # option for both OAuth2 and OIDC: request a fresh login so the user can
        # enter a different account instead of silently reusing browser cookies.
        "auth_type": "reauthenticate",
        "state": flow.state,
        "nonce": flow.nonce,
        "code_challenge": _pkce_challenge(flow.oauth_verifier),
        "code_challenge_method": "S256",
    }
    return {"state": flow.state, "authorizationUrl": f"{NAVER_AUTH_URL}?{urlencode(parameters)}"}


@router.get("/naver/callback")
def callback_naver(code: str | None = None, state: str | None = None, error: str | None = None) -> RedirectResponse:
    _require_naver_configuration()
    if state is None or len(state) > 128:
        raise HTTPException(status_code=400, detail="Invalid or expired Naver sign-in")
    with _flows_lock:
        _expire_flows()
        flow = _flows.get(state)
        if flow is None or flow.phase != "pending":
            raise HTTPException(status_code=400, detail="Invalid or expired Naver sign-in")
        # Consume callback state before exchanging the code, including cancellation.
        flow.phase = "processing"
    identity, outcome = None, None
    if error:
        outcome = "cancelled" if error.strip().lower() in {"access_denied", "cancelled", "canceled"} else "login_failed"
    elif not code or len(code) > 4096:
        outcome = "login_failed"
    else:
        try:
            identity = _naver_identity(code, flow)
        except HTTPException:
            # Provider errors/tokens never appear in the app link or response.
            outcome = "login_failed"
    with _flows_lock:
        _expire_flows()
        if _flows.get(state) is not flow:
            return _app_handoff(state, "login_failed")
        flow.identity = identity
        flow.error = outcome
        flow.phase = "error" if outcome else "ready"
    return _app_handoff(state, outcome)


@router.post("/naver/complete")
def complete_naver(request: NaverCompleteRequest) -> dict[str, str]:
    _require_naver_configuration()
    with _flows_lock:
        _expire_flows()
        flow = _flows.get(request.state)
        if flow is None:
            raise HTTPException(status_code=400, detail="Invalid or expired Naver sign-in")
        if not hmac.compare_digest(_pkce_challenge(request.verifier), flow.app_challenge):
            raise HTTPException(status_code=401, detail="Naver sign-in handoff verification failed")
        if flow.phase in {"pending", "processing"}:
            raise HTTPException(status_code=409, detail="Naver sign-in has not completed")
        del _flows[request.state]
    if flow.error or flow.identity is None:
        raise HTTPException(status_code=400, detail="Naver sign-in did not complete")
    return _custom_token(flow.identity)


class OAuthCallbackAccessLogFilter(logging.Filter):
    """Uvicorn normally logs callback query strings containing OAuth codes."""

    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.args, tuple) and len(record.args) >= 3:
            values = list(record.args)
            if isinstance(values[2], str) and values[2].split("?", 1)[0].rstrip("/") == "/auth/social/naver/callback":
                values[2] = "/auth/social/naver/callback"
                record.args = tuple(values)
        if isinstance(record.msg, str):
            record.msg = re.sub(r"/auth/social/naver/callback/?\?[^\s\"]+", "/auth/social/naver/callback", record.msg)
        return True


def install_social_auth_access_log_filter() -> None:
    logger = logging.getLogger("uvicorn.access")
    if not any(isinstance(item, OAuthCallbackAccessLogFilter) for item in logger.filters):
        logger.addFilter(OAuthCallbackAccessLogFilter())
