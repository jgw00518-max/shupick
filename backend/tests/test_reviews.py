import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.reviews import ReviewRequest

def test_review_validation():
    for rating in [0,6]:
        with pytest.raises(ValueError): ReviewRequest(orderNumber='order',itemKey='item',content='review',rating=rating)
    with pytest.raises(ValueError): ReviewRequest(orderNumber='order',itemKey='item',content='review',rating=5,photos=['not-base64'])

def test_review_endpoints_require_auth():
    client=TestClient(app)
    assert client.get('/reviews').status_code==401
    assert client.post('/reviews',json={}).status_code==401
