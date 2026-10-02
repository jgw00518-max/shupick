import pytest

from app.orders import validate_order_items
from app.schemas import OrderItemCreateRequest


def test_order_items_reject_duplicate_variant() -> None:
    items = [
        OrderItemCreateRequest(productVariantId=1, quantity=1),
        OrderItemCreateRequest(productVariantId=1, quantity=2),
    ]

    with pytest.raises(ValueError, match="Duplicate"):
        validate_order_items(items)


def test_order_items_accept_distinct_variants() -> None:
    items = [
        OrderItemCreateRequest(productVariantId=1, quantity=1),
        OrderItemCreateRequest(productVariantId=2, quantity=2),
    ]

    validate_order_items(items)
