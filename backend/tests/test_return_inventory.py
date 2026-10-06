from unittest.mock import MagicMock, patch

import pytest

from app.returns import InspectionRequest, restore_inspected_inventory


@pytest.mark.parametrize('flags,defective', [({}, 0), ({'hasProductDefect': True}, 2), ({'isWrongItem': True}, 2), ({'packagingIntact': False}, 2)])
def test_inspected_inventory_classification(flags, defective):
    connection = MagicMock()
    cursor = connection.cursor.return_value.__enter__.return_value
    cursor.fetchall.return_value = [{'product_variant_id': 5, 'quantity': 2}]
    cursor.fetchone.side_effect = [{'product_variant_id': 5}, None]
    with patch('app.returns._insert_movement') as movement:
        restore_inspected_inventory(connection, 7, InspectionRequest(accepted=True, notes='검수', **flags))
    assert movement.call_args.kwargs['on_hand_delta'] == 2
    assert movement.call_args.kwargs['defective_delta'] == defective
    assert movement.call_args.kwargs['idempotency_key'] == 'return-intake-7-5'
    assert cursor.execute.call_args.args[1] == (2, defective, 5)


def test_rejected_inspection_does_not_restore_inventory():
    connection = MagicMock()
    restore_inspected_inventory(connection, 7, InspectionRequest(accepted=False, notes='반품 거절'))
    connection.cursor.assert_not_called()


def test_existing_movement_does_not_restore_twice():
    connection = MagicMock()
    cursor = connection.cursor.return_value.__enter__.return_value
    cursor.fetchall.return_value = [{'product_variant_id': 5, 'quantity': 2}]
    cursor.fetchone.side_effect = [{'product_variant_id': 5}, {'inventory_movement_id': 9}]
    with patch('app.returns._insert_movement') as movement:
        restore_inspected_inventory(connection, 7, InspectionRequest(accepted=True, notes='검수'))
    movement.assert_not_called()
    assert not any('UPDATE headquarters_inventory' in call.args[0] for call in cursor.execute.call_args_list)
