from fastapi.testclient import TestClient
from fastapi import HTTPException
from contextlib import contextmanager
import pytest

from app import pickup_tracking
from app.auth import CurrentEmployee
from app.main import app


def test_tracking_requires_login():
    assert TestClient(app).get('/orders/1/tracking').status_code == 401


def test_arrival_and_pickup_require_staff_authentication():
    client = TestClient(app)
    assert client.post('/fulfillments/1/arrive').status_code == 401
    assert client.post('/orders/1/pickup/complete',json={'paymentCode':'ORD-1'}).status_code == 401


@pytest.mark.parametrize('operation', ['arrive', 'complete'])
def test_pickup_transitions_reject_other_branch(monkeypatch, operation):
    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *_):
            return None

        def execute(self, query, parameters):
            self.query = query
            self.parameters = parameters

        def fetchone(self):
            if 'employee_branch_assignments' in self.query:
                assert self.parameters == (5, 2)
                return None
            if 'FROM fulfillments' in self.query:
                return {'order_id': 10, 'destination_branch_id': 2}
            return {'order_number': 'ORD-10', 'pickup_branch_id': 2}

    class Connection:
        def cursor(self):
            return Cursor()

    @contextmanager
    def fake_connection():
        yield Connection()

    monkeypatch.setattr(pickup_tracking, 'mysql_connection', fake_connection)
    employee = CurrentEmployee(5, 'uid', 'EMP-5', '직원')
    with pytest.raises(HTTPException) as error:
        if operation == 'arrive':
            pickup_tracking.arrive(3, employee)
        else:
            pickup_tracking.complete_pickup(
                10, pickup_tracking.PickupConfirmation(paymentCode='ORD-10'), employee
            )
    assert error.value.status_code == 403
