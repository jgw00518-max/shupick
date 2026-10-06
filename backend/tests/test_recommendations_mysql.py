"""Opt-in MySQL checks using temporary events/inventory, never persisted test data."""

from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
import os

import pytest

from app import recommendations
from app.database import mysql_connection


pytestmark = pytest.mark.skipif(
    os.getenv("SHOEPICK_MYSQL_TESTS") != "1", reason="Opt-in local catalog MySQL checks",
)


@pytest.fixture
def catalog(monkeypatch):
    with mysql_connection() as db:
        with db.cursor() as cursor:
            cursor.execute("SELECT model_code,product_id FROM products WHERE model_code LIKE 'SP-%%' AND is_active=TRUE")
            ids = {row["model_code"]: row["product_id"] for row in cursor.fetchall()}
            if len(ids) != 10:
                pytest.skip("Requires the ten-product initial SHOEPICK catalog")
            for table in ("test_reco_seed_views", "test_reco_other_views"):
                cursor.execute(f"""CREATE TEMPORARY TABLE {table} (
                    customer_id BIGINT, session_key VARCHAR(100), product_id BIGINT,
                    event_type VARCHAR(30), occurred_at DATETIME(6))""")
            cursor.execute("""CREATE TEMPORARY TABLE test_reco_inventory (
                product_variant_id BIGINT PRIMARY KEY, available_quantity INT)""")
            cursor.execute("""INSERT INTO test_reco_inventory
                SELECT product_variant_id,available_quantity FROM headquarters_inventory""")
        sql = recommendations.RECOMMENDATIONS_SQL.replace(
            "customer_interaction_events seed", "test_reco_seed_views seed",
        ).replace("customer_interaction_events other", "test_reco_other_views other").replace(
            "headquarters_inventory inventory", "test_reco_inventory inventory",
        )
        monkeypatch.setattr(recommendations, "RECOMMENDATIONS_SQL", sql)

        @contextmanager
        def connection():
            yield db
        monkeypatch.setattr(recommendations, "mysql_connection", connection)
        try:
            yield db, ids
        finally:
            db.rollback()


def view(db, ids, customer, model, session, *, offset=0, event="VIEW"):
    timestamp = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(minutes=offset)
    with db.cursor() as cursor:
        for table in ("test_reco_seed_views", "test_reco_other_views"):
            cursor.execute(f"INSERT INTO {table} VALUES (%s,%s,%s,%s,%s)",
                           (customer, session, ids[model], event, timestamp))


def result(ids, model="SP-001"):
    return recommendations.product_recommendations(ids[model], limit=4)


def test_unsigned_prices_and_cold_start_similarity(catalog):
    _, ids = catalog
    response = result(ids)
    assert response.products[0].id == ids["SP-002"]
    assert not response.coViewedProductIds
    assert ids["SP-001"] not in [product.id for product in response.products]
    assert len(response.products) == 4


def test_repeats_count_once_and_two_customers_change_recommendation_order(catalog):
    db, ids = catalog
    for _ in range(10):
        view(db, ids, 1, "SP-001", "one")
        view(db, ids, 1, "SP-008", "one")
    assert not result(ids).coViewedProductIds
    view(db, ids, 2, "SP-001", "two")
    view(db, ids, 2, "SP-008", "two")
    response = result(ids)
    assert response.products[0].id == ids["SP-008"]
    assert response.coViewedProductIds == [ids["SP-008"]]


def test_customer_session_time_event_and_gender_boundaries(catalog):
    db, ids = catalog
    for customer in (1, 2):
        view(db, ids, customer, "SP-001", "source")
        view(db, ids, customer, "SP-005", "different-session")
        view(db, ids, customer, "SP-001", "gap", offset=-120)
        view(db, ids, customer, "SP-006", "gap")
        view(db, ids, customer, "SP-001", "future", offset=60)
        view(db, ids, customer, "SP-007", "future", offset=60)
        view(db, ids, customer, "SP-001", "wish")
        view(db, ids, customer, "SP-004", "wish", event="WISH_ADD")
        view(db, ids, customer, "SP-001", "kids")
        view(db, ids, customer, "SP-009", "kids")
        view(db, ids, customer, "SP-001", "expired", offset=-31*24*60)
        view(db, ids, customer, "SP-008", "expired", offset=-31*24*60)
    view(db, ids, 3, "SP-001", "shared-session-name")
    view(db, ids, 4, "SP-003", "shared-session-name")
    assert not result(ids).coViewedProductIds
    assert ids["SP-009"] not in [product.id for product in result(ids).products]
    assert [product.id for product in result(ids, "SP-009").products] == [ids["SP-010"]]


def test_out_of_stock_co_viewed_product_is_excluded(catalog):
    db, ids = catalog
    for customer in (1, 2):
        view(db, ids, customer, "SP-001", "view")
        view(db, ids, customer, "SP-008", "view")
    assert ids["SP-008"] in result(ids).coViewedProductIds
    with db.cursor() as cursor:
        cursor.execute("""UPDATE test_reco_inventory i JOIN product_variants v USING(product_variant_id)
            SET i.available_quantity=0 WHERE v.product_id=%s""", (ids["SP-008"],))
    response = result(ids)
    assert ids["SP-008"] not in [product.id for product in response.products]
    assert not response.coViewedProductIds
