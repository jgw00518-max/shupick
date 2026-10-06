import pytest
from fastapi import HTTPException
from app.returns import ReturnSelection, select_return_items

ROWS = [{'order_item_id': 7, 'item_key': '1-250-BLK', 'quantity': 3}]


def test_partial_quantity_and_legacy_full_return():
    assert select_return_items(ROWS, [ReturnSelection(itemKey='1-250-BLK', quantity=1)]) == [(7, 1)]
    assert select_return_items(ROWS, None) == [(7, 3)]


@pytest.mark.parametrize('items', [
    [ReturnSelection(itemKey='unknown', quantity=1)],
    [ReturnSelection(itemKey='1-250-BLK', quantity=4)],
    [ReturnSelection(itemKey='1-250-BLK', quantity=1)] * 2,
])
def test_invalid_selection(items):
    with pytest.raises(HTTPException):
        select_return_items(ROWS, items)
