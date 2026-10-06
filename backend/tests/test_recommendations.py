from contextlib import contextmanager

import pytest
from fastapi.testclient import TestClient
from pymysql import OperationalError

from app import recommendations
from app.main import app


def product_row(identifier):
    return dict(product_id=identifier, product_name=f"추천 상품 {identifier}", category_name="스포츠",
                middle_category="스포츠", subcategory="러닝화", price=89000, gender_name="공용",
                color_code="BLK", color_name="블랙", image_url="https://example.test/shoe.png",
                review_count=0, sales_count=0)


def fake_database(monkeypatch, *, source=True, ranked=(), products=(), error=None):
    class Cursor:
        def __init__(self):
            self.query = 0
        def __enter__(self):
            return self
        def __exit__(self, *args):
            pass
        def execute(self, sql, args=()):
            if error:
                raise error
            self.query += 1
        def fetchone(self):
            return {"product_id": 91} if source else None
        def fetchall(self):
            return list(ranked if self.query == 2 else products)

    class Connection:
        def cursor(self):
            return Cursor()

    @contextmanager
    def connection():
        yield Connection()
    monkeypatch.setattr(recommendations, "mysql_connection", connection)


def test_public_recommendations_preserve_rank_and_hide_customer_details(monkeypatch):
    fake_database(monkeypatch, ranked=[dict(product_id=3, co_viewers=8), dict(product_id=2, co_viewers=0)],
                  products=[product_row(2), product_row(3)])
    response = TestClient(app).get("/products/91/recommendations")
    assert response.status_code == 200
    body = response.json()
    assert [product["id"] for product in body["products"]] == [3, 2]
    assert body["coViewedProductIds"] == [3]
    assert set(body) == {"products", "coViewedProductIds"}
    assert "customer_id" not in response.text
    assert "co_viewers" not in response.text


def test_no_other_sellable_product_returns_empty_list(monkeypatch):
    fake_database(monkeypatch)
    assert TestClient(app).get("/products/91/recommendations").json() == {
        "products": [], "coViewedProductIds": [],
    }


def test_inactive_or_missing_source_returns_404(monkeypatch):
    fake_database(monkeypatch, source=False)
    assert TestClient(app).get("/products/91/recommendations").status_code == 404


def test_database_error_returns_503_for_client_fallback(monkeypatch):
    fake_database(monkeypatch, error=OperationalError(2003, "Unavailable"))
    assert TestClient(app).get("/products/91/recommendations").status_code == 503


@pytest.mark.parametrize("path", ["/products/0/recommendations", "/products/91/recommendations?limit=0",
                                 "/products/91/recommendations?limit=11"])
def test_recommendation_bounds_are_validated(path):
    assert TestClient(app).get(path).status_code == 422
