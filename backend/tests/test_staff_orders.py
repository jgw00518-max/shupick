from contextlib import contextmanager
from datetime import datetime

from fastapi.testclient import TestClient

from app import staff_orders
from app.auth import CurrentEmployee, get_current_employee
from app.main import app


def _employee():
    return CurrentEmployee(7, 'staff-uid', 'EMP-0007', '테스트 직원')


def test_staff_orders_require_login():
    assert TestClient(app).get('/staff/orders').status_code == 401
    assert TestClient(app).post('/staff/pickups/verify', json={'paymentCode': 'ORD-1'}).status_code == 401


def test_branch_orders_are_scoped_to_current_assignment(monkeypatch):
    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *_):
            return None

        def execute(self, query, parameters):
            self.query = query
            self.parameters = parameters

        def fetchone(self):
            if 'employee_roles' in self.query:
                return None
            assert 'employee_branch_assignments' in self.query
            assert self.parameters == (7, 2)
            return {'ok': 1}

        def fetchall(self):
            if 'FROM orders o' in self.query:
                assert 'eba.branch_id=o.pickup_branch_id' in self.query
                assert self.parameters == (0, 7, 2, 2)
                return [{'order_id': 10, 'order_number': 'ORD-10', 'order_status': 'READY_FOR_PICKUP',
                         'ordered_at': datetime(2026, 10, 5), 'pickup_branch_id': 2,
                         'customer_name': '고객', 'branch_name': '강남점', 'fulfillment_id': 3,
                         'fulfillment_status': 'READY_FOR_PICKUP'}]
            assert self.parameters == (10,)
            return [{'order_id': 10, 'product_name': '운동화', 'color_name': '검정',
                     'size_mm': 260, 'quantity': 1}]

    cursor = Cursor()

    class Connection:
        def cursor(self):
            return cursor

    @contextmanager
    def fake_connection():
        yield Connection()

    monkeypatch.setattr(staff_orders, 'mysql_connection', fake_connection)
    app.dependency_overrides[get_current_employee] = _employee
    try:
        response = TestClient(app).get('/staff/orders?branchId=2')
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 200
    assert response.json()[0]['orderNumber'] == 'ORD-10'
    assert response.json()[0]['products'] == ['운동화 · 검정 / 260 × 1']


def test_pickup_code_not_found_outside_assigned_branch(monkeypatch):
    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *_):
            return None

        def execute(self, query, parameters):
            assert 'eba.branch_id=o.pickup_branch_id' in query
            assert parameters == ('ORD-OTHER', 7)

        def fetchone(self):
            return None

    class Connection:
        def cursor(self):
            return Cursor()

    @contextmanager
    def fake_connection():
        yield Connection()

    monkeypatch.setattr(staff_orders, 'mysql_connection', fake_connection)
    app.dependency_overrides[get_current_employee] = _employee
    try:
        response = TestClient(app).post('/staff/pickups/verify', json={'paymentCode': 'ord-other'})
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 404
