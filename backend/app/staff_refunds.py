"""Server-calculated return refunds for the Flutter test payment flow."""
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from pymysql import MySQLError

from .auth import CurrentEmployee, require_permission
from .database import mysql_connection
from .refund_allocation import line_allocations, quantity_share
from .refunds import create_refund, complete_refund, _refund_response
from .schemas import RefundCreateRequest, RefundCompleteRequest, RefundItemRequest

router = APIRouter(prefix='/staff/returns', tags=['staff return refunds'])
refund_employee = require_permission('REFUND_MANAGE')


class TestRefundConfirmation(BaseModel):
    confirmTest: Literal[True]
    expectedRefundAmount: int = Field(ge=0)


def load_return_refund(return_id: int):
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute('''SELECT rr.return_request_id,rr.order_id,rr.request_status,rr.inspection_result,
                    o.order_number,o.coupon_discount,o.points_used,o.purchase_confirmed_at,c.customer_name
                    FROM return_requests rr JOIN orders o ON o.order_id=rr.order_id
                    JOIN customers c ON c.customer_id=rr.customer_id WHERE rr.return_request_id=%s''', (return_id,))
                returned = cursor.fetchone()
                if returned is None:
                    raise HTTPException(404, '반품 요청을 찾지 못했습니다.')
                if returned['request_status'] not in ('APPROVED', 'COMPLETED') or returned['inspection_result'] != 'ACCEPTED':
                    raise HTTPException(409, '본사 검수에서 승인된 반품만 환불할 수 있습니다.')
                if returned['purchase_confirmed_at'] is not None:
                    raise HTTPException(409, '구매확정된 주문은 환불할 수 없습니다.')
                cursor.execute("""SELECT payment_id,payment_status,payment_method,transaction_key FROM payments
                    WHERE order_id=%s AND payment_status IN ('PAID','PARTIALLY_REFUNDED','REFUNDED')
                    ORDER BY payment_id DESC LIMIT 1""", (returned['order_id'],))
                payment = cursor.fetchone()
                if payment is None:
                    raise HTTPException(409, '환불할 결제 내역이 없습니다.')
                cursor.execute('''SELECT order_item_id,quantity,unit_price,product_name,color_name,size_mm
                    FROM order_items WHERE order_id=%s ORDER BY order_item_id''', (returned['order_id'],))
                purchased = cursor.fetchall()
                allocations = line_allocations(purchased, int(returned['coupon_discount']), int(returned['points_used']))
                by_id = {item['order_item_id']: item for item in purchased}
                cursor.execute('SELECT order_item_id,quantity FROM return_items WHERE return_request_id=%s ORDER BY order_item_id', (return_id,))
                selections = cursor.fetchall()
                if not selections:
                    raise HTTPException(409, '검수된 반품 상품 내역이 없습니다.')
                items = []
                for selected in selections:
                    original = by_id.get(selected['order_item_id'])
                    if original is None or not 0 < int(selected['quantity']) <= int(original['quantity']):
                        raise HTTPException(409, '반품 상품 수량을 확인해주세요.')
                    cash, points, quantity = allocations[selected['order_item_id']]
                    count = int(selected['quantity'])
                    items.append(dict(orderItemId=selected['order_item_id'], name=original['product_name'],
                        color=original['color_name'], size=original['size_mm'], quantity=count,
                        refundAmount=quantity_share(cash, quantity, 0, count),
                        allocatedPoints=quantity_share(points, quantity, 0, count)))
                cursor.execute("""SELECT * FROM refunds WHERE return_request_id=%s AND refund_type='RETURN'
                    AND refund_status<>'CANCELED' ORDER BY refund_id DESC LIMIT 1""", (return_id,))
                existing = cursor.fetchone()
        return dict(returnId=return_id, orderId=returned['order_id'], orderNumber=returned['order_number'],
            customerName=returned['customer_name'], returnStatus=returned['request_status'],
            paymentId=payment['payment_id'], paymentMethod=payment['payment_method'],
            testPayment=str(payment['transaction_key']).startswith('flutter-payment-'),
            items=items, refundAmount=sum(item['refundAmount'] for item in items),
            allocatedPoints=sum(item['allocatedPoints'] for item in items),
            refund=_refund_response(existing).model_dump() if existing else None)
    except MySQLError as error:
        raise HTTPException(503, 'Database unavailable') from error


@router.get('/{return_id}/refund')
def return_refund_details(return_id: int, _: CurrentEmployee = Depends(refund_employee)):
    return load_return_refund(return_id)


@router.post('/{return_id}/refund/test', description='Complete only Flutter-generated test payments; no payment provider is called.')
def execute_test_return_refund(return_id: int, confirmation: TestRefundConfirmation,
                               employee: CurrentEmployee = Depends(refund_employee)):
    plan = load_return_refund(return_id)
    if confirmation.expectedRefundAmount != plan['refundAmount']:
        raise HTTPException(409, '환불 금액이 변경되었습니다. 내역을 다시 조회해주세요.')
    if not plan['testPayment']:
        raise HTTPException(409, '이 결제는 테스트 환불 대상이 아닙니다. 결제사 환불 연동이 필요합니다.')
    existing = plan['refund']
    if existing and existing['refundStatus'] == 'SUCCEEDED':
        return existing
    if plan['returnStatus'] != 'APPROVED':
        raise HTTPException(409, '환불 가능한 승인 상태가 아닙니다.')
    if existing:
        if existing['refundAmount'] != plan['refundAmount'] or existing['paymentId'] != plan['paymentId']:
            raise HTTPException(409, '기존 환불 내역과 계산 금액이 다릅니다. 관리자 확인이 필요합니다.')
        refund_id = existing['refundId']
    else:
        request = RefundCreateRequest(paymentId=plan['paymentId'], returnRequestId=return_id,
            refundType='RETURN', refundAmount=plan['refundAmount'], idempotencyKey=f'staff-return-refund-{return_id}',
            items=[RefundItemRequest(orderItemId=item['orderItemId'], quantity=item['quantity'], refundAmount=item['refundAmount'])
                   for item in plan['items']])
        refund = create_refund(request, employee)
        if refund.refundStatus == 'CANCELED':
            raise HTTPException(409, '취소된 환불 기록이 있습니다. 관리자 확인이 필요합니다.')
        refund_id = refund.refundId
    return complete_refund(refund_id, RefundCompleteRequest(providerRefundKey=f'TEST-RETURN-{return_id}-{refund_id}'), employee)
