from fastapi.testclient import TestClient
from app.main import app


def test_tracking_requires_login():
    assert TestClient(app).get('/orders/1/tracking').status_code == 401


def test_arrival_and_pickup_require_staff_authentication():
    client = TestClient(app)
    assert client.post('/fulfillments/1/arrive').status_code == 401
    assert client.post('/orders/1/pickup/complete',json={'paymentCode':'ORD-1'}).status_code == 401
