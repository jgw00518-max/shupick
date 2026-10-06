"""Retryable local demo maintenance with stable monthly benefit assessments."""
from datetime import datetime, timedelta, timezone
from .database import mysql_connection
from .orders import _release_reservations
from .status_history import record_order_status
from .points import expire_all_due_points
from .outbox import enqueue_outbox_event


def month_window(now:datetime):
    month=now.date().replace(day=1)
    start=month.replace(year=month.year-1)
    next_month=month.replace(year=month.year+1,month=1) if month.month==12 else month.replace(month=month.month+1)
    return month,start,next_month


def assess_memberships(connection,now:datetime)->dict:
    month,start,next_month=month_window(now)
    assessed=issued=0
    with connection.cursor() as cursor:
        cursor.execute('SELECT * FROM membership_tiers WHERE is_active=TRUE ORDER BY minimum_amount DESC')
        tiers=cursor.fetchall()
        cursor.execute('SELECT customer_id FROM customers WHERE deleted_at IS NULL ORDER BY customer_id')
        customers=cursor.fetchall()
        for customer in customers:
            customer_id=customer['customer_id']
            cursor.execute('SELECT customer_id FROM customers WHERE customer_id=%s FOR UPDATE',(customer_id,))
            cursor.execute('SELECT membership_tier_id FROM membership_assessments WHERE customer_id=%s AND benefit_month=%s',(customer_id,month))
            existing=cursor.fetchone()
            if existing is None:
                cursor.execute('''SELECT COALESCE(SUM(o.paid_total),0) AS gross,
                    COALESCE(SUM((SELECT COALESCE(SUM(r.refund_amount),0) FROM refunds r
                      WHERE r.order_id=o.order_id AND r.refund_status='SUCCEEDED' AND r.completed_at<%s)),0) AS returned
                    FROM orders o WHERE o.customer_id=%s AND o.purchase_confirmed_at>=%s AND o.purchase_confirmed_at<%s''',(month,customer_id,start,month))
                amounts=cursor.fetchone()
                gross=int(amounts['gross']); returned=min(gross,int(amounts['returned']))
                net=gross-returned
                tier=next((tier for tier in tiers if int(tier['minimum_amount'])<=net and (tier['maximum_amount_exclusive'] is None or net<int(tier['maximum_amount_exclusive']))),None)
                if tier is None: raise ValueError('Membership tier ranges do not cover purchase amount')
                tier_id=tier['membership_tier_id']
                cursor.execute('''INSERT INTO membership_assessments
                    (customer_id,membership_tier_id,benefit_month,calculation_started_at,calculation_ended_at,confirmed_purchase_amount,canceled_amount,returned_amount,net_purchase_amount)
                    VALUES (%s,%s,%s,%s,%s,%s,0,%s,%s)''',(customer_id,tier_id,month,start,month-timedelta(days=1),gross,returned,net))
                assessed+=1
            else: tier_id=existing['membership_tier_id']
            cursor.execute('''SELECT r.coupon_definition_id,r.monthly_quantity FROM membership_coupon_rules r
                JOIN coupon_definitions d ON d.coupon_definition_id=r.coupon_definition_id
                WHERE r.membership_tier_id=%s AND d.is_active=TRUE''',(tier_id,))
            rules=cursor.fetchall()
            for rule in rules:
                for sequence in range(1,int(rule['monthly_quantity'])+1):
                    cursor.execute('''INSERT IGNORE INTO customer_coupons
                        (customer_id,coupon_definition_id,benefit_month,issue_sequence,issued_at,expires_at)
                        VALUES (%s,%s,%s,%s,%s,%s)''',(customer_id,rule['coupon_definition_id'],month,sequence,now,datetime.combine(next_month,datetime.min.time())))
                    issued+=cursor.rowcount
        cursor.execute("UPDATE customer_coupons SET coupon_status='EXPIRED' WHERE coupon_status='AVAILABLE' AND expires_at<=%s",(now,))
    return {'assessed':assessed,'issuedCoupons':issued}


def release_expired_orders(connection,now:datetime)->int:
    count=0
    with connection.cursor() as cursor:
        cursor.execute("SELECT DISTINCT o.order_id FROM orders o JOIN inventory_reservations ir ON ir.order_id=o.order_id WHERE o.order_status='PENDING_PAYMENT' AND ir.reservation_status='RESERVED' AND ir.expires_at<=%s ORDER BY o.order_id",(now,))
        ids=[row['order_id'] for row in cursor.fetchall()]
        for identifier in ids:
            cursor.execute('SELECT order_status FROM orders WHERE order_id=%s FOR UPDATE',(identifier,))
            if cursor.fetchone()['order_status']!='PENDING_PAYMENT': continue
            _release_reservations(connection,identifier,'미결제 예약 기간 만료','EXPIRED')
            record_order_status(connection,identifier,'CANCELED',source='SCHEDULED_JOB',reason='미결제 예약 기간 만료')
            cursor.execute("UPDATE orders SET canceled_at=%s WHERE order_id=%s",(now,identifier))
            cursor.execute('SELECT pickup_id,pickup_status FROM pickups WHERE order_id=%s FOR UPDATE',(identifier,))
            pickup=cursor.fetchone()
            if pickup is not None and pickup['pickup_status']!='CANCELED':
                cursor.execute("UPDATE pickups SET pickup_status='CANCELED' WHERE pickup_id=%s",(pickup['pickup_id'],))
                cursor.execute("INSERT INTO pickup_status_history (pickup_id,previous_status,new_status,change_source,actor_type) VALUES (%s,%s,'CANCELED','SCHEDULED_JOB','SYSTEM')",(pickup['pickup_id'],pickup['pickup_status']))
                history_id=cursor.lastrowid
                enqueue_outbox_event(connection,aggregate_type='PICKUP',aggregate_id=pickup['pickup_id'],event_type='PICKUP_STATUS_CHANGED',payload={'pickupId':pickup['pickup_id'],'orderId':identifier,'status':'CANCELED'},idempotency_key=f'pickup-status-history-{history_id}')
            count+=1
    return count


def run_once(now:datetime|None=None)->dict:
    # 기존 MySQL DATETIME은 한국 로컬 시각이므로 OS 시간대와 무관하게 맞춥니다.
    now=now or datetime.now(timezone(timedelta(hours=9))).replace(tzinfo=None)
    result={}
    with mysql_connection() as connection:
        result['expiredPoints']=expire_all_due_points(connection,now)
        connection.commit()
    with mysql_connection() as connection:
        result['expiredOrders']=release_expired_orders(connection,now)
        connection.commit()
    with mysql_connection() as connection:
        result.update(assess_memberships(connection,now))
        connection.commit()
    return result
