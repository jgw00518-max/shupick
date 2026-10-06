import pytest

from app.procurement import validate_procurement_items
from app.schemas import ProcurementItemRequest


def test_procurement_items_reject_duplicate_variant() -> None:
    items = [
        ProcurementItemRequest(productVariantId=1, requestedQuantity=10),
        ProcurementItemRequest(productVariantId=1, requestedQuantity=20),
    ]

    with pytest.raises(ValueError, match="Duplicate"):
        validate_procurement_items(items)
