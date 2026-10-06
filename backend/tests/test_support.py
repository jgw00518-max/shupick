import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.support import InquiryRequest,RestockRequest

def test_support_requires_customer_authentication():
    client=TestClient(app)
    assert client.get('/inquiries').status_code==401
    assert client.get('/restock-subscriptions').status_code==401
    assert client.post('/inquiries/1/answer',json={'answer':'reply'}).status_code==401

def test_support_validation():
    with pytest.raises(ValueError): InquiryRequest(kind='INVALID',title='title',body='body')
    with pytest.raises(ValueError): InquiryRequest(kind='OTHER',title='',body='body')
    with pytest.raises(ValueError): RestockRequest(keys=['key']*201)
