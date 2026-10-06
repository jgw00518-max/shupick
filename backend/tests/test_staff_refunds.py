from contextlib import contextmanager
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app import staff_refunds
from app.auth import CurrentEmployee
from app.main import app
from app.schemas import RefundResponse

EMPLOYEE = CurrentEmployee(7, 'uid', 'EMP-7', '본사 직원')


def result(status='SUCCEEDED'):
    return RefundResponse(refundId=70, refundNumber='RF-70', paymentId=1, orderId=10,
        refundType='RETURN', refundStatus=status, refundAmount=75, retryCount=0)


def plan():
    return dict(returnId=3, orderId=10, orderNumber='ORD-10', customerName='고객', returnStatus='APPROVED',
        paymentId=1, paymentMethod='CARD', testPayment=True, refundAmount=75, allocatedPoints=25, refund=None,
        items=[dict(orderItemId=8, name='운동화', color='BLACK', size=260, quantity=1, refundAmount=75, allocatedPoints=25)])


def test_refund_routes_require_login():
    assert TestClient(app).get('/staff/returns/3/refund').status_code == 401
    assert TestClient(app).post('/staff/returns/3/refund/test', json={'confirmTest': True, 'expectedRefundAmount':75}).status_code == 401


def test_quote_allocates_discount_points_and_partial_quantity_on_server(monkeypatch):
    cursor = MagicMock()
    cursor.__enter__.return_value = cursor
    cursor.fetchone.side_effect = [
        dict(return_request_id=3,order_id=10,request_status='APPROVED',inspection_result='ACCEPTED',
            order_number='ORD-10',customer_name='고객',coupon_discount=100,points_used=50,purchase_confirmed_at=None),
        dict(payment_id=1,payment_status='PAID',payment_method='CARD',transaction_key='flutter-payment-123-456'), None,
    ]
    cursor.fetchall.side_effect = [
        [dict(order_item_id=8,quantity=2,unit_price=150,product_name='운동화',color_name='BLACK',size_mm=260)],
        [dict(order_item_id=8,quantity=1)],
    ]
    connection = MagicMock()
    connection.cursor.return_value = cursor
    @contextmanager
    def database(): yield connection
    monkeypatch.setattr(staff_refunds, 'mysql_connection', database)
    quote = staff_refunds.load_return_refund(3)
    assert quote['refundAmount'] == 75
    assert quote['allocatedPoints'] == 25
    assert quote['testPayment'] is True
    connection.commit.assert_not_called()


def test_process_creates_server_amount_with_stable_key_and_completes(monkeypatch):
    monkeypatch.setattr(staff_refunds, 'load_return_refund', lambda _: plan())
    create = MagicMock(return_value=result('REQUESTED'))
    complete = MagicMock(return_value=result())
    monkeypatch.setattr(staff_refunds, 'create_refund', create)
    monkeypatch.setattr(staff_refunds, 'complete_refund', complete)
    response = staff_refunds.execute_test_return_refund(3, staff_refunds.TestRefundConfirmation(confirmTest=True, expectedRefundAmount=75), EMPLOYEE)
    request = create.call_args.args[0]
    assert request.paymentId == 1 and request.refundAmount == 75
    assert request.returnRequestId == 3 and request.idempotencyKey == 'staff-return-refund-3'
    assert request.items[0].quantity == 1
    assert complete.call_args.args[1].providerRefundKey == 'TEST-RETURN-3-70'
    assert response.refundStatus == 'SUCCEEDED'


@pytest.mark.parametrize('change', ['real_payment', 'unapproved', 'changed_amount'])
def test_invalid_test_refunds_do_not_mutate(monkeypatch, change):
    quote = plan()
    if change == 'real_payment': quote['testPayment'] = False
    if change == 'unapproved': quote['returnStatus'] = 'REQUESTED'
    if change == 'changed_amount': quote['refundAmount'] = 999
    monkeypatch.setattr(staff_refunds, 'load_return_refund', lambda _: quote)
    create = MagicMock(); complete = MagicMock()
    monkeypatch.setattr(staff_refunds, 'create_refund', create)
    monkeypatch.setattr(staff_refunds, 'complete_refund', complete)
    with pytest.raises(HTTPException) as error:
        staff_refunds.execute_test_return_refund(3, staff_refunds.TestRefundConfirmation(confirmTest=True, expectedRefundAmount=75), EMPLOYEE)
    assert error.value.status_code == 409
    create.assert_not_called(); complete.assert_not_called()


@pytest.mark.parametrize('status', ['SUCCEEDED', 'FAILED', 'REQUESTED'])
def test_repeated_or_failed_request_reuses_existing_refund(monkeypatch, status):
    quote = plan(); quote['refund'] = result(status).model_dump()
    if status == 'SUCCEEDED': quote['returnStatus'] = 'COMPLETED'
    monkeypatch.setattr(staff_refunds, 'load_return_refund', lambda _: quote)
    create = MagicMock(); complete = MagicMock(return_value=result())
    monkeypatch.setattr(staff_refunds, 'create_refund', create)
    monkeypatch.setattr(staff_refunds, 'complete_refund', complete)
    staff_refunds.execute_test_return_refund(3, staff_refunds.TestRefundConfirmation(confirmTest=True, expectedRefundAmount=75), EMPLOYEE)
    create.assert_not_called()
    if status == 'SUCCEEDED': complete.assert_not_called()
    else: assert complete.call_args.args[0] == 70


def test_api_requires_confirmation_and_expected_amount(monkeypatch):
    app.dependency_overrides[staff_refunds.refund_employee] = lambda: EMPLOYEE
    try:
        assert TestClient(app).post('/staff/returns/3/refund/test', json={'confirmTest':False,'expectedRefundAmount':75}).status_code == 422
        assert TestClient(app).post('/staff/returns/3/refund/test', json={'confirmTest':True}).status_code == 422
    finally: app.dependency_overrides.clear()
