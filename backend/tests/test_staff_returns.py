from contextlib import contextmanager
from datetime import datetime, timedelta
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

from app import staff_returns
from app.auth import CurrentCustomer, CurrentEmployee, get_current_customer, get_current_employee
from app.main import app


BODY = dict(reason='사이즈 불일치', unworn=True, undamaged=True, completePackaging=True,
            items=[dict(itemKey='5-260-BLACK', quantity=1)])


@pytest.fixture
def setup_return(monkeypatch):
    order = dict(order_id=10, order_number='ORD-10', order_status='COMPLETED', purchase_confirmed_at=None,
                 customer_id=12, pickup_branch_id=3, customer_name='고객', branch_name='강남점')
    state = dict(assigned=True, order=order, picked=datetime.now()-timedelta(days=1), duplicate=False)
    cursor = MagicMock()
    cursor.__enter__.return_value = cursor
    cursor.lastrowid = 70

    def fetchone():
        query = cursor.execute.call_args.args[0]
        if 'FROM employee_branch_assignments' in query:
            assert "'BRANCH_STAFF','BRANCH_MANAGER'" in query
            assert 'eba.ended_at IS NULL' in query
            return {'ok': 1} if state['assigned'] else None
        if 'FROM orders' in query:
            return state['order']
        if 'FROM pickups' in query:
            return {'picked_up_at': state['picked']}
        if 'FROM return_requests' in query:
            return {'return_request_id': 1} if state['duplicate'] else None
        raise AssertionError(query)

    cursor.fetchone.side_effect = fetchone
    cursor.fetchall.return_value = [dict(order_item_id=8, product_name='운동화', color_name='BLACK',
        size_mm=260, quantity=2, item_key='5-260-BLACK')]
    connection = MagicMock()
    connection.cursor.return_value = cursor
    @contextmanager
    def database():
        yield connection
    monkeypatch.setattr(staff_returns, 'mysql_connection', database)
    app.dependency_overrides[get_current_employee] = lambda: CurrentEmployee(7, 'uid', 'EMP-7', '직원')
    app.dependency_overrides[get_current_customer] = lambda: CurrentCustomer(12, 'customer-uid', 'customer@example.com')
    yield TestClient(app), state, cursor, connection
    app.dependency_overrides.clear()


def test_staff_return_requires_login():
    assert TestClient(app).get('/staff/returns/order?branchId=3&orderNumber=ORD-10').status_code == 401
    assert TestClient(app).post('/staff/orders/10/returns', json=BODY).status_code == 401


def test_lookup_only_selected_branch_and_preserves_item_quantity(setup_return):
    client, _, cursor, _ = setup_return
    response = client.get('/staff/returns/order?branchId=3&orderNumber=ord-10')
    assert response.status_code == 200
    assert response.json()['items'][0]['quantity'] == 2
    lookup = [call for call in cursor.execute.call_args_list if 'FROM orders' in call.args[0]][0]
    assert lookup.args[1] == ('ORD-10', 3)


def test_registration_uses_order_customer_branch_and_employee_and_does_not_restock(setup_return):
    client, _, cursor, connection = setup_return
    response = client.post('/staff/orders/10/returns', json=BODY)
    assert response.status_code == 201
    assert response.json() == {'id': 70, 'status': 'REQUESTED'}
    insert = [call for call in cursor.execute.call_args_list if 'INSERT INTO return_requests' in call.args[0]][0]
    assert insert.args[1][:4] == (10, 12, 3, 7)
    assert cursor.executemany.call_args.args[1] == [(70, 8, 1)]
    connection.commit.assert_called_once()
    assert not any('UPDATE headquarters_inventory' in call.args[0] for call in cursor.execute.call_args_list)


@pytest.mark.parametrize('condition,status', [('unassigned',403), ('confirmed',409), ('duplicate',409), ('expired',409), ('not_completed',409)])
def test_registration_rejects_invalid_scope_or_order_without_writing(setup_return, condition, status):
    client, state, cursor, connection = setup_return
    if condition == 'unassigned': state['assigned'] = False
    if condition == 'confirmed': state['order']['purchase_confirmed_at'] = datetime.now()
    if condition == 'duplicate': state['duplicate'] = True
    if condition == 'expired': state['picked'] = datetime.now()-timedelta(days=8)
    if condition == 'not_completed': state['order']['order_status'] = 'READY_FOR_PICKUP'
    assert client.post('/staff/orders/10/returns', json=BODY).status_code == status
    connection.commit.assert_not_called()
    cursor.executemany.assert_not_called()


def test_quantity_and_blank_reason_validation(setup_return):
    client, _, _, connection = setup_return
    assert client.post('/staff/orders/10/returns', json={**BODY, 'items': [{'itemKey': '5-260-BLACK', 'quantity': 3}]}).status_code == 422
    assert client.post('/staff/orders/10/returns', json={**BODY, 'reason': '   '}).status_code == 422
    connection.commit.assert_not_called()


def test_defect_exception_can_be_registered_after_seven_days(setup_return):
    client, state, _, _ = setup_return
    state['picked'] = datetime.now()-timedelta(days=8)
    assert client.post('/staff/orders/10/returns', json={**BODY, 'reasonCode': 'PRODUCT_DEFECT', 'unworn': False}).status_code == 201


def test_customer_cannot_register_directly(setup_return):
    client, _, _, connection = setup_return
    assert client.post('/orders/10/returns', json=BODY).status_code == 403
    connection.commit.assert_not_called()
