from contextlib import contextmanager

from fastapi.testclient import TestClient

from app import staff_registration
from app.auth import FirebaseIdentity, verify_firebase_identity
from app.main import app


class RegistrationCursor:
    lastrowid = 11

    def __init__(self):
        self.query = ""
        self.parameters = ()
        self.executed = []

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return None

    def execute(self, query, parameters=()):
        self.query = query
        self.parameters = parameters
        self.executed.append((query, parameters))

    def fetchone(self):
        if "SELECT branch_id FROM branches" in self.query:
            raise AssertionError("Branch lookup must use fetchall")
        if "SELECT role_id FROM roles" in self.query:
            return {"role_id": 7}
        return None

    def fetchall(self):
        assert "district_code=%s AND is_active=TRUE" in self.query
        return [{"branch_id": 3}]


class RegistrationConnection:
    def __init__(self):
        self.value = RegistrationCursor()
        self.committed = False

    def cursor(self):
        return self.value

    def commit(self):
        self.committed = True

    def rollback(self):
        raise AssertionError("Successful registration must not roll back")


def test_staff_registration_requires_firebase_token():
    response = TestClient(app).post('/auth/employee/register', json={})
    assert response.status_code == 401


def test_staff_registration_rejects_role_outside_affiliation():
    app.dependency_overrides[verify_firebase_identity] = lambda: FirebaseIdentity(
        uid='new-uid', email='new@example.com', email_verified=False
    )
    try:
        response = TestClient(app).post('/auth/employee/register', json={
            'employeeName': '테스트 직원', 'affiliation': 'BRANCH',
            'districtCode': 'SEOUL-GANGNAM', 'roleCode': 'DIRECTOR',
        })
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 422


def test_registration_saves_active_employee_and_selected_access(monkeypatch):
    connection = RegistrationConnection()

    @contextmanager
    def fake_connection():
        yield connection

    monkeypatch.setattr(staff_registration, 'mysql_connection', fake_connection)
    app.dependency_overrides[verify_firebase_identity] = lambda: FirebaseIdentity(
        uid='new-uid', email='new@example.com', email_verified=False
    )
    try:
        response = TestClient(app).post('/auth/employee/register', json={
            'employeeName': '테스트 직원', 'affiliation': 'BRANCH',
            'districtCode': 'SEOUL-GANGNAM', 'roleCode': 'BRANCH_STAFF',
        })
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 201
    assert response.json() == {'employeeId': 11, 'status': 'ACTIVE'}
    assert connection.committed
    writes = [(query, params) for query, params in connection.value.executed if query.strip().startswith('INSERT')]
    assert len(writes) == 3
    employee_insert = writes[0]
    assert 'is_active' in employee_insert[0] and 'TRUE' in employee_insert[0]
    assert employee_insert[1][0:2] == ('new-uid', 'new@example.com')
    assert writes[1][1] == (11, 7)
    assert writes[2][1] == (11, 3)


def test_head_office_registration_has_no_branch_assignment(monkeypatch):
    connection = RegistrationConnection()

    @contextmanager
    def fake_connection():
        yield connection

    monkeypatch.setattr(staff_registration, 'mysql_connection', fake_connection)
    app.dependency_overrides[verify_firebase_identity] = lambda: FirebaseIdentity(
        uid='hq-uid', email='hq@example.com', email_verified=False
    )
    try:
        response = TestClient(app).post('/auth/employee/register', json={
            'employeeName': '본사 직원', 'affiliation': 'HQ', 'roleCode': 'HQ_STAFF',
            'districtCode': None,
        })
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 201
    assert response.json() == {'employeeId': 11, 'status': 'ACTIVE'}
    assert connection.committed
    assert not any('SELECT branch_id FROM branches' in query for query, _ in connection.value.executed)
    writes = [query for query, _ in connection.value.executed if query.strip().startswith('INSERT')]
    assert len(writes) == 2
    assert not any('employee_branch_assignments' in query for query in writes)


def test_branch_registration_requires_district():
    app.dependency_overrides[verify_firebase_identity] = lambda: FirebaseIdentity(
        uid='new-uid', email='new@example.com', email_verified=False
    )
    try:
        response = TestClient(app).post('/auth/employee/register', json={
            'employeeName': '대리점 직원', 'affiliation': 'BRANCH', 'roleCode': 'BRANCH_STAFF',
        })
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 422


def test_inactive_employee_cannot_open_staff_profile(monkeypatch):
    from app import auth

    class PendingCursor:
        def __enter__(self):
            return self

        def __exit__(self, *_):
            return None

        def execute(self, query, parameters):
            assert 'is_active=TRUE' in query
            assert parameters == ('pending-uid',)

        def fetchone(self):
            return None

    class PendingConnection:
        def cursor(self):
            return PendingCursor()

    @contextmanager
    def fake_connection():
        yield PendingConnection()

    monkeypatch.setattr(auth, 'mysql_connection', fake_connection)
    app.dependency_overrides[verify_firebase_identity] = lambda: FirebaseIdentity(
        uid='pending-uid', email='pending@example.com', email_verified=True
    )
    try:
        response = TestClient(app).get('/auth/employee/me')
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 403
