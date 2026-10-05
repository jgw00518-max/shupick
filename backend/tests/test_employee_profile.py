from contextlib import contextmanager

from fastapi.testclient import TestClient

from app.auth import CurrentEmployee, get_current_employee
from app.main import app


class FakeCursor:
    def __init__(self, roles, branches):
        self.roles = roles
        self.branches = branches
        self.query = ""
        self.parameters = None

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return None

    def execute(self, query, parameters):
        self.query = query
        self.parameters = parameters

    def fetchall(self):
        assert self.parameters == (7,)
        if "employee_roles" in self.query:
            return self.roles
        assert "ended_at IS NULL" in self.query
        assert "b.is_active=TRUE" in self.query
        return self.branches


class FakeConnection:
    def __init__(self, cursor):
        self.value = cursor

    def cursor(self):
        return self.value


def test_employee_profile_requires_authentication():
    response = TestClient(app).get('/auth/employee/me')
    assert response.status_code == 401


def test_employee_profile_returns_server_assigned_roles_and_branches(monkeypatch):
    from app import auth

    cursor = FakeCursor(
        roles=[{'role_code': 'BRANCH_STAFF', 'role_name': '대리점 직원'}],
        branches=[{'branch_id': 3, 'branch_code': 'SEL-SD',
                   'branch_name': 'SHOEPICK 성동점', 'district_code': 'SEOUL-SEONGDONG'}],
    )

    @contextmanager
    def fake_connection():
        yield FakeConnection(cursor)

    monkeypatch.setattr(auth, 'mysql_connection', fake_connection)
    app.dependency_overrides[get_current_employee] = lambda: CurrentEmployee(
        employee_id=7, firebase_uid='staff-uid', employee_code='EMP-0007', employee_name='테스트 직원'
    )
    try:
        response = TestClient(app).get('/auth/employee/me')
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json() == {
        'employeeId': 7, 'employeeCode': 'EMP-0007', 'employeeName': '테스트 직원',
        'roles': [{'roleCode': 'BRANCH_STAFF', 'roleName': '대리점 직원'}],
        'branches': [{'branchId': 3, 'branchCode': 'SEL-SD',
                      'branchName': 'SHOEPICK 성동점', 'districtCode': 'SEOUL-SEONGDONG'}],
    }


def test_employee_without_active_role_is_rejected(monkeypatch):
    from app import auth

    @contextmanager
    def fake_connection():
        yield FakeConnection(FakeCursor([], []))

    monkeypatch.setattr(auth, 'mysql_connection', fake_connection)
    app.dependency_overrides[get_current_employee] = lambda: CurrentEmployee(
        employee_id=7, firebase_uid='staff-uid', employee_code='EMP-0007', employee_name='테스트 직원'
    )
    try:
        response = TestClient(app).get('/auth/employee/me')
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 403
