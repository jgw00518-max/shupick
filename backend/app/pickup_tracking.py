"""Owned tracking reads and staff-operated branch handover transitions."""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from .auth import CurrentCustomer, CurrentEmployee, get_current_customer, require_permission
from .database import mysql_connection
from .status_history import record_order_status, record_fulfillment_status
from .outbox import enqueue_outbox_event

router = APIRouter(tags=['pickup'])


@router.get('/orders/{order_id}/tracking')
def tracking(order_id: int, customer: CurrentCustomer = Depends(get_current_customer)):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("""SELECT o.order_number,o.order_status,b.branch_name,b.address,b.phone,
                p.pickup_status,p.arrived_at,p.pickup_deadline_at,p.picked_up_at,
                f.fulfillment_id,f.fulfillment_status,f.tracking_number,f.shipped_at
                FROM orders o JOIN branches b ON b.branch_id=o.pickup_branch_id
                LEFT JOIN pickups p ON p.order_id=o.order_id
                LEFT JOIN fulfillments f ON f.order_id=o.order_id
                WHERE o.order_id=%s AND o.customer_id=%s ORDER BY f.fulfillment_id DESC LIMIT 1""", (order_id,customer.customer_id))
            row = cursor.fetchone()
            if row is None: raise HTTPException(404,'Order not found')
            cursor.execute('SELECT new_status,changed_at,change_reason FROM order_status_history WHERE order_id=%s ORDER BY changed_at,order_status_history_id', (order_id,))
            row['history'] = cursor.fetchall()
            cursor.execute("""SELECT bh.day_of_week,bh.opens_at,bh.closes_at,bh.is_closed
                FROM branch_business_hours bh JOIN orders o ON o.pickup_branch_id=bh.branch_id
                WHERE o.order_id=%s ORDER BY bh.day_of_week""", (order_id,))
            row['businessHours'] = [{**hour, 'opens_at':str(hour['opens_at']) if hour['opens_at'] is not None else None,
                'closes_at':str(hour['closes_at']) if hour['closes_at'] is not None else None} for hour in cursor.fetchall()]
            return row


def change_pickup(connection, pickup: dict, new_status: str, employee_id: int):
    with connection.cursor() as cursor:
        cursor.execute('UPDATE pickups SET pickup_status=%s,handled_by_employee_id=%s WHERE pickup_id=%s', (new_status,employee_id,pickup['pickup_id']))
        cursor.execute("""INSERT INTO pickup_status_history
            (pickup_id,previous_status,new_status,change_source,actor_type,actor_employee_id)
            VALUES (%s,%s,%s,'BRANCH_API','EMPLOYEE',%s)""", (pickup['pickup_id'],pickup['pickup_status'],new_status,employee_id))
        history_id = cursor.lastrowid
    enqueue_outbox_event(connection,aggregate_type='PICKUP',aggregate_id=pickup['pickup_id'],event_type='PICKUP_STATUS_CHANGED',
        payload={'pickupId':pickup['pickup_id'],'orderId':pickup['order_id'],'status':new_status},idempotency_key=f'pickup-status-history-{history_id}')


@router.post('/fulfillments/{fulfillment_id}/arrive')
def arrive(fulfillment_id: int, employee: CurrentEmployee = Depends(require_permission('PICKUP_MANAGE'))):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute('SELECT * FROM fulfillments WHERE fulfillment_id=%s FOR UPDATE', (fulfillment_id,))
            fulfillment = cursor.fetchone()
            if fulfillment is None: raise HTTPException(404,'Fulfillment not found')
            cursor.execute('SELECT * FROM orders WHERE order_id=%s FOR UPDATE', (fulfillment['order_id'],))
            order = cursor.fetchone()
            if order['order_status'] in ('CANCELED','REFUNDED'): raise HTTPException(409,'Order inactive')
            if fulfillment['fulfillment_status']=='READY_FOR_PICKUP': return {'status':'READY_FOR_PICKUP'}
            if fulfillment['fulfillment_status']!='IN_TRANSIT': raise HTTPException(409,'Shipment must precede arrival')
            cursor.execute('SELECT * FROM pickups WHERE order_id=%s FOR UPDATE', (fulfillment['order_id'],))
            pickup = cursor.fetchone()
            cursor.execute("""UPDATE fulfillments SET arrived_at=NOW(),inspected_at=NOW() WHERE fulfillment_id=%s""",(fulfillment_id,))
            cursor.execute("""INSERT INTO pickup_holdings (fulfillment_item_id,branch_id,holding_status,quantity,received_at,ready_at)
                SELECT fulfillment_item_id,%s,'READY_FOR_PICKUP',quantity,NOW(),NOW() FROM fulfillment_items WHERE fulfillment_id=%s""",(fulfillment['destination_branch_id'],fulfillment_id))
            cursor.execute("""UPDATE pickups p LEFT JOIN pickup_retention_policies policy
                ON policy.pickup_retention_policy_id=p.pickup_retention_policy_id
                SET p.arrived_at=NOW(),p.ready_at=NOW(),p.pickup_deadline_at=DATE_ADD(NOW(),INTERVAL COALESCE(policy.holding_days,14) DAY)
                WHERE p.pickup_id=%s""", (pickup['pickup_id'],))
        change_pickup(connection,pickup,'READY_FOR_PICKUP',employee.employee_id)
        record_fulfillment_status(connection,fulfillment_id,'READY_FOR_PICKUP',source='BRANCH_API',reason='대리점 도착 및 검수 완료',actor_employee_id=employee.employee_id)
        record_order_status(connection,fulfillment['order_id'],'READY_FOR_PICKUP',source='BRANCH_API',actor_type='EMPLOYEE',actor_employee_id=employee.employee_id)
        connection.commit()
        return {'status':'READY_FOR_PICKUP'}


class PickupConfirmation(BaseModel):
    paymentCode: str = Field(min_length=1,max_length=32)


@router.post('/orders/{order_id}/pickup/complete')
def complete_pickup(order_id: int, request: PickupConfirmation, employee: CurrentEmployee = Depends(require_permission('PICKUP_MANAGE'))):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute('SELECT * FROM orders WHERE order_id=%s FOR UPDATE', (order_id,))
            order = cursor.fetchone()
            if order is None: raise HTTPException(404,'Order not found')
            if request.paymentCode != order['order_number']: raise HTTPException(403,'Payment code mismatch')
            if order['order_status']=='COMPLETED': return {'status':'COMPLETED'}
            if order['order_status']!='READY_FOR_PICKUP': raise HTTPException(409,'Order is not ready for pickup')
            cursor.execute('SELECT * FROM pickups WHERE order_id=%s FOR UPDATE', (order_id,))
            pickup = cursor.fetchone()
            cursor.execute('UPDATE pickups SET picked_up_at=NOW() WHERE pickup_id=%s', (pickup['pickup_id'],))
            cursor.execute("UPDATE pickup_holdings ph JOIN fulfillment_items fi ON fi.fulfillment_item_id=ph.fulfillment_item_id SET ph.holding_status='PICKED_UP',ph.picked_up_at=NOW() WHERE fi.order_id=%s AND ph.holding_status='READY_FOR_PICKUP'", (order_id,))
            cursor.execute('SELECT fulfillment_id FROM fulfillments WHERE order_id=%s', (order_id,))
            fulfillments = cursor.fetchall()
        change_pickup(connection,pickup,'COMPLETED',employee.employee_id)
        for fulfillment in fulfillments:
            record_fulfillment_status(connection,fulfillment['fulfillment_id'],'COMPLETED',source='BRANCH_API',actor_employee_id=employee.employee_id)
        record_order_status(connection,order_id,'COMPLETED',source='BRANCH_API',actor_type='EMPLOYEE',actor_employee_id=employee.employee_id)
        connection.commit()
        return {'status':'COMPLETED'}
