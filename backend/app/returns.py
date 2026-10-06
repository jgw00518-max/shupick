"""Customer-owned return requests; refund approval remains a staff operation."""
from datetime import datetime, timedelta
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from .auth import CurrentCustomer, CurrentEmployee, get_current_customer, require_permission
from .database import mysql_connection
from .orders import _insert_movement
from .refund_allocation import line_allocations, quantity_share

router = APIRouter(tags=["returns"])

class ReturnSelection(BaseModel):
    itemKey: str = Field(min_length=1, max_length=150)
    quantity: int = Field(gt=0)


class ReturnRequest(BaseModel):
    reason: str = Field(min_length=1, max_length=1000)
    reasonCode: Literal['CUSTOMER_CHANGE','PRODUCT_DEFECT','WRONG_ITEM'] = 'CUSTOMER_CHANGE'
    unworn: bool = False
    undamaged: bool = False
    completePackaging: bool = False
    items: list[ReturnSelection] | None = Field(default=None, min_length=1)


def select_return_items(rows, selections):
    """서버 주문 스냅샷으로 선택 수량과 중복 항목을 검증한다."""
    if selections is None:
        return [(row['order_item_id'], row['quantity']) for row in rows]
    selected = []
    seen = set()
    for selection in selections:
        matches = [row for row in rows if row['item_key'] == selection.itemKey]
        if len(matches) != 1 or selection.itemKey in seen:
            raise HTTPException(422, 'Invalid or duplicate return item')
        row = matches[0]
        if selection.quantity > row['quantity']:
            raise HTTPException(422, 'Return quantity exceeds purchased quantity')
        seen.add(selection.itemKey)
        selected.append((row['order_item_id'], selection.quantity))
    return selected


def validate_return(request: ReturnRequest, picked_up_at: datetime | None):
    if picked_up_at is None:
        raise HTTPException(409, '수령 완료 후 반품을 신청할 수 있습니다.')
    if request.reasonCode == 'CUSTOMER_CHANGE':
        if datetime.now() > picked_up_at + timedelta(days=7):
            raise HTTPException(409, '수령 후 7일의 반품 기간이 지났습니다.')
        if not (request.unworn and request.undamaged and request.completePackaging):
            raise HTTPException(409, '미착용·훼손 없음·구성품 및 포장 유지 조건을 확인해주세요.')


class InspectionRequest(BaseModel):
    accepted: bool
    notes: str = Field(min_length=1, max_length=1000)
    hasWearMarks: bool = False
    hasProductDamage: bool = False
    hasCustomerFault: bool = False
    componentsComplete: bool = True
    packagingIntact: bool = True
    hasProductDefect: bool = False
    isWrongItem: bool = False


def restore_inspected_inventory(connection, return_id: int, request: InspectionRequest):
    """본사 검수 승인 실물만 입고하며, 판매 부적합 상품은 격리한다."""
    if not request.accepted:
        return
    quarantined = (
        request.hasWearMarks or request.hasProductDamage or request.hasCustomerFault
        or not request.componentsComplete or not request.packagingIntact
        or request.hasProductDefect or request.isWrongItem
    )
    with connection.cursor() as cursor:
        cursor.execute("""SELECT oi.product_variant_id,SUM(ri.quantity) AS quantity
            FROM return_items ri JOIN order_items oi ON oi.order_item_id=ri.order_item_id
            WHERE ri.return_request_id=%s GROUP BY oi.product_variant_id
            ORDER BY oi.product_variant_id""", (return_id,))
        items = cursor.fetchall()
        if not items:
            raise HTTPException(409, 'Return items not found')
        for item in items:
            variant_id = int(item['product_variant_id'])
            quantity = int(item['quantity'])
            key = f'return-intake-{return_id}-{variant_id}'
            cursor.execute('SELECT product_variant_id FROM headquarters_inventory WHERE product_variant_id=%s FOR UPDATE', (variant_id,))
            if cursor.fetchone() is None:
                raise HTTPException(409, 'Headquarters inventory not found')
            cursor.execute('SELECT inventory_movement_id FROM inventory_movements WHERE idempotency_key=%s', (key,))
            if cursor.fetchone() is not None:
                continue
            defective_delta = quantity if quarantined else 0
            cursor.execute('UPDATE headquarters_inventory SET on_hand_quantity=on_hand_quantity+%s,defective_quantity=defective_quantity+%s WHERE product_variant_id=%s', (quantity, defective_delta, variant_id))
            _insert_movement(connection, product_variant_id=variant_id,
                movement_type='RETURN_QUARANTINE' if quarantined else 'RETURN_RESTOCK',
                on_hand_delta=quantity, reserved_delta=0, defective_delta=defective_delta,
                reference_type='RETURN', reference_id=return_id, idempotency_key=key,
                reason='본사 반품 검수 승인: 판매 불가 격리' if quarantined else '본사 반품 검수 승인: 판매 재고 복구')


@router.post('/returns/{return_id}/inspection')
def inspect_return(return_id: int, request: InspectionRequest, employee: CurrentEmployee = Depends(require_permission('REFUND_MANAGE'))):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute('SELECT * FROM return_requests WHERE return_request_id=%s FOR UPDATE', (return_id,))
            row = cursor.fetchone()
            if row is None: raise HTTPException(404,'Return not found')
            if row['request_status'] != 'REQUESTED': raise HTTPException(409,'Return already inspected')
            meets_conditions = (not request.hasWearMarks and not request.hasProductDamage and not request.hasCustomerFault and request.componentsComplete and request.packagingIntact)
            if request.accepted and not (meets_conditions or request.hasProductDefect or request.isWrongItem):
                raise HTTPException(409,'Inspection conditions not satisfied')
            decision = 'ACCEPTED' if request.accepted else 'REJECTED'
            restore_inspected_inventory(connection, return_id, request)
            cursor.execute("""INSERT INTO after_sales_inspections
                (return_request_id,inspection_stage,inspected_by_employee_id,has_wear_marks,has_product_damage,has_customer_fault,components_complete,packaging_intact,has_product_defect,is_wrong_item,inspection_decision,inspection_notes)
                VALUES (%s,'HEADQUARTERS',%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                (return_id,employee.employee_id,request.hasWearMarks,request.hasProductDamage,request.hasCustomerFault,request.componentsComplete,request.packagingIntact,request.hasProductDefect,request.isWrongItem,decision,request.notes))
            cursor.execute('UPDATE return_requests SET request_status=%s,inspection_result=%s,handled_by_employee_id=%s,processed_at=NOW(),rejection_reason=%s WHERE return_request_id=%s', ('APPROVED' if request.accepted else 'REJECTED',decision,employee.employee_id,None if request.accepted else request.notes,return_id))
        connection.commit()
        return {'id':return_id,'status':'APPROVED' if request.accepted else 'REJECTED'}


@router.get('/returns')
def list_returns(current: CurrentCustomer = Depends(get_current_customer)):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT rr.return_request_id AS id,rr.order_id AS orderId,rr.request_status AS status,rr.return_reason AS reason,(SELECT COALESCE(SUM(r.refund_amount),0) FROM refunds r WHERE r.return_request_id=rr.return_request_id AND r.refund_status='SUCCEEDED') AS refundAmount FROM return_requests rr WHERE rr.customer_id=%s ORDER BY rr.requested_at DESC", (current.customer_id,))
            return cursor.fetchall()


@router.get('/returns/{return_id}/quote')
def quote_return(return_id: int, current: CurrentCustomer = Depends(get_current_customer)):
    """고객 소유 반품의 결제 스냅샷 기준 예상 환불액을 조회한다."""
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute('SELECT o.order_id,o.coupon_discount,o.points_used FROM return_requests rr JOIN orders o ON o.order_id=rr.order_id WHERE rr.return_request_id=%s AND rr.customer_id=%s', (return_id,current.customer_id))
            order = cursor.fetchone()
            if order is None:
                raise HTTPException(404, 'Return not found')
            cursor.execute('SELECT order_item_id,quantity,unit_price FROM order_items WHERE order_id=%s ORDER BY order_item_id', (order['order_id'],))
            allocations = line_allocations(cursor.fetchall(), int(order['coupon_discount']), int(order['points_used']))
            cursor.execute('SELECT order_item_id,quantity FROM return_items WHERE return_request_id=%s', (return_id,))
            items = []
            for row in cursor.fetchall():
                cash, points, quantity = allocations[row['order_item_id']]
                items.append(dict(orderItemId=row['order_item_id'],quantity=row['quantity'],refundAmount=quantity_share(cash,quantity,0,row['quantity']),allocatedPoints=quantity_share(points,quantity,0,row['quantity'])))
            return dict(items=items,refundAmount=sum(item['refundAmount'] for item in items),allocatedPoints=sum(item['allocatedPoints'] for item in items),pointsNote='만료된 포인트는 복원되지 않습니다.')


@router.post('/orders/{order_id}/returns', status_code=201)
def request_return(order_id: int, request: ReturnRequest, current: CurrentCustomer = Depends(get_current_customer)):
    raise HTTPException(403, '반품은 수령한 대리점에 방문하여 직원에게 접수해주세요.')
