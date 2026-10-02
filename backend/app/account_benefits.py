"""Customer benefit summaries and explicit purchase confirmation."""
from fastapi import APIRouter,Depends,HTTPException
from .auth import CurrentCustomer,get_current_customer
from .database import mysql_connection
from .points import get_wallet
from .checkout_benefits import list_coupons
router=APIRouter(tags=['account-benefits'])

@router.get('/account/benefits')
def account_benefits(customer:CurrentCustomer=Depends(get_current_customer)):
    wallet=get_wallet(customer)
    coupons=list_coupons(customer)
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute('''SELECT t.tier_name,a.net_purchase_amount,a.benefit_month FROM membership_assessments a
                JOIN membership_tiers t ON t.membership_tier_id=a.membership_tier_id
                WHERE a.customer_id=%s AND a.benefit_month=DATE_SUB(CURDATE(),INTERVAL DAYOFMONTH(CURDATE())-1 DAY)''',(customer.customer_id,))
            membership=cursor.fetchone()
            cursor.execute('SELECT transaction_type,point_amount,balance_after,description,created_at FROM point_transactions WHERE customer_id=%s ORDER BY created_at DESC,point_transaction_id DESC LIMIT 100',(customer.customer_id,))
            history=cursor.fetchall()
    return {'membership':membership,'coupons':coupons,'wallet':wallet.model_dump(),'pointHistory':history}

@router.post('/orders/{order_id}/confirm')
def confirm_order(order_id:int,customer:CurrentCustomer=Depends(get_current_customer)):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute('SELECT order_status,purchase_confirmed_at FROM orders WHERE order_id=%s AND customer_id=%s FOR UPDATE',(order_id,customer.customer_id))
            order=cursor.fetchone()
            if order is None:raise HTTPException(404,'Order not found')
            if order['purchase_confirmed_at'] is not None:return {'confirmed':True}
            if order['order_status']!='COMPLETED':raise HTTPException(409,'수령 완료 후 구매확정할 수 있습니다.')
            cursor.execute("SELECT return_request_id FROM return_requests WHERE order_id=%s AND request_status NOT IN ('REJECTED','CANCELED')",(order_id,))
            if cursor.fetchone() is not None:raise HTTPException(409,'반품 진행 중인 주문은 구매확정할 수 없습니다.')
            cursor.execute("SELECT refund_id FROM refunds WHERE order_id=%s AND refund_status<>'CANCELED'", (order_id,))
            if cursor.fetchone() is not None:raise HTTPException(409,'환불 이력이 있는 주문은 구매확정할 수 없습니다.')
            cursor.execute('UPDATE orders SET purchase_confirmed_at=NOW() WHERE order_id=%s',(order_id,))
        connection.commit()
        return {'confirmed':True}
