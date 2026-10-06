"""UID-scoped phone enrollment. SMS proves possession, not name or birthday."""

from dataclasses import dataclass
from datetime import date
import re
import time

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.routing import APIRoute
from firebase_admin import auth
from firebase_admin.exceptions import FirebaseError
from pydantic import BaseModel, ConfigDict, Field, SecretStr, field_validator
from pymysql import MySQLError

from .auth import (
    CurrentCustomer, FIREBASE_CLOCK_SKEW_SECONDS, get_current_customer, get_firebase_app,
)
from .database import mysql_connection


class PrivateValidationRoute(APIRoute):
    def get_route_handler(self):
        original = super().get_route_handler()

        async def handler(request: Request):
            try:
                return await original(request)
            except RequestValidationError:
                # Default validation responses can echo a submitted token.
                raise HTTPException(422, "Invalid enrollment request") from None

        return handler


router = APIRouter(prefix="/auth", tags=["customer enrollment"], route_class=PrivateValidationRoute)


class EnrollmentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    phoneToken: SecretStr | None = Field(default=None, repr=False)
    phoneConsent: bool = False
    birthDate: date | None = None
    birthdayConsent: bool = False

    @field_validator("birthDate")
    @classmethod
    def valid_birthday(cls, value):
        if value is not None and not date(1900, 1, 1) <= value <= date.today():
            raise ValueError("Invalid birth date")
        return value


@dataclass(frozen=True, repr=False)
class VerifiedPhoneIdentity:
    uid: str
    phone: str


def verify_phone_token(token: SecretStr | None) -> VerifiedPhoneIdentity:
    if token is None or not 1 <= len(token.get_secret_value()) <= 10000:
        raise HTTPException(401, "Fresh SMS authentication is required")
    try:
        app = get_firebase_app()
        claims = auth.verify_id_token(
            token.get_secret_value(), app=app, check_revoked=True,
            clock_skew_seconds=FIREBASE_CLOCK_SKEW_SECONDS,
        )
        uid = claims.get("uid") or claims.get("sub")
        phone = claims.get("phone_number")
        auth_time = claims.get("auth_time")
        if (
            not isinstance(uid, str) or not uid
            or not isinstance(phone, str) or not re.fullmatch(r"\+8210\d{8}", phone)
            or claims.get("firebase", {}).get("sign_in_provider") != "phone"
            or type(auth_time) not in (int, float)
            or not -FIREBASE_CLOCK_SKEW_SECONDS <= time.time() - auth_time <= 300
        ):
            raise ValueError("Invalid phone proof")
        # Do not accept a token whose phone has since changed or user was disabled.
        user = auth.get_user(uid, app=app)
        if user.disabled or user.phone_number != phone:
            raise ValueError("Phone identity changed")
        return VerifiedPhoneIdentity(uid, phone)
    except HTTPException:
        raise
    except (FirebaseError, ValueError, TypeError, AttributeError):
        raise HTTPException(401, "Fresh SMS authentication is required") from None


def validate_consents(request: EnrollmentRequest):
    if request.phoneToken is not None and request.phoneConsent is not True:
        raise HTTPException(422, "Phone authentication consent is required")
    if request.birthDate is not None and request.birthdayConsent is not True:
        raise HTTPException(422, "Birthday storage consent is required")


def masked_phone(phone: str | None) -> str | None:
    return None if phone is None else "010-****-" + phone[-4:]


@router.post("/phone/validate")
def validate_phone_before_signup(request: EnrollmentRequest):
    """Fail before creating an email account if proof or database setup is invalid."""
    validate_consents(request)
    verify_phone_token(request.phoneToken)
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT customer_id FROM customer_enrollments LIMIT 0")
    except MySQLError:
        raise HTTPException(503, "Enrollment database is not ready") from None
    return {"verified": True}


@router.get("/customer/enrollment")
def get_enrollment(current: CurrentCustomer = Depends(get_current_customer)):
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """SELECT c.birth_date,e.verified_phone FROM customers c
                    LEFT JOIN customer_enrollments e ON e.customer_id=c.customer_id
                    WHERE c.customer_id=%s AND c.firebase_uid=%s AND c.deleted_at IS NULL""",
                    (current.customer_id, current.firebase_uid),
                )
                row = cursor.fetchone()
    except MySQLError:
        raise HTTPException(503, "Enrollment database is not ready") from None
    if row is None:
        raise HTTPException(404, "Customer profile is unavailable")
    return {
        "phoneVerified": row["verified_phone"] is not None,
        "maskedPhone": masked_phone(row["verified_phone"]),
        "birthDate": None if row["birth_date"] is None else str(row["birth_date"]),
    }


@router.post("/customer/enrollment")
def save_enrollment(request: EnrollmentRequest, current: CurrentCustomer = Depends(get_current_customer)):
    validate_consents(request)
    phone = None if request.phoneToken is None else verify_phone_token(request.phoneToken)
    try:
        with mysql_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute(
                        "SELECT customer_id FROM customers WHERE customer_id=%s AND firebase_uid=%s AND deleted_at IS NULL FOR UPDATE",
                        (current.customer_id, current.firebase_uid),
                    )
                    if cursor.fetchone() is None:
                        raise HTTPException(404, "Customer profile is unavailable")
                    cursor.execute(
                        "SELECT verified_phone FROM customer_enrollments WHERE customer_id=%s FOR UPDATE",
                        (current.customer_id,),
                    )
                    previous = cursor.fetchone()
                    if phone is None and previous is None:
                        raise HTTPException(422, "SMS authentication is required before enrollment")
                    if phone is not None:
                        cursor.execute(
                            """INSERT INTO customer_enrollments
                              (customer_id,verified_phone,firebase_phone_uid,phone_verified_at,phone_consent_at,birth_date_consent_at)
                            VALUES (%s,%s,%s,UTC_TIMESTAMP(6),UTC_TIMESTAMP(6),IF(%s,UTC_TIMESTAMP(6),NULL))
                            ON DUPLICATE KEY UPDATE verified_phone=VALUES(verified_phone),
                              firebase_phone_uid=VALUES(firebase_phone_uid),phone_verified_at=UTC_TIMESTAMP(6),
                              phone_consent_at=UTC_TIMESTAMP(6),birth_date_consent_at=VALUES(birth_date_consent_at)""",
                            (current.customer_id, phone.phone, phone.uid, request.birthDate is not None),
                        )
                    else:
                        cursor.execute(
                            "UPDATE customer_enrollments SET birth_date_consent_at=IF(%s,UTC_TIMESTAMP(6),NULL) WHERE customer_id=%s",
                            (request.birthDate is not None, current.customer_id),
                        )
                    cursor.execute("UPDATE customers SET birth_date=%s WHERE customer_id=%s", (request.birthDate, current.customer_id))
                connection.commit()
                return {"saved": True}
            except Exception:
                connection.rollback()
                raise
    except MySQLError:
        raise HTTPException(503, "Enrollment database is not ready") from None
