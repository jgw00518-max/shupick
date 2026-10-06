"""Firebase ID-token verification and MySQL customer profile linking."""

from dataclasses import dataclass
from pathlib import Path
from collections.abc import Callable
from typing import Any
import logging
import re

import firebase_admin
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth, credentials
from firebase_admin.exceptions import FirebaseError
from pymysql import MySQLError

from .config import settings
from .database import mysql_connection
from .schemas import CustomerProfileResponse, CustomerProfileSyncRequest, EmployeeProfileResponse


router = APIRouter(prefix="/auth", tags=["auth"])
bearer_scheme = HTTPBearer(auto_error=False)
logger = logging.getLogger("uvicorn.error")
# Firebase permits at most 60 seconds. Keep the tolerance bounded to 30 seconds;
# signature, project, expiry (with this tolerance), and revocation checks remain enabled.
FIREBASE_CLOCK_SKEW_SECONDS = 30


def _token_error_reason(error: Exception) -> str:
    """Classify verification failures without logging tokens or exception text."""
    error_type = type(error).__name__
    known_errors = {
        "ExpiredIdTokenError": "expired_token",
        "RevokedIdTokenError": "revoked_token",
        "UserDisabledError": "disabled_user",
        "UserNotFoundError": "user_not_found",
        "CertificateFetchError": "certificate_fetch_failed",
        "TenantIdMismatchError": "tenant_mismatch",
        "PermissionDeniedError": "server_permission_denied",
    }
    if error_type in known_errors:
        return known_errors[error_type]
    message = str(error).lower()
    if "used too early" in message or "not yet valid" in message or "issued in the future" in message:
        return "token_issued_in_future"
    if 'incorrect "aud"' in message or "audience" in message:
        return "project_mismatch"
    if 'incorrect "iss"' in message or "issuer" in message:
        return "issuer_mismatch"
    if "signature" in message:
        return "invalid_signature"
    return "invalid_token"


@dataclass(frozen=True)
class FirebaseIdentity:
    """Verified identity claims used by backend dependencies."""

    uid: str
    email: str | None
    email_verified: bool


@dataclass(frozen=True)
class CurrentCustomer:
    """MySQL customer resolved from a verified Firebase UID."""

    customer_id: int
    firebase_uid: str
    email: str | None


@dataclass(frozen=True)
class CurrentEmployee:
    """Active employee resolved from a verified Firebase UID."""

    employee_id: int
    firebase_uid: str
    employee_code: str
    employee_name: str


def get_firebase_app() -> firebase_admin.App:
    if not settings.firebase_project_id:
        raise HTTPException(status_code=503, detail="Firebase Authentication is not configured")
    try:
        return firebase_admin.get_app()
    except ValueError:
        options = {"projectId": settings.firebase_project_id}
        if settings.firebase_credentials_path:
            credential_path = Path(settings.firebase_credentials_path)
            if not credential_path.is_file():
                raise HTTPException(status_code=503, detail="Firebase credentials file was not found")
            credential = credentials.Certificate(str(credential_path))
            return firebase_admin.initialize_app(credential, options)
        return firebase_admin.initialize_app(options=options)


def verify_firebase_identity(
    authorization: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> FirebaseIdentity:
    """Verify a client Firebase ID token and expose its stable UID."""

    if authorization is None or authorization.scheme.lower() != "bearer":
        logger.warning("Firebase auth rejected: reason=missing_bearer_token")
        raise HTTPException(status_code=401, detail="Firebase ID token is required")
    try:
        decoded: dict[str, Any] = auth.verify_id_token(
            authorization.credentials,
            app=get_firebase_app(),
            check_revoked=True,
            clock_skew_seconds=FIREBASE_CLOCK_SKEW_SECONDS,
        )
    except HTTPException:
        raise
    except (FirebaseError, ValueError) as error:
        reason = _token_error_reason(error)
        logger.warning(
            "Firebase auth rejected: reason=%s error_type=%s",
            reason,
            type(error).__name__,
        )
        if reason == "token_issued_in_future":
            # Only extract numeric clock information, never log the JWT or raw error.
            match = re.search(r"Token used too early, (\d{1,12}) < (\d{1,12})", str(error))
            offset = int(match[2]) - int(match[1]) if match else "unknown"
            logger.warning(
                "Firebase clock mismatch: token_ahead_seconds=%s allowed_seconds=%s; "
                "synchronize the server clock if this persists",
                offset,
                FIREBASE_CLOCK_SKEW_SECONDS,
            )
        raise HTTPException(status_code=401, detail="Invalid or expired Firebase ID token") from error

    uid = decoded.get("uid") or decoded.get("sub")
    if not uid:
        raise HTTPException(status_code=401, detail="Firebase token does not contain a UID")
    return FirebaseIdentity(
        uid=str(uid),
        email=None if decoded.get("email") is None else str(decoded["email"]),
        email_verified=bool(decoded.get("email_verified", False)),
    )


def get_current_customer(
    identity: FirebaseIdentity = Depends(verify_firebase_identity),
) -> CurrentCustomer:
    """Resolve the verified Firebase UID to the MySQL business customer."""

    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT customer_id,firebase_uid,email FROM customers WHERE firebase_uid=%s AND deleted_at IS NULL",
                    (identity.uid,),
                )
                row = cursor.fetchone()
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    if row is None:
        raise HTTPException(status_code=404, detail="Customer profile is not linked; call /auth/customer/sync")
    return CurrentCustomer(
        customer_id=int(row["customer_id"]),
        firebase_uid=str(row["firebase_uid"]),
        email=None if row["email"] is None else str(row["email"]),
    )


def get_current_employee(
    identity: FirebaseIdentity = Depends(verify_firebase_identity),
) -> CurrentEmployee:
    """Resolve an active employee from the verified Firebase UID."""

    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT employee_id,firebase_uid,employee_code,employee_name
                    FROM employees
                    WHERE firebase_uid=%s AND is_active=TRUE
                    """,
                    (identity.uid,),
                )
                row = cursor.fetchone()
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    if row is None:
        raise HTTPException(status_code=403, detail="Active employee account is required")
    return CurrentEmployee(
        employee_id=int(row["employee_id"]),
        firebase_uid=str(row["firebase_uid"]),
        employee_code=str(row["employee_code"]),
        employee_name=str(row["employee_name"]),
    )


def require_permission(permission_code: str) -> Callable[..., CurrentEmployee]:
    """Create a FastAPI dependency that enforces one employee permission."""

    def permission_dependency(
        current: CurrentEmployee = Depends(get_current_employee),
    ) -> CurrentEmployee:
        try:
            with mysql_connection() as connection:
                with connection.cursor() as cursor:
                    cursor.execute(
                        """
                        SELECT 1
                        FROM employee_roles er
                        JOIN roles r ON r.role_id=er.role_id AND r.is_active=TRUE
                        JOIN role_permissions rp ON rp.role_id=r.role_id
                        JOIN permissions p ON p.permission_id=rp.permission_id
                        WHERE er.employee_id=%s AND p.permission_code=%s
                        LIMIT 1
                        """,
                        (current.employee_id, permission_code),
                    )
                    allowed = cursor.fetchone() is not None
        except MySQLError as error:
            raise HTTPException(status_code=503, detail="Database unavailable") from error
        if not allowed:
            raise HTTPException(status_code=403, detail=f"Missing permission: {permission_code}")
        return current

    return permission_dependency


def _profile_response(row: dict[str, Any]) -> CustomerProfileResponse:
    return CustomerProfileResponse(
        customerId=int(row["customer_id"]),
        firebaseUid=str(row["firebase_uid"]),
        email=None if row["email"] is None else str(row["email"]),
        customerName=str(row["customer_name"]),
        phone=row["phone"],
        birthDate=None if row["birth_date"] is None else str(row["birth_date"]),
    )


@router.post("/customer/sync", response_model=CustomerProfileResponse)
def sync_customer_profile(
    request: CustomerProfileSyncRequest,
    identity: FirebaseIdentity = Depends(verify_firebase_identity),
) -> CustomerProfileResponse:
    """Create or update a MySQL profile after Firebase authentication."""

    if not identity.email:
        raise HTTPException(status_code=422, detail="Firebase account does not provide an email")
    try:
        with mysql_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT * FROM customers WHERE firebase_uid=%s FOR UPDATE", (identity.uid,))
                    customer = cursor.fetchone()
                    if customer is None:
                        cursor.execute("SELECT * FROM customers WHERE email=%s FOR UPDATE", (identity.email,))
                        email_customer = cursor.fetchone()
                        if email_customer is not None:
                            if request.ensureOnly and email_customer["deleted_at"] is not None:
                                raise HTTPException(status_code=409, detail="Customer profile is deleted")
                            if not identity.email_verified:
                                raise HTTPException(status_code=409, detail="Verified email is required to link an existing profile")
                            if not str(email_customer["firebase_uid"]).startswith("legacy-customer-"):
                                raise HTTPException(status_code=409, detail="Email is already linked to another Firebase account")
                            cursor.execute(
                                """
                                UPDATE customers
                                SET firebase_uid=%s,customer_name=%s,phone=%s,birth_date=%s,deleted_at=NULL
                                WHERE customer_id=%s
                                """,
                                (
                                    identity.uid,
                                    email_customer["customer_name"] if request.ensureOnly else request.customerName,
                                    email_customer["phone"] if request.ensureOnly or "phone" not in request.model_fields_set else request.phone,
                                    email_customer["birth_date"] if request.ensureOnly or "birthDate" not in request.model_fields_set else request.birthDate,
                                    email_customer["customer_id"],
                                ),
                            )
                            customer_id = int(email_customer["customer_id"])
                        else:
                            cursor.execute(
                                """
                                INSERT INTO customers
                                  (firebase_uid,email,customer_name,phone,birth_date)
                                VALUES (%s,%s,%s,%s,%s)
                                """,
                                (identity.uid, identity.email, request.customerName, request.phone, request.birthDate),
                            )
                            customer_id = cursor.lastrowid
                            cursor.execute(
                                "INSERT INTO point_wallets (customer_id,point_balance) VALUES (%s,0)",
                                (customer_id,),
                            )
                    else:
                        customer_id = int(customer["customer_id"])
                        if request.ensureOnly and customer["deleted_at"] is not None:
                            raise HTTPException(status_code=409, detail="Customer profile is deleted")
                        if not request.ensureOnly:
                            cursor.execute(
                                """
                                UPDATE customers
                                SET email=%s,customer_name=%s,phone=%s,birth_date=%s,deleted_at=NULL
                                WHERE customer_id=%s
                                """,
                                (identity.email, request.customerName, request.phone if "phone" in request.model_fields_set else customer.get("phone"), request.birthDate if "birthDate" in request.model_fields_set else customer.get("birth_date"), customer_id),
                            )
                    cursor.execute("SELECT * FROM customers WHERE customer_id=%s", (customer_id,))
                    result = cursor.fetchone()
                connection.commit()
                return _profile_response(result)
            except Exception:
                connection.rollback()
                raise
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error


@router.get("/me", response_model=CustomerProfileResponse)
def get_my_profile(current: CurrentCustomer = Depends(get_current_customer)) -> CustomerProfileResponse:
    """Return the business profile for the signed-in Firebase user."""

    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT * FROM customers WHERE customer_id=%s", (current.customer_id,))
                row = cursor.fetchone()
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return _profile_response(row)


@router.get("/employee/me", response_model=EmployeeProfileResponse)
def get_employee_profile(
    current: CurrentEmployee = Depends(get_current_employee),
) -> EmployeeProfileResponse:
    """Return only active roles and current branch assignments for this employee."""

    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """SELECT r.role_code,r.role_name
                    FROM employee_roles er JOIN roles r ON r.role_id=er.role_id
                    WHERE er.employee_id=%s AND r.is_active=TRUE
                    ORDER BY r.role_code""",
                    (current.employee_id,),
                )
                roles = cursor.fetchall()
                cursor.execute(
                    """SELECT DISTINCT b.branch_id,b.branch_code,b.branch_name,b.district_code
                    FROM employee_branch_assignments eba
                    JOIN branches b ON b.branch_id=eba.branch_id
                    WHERE eba.employee_id=%s AND eba.ended_at IS NULL AND b.is_active=TRUE
                    ORDER BY b.branch_name,b.branch_id""",
                    (current.employee_id,),
                )
                branches = cursor.fetchall()
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error

    if not roles:
        raise HTTPException(status_code=403, detail="Active employee role is required")

    return EmployeeProfileResponse(
        employeeId=current.employee_id,
        employeeCode=current.employee_code,
        employeeName=current.employee_name,
        roles=[
            {"roleCode": row["role_code"], "roleName": row["role_name"]}
            for row in roles
        ],
        branches=[
            {
                "branchId": int(row["branch_id"]),
                "branchCode": row["branch_code"],
                "branchName": row["branch_name"],
                "districtCode": row["district_code"],
            }
            for row in branches
        ],
    )
