"""Local MySQL integration check; all fixture changes are rolled back."""
from contextlib import contextmanager
from unittest.mock import patch
from uuid import uuid4
from fastapi.testclient import TestClient
from app.auth import CurrentCustomer, get_current_customer
from app.database import mysql_connection
from app.main import app
from app.refunds import create_refund, complete_refund
from app.schemas import RefundCreateRequest, RefundCompleteRequest
from app.returns import inspect_return, InspectionRequest, restore_inspected_inventory
from app.auth import CurrentEmployee
from app.orders import ship_fulfillment
from app.pickup_tracking import arrive, complete_pickup, PickupConfirmation
from app.support import answer_inquiry,AnswerRequest
from app.scheduled_jobs import release_expired_orders
from datetime import datetime,timedelta


def run(zero_cash=False):
    with mysql_connection() as connection:
        class Transaction:
            def cursor(self): return connection.cursor()
            def commit(self): pass
            def rollback(self): pass
        @contextmanager
        def transaction(): yield Transaction()
        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT customer_id FROM customers LIMIT 1")
                customer_id = cursor.fetchone()['customer_id']
                cursor.execute("SELECT branch_id FROM branches WHERE is_active=TRUE LIMIT 1")
                branch_id = cursor.fetchone()['branch_id']
                cursor.execute("SELECT product_variant_id FROM headquarters_inventory WHERE available_quantity>0 LIMIT 1")
                variant_id = cursor.fetchone()['product_variant_id']
                cursor.execute("SELECT coupon_definition_id FROM coupon_definitions WHERE is_active=TRUE AND discount_type='PERCENT' LIMIT 1")
                definition = cursor.fetchone()['coupon_definition_id']
                cursor.execute("INSERT INTO customer_coupons (customer_id,coupon_definition_id,benefit_month,issue_sequence,expires_at) VALUES (%s,%s,DATE_SUB(CURDATE(),INTERVAL DAYOFMONTH(CURDATE())-1 DAY),250,DATE_ADD(NOW(),INTERVAL 1 DAY))", (customer_id, definition))
                coupon_id = cursor.lastrowid
                cursor.execute("INSERT INTO point_wallets (customer_id,point_balance) VALUES (%s,0) ON DUPLICATE KEY UPDATE point_balance=point_balance", (customer_id,))
                cursor.execute("UPDATE point_wallets SET point_balance=point_balance+1000 WHERE customer_id=%s", (customer_id,))
                cursor.execute("SELECT point_balance FROM point_wallets WHERE customer_id=%s", (customer_id,))
                before = cursor.fetchone()['point_balance']
                cursor.execute("INSERT INTO point_transactions (customer_id,transaction_type,point_amount,balance_after,idempotency_key,expires_at) VALUES (%s,'EARN',1000,%s,%s,DATE_ADD(NOW(),INTERVAL 1 YEAR))", (customer_id,before,str(uuid4())))
                source = cursor.lastrowid
                cursor.execute("INSERT INTO point_lots (customer_id,source_transaction_id,original_amount,remaining_amount,earned_at,expires_at) VALUES (%s,%s,1000,1000,NOW(),DATE_ADD(NOW(),INTERVAL 1 YEAR))", (customer_id, source))
            app.dependency_overrides[get_current_customer] = lambda: CurrentCustomer(customer_id,'test','test')
            with patch('app.orders.mysql_connection', transaction), patch('app.checkout_benefits.mysql_connection', transaction), patch('app.points.mysql_connection', transaction):
                client = TestClient(app)
                assert client.get('/coupons').status_code == 200
                assert client.get('/points/wallet').status_code == 200
                reserved = client.post('/orders/reserve', json={'pickupBranchId':branch_id,'idempotencyKey':str(uuid4()),'items':[{'productVariantId':variant_id,'quantity':1}]})
                assert reserved.status_code == 201, reserved.text
                order_id = reserved.json()['orderId']
                payload = dict(paymentMethod='CARD',transactionKey=str(uuid4()),customerCouponId=coupon_id,pointsUsed=500)
                paid = client.post(f'/orders/{order_id}/payments/complete',json=payload)
                assert paid.status_code == 200, paid.text
                assert paid.json()['couponDiscount'] > 0
                assert paid.json()['pointsUsed'] == 500
                assert client.post(f'/orders/{order_id}/payments/complete',json=payload).status_code == 200
                with connection.cursor() as cursor:
                    cursor.execute("SELECT point_balance FROM point_wallets WHERE customer_id=%s", (customer_id,))
                    assert cursor.fetchone()['point_balance'] == before-500
                    cursor.execute("SELECT coupon_status,used_order_id FROM customer_coupons WHERE customer_coupon_id=%s", (coupon_id,))
                    coupon = cursor.fetchone()
                    assert coupon['coupon_status']=='USED' and coupon['used_order_id']==order_id
                print('coupon_query+wallet+demo_payment+ledger+idempotent_retry=ok')
                pending=client.post('/orders/reserve',json={'pickupBranchId':branch_id,'idempotencyKey':str(uuid4()),'items':[{'productVariantId':variant_id,'quantity':1}]})
                assert pending.status_code==201,pending.text
                expired_count=release_expired_orders(connection,datetime.now()+timedelta(minutes=16))
                assert expired_count>=1
                with connection.cursor() as cursor:
                    cursor.execute('SELECT order_status FROM orders WHERE order_id=%s',(pending.json()['orderId'],))
                    assert cursor.fetchone()['order_status']=='CANCELED'
                    cursor.execute('SELECT reservation_status FROM inventory_reservations WHERE order_id=%s',(pending.json()['orderId'],))
                    assert cursor.fetchone()['reservation_status']=='EXPIRED'
                print('unpaid_reservation_expiration=ok; paid_order_preserved=ok')
                with patch('app.support.mysql_connection',transaction):
                    created=client.post('/inquiries',json={'kind':'PRODUCT','title':'Test inquiry','body':'Test content'})
                    assert created.status_code==201,created.text
                    with connection.cursor() as cursor:
                        cursor.execute('SELECT employee_id FROM employees LIMIT 1')
                        support_employee=CurrentEmployee(cursor.fetchone()['employee_id'],'test','test','test')
                        cursor.execute("SELECT CONCAT(product_id,':',color_name,':',size_mm) AS subscription_key FROM product_variants WHERE product_variant_id=%s",(variant_id,))
                        subscription_key=cursor.fetchone()['subscription_key']
                    answer_inquiry(created.json()['id'],AnswerRequest(answer='Test answer'),support_employee)
                    assert any(row['id']==created.json()['id'] and row['answer']=='Test answer' for row in client.get('/inquiries').json())
                    assert client.put('/restock-subscriptions',json={'keys':[subscription_key]}).status_code==200
                    assert subscription_key in client.get('/restock-subscriptions').json()
                    assert client.put('/restock-subscriptions',json={'keys':[]}).status_code==200
                    assert client.get('/restock-subscriptions').json()==[]
                    print('inquiry_create+answer+restock_subscribe+unsubscribe=ok')
                with patch('app.interactions.mysql_connection',transaction):
                    event=dict(eventKey=str(uuid4()),sessionKey='test-session',productId=1,eventType='VIEW',occurredAt='2026-10-03T00:00:00Z')
                    with connection.cursor() as cursor:
                        cursor.execute('SELECT product_id FROM product_variants WHERE product_variant_id=%s',(variant_id,))
                        event['productId']=cursor.fetchone()['product_id']
                    response=client.post('/interactions',json=event)
                    assert response.status_code==201,response.text
                    repeated=client.post('/interactions',json=event)
                    assert repeated.status_code==201 and repeated.json()['duplicate']
                    event['eventType']='WISH_ADD'
                    assert client.post('/interactions',json=event).status_code==409
                    print('interaction_insert+retry_dedup+payload_guard=ok')
                with connection.cursor() as cursor:
                    cursor.execute('SELECT employee_id FROM employees LIMIT 1')
                    tracking_employee = CurrentEmployee(cursor.fetchone()['employee_id'],'test','test','test')
                with patch('app.pickup_tracking.mysql_connection',transaction):
                    ship_fulfillment(paid.json()['fulfillmentId'],tracking_employee)
                    arrive(paid.json()['fulfillmentId'],tracking_employee)
                    tracked = client.get(f'/orders/{order_id}/tracking')
                    assert tracked.status_code==200, tracked.text
                    assert tracked.json()['order_status']=='READY_FOR_PICKUP'
                    assert tracked.json()['pickup_deadline_at'] is not None
                    complete_pickup(order_id,PickupConfirmation(paymentCode=paid.json()['orderNumber']),tracking_employee)
                    complete_pickup(order_id,PickupConfirmation(paymentCode=paid.json()['orderNumber']),tracking_employee)
                    assert client.get(f'/orders/{order_id}/tracking').json()['order_status']=='COMPLETED'
                    print('shipment+arrival+tracking+pickup+retry=ok')
                with patch('app.account_benefits.mysql_connection',transaction):
                    with connection.cursor() as cursor:
                        cursor.execute("SELECT CONCAT(v.product_id,'-',oi.size_mm,'-',oi.color_name) AS item_key FROM order_items oi JOIN product_variants v ON v.product_variant_id=oi.product_variant_id WHERE oi.order_id=%s LIMIT 1", (order_id,))
                        unconfirmed_key=cursor.fetchone()['item_key']
                    with patch('app.reviews.mysql_connection',transaction):
                        assert client.post('/reviews',json=dict(orderNumber=paid.json()['orderNumber'],itemKey=unconfirmed_key,rating=5,content='Before confirmation')).status_code==409
                    assert client.post('/points/credit',json={}).status_code==404
                    dashboard=client.get('/account/benefits')
                    assert dashboard.status_code==200,dashboard.text
                    assert dashboard.json()['wallet']['balance']==before-500
                    assert client.post(f'/orders/{order_id}/confirm').status_code==200
                    with connection.cursor() as cursor:
                        cursor.execute('SELECT purchase_confirmed_at FROM orders WHERE order_id=%s',(order_id,))
                        confirmed_at=cursor.fetchone()['purchase_confirmed_at']
                    assert confirmed_at is not None
                    assert client.post(f'/orders/{order_id}/confirm').status_code==200
                    with connection.cursor() as cursor:
                        cursor.execute('SELECT purchase_confirmed_at FROM orders WHERE order_id=%s',(order_id,))
                        assert cursor.fetchone()['purchase_confirmed_at']==confirmed_at
                    print('benefits_dashboard+purchase_confirmation+retry=ok')
                with patch('app.reviews.mysql_connection',transaction):
                    with connection.cursor() as cursor:
                        cursor.execute("SELECT CONCAT(v.product_id,'-',oi.size_mm,'-',oi.color_name) AS item_key FROM order_items oi JOIN product_variants v ON v.product_variant_id=oi.product_variant_id WHERE oi.order_id=%s LIMIT 1",(order_id,))
                        item_key=cursor.fetchone()['item_key']
                    review=dict(orderNumber=paid.json()['orderNumber'],itemKey=item_key,rating=5,content='Integration review')
                    assert client.post('/reviews',json=review).status_code==201
                    product_id=int(item_key.split('-')[0])
                    public=client.get(f'/reviews/products/{product_id}').json()
                    assert any(row['content']=='Integration review' for row in public['items'])
                    assert all('customer_id' not in row and 'orderNumber' not in row and 'itemKey' not in row for row in public['items'])
                    assert client.post('/reviews',json=review).status_code==409
                    review['rating']=4
                    assert client.put('/reviews',json=review).status_code==200
                    assert any(r['rating']==4 and r['orderNumber']==review['orderNumber'] for r in client.get('/reviews').json())
                    assert client.request('DELETE','/reviews',json={'orderNumber':review['orderNumber'],'itemKey':item_key}).status_code==200
                    public=client.get(f'/reviews/products/{product_id}').json()
                    assert all(row['content']!='Integration review' for row in public['items'])
                    assert all(r['orderNumber']!=review['orderNumber'] for r in client.get('/reviews').json())
                    assert client.post('/reviews',json=review).status_code==201
                    print('review_create+duplicate_guard+update+delete+recreate=ok')
                with patch('app.refunds.mysql_connection', transaction):
                    from fastapi import HTTPException
                    try:
                        create_refund(RefundCreateRequest(paymentId=paid.json()['paymentId'],refundType='ORDER_CANCEL',refundAmount=paid.json()['paidTotal'],idempotencyKey=str(uuid4())))
                        raise AssertionError('Confirmed order refund must be rejected')
                    except HTTPException as error:
                        assert error.status_code==409
                    with connection.cursor() as cursor:
                        cursor.execute('SELECT point_balance FROM point_wallets WHERE customer_id=%s',(customer_id,))
                        assert cursor.fetchone()['point_balance']==before-500+1000
                        cursor.execute('SELECT coupon_status FROM customer_coupons WHERE customer_coupon_id=%s',(coupon_id,))
                        assert cursor.fetchone()['coupon_status']=='USED'
                    with patch('app.returns.mysql_connection',transaction):
                        assert client.post(f'/orders/{order_id}/returns',json=dict(reason='반품',unworn=True,undamaged=True,completePackaging=True)).status_code==409
                    print('review_reward_once+confirmed_return_and_refund_block=ok')
                new_order=client.post('/orders/reserve',json={'pickupBranchId':branch_id,'idempotencyKey':str(uuid4()),'items':[{'productVariantId':variant_id,'quantity':2}]})
                assert new_order.status_code==201,new_order.text
                order_id=new_order.json()['orderId']
                if zero_cash:
                    with connection.cursor() as cursor:
                        cursor.execute('UPDATE order_items SET unit_price=1000 WHERE order_id=%s',(order_id,))
                        cursor.execute('UPDATE orders SET subtotal_amount=2000,paid_total=2000 WHERE order_id=%s',(order_id,))
                payment=client.post(f'/orders/{order_id}/payments/complete',json={'paymentMethod':'CARD','transactionKey':str(uuid4()),'pointsUsed':2000})
                assert payment.status_code==200,payment.text
                with patch('app.pickup_tracking.mysql_connection',transaction):
                    ship_fulfillment(payment.json()['fulfillmentId'],tracking_employee)
                    arrive(payment.json()['fulfillmentId'],tracking_employee)
                    complete_pickup(order_id,PickupConfirmation(paymentCode=payment.json()['orderNumber']),tracking_employee)
                with patch('app.returns.mysql_connection',transaction),patch('app.refunds.mysql_connection',transaction):
                    with connection.cursor() as cursor:
                        cursor.execute("SELECT CONCAT(v.product_id,'-',oi.size_mm,'-',oi.color_name) AS item_key FROM order_items oi JOIN product_variants v ON v.product_variant_id=oi.product_variant_id WHERE oi.order_id=%s",(order_id,))
                        item_key=cursor.fetchone()['item_key']
                        cursor.execute('SELECT point_balance FROM point_wallets WHERE customer_id=%s',(customer_id,))
                        point_before_partial=cursor.fetchone()['point_balance']
                    returned = client.post(f'/orders/{order_id}/returns',json=dict(reason='테스트',unworn=True,undamaged=True,completePackaging=True,items=[dict(itemKey=item_key,quantity=1)]))
                    assert returned.status_code==201, returned.text
                    quote=client.get(f"/returns/{returned.json()['id']}/quote")
                    assert quote.status_code==200,quote.text
                    assert quote.json()['refundAmount']==payment.json()['paidTotal']//2
                    assert quote.json()['allocatedPoints']==1000
                    assert client.get('/returns').status_code==200
                    assert client.post(f'/orders/{order_id}/returns',json=dict(reason='테스트',unworn=True,undamaged=True,completePackaging=True)).status_code==409
                    with connection.cursor() as cursor:
                        cursor.execute('SELECT * FROM headquarters_inventory WHERE product_variant_id=%s',(variant_id,))
                        inventory_before=cursor.fetchone()
                    inspection=InspectionRequest(accepted=True,notes='시연 검수')
                    inspect_return(returned.json()['id'],inspection,tracking_employee)
                    restore_inspected_inventory(connection,returned.json()['id'],inspection)
                    with connection.cursor() as cursor:
                        cursor.execute('SELECT order_item_id,quantity FROM order_items WHERE order_id=%s',(order_id,))
                        item=cursor.fetchone()
                        item['quantity']=1
                    partial_amount=payment.json()['paidTotal']//2
                    refund=create_refund(RefundCreateRequest(paymentId=payment.json()['paymentId'],returnRequestId=returned.json()['id'],refundType='RETURN',refundAmount=partial_amount,idempotencyKey=str(uuid4()),items=[{'orderItemId':item['order_item_id'],'quantity':item['quantity'],'refundAmount':partial_amount}]))
                    complete_refund(refund.refundId,RefundCompleteRequest(providerRefundKey=str(uuid4())))
                    complete_refund(refund.refundId,RefundCompleteRequest(providerRefundKey=str(uuid4())))
                    with connection.cursor() as cursor:
                        cursor.execute('SELECT points_used FROM orders WHERE order_id=%s',(order_id,))
                        used_points=cursor.fetchone()['points_used']
                        assert used_points==2000
                        cursor.execute('SELECT point_balance FROM point_wallets WHERE customer_id=%s',(customer_id,))
                        assert cursor.fetchone()['point_balance']==point_before_partial+1000
                        if zero_cash:
                            cursor.execute('SELECT payment_status FROM payments WHERE payment_id=%s',(payment.json()['paymentId'],))
                            assert cursor.fetchone()['payment_status']=='PARTIALLY_REFUNDED'
                        cursor.execute('SELECT * FROM headquarters_inventory WHERE product_variant_id=%s',(variant_id,))
                        inventory_after=cursor.fetchone()
                        assert inventory_after['on_hand_quantity']==inventory_before['on_hand_quantity']+item['quantity']
                        assert inventory_after['available_quantity']==inventory_before['available_quantity']+item['quantity']
                        assert inventory_after['defective_quantity']==inventory_before['defective_quantity']
                        cursor.execute('SELECT COUNT(*) AS count FROM inventory_movements WHERE idempotency_key=%s',(f"return-intake-{returned.json()['id']}-{variant_id}",))
                        assert cursor.fetchone()['count']==1
                    assert any(entry['id']==returned.json()['id'] and entry['status']=='COMPLETED' for entry in client.get('/returns').json())
                    print('new_order+pickup+return+inspection+restock+refund+retry=ok')
        finally:
            app.dependency_overrides.clear()
            connection.rollback()
            print('test_changes=rolled_back')


if __name__ == '__main__':
    import sys
    run(zero_cash='--zero-cash' in sys.argv)
