"""Staff inquiry integration must enforce employee and business permissions.

All identities and MySQL connections in these tests are local fakes. No Firebase
token, account, or real database is read or changed.
"""

from contextlib import contextmanager
from datetime import datetime
from decimal import Decimal
from importlib import import_module
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

import app.auth as auth_module
import app.support as support_module
from app.auth import CurrentEmployee, FirebaseIdentity
from app.main import app


EMPLOYEE = CurrentEmployee(2, "staff-test-uid", "EMP-0002", "본사 직원")
IDENTITY = FirebaseIdentity("staff-test-uid", "staff@example.com", False)


def employee_row():
    return {
        "employee_id": EMPLOYEE.employee_id,
        "firebase_uid": EMPLOYEE.firebase_uid,
        "employee_code": EMPLOYEE.employee_code,
        "employee_name": EMPLOYEE.employee_name,
    }


def normalized_sql(call):
    sql = " ".join(call.args[0].split()).lower().replace("`", "")
    return sql.replace(" = ", "=").replace("= ", "=").replace(" =", "=")


def assert_read_only(cursor, connection):
    assert all(normalized_sql(call).startswith("select")
               for call in cursor.execute.call_args_list)
    connection.commit.assert_not_called()


def fake_database(monkeypatch, module, *, one=(), many=()):
    cursor = MagicMock()
    cursor.__enter__.return_value = cursor
    cursor.fetchone.side_effect = list(one)
    cursor.fetchall.side_effect = list(many)
    connection = MagicMock()
    connection.cursor.return_value = cursor

    @contextmanager
    def connect():
        yield connection

    monkeypatch.setattr(module, "mysql_connection", connect)
    return cursor, connection


@pytest.fixture
def client(monkeypatch):
    previous = dict(app.dependency_overrides)

    def forbid_real_database():
        raise AssertionError("A staff test must never open a real database")

    for module in (auth_module, support_module, import_module("app.staff_work")):
        monkeypatch.setattr(module, "mysql_connection", forbid_real_database)
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.clear()
        app.dependency_overrides.update(previous)


def override_identity(identity=IDENTITY):
    app.dependency_overrides[auth_module.verify_firebase_identity] = lambda: identity


def override_employee():
    app.dependency_overrides[auth_module.get_current_employee] = lambda: EMPLOYEE


def test_staff_routes_are_registered(client):
    paths = client.get("/openapi.json").json()["paths"]
    for path in (
        "/auth/employee/me", "/staff/inquiries", "/staff/customers",
        "/staff/customers/{customer_id}", "/inquiries/{inquiry_id}/answer",
    ):
        assert path in paths


@pytest.mark.parametrize("method,path,body", [
    ("GET", "/auth/employee/me", None),
    ("GET", "/staff/inquiries", None),
    ("GET", "/staff/customers", None),
    ("GET", "/staff/customers/1", None),
    ("POST", "/inquiries/1/answer", {"answer": "reply"}),
])
def test_staff_routes_require_auth_before_database(client, method, path, body):
    response = client.request(method, path, json=body)
    assert response.status_code == 401


@pytest.mark.parametrize("uid", ["customer-only-uid", "unlinked-staff-uid"])
def test_customer_or_unlinked_identity_cannot_become_employee(client, monkeypatch, uid):
    override_identity(FirebaseIdentity(uid, "test@example.com", False))
    cursor, connection = fake_database(monkeypatch, auth_module, one=[None])
    response = client.get("/auth/employee/me")
    assert response.status_code == 403
    assert cursor.execute.call_args.args[1] == (uid,)
    assert "is_active=true" in normalized_sql(cursor.execute.call_args)
    assert_read_only(cursor, connection)


def test_inactive_employee_is_filtered_before_permission_lookup(monkeypatch):
    cursor, connection = fake_database(monkeypatch, auth_module, one=[None])
    with pytest.raises(HTTPException) as rejected:
        auth_module.get_current_employee(IDENTITY)
    assert rejected.value.status_code == 403
    assert "is_active=true" in normalized_sql(cursor.execute.call_args)
    assert_read_only(cursor, connection)


def test_employee_profile_maps_only_active_roles_and_assigned_branches(client, monkeypatch):
    override_employee()
    cursor, connection = fake_database(
        monkeypatch, auth_module,
        many=[
            [{"role_code": "HQ_STAFF", "role_name": "본사 직원"}],
            [{"branch_id": 1, "branch_code": "SEL-SD",
              "branch_name": "성동점", "district_code": "SEOUL-SEONGDONG"}],
        ],
    )
    response = client.get("/auth/employee/me")
    assert response.status_code == 200
    assert response.json() == {
        "employeeId": 2, "employeeCode": "EMP-0002", "employeeName": "본사 직원",
        "roles": [{"roleCode": "HQ_STAFF", "roleName": "본사 직원"}],
        "branches": [{"branchId": 1, "branchCode": "SEL-SD",
                      "branchName": "성동점", "districtCode": "SEOUL-SEONGDONG"}],
    }
    statements = [normalized_sql(call) for call in cursor.execute.call_args_list]
    assert any("roles" in sql and "is_active=true" in sql for sql in statements)
    assert any("ended_at is null" in sql and "is_active=true" in sql
               for sql in statements)
    assert_read_only(cursor, connection)


def test_employee_profile_without_active_roles_is_forbidden(client, monkeypatch):
    override_employee()
    cursor, connection = fake_database(monkeypatch, auth_module, many=[[], []])
    response = client.get("/auth/employee/me")
    assert response.status_code == 403
    assert_read_only(cursor, connection)


def test_hq_profile_requires_no_branch_assignment(client, monkeypatch):
    override_identity()
    cursor, connection = fake_database(
        monkeypatch, auth_module, one=[employee_row()],
        many=[[{"role_code": "HQ_STAFF", "role_name": "본사 직원"}], []],
    )
    response = client.get("/auth/employee/me")
    assert response.status_code == 200
    assert response.json()["employeeId"] == 2
    assert response.json()["branches"] == []
    assert "firebase_uid" not in response.json()
    assert "firebaseUid" not in response.json()
    assert_read_only(cursor, connection)


@pytest.mark.parametrize("path", ["/staff/inquiries", "/staff/customers", "/staff/customers/1"])
def test_staff_reads_require_active_support_permission(client, monkeypatch, path):
    override_employee()
    cursor, connection = fake_database(monkeypatch, auth_module, one=[None])
    response = client.get(path)
    assert response.status_code == 403
    assert cursor.execute.call_args.args[1] == (2, "SUPPORT_MANAGE")
    assert "is_active=true" in normalized_sql(cursor.execute.call_args)
    assert_read_only(cursor, connection)


def test_missing_or_inactive_role_does_not_allow_answer(client, monkeypatch):
    override_employee()
    cursor, connection = fake_database(monkeypatch, auth_module, one=[None])
    response = client.post("/inquiries/1/answer", json={"answer": "reply"})
    assert response.status_code == 403
    assert cursor.execute.call_args.args[1] == (2, "SUPPORT_MANAGE")
    assert "is_active=true" in normalized_sql(cursor.execute.call_args)
    assert_read_only(cursor, connection)


def test_staff_inquiry_list_maps_customer_and_latest_response(client, monkeypatch):
    override_employee()
    permissions, _ = fake_database(monkeypatch, auth_module, one=[{"allowed": 1}])
    work = import_module("app.staff_work")
    cursor, connection = fake_database(monkeypatch, work, many=[[
        {
            "inquiry_id": 11, "customer_id": 42, "customer_name": "테스트 고객",
            "inquiry_type": "OTHER", "title": "DB 연결 테스트",
            "inquiry_content": "저장 확인 문의", "inquiry_status": "ANSWERED",
            "created_at": datetime(2026, 10, 6, 10, 20), "answer": "최신 답변",
        },
    ]])
    response = client.get("/staff/inquiries")
    assert response.status_code == 200
    assert response.json() == [{
        "id": 11, "customerId": 42, "customerName": "테스트 고객", "type": "OTHER",
        "title": "DB 연결 테스트", "body": "저장 확인 문의", "status": "ANSWERED",
        "createdAt": "2026-10-06T10:20:00", "answer": "최신 답변",
    }]
    assert permissions.execute.call_args.args[1] == (2, "SUPPORT_MANAGE")
    sql = normalized_sql(cursor.execute.call_args)
    assert "responded_at desc" in sql
    assert "inquiry_response_id desc" in sql
    assert "limit 100" in sql
    assert_read_only(cursor, connection)


def test_staff_customer_list_maps_totals_and_excludes_deleted_profiles(client, monkeypatch):
    override_employee()
    fake_database(monkeypatch, auth_module, one=[{"allowed": 1}])
    work = import_module("app.staff_work")
    cursor, connection = fake_database(monkeypatch, work, many=[[
        {
            "customer_id": 42, "customer_name": "테스트 고객", "email": "test@example.com",
            "phone": None, "order_count": 1, "paid_total": Decimal("129000.00"),
            "last_ordered_at": datetime(2026, 10, 6, 9, 30), "point_balance": 0,
        },
    ]])
    response = client.get("/staff/customers")
    assert response.status_code == 200
    assert response.json() == [{
        "id": 42, "name": "테스트 고객", "email": "test@example.com", "phone": None,
        "orderCount": 1, "paidTotal": "129000.00", "lastOrderedAt": "2026-10-06T09:30:00",
        "pointBalance": 0,
    }]
    sql = normalized_sql(cursor.execute.call_args)
    assert "deleted_at is null" in sql
    assert "limit 200" in sql
    assert_read_only(cursor, connection)


def test_staff_customer_detail_returns_owned_orders_and_returns(client, monkeypatch):
    override_employee()
    fake_database(monkeypatch, auth_module, one=[{"allowed": 1}])
    work = import_module("app.staff_work")
    cursor, connection = fake_database(
        monkeypatch, work,
        one=[{"customer_id": 42, "customer_name": "테스트 고객", "email": "test@example.com",
              "phone": None}],
        many=[
            [{"order_id": 7, "order_number": "ORD-7", "order_status": "PAID",
              "paid_total": Decimal("129000.00"), "ordered_at": datetime(2026, 10, 6, 9, 30),
              "branch_name": "성동점"}],
            [{"return_request_id": 9, "order_id": 7, "request_status": "REQUESTED",
              "return_reason": "반품 문의"}],
        ],
    )
    response = client.get("/staff/customers/42")
    assert response.status_code == 200
    assert response.json() == {
        "id": 42, "name": "테스트 고객", "email": "test@example.com", "phone": None,
        "orders": [{"id": 7, "number": "ORD-7", "status": "PAID", "paidTotal": "129000.00",
                    "orderedAt": "2026-10-06T09:30:00", "branchName": "성동점"}],
        "returns": [{"id": 9, "orderId": 7, "status": "REQUESTED", "reason": "반품 문의"}],
    }
    calls = cursor.execute.call_args_list
    assert all(call.args[1] == (42,) for call in calls)
    assert "deleted_at is null" in normalized_sql(calls[0])
    assert "customer_id=%s" in normalized_sql(calls[1])
    assert "customer_id=%s" in normalized_sql(calls[2])
    assert_read_only(cursor, connection)


def test_staff_customer_detail_missing_or_deleted_profile_is_404(client, monkeypatch):
    override_employee()
    fake_database(monkeypatch, auth_module, one=[{"allowed": 1}])
    work = import_module("app.staff_work")
    cursor, connection = fake_database(monkeypatch, work, one=[None])
    response = client.get("/staff/customers/999")
    assert response.status_code == 404
    assert cursor.execute.call_args.args[1] == (999,)
    assert "deleted_at is null" in normalized_sql(cursor.execute.call_args)
    assert_read_only(cursor, connection)


def test_answer_uses_authenticated_employee_and_commits_response_and_status(client, monkeypatch):
    override_employee()
    fake_database(monkeypatch, auth_module, one=[{"allowed": 1}])
    cursor, connection = fake_database(monkeypatch, support_module, one=[{"inquiry_id": 11}])
    response = client.post("/inquiries/11/answer", json={"answer": "  확인했습니다.  "})
    assert response.status_code == 200
    assert response.json() == {"answered": True}
    calls = cursor.execute.call_args_list
    assert "for update" in normalized_sql(calls[0])
    insert = next(call for call in calls if normalized_sql(call).startswith("insert"))
    update = next(call for call in calls if normalized_sql(call).startswith("update"))
    assert insert.args[1] == (11, 2, "확인했습니다.")
    assert "inquiry_responses" in normalized_sql(insert)
    assert "answered" in normalized_sql(update)
    assert update.args[1] == (11,)
    connection.commit.assert_called_once()


def test_whitespace_answer_is_rejected_without_business_write(client, monkeypatch):
    override_employee()
    fake_database(monkeypatch, auth_module, one=[{"allowed": 1}])
    response = client.post("/inquiries/11/answer", json={"answer": " \t\n "})
    assert response.status_code == 422


def test_answer_to_missing_inquiry_has_no_writes(client, monkeypatch):
    override_employee()
    fake_database(monkeypatch, auth_module, one=[{"allowed": 1}])
    cursor, connection = fake_database(monkeypatch, support_module, one=[None])
    response = client.post("/inquiries/999/answer", json={"answer": "reply"})
    assert response.status_code == 404
    assert_read_only(cursor, connection)
