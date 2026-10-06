"""Self-service staff registration for the test environment."""

from typing import Literal
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from pymysql import IntegrityError, MySQLError

from .auth import FirebaseIdentity, verify_firebase_identity
from .database import mysql_connection


router = APIRouter(prefix="/auth/employee", tags=["staff registration"])

ROLE_LABELS = {
    "BRANCH_STAFF": "대리점 직원",
    "BRANCH_MANAGER": "대리점장",
    "HQ_STAFF": "본사 사원",
    "TEAM_LEAD": "본사 팀장",
    "DIRECTOR": "본사 이사",
    "EXECUTIVE": "본사 임원",
}
AFFILIATION_ROLES = {
    "BRANCH": {"BRANCH_STAFF", "BRANCH_MANAGER"},
    "HQ": {"HQ_STAFF", "TEAM_LEAD", "DIRECTOR", "EXECUTIVE"},
}


class StaffRegistrationRequest(BaseModel):
    employeeName: str = Field(min_length=1, max_length=100)
    affiliation: Literal["BRANCH", "HQ"]
    districtCode: str | None = Field(default=None, pattern=r"^SEOUL-[A-Z]+$", max_length=20)
    roleCode: Literal[
        "BRANCH_STAFF", "BRANCH_MANAGER", "HQ_STAFF", "TEAM_LEAD", "DIRECTOR", "EXECUTIVE"
    ]


class StaffRegistrationResponse(BaseModel):
    employeeId: int
    status: Literal["ACTIVE"]


@router.post("/register", response_model=StaffRegistrationResponse, status_code=201)
def register_staff(
    request: StaffRegistrationRequest,
    identity: FirebaseIdentity = Depends(verify_firebase_identity),
) -> StaffRegistrationResponse:
    """Activate an employee after the client creates a Firebase user."""

    name = request.employeeName.strip()
    if not name:
        raise HTTPException(status_code=422, detail="Employee name is required")
    if request.roleCode not in AFFILIATION_ROLES[request.affiliation]:
        raise HTTPException(status_code=422, detail="Role does not match affiliation")
    if request.affiliation == "BRANCH" and not request.districtCode:
        raise HTTPException(status_code=422, detail="Branch district is required")
    if request.affiliation == "HQ" and request.districtCode is not None:
        raise HTTPException(status_code=422, detail="Head office must not select a branch")
    if not identity.email:
        raise HTTPException(status_code=422, detail="Firebase account email is required")

    email = identity.email.strip().lower()
    department = "대리점" if request.affiliation == "BRANCH" else "본사"
    try:
        with mysql_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute(
                        "SELECT employee_id FROM employees WHERE firebase_uid=%s FOR UPDATE",
                        (identity.uid,),
                    )
                    existing = cursor.fetchone()
                    if existing:
                        raise HTTPException(status_code=409, detail="Firebase user is already linked to an employee")

                    cursor.execute(
                        "SELECT employee_id FROM employees WHERE email=%s FOR UPDATE", (email,)
                    )
                    if cursor.fetchone():
                        raise HTTPException(status_code=409, detail="Email is linked to another employee")

                    branch_id = None
                    if request.affiliation == "BRANCH":
                        cursor.execute(
                            """SELECT branch_id FROM branches
                               WHERE district_code=%s AND is_active=TRUE""",
                            (request.districtCode,),
                        )
                        branches = cursor.fetchall()
                        if len(branches) != 1:
                            raise HTTPException(status_code=422, detail="Select an available district branch")
                        branch_id = branches[0]["branch_id"]
                    cursor.execute(
                        "SELECT role_id FROM roles WHERE role_code=%s AND is_active=TRUE",
                        (request.roleCode,),
                    )
                    role = cursor.fetchone()
                    if role is None:
                        raise HTTPException(status_code=422, detail="Selected role is unavailable")

                    cursor.execute(
                        """INSERT INTO employees
                           (firebase_uid,email,employee_code,employee_name,department,position,is_active)
                           VALUES (%s,%s,%s,%s,%s,%s,TRUE)""",
                        (
                            identity.uid, email, f"REG-{uuid4().hex[:20].upper()}",
                            name, department, ROLE_LABELS[request.roleCode],
                        ),
                    )
                    employee_id = int(cursor.lastrowid)
                    cursor.execute(
                        "INSERT INTO employee_roles (employee_id,role_id) VALUES (%s,%s)",
                        (employee_id, role["role_id"]),
                    )
                    if branch_id is not None:
                        cursor.execute(
                            "INSERT INTO employee_branch_assignments (employee_id,branch_id) VALUES (%s,%s)",
                            (employee_id, branch_id),
                        )
                connection.commit()
            except Exception:
                connection.rollback()
                raise
    except HTTPException:
        raise
    except IntegrityError as error:
        raise HTTPException(status_code=409, detail="Employee registration conflicts with an existing account") from error
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error

    return StaffRegistrationResponse(employeeId=employee_id, status="ACTIVE")
