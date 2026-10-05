from contextlib import contextmanager
from datetime import datetime

from fastapi.testclient import TestClient

from app import staff_work
from app.auth import CurrentEmployee, get_current_employee
from app.main import app


def test_staff_returns_filter_selected_branch_and_current_assignment(monkeypatch):
    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *_):
            return None

        def execute(self, query, parameters):
            self.query = query
            self.parameters = parameters

        def fetchone(self):
            assert 'employee_roles' in self.query
            return None

        def fetchall(self):
            assert 'rr.branch_id=%s' in self.query
            assert 'eba.branch_id=rr.branch_id' in self.query
            assert 'eba.ended_at IS NULL' in self.query
            assert self.parameters == (3, 3, 0, 7)
            return [{
                'return_request_id': 9,
                'order_id': 11,
                'request_status': 'REQUESTED',
                'return_reason': '사이즈 불일치',
                'requested_at': datetime(2026, 10, 5),
                'order_number': 'ORD-11',
                'customer_name': '고객',
                'branch_name': '성동점',
            }]

    cursor = Cursor()

    class Connection:
        def cursor(self):
            return cursor

    @contextmanager
    def fake_connection():
        yield Connection()

    monkeypatch.setattr(staff_work, 'mysql_connection', fake_connection)
    app.dependency_overrides[get_current_employee] = lambda: CurrentEmployee(7, 'uid', 'EMP-7', '직원')
    try:
        response = TestClient(app).get('/staff/returns?branchId=3')
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()[0]['orderNumber'] == 'ORD-11'
