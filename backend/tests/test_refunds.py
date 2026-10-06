import pytest

from app.refunds import validate_refund_items
from app.schemas import RefundItemRequest


def test_return_items_must_match_refund_amount() -> None:
    items = [RefundItemRequest(orderItemId=1, quantity=1, refundAmount=9000)]

    with pytest.raises(ValueError, match="must equal"):
        validate_refund_items("RETURN", 10000, items)


def test_return_items_reject_duplicate_order_item() -> None:
    items = [
        RefundItemRequest(orderItemId=1, quantity=1, refundAmount=5000),
        RefundItemRequest(orderItemId=1, quantity=1, refundAmount=5000),
    ]

    with pytest.raises(ValueError, match="Duplicate"):
        validate_refund_items("RETURN", 10000, items)


def test_order_cancel_cannot_include_items() -> None:
    items = [RefundItemRequest(orderItemId=1, quantity=1, refundAmount=10000)]

    with pytest.raises(ValueError, match="Only RETURN"):
        validate_refund_items("ORDER_CANCEL", 10000, items)
