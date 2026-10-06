"""Append-only recommendation events, separate from device shopping state."""
from datetime import datetime, timezone
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from .auth import CurrentCustomer,get_current_customer
from .database import mysql_connection

router=APIRouter(prefix='/interactions',tags=['interactions'])

class InteractionRequest(BaseModel):
    eventKey:str=Field(min_length=1,max_length=100)
    sessionKey:str=Field(min_length=1,max_length=100)
    productId:int=Field(gt=0)
    eventType:Literal['VIEW','WISH_ADD','WISH_REMOVE','CART_ADD','CART_REMOVE','CART_QUANTITY','CART_OPTION']
    color:str|None=Field(default=None,max_length=50)
    size:int|None=Field(default=None,gt=0)
    quantity:int|None=Field(default=None,ge=0,le=99)
    occurredAt:datetime


@router.post('',status_code=201)
def record_interaction(request:InteractionRequest,customer:CurrentCustomer=Depends(get_current_customer)):
    occurred=request.occurredAt
    if occurred.tzinfo is None: raise HTTPException(422,'Timestamp must include timezone')
    occurred=occurred.astimezone(timezone.utc).replace(tzinfo=None)
    fields=(customer.customer_id,request.sessionKey,request.productId,request.eventType,request.color,request.size,request.quantity,occurred)
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            # 같은 고객 행을 잠가 중복 요청의 확인과 삽입을 직렬화합니다.
            cursor.execute('SELECT customer_id FROM customers WHERE customer_id=%s FOR UPDATE',(customer.customer_id,))
            cursor.execute('SELECT * FROM customer_interaction_events WHERE event_key=%s',(request.eventKey,))
            existing=cursor.fetchone()
            if existing is not None:
                old=tuple(existing[key] for key in ['customer_id','session_key','product_id','event_type','color_name','size_mm','quantity','occurred_at'])
                if old!=fields: raise HTTPException(409,'Event key belongs to another payload')
                return {'id':existing['interaction_event_id'],'duplicate':True}
            cursor.execute('SELECT product_id FROM products WHERE product_id=%s',(request.productId,))
            if cursor.fetchone() is None: raise HTTPException(404,'Product not found')
            cursor.execute('''INSERT INTO customer_interaction_events
                (event_key,customer_id,session_key,product_id,event_type,color_name,size_mm,quantity,occurred_at)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)''',(request.eventKey,*fields))
            identifier=cursor.lastrowid
        connection.commit()
        return {'id':identifier,'duplicate':False}
