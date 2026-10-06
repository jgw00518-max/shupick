"""Create one dedicated HQ support test account, with a locally entered password.

No existing Firebase user, employee, customer, or password is updated. The
staff-app self-registration API is deliberately not enabled by this utility.
"""

import argparse
from getpass import getpass
from uuid import uuid4

from firebase_admin import auth

from app.auth import get_firebase_app
from app.config import settings
from app.database import mysql_connection


TEST_EMAIL = "shupickstafftest01@example.com"
TEST_EMPLOYEE_CODE = "TEST-HQ-0001"
TEST_EMPLOYEE_NAME = "테스트 본사 직원"


class SetupError(Exception):
    """Expected setup failure that is safe to show without credentials."""


def required_role(cursor) -> int:
    cursor.execute(
        """SELECT r.role_id
        FROM roles r JOIN role_permissions rp ON rp.role_id=r.role_id
        JOIN permissions p ON p.permission_id=rp.permission_id
        WHERE r.role_code='HQ_STAFF' AND r.is_active=TRUE
          AND p.permission_code='SUPPORT_MANAGE'"""
    )
    role = cursor.fetchone()
    if role is None:
        raise SetupError("HQ_STAFF의 SUPPORT_MANAGE 권한이 없습니다. 먼저 서버 설정을 확인해주세요.")
    cursor.execute(
        "SELECT employee_id FROM employees WHERE employee_code=%s",
        (TEST_EMPLOYEE_CODE,),
    )
    if cursor.fetchone() is not None:
        raise SetupError("이 테스트 직원이 이미 있습니다. 기존 직원이나 비밀번호는 변경하지 않았습니다.")
    return int(role["role_id"])


def check_setup(firebase_app) -> None:
    if (settings.mysql_host not in {"127.0.0.1", "localhost", "::1"}
            or settings.mysql_database != "shupick_v2"
            or settings.firebase_project_id != "shupick-71b8f"):
        raise SetupError("예상한 테스트 DB 또는 Firebase 프로젝트가 아닙니다. 설정을 확인해주세요.")
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("START TRANSACTION READ ONLY")
            required_role(cursor)
        connection.rollback()
    try:
        auth.get_user_by_email(TEST_EMAIL, app=firebase_app)
    except auth.UserNotFoundError:
        return
    raise SetupError("이 Firebase 이메일 계정이 이미 있습니다. 기존 계정이나 비밀번호는 변경하지 않았습니다.")


def create_account(password: str, firebase_app) -> None:
    """Insert a new employee and the HQ role only after a new Firebase user is created."""
    uid = f"staff-test-{uuid4().hex}"
    with mysql_connection() as connection:
        try:
            with connection.cursor() as cursor:
                role_id = required_role(cursor)
                # MySQL rows are uncommitted until Firebase creation succeeds.
                cursor.execute(
                    """INSERT INTO employees
                    (firebase_uid,employee_code,employee_name,department,position,is_active)
                    VALUES (%s,%s,%s,%s,%s,TRUE)""",
                    (uid, TEST_EMPLOYEE_CODE, TEST_EMPLOYEE_NAME, "TEST", "HQ_STAFF"),
                )
                employee_id = cursor.lastrowid
                cursor.execute(
                    "INSERT INTO employee_roles (employee_id,role_id) VALUES (%s,%s)",
                    (employee_id, role_id),
                )
                try:
                    auth.create_user(
                        uid=uid,
                        email=TEST_EMAIL,
                        password=password,
                        display_name=TEST_EMPLOYEE_NAME,
                        disabled=False,
                        email_verified=False,
                        app=firebase_app,
                    )
                except Exception as error:
                    # A timeout can happen after Firebase accepted creation.
                    # The SQL transaction will roll back, but never assume the
                    # remote account is absent or delete an existing account.
                    raise SetupError(
                        "Firebase 계정 생성 완료를 확인하지 못했습니다. "
                        "MySQL 신규 직원 정보는 저장하지 않습니다. "
                        "재실행하지 말고 이 메시지를 알려주세요."
                    ) from error
        except BaseException:
            connection.rollback()
            raise
        try:
            connection.commit()
        except Exception as error:
            # A failed commit may already have reached MySQL. Never delete the
            # Firebase user or reset an existing account to guess the outcome.
            raise SetupError(
                "Firebase 테스트 계정은 생성됐지만 MySQL 연결 완료를 확인하지 못했습니다. "
                "재실행하거나 계정을 삭제하지 말고 이 메시지를 알려주세요."
            ) from error


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="직원 전용 테스트 계정 생성 (기존 계정 변경 없음)")
    parser.add_argument("--check", action="store_true", help="읽기 전용으로 준비 상태만 확인")
    args = parser.parse_args(argv)
    print(f"대상 직원 이메일: {TEST_EMAIL}")
    print("기존 고객/직원 계정과 비밀번호는 변경하지 않습니다.")
    try:
        firebase_app = get_firebase_app()
        check_setup(firebase_app)
        if args.check:
            print("준비 확인 완료. 계정과 DB는 변경하지 않았습니다.")
            return 0
        print("입력한 비밀번호는 화면에 표시되거나 파일에 저장되지 않습니다. Ctrl+C로 취소할 수 있습니다.")
        password = getpass("새 비밀번호 (8자 이상): ")
        confirmation = getpass("같은 비밀번호를 다시 입력: ")
        if len(password) < 8:
            raise SetupError("비밀번호는 8자 이상이어야 합니다. 계정은 생성하지 않았습니다.")
        if password != confirmation:
            raise SetupError("비밀번호가 일치하지 않습니다. 계정은 생성하지 않았습니다.")
        create_account(password, firebase_app)
        print("직원 테스트 계정 생성 및 MySQL 연결 완료!")
        print(f"로그인 이메일: {TEST_EMAIL}")
        print("역할: 본사 직원 (HQ_STAFF). 비밀번호는 방금 입력한 값입니다.")
        print("직원 앱에서 로그인한 뒤 '고객 관리'에서 문의를 확인해주세요.")
        return 0
    except SetupError as error:
        print(str(error))
        return 1
    except KeyboardInterrupt:
        print("취소했습니다. 완료 메시지가 없으면 연결 상태를 확인한 뒤 다시 진행해주세요.")
        return 1
    except Exception as error:
        # SDK/connection messages can contain confidential configuration.
        print(f"계정 준비가 완료되지 않았습니다. 오류 종류: {type(error).__name__}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
