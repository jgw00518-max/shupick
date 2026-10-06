"""Owned inquiries and SKU-specific restock subscriptions."""
from typing import Literal
from fastapi import APIRouter,Depends,HTTPException
from pydantic import BaseModel,Field,field_validator
from .auth import CurrentCustomer,CurrentEmployee,get_current_customer,require_permission
from .database import mysql_connection

router=APIRouter(tags=['support'])
KINDS={'PRODUCT':'상품 문의','DELIVERY':'배송 문의','PAYMENT':'결제 문의','OTHER':'기타 문의'}

def inquiry_json(row):
    return dict(id=row['inquiry_id'],kind=KINDS.get(row['inquiry_type'],row['inquiry_type']),title=row['title'],body=row['inquiry_content'],date=row['created_at'].strftime('%Y.%m.%d'),answer=row.get('answer'))

@router.get('/inquiries')
def inquiries(customer:CurrentCustomer=Depends(get_current_customer)):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute('''SELECT i.*,(SELECT response_content FROM inquiry_responses r
                WHERE r.inquiry_id=i.inquiry_id ORDER BY responded_at DESC,inquiry_response_id DESC LIMIT 1) AS answer
                FROM inquiries i WHERE customer_id=%s ORDER BY created_at DESC,inquiry_id DESC''',(customer.customer_id,))
            return [inquiry_json(row) for row in cursor.fetchall()]

class InquiryRequest(BaseModel):
    kind:Literal['PRODUCT','DELIVERY','PAYMENT','OTHER']
    title:str=Field(min_length=1,max_length=150)
    body:str=Field(min_length=1,max_length=10000)
    productId:int|None=Field(default=None,gt=0)

@router.post('/inquiries',status_code=201)
def create_inquiry(request:InquiryRequest,customer:CurrentCustomer=Depends(get_current_customer)):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            if request.productId is not None:
                cursor.execute('SELECT product_id FROM products WHERE product_id=%s',(request.productId,))
                if cursor.fetchone() is None: raise HTTPException(404,'Product not found')
            cursor.execute('INSERT INTO inquiries (customer_id,product_id,inquiry_type,title,inquiry_content) VALUES (%s,%s,%s,%s,%s)',(customer.customer_id,request.productId,request.kind,request.title,request.body))
            identifier=cursor.lastrowid
            cursor.execute('SELECT * FROM inquiries WHERE inquiry_id=%s',(identifier,))
            row=cursor.fetchone()
        connection.commit()
        return inquiry_json(row)

class AnswerRequest(BaseModel):
    answer:str=Field(min_length=1,max_length=10000)

    @field_validator('answer',mode='before')
    @classmethod
    def strip_answer(cls,value):
        return value.strip() if isinstance(value,str) else value

@router.post('/inquiries/{inquiry_id}/answer')
def answer_inquiry(inquiry_id:int,request:AnswerRequest,employee:CurrentEmployee=Depends(require_permission('SUPPORT_MANAGE'))):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute('SELECT inquiry_id FROM inquiries WHERE inquiry_id=%s FOR UPDATE',(inquiry_id,))
            if cursor.fetchone() is None: raise HTTPException(404,'Inquiry not found')
            cursor.execute('INSERT INTO inquiry_responses (inquiry_id,employee_id,response_content) VALUES (%s,%s,%s)',(inquiry_id,employee.employee_id,request.answer))
            cursor.execute("UPDATE inquiries SET inquiry_status='ANSWERED' WHERE inquiry_id=%s",(inquiry_id,))
        connection.commit()
        return {'answered':True}

@router.get('/restock-subscriptions')
def restock_subscriptions(customer:CurrentCustomer=Depends(get_current_customer)):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT CONCAT(v.product_id,':',v.color_name,':',v.size_mm) AS subscription_key FROM restock_subscriptions s JOIN product_variants v ON v.product_variant_id=s.product_variant_id WHERE s.customer_id=%s",(customer.customer_id,))
            return [row['subscription_key'] for row in cursor.fetchall()]

class RestockRequest(BaseModel):
    keys:list[str]=Field(max_length=200)

@router.put('/restock-subscriptions')
def save_restock(request:RestockRequest,customer:CurrentCustomer=Depends(get_current_customer)):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute('SELECT customer_id FROM customers WHERE customer_id=%s FOR UPDATE',(customer.customer_id,))
            variants=[]
            for key in set(request.keys):
                cursor.execute("SELECT product_variant_id FROM product_variants WHERE CONCAT(product_id,':',color_name,':',size_mm)=%s",(key,))
                variant=cursor.fetchone()
                if variant is None: raise HTTPException(422,'Invalid product option')
                variants.append(variant['product_variant_id'])
            cursor.execute('DELETE FROM restock_subscriptions WHERE customer_id=%s',(customer.customer_id,))
            for variant_id in variants:
                cursor.execute('INSERT INTO restock_subscriptions (customer_id,product_variant_id) VALUES (%s,%s)',(customer.customer_id,variant_id))
        connection.commit()
        return {'count':len(variants)}
