"""Returns registered in person by an employee of the pickup branch."""
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import Field, field_validator
from pymysql import MySQLError

from .auth import CurrentEmployee, get_current_employee
from .database import mysql_connection
from .returns import ReturnRequest, ReturnSelection, select_return_items, validate_return

router = APIRouter(prefix='/staff', tags=['staff returns'])


class StaffReturnRequest(ReturnRequest):
    items: list[ReturnSelection] = Field(min_length=1)

    @field_validator('reason')
    @classmethod
    def meaningful_reason(cls, value):
        if not value.strip():
            raise ValueError('반품 사유를 입력해주세요.')
        return value.strip()


def require_return_branch(cursor, employee_id: int, branch_id: int):
    cursor.execute('''SELECT 1 FROM employee_branch_assignments eba
        JOIN branches b ON b.branch_id=eba.branch_id AND b.is_active=TRUE
        WHERE eba.employee_id=%s AND eba.branch_id=%s AND eba.ended_at IS NULL
          AND EXISTS (SELECT 1 FROM employee_roles er JOIN roles r ON r.role_id=er.role_id
            WHERE er.employee_id=eba.employee_id AND r.is_active=TRUE
              AND r.role_code IN ('BRANCH_STAFF','BRANCH_MANAGER')) LIMIT 1''',
        (employee_id, branch_id))
    if cursor.fetchone() is None:
        raise HTTPException(403, '소속 대리점 직원 또는 점장만 반품을 접수할 수 있습니다.')


def check_return_order(cursor, order):
    if order['order_status'] != 'COMPLETED':
        raise HTTPException(409, '수령 완료된 주문만 반품할 수 있습니다.')
    if order['purchase_confirmed_at'] is not None:
        raise HTTPException(409, '구매확정된 주문은 반품할 수 없습니다.')
    cursor.execute('SELECT picked_up_at FROM pickups WHERE order_id=%s', (order['order_id'],))
    pickup = cursor.fetchone()
    if pickup is None or pickup['picked_up_at'] is None:
        raise HTTPException(409, '상품 수령 기록이 없습니다.')
    cursor.execute("SELECT return_request_id FROM return_requests WHERE order_id=%s AND request_status NOT IN ('REJECTED','CANCELED')", (order['order_id'],))
    if cursor.fetchone() is not None:
        raise HTTPException(409, '이미 접수된 반품이 있습니다. 기존 반품 현황을 확인해주세요.')
    return pickup['picked_up_at']


def return_order_items(cursor, order_id):
    cursor.execute('''SELECT oi.order_item_id,oi.product_name,oi.color_name,oi.size_mm,oi.quantity,
        CONCAT(v.product_id,'-',oi.size_mm,'-',oi.color_name) AS item_key
        FROM order_items oi JOIN product_variants v ON v.product_variant_id=oi.product_variant_id
        WHERE oi.order_id=%s ORDER BY oi.order_item_id''', (order_id,))
    return cursor.fetchall()


@router.get('/returns/order')
def lookup_return_order(
    branch_id: int = Query(alias='branchId', gt=0),
    order_number: str = Query(alias='orderNumber', min_length=1, max_length=100),
    employee: CurrentEmployee = Depends(get_current_employee),
):
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                require_return_branch(cursor, employee.employee_id, branch_id)
                cursor.execute('''SELECT o.order_id,o.order_number,o.order_status,o.purchase_confirmed_at,
                    o.customer_id,o.pickup_branch_id,c.customer_name,b.branch_name
                    FROM orders o JOIN customers c ON c.customer_id=o.customer_id
                    JOIN branches b ON b.branch_id=o.pickup_branch_id
                    WHERE o.order_number=%s AND o.pickup_branch_id=%s''',
                    (order_number.strip().upper(), branch_id))
                order = cursor.fetchone()
                if order is None:
                    raise HTTPException(404, '해당 지점의 주문을 찾지 못했습니다. 주문번호를 확인해주세요.')
                picked_up_at = check_return_order(cursor, order)
                items = return_order_items(cursor, order['order_id'])
        return dict(orderId=order['order_id'], orderNumber=order['order_number'],
            customerName=order['customer_name'], branchName=order['branch_name'],
            pickedUpAt=picked_up_at.isoformat(), returnDeadlineAt=(picked_up_at+timedelta(days=7)).isoformat(),
            items=[dict(itemKey=item['item_key'], name=item['product_name'],
                color=item['color_name'], size=item['size_mm'], quantity=item['quantity']) for item in items])
    except MySQLError as error:
        raise HTTPException(503, 'Database unavailable') from error


@router.post('/orders/{order_id}/returns', status_code=201)
def register_branch_return(order_id: int, request: StaffReturnRequest,
                           employee: CurrentEmployee = Depends(get_current_employee)):
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute('SELECT * FROM orders WHERE order_id=%s FOR UPDATE', (order_id,))
                order = cursor.fetchone()
                if order is None:
                    raise HTTPException(404, '주문을 찾지 못했습니다.')
                require_return_branch(cursor, employee.employee_id, order['pickup_branch_id'])
                picked_up_at = check_return_order(cursor, order)
                validate_return(request, picked_up_at)
                selected = select_return_items(return_order_items(cursor, order_id), request.items)
                cursor.execute('''INSERT INTO return_requests
                    (order_id,customer_id,branch_id,handled_by_employee_id,return_reason,return_reason_code,return_deadline_at)
                    VALUES (%s,%s,%s,%s,%s,%s,%s)''',
                    (order_id,order['customer_id'],order['pickup_branch_id'],employee.employee_id,
                     request.reason.strip(),request.reasonCode,picked_up_at+timedelta(days=7)))
                identifier = cursor.lastrowid
                cursor.executemany('INSERT INTO return_items (return_request_id,order_item_id,quantity) VALUES (%s,%s,%s)',
                    [(identifier,item_id,quantity) for item_id,quantity in selected])
            connection.commit()
        return dict(id=identifier, status='REQUESTED')
    except MySQLError as error:
        raise HTTPException(503, 'Database unavailable') from error
