import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.interactions import InteractionRequest

def test_events_require_authentication():
    assert TestClient(app).post('/interactions',json={}).status_code==401

def test_invalid_event_and_quantity_are_rejected():
    payload=dict(eventKey='key',sessionKey='session',productId=1,eventType='VIEW',occurredAt='2026-10-03T00:00:00Z')
    assert InteractionRequest(**payload).productId==1
    for change in [dict(eventType='INVALID'),dict(quantity=100),dict(productId=0)]:
        with pytest.raises(ValueError): InteractionRequest(**{**payload,**change})
