from fastapi.testclient import TestClient
from app.main import app

def test_account_benefits_and_confirmation_require_authentication():
    client=TestClient(app)
    assert client.get('/account/benefits').status_code==401
    assert client.post('/orders/1/confirm').status_code==401
