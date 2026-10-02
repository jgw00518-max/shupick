from unittest.mock import patch

from fastapi.testclient import TestClient

from app.auth import CurrentCustomer, get_current_customer
from app.main import app


def test_order_queries_use_authenticated_customer_and_hide_missing_orders():
    app.dependency_overrides[get_current_customer] = lambda: CurrentCustomer(7, "uid", "test@example.com")
    try:
        with patch("app.order_queries.read_orders", return_value=[]) as read:
            client = TestClient(app)
            assert client.get("/orders").json() == []
            read.assert_called_with(7)
            assert client.get("/orders/99").status_code == 404
            read.assert_called_with(7, 99)
    finally:
        app.dependency_overrides.clear()


def test_order_queries_require_authentication():
    assert TestClient(app).get("/orders").status_code == 401
