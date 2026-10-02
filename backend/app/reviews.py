"""Customer-owned purchase reviews with demo photo payload storage."""
import base64
from fastapi import Query
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator
from .auth import CurrentCustomer, get_current_customer
from .database import mysql_connection

router = APIRouter(prefix='/reviews',tags=['reviews'])


@router.get('/products/{product_id}')
def public_reviews(product_id: int, offset: int = Query(default=0, ge=0), limit: int = Query(default=20, ge=1, le=50)):
    """구매확정된 공개 리뷰만 조회하며 고객·주문 식별자는 노출하지 않는다."""
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute('SELECT product_id FROM products WHERE product_id=%s', (product_id,))
            if cursor.fetchone() is None:
                raise HTTPException(404, 'Product not found')
            predicate = '''FROM reviews r JOIN order_items oi ON oi.order_item_id=r.order_item_id
                JOIN orders o ON o.order_id=oi.order_id JOIN product_variants v ON v.product_variant_id=oi.product_variant_id
                WHERE v.product_id=%s AND r.deleted_at IS NULL AND o.purchase_confirmed_at IS NOT NULL'''
            cursor.execute('SELECT COUNT(*) AS count,COALESCE(AVG(r.rating),0) AS average '+predicate, (product_id,))
            summary=cursor.fetchone()
            cursor.execute('''SELECT r.review_id AS id,r.rating,r.review_content AS content,
                r.fit_size AS fitSize,r.fit_width AS fitWidth,r.fit_comfort AS fitComfort,
                oi.color_name AS color,oi.size_mm AS size,r.created_at AS createdAt '''+predicate+
                ' ORDER BY r.created_at DESC,r.review_id DESC LIMIT %s OFFSET %s', (product_id,limit,offset))
            rows=cursor.fetchall()
            for row in rows:
                cursor.execute('SELECT photo_base64 FROM review_photo_payloads WHERE review_id=%s ORDER BY sort_order', (row['id'],))
                row['photos']=[photo['photo_base64'] for photo in cursor.fetchall()]
            return dict(count=int(summary['count']),average=float(summary['average']),items=rows,hasMore=offset+len(rows)<int(summary['count']))

class ReviewRequest(BaseModel):
    orderNumber: str = Field(min_length=1,max_length=32)
    itemKey: str = Field(min_length=1,max_length=150)
    rating: int = Field(ge=1,le=5)
    content: str = Field(min_length=1,max_length=5000)
    fitSize: str = Field(default='정사이즈',max_length=30)
    fitWidth: str = Field(default='적당함',max_length=30)
    fitComfort: str = Field(default='편함',max_length=30)
    photos: list[str] = Field(default_factory=list,max_length=3)

    @field_validator('photos')
    @classmethod
    def validate_photos(cls,photos):
        for photo in photos:
            if len(photo)>7*1024*1024: raise ValueError('Photo exceeds 5MB')
            try: data=base64.b64decode(photo,validate=True)
            except ValueError: raise ValueError('Invalid photo encoding')
            if len(data)>5*1024*1024: raise ValueError('Photo exceeds 5MB')
            if not (data.startswith(b'\xff\xd8\xff') or data.startswith(b'\x89PNG\r\n\x1a\n') or (data.startswith(b'RIFF') and data[8:12]==b'WEBP')):
                raise ValueError('Only JPEG, PNG and WebP photos are supported')
        return photos


def owned_item(cursor,customer_id,order_number,item_key):
    cursor.execute("""SELECT oi.order_item_id,o.order_status,o.purchase_confirmed_at FROM order_items oi
        JOIN orders o ON o.order_id=oi.order_id JOIN product_variants v ON v.product_variant_id=oi.product_variant_id
        WHERE o.customer_id=%s AND o.order_number=%s
        AND CONCAT(v.product_id,'-',oi.size_mm,'-',oi.color_name)=%s FOR UPDATE""",(customer_id,order_number,item_key))
    item=cursor.fetchone()
    if item is None: raise HTTPException(404,'Purchased item not found')
    return item


@router.get('')
def list_reviews(customer: CurrentCustomer=Depends(get_current_customer)):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("""SELECT r.review_id AS id,o.order_number AS orderNumber,
                CONCAT(v.product_id,'-',oi.size_mm,'-',oi.color_name) AS itemKey,
                r.rating,r.review_content AS content,r.fit_size AS fitSize,r.fit_width AS fitWidth,r.fit_comfort AS fitComfort
                FROM reviews r JOIN order_items oi ON oi.order_item_id=r.order_item_id
                JOIN orders o ON o.order_id=oi.order_id JOIN product_variants v ON v.product_variant_id=oi.product_variant_id
                WHERE r.customer_id=%s AND r.deleted_at IS NULL ORDER BY r.created_at DESC,r.review_id DESC""",(customer.customer_id,))
            rows=cursor.fetchall()
            cursor.execute('SELECT p.review_id,p.photo_base64 FROM review_photo_payloads p JOIN reviews r ON r.review_id=p.review_id WHERE r.customer_id=%s AND r.deleted_at IS NULL ORDER BY p.sort_order',(customer.customer_id,))
            photos={row['id']:[] for row in rows}
            for photo in cursor.fetchall(): photos[photo['review_id']].append(photo['photo_base64'])
            return [{**row,'photos':photos[row['id']]} for row in rows]


def save_review(request:ReviewRequest,customer:CurrentCustomer,editing:bool):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            item=owned_item(cursor,customer.customer_id,request.orderNumber,request.itemKey)
            if item['purchase_confirmed_at'] is None:
                raise HTTPException(409, '구매확정 후 리뷰를 작성할 수 있습니다.')
            cursor.execute('SELECT * FROM reviews WHERE order_item_id=%s FOR UPDATE',(item['order_item_id'],))
            existing=cursor.fetchone()
            if editing:
                if existing is None or existing['deleted_at'] is not None: raise HTTPException(404,'Review not found')
                if existing['customer_id']!=customer.customer_id: raise HTTPException(403,'Review belongs to another customer')
            else:
                if item['order_status']!='COMPLETED': raise HTTPException(409,'수령 완료 상품만 리뷰를 작성할 수 있습니다.')
                if existing is not None and existing['deleted_at'] is None: raise HTTPException(409,'이미 리뷰를 작성한 상품입니다.')
            fields=(request.rating,request.content,request.fitSize,request.fitWidth,request.fitComfort)
            if existing is None:
                cursor.execute('INSERT INTO reviews (order_item_id,customer_id,rating,review_content,fit_size,fit_width,fit_comfort) VALUES (%s,%s,%s,%s,%s,%s,%s)',(item['order_item_id'],customer.customer_id,*fields))
                review_id=cursor.lastrowid
            else:
                review_id=existing['review_id']
                cursor.execute('UPDATE reviews SET rating=%s,review_content=%s,fit_size=%s,fit_width=%s,fit_comfort=%s,deleted_at=NULL WHERE review_id=%s',(*fields,review_id))
            cursor.execute('DELETE FROM review_photo_payloads WHERE review_id=%s',(review_id,))
            for index,photo in enumerate(request.photos):
                cursor.execute('INSERT INTO review_photo_payloads (review_id,sort_order,photo_base64) VALUES (%s,%s,%s)',(review_id,index,photo))
            # 구매 항목당 최초 작성에만 1,000P 지급한다. 삭제 후 재작성도 중복 지급하지 않는다.
            if not editing:
                key=f'review-reward-{item["order_item_id"]}'
                cursor.execute('INSERT INTO point_wallets (customer_id,point_balance) VALUES (%s,0) ON DUPLICATE KEY UPDATE point_balance=point_balance', (customer.customer_id,))
                cursor.execute('SELECT point_balance FROM point_wallets WHERE customer_id=%s FOR UPDATE', (customer.customer_id,))
                balance=int(cursor.fetchone()['point_balance'])
                cursor.execute('SELECT point_transaction_id FROM point_transactions WHERE idempotency_key=%s', (key,))
                if cursor.fetchone() is None:
                    cursor.execute("""INSERT INTO point_transactions
                        (customer_id,transaction_type,point_amount,balance_after,idempotency_key,description,expires_at)
                        VALUES (%s,'EARN',1000,%s,%s,'리뷰 최초 작성 적립',DATE_ADD(NOW(),INTERVAL 1 YEAR))""", (customer.customer_id,balance+1000,key))
                    transaction_id=cursor.lastrowid
                    cursor.execute("""INSERT INTO point_lots (customer_id,source_transaction_id,original_amount,remaining_amount,earned_at,expires_at,lot_status)
                        SELECT customer_id,point_transaction_id,point_amount,point_amount,NOW(),expires_at,'AVAILABLE' FROM point_transactions WHERE point_transaction_id=%s""", (transaction_id,))
                    cursor.execute('UPDATE point_wallets SET point_balance=%s WHERE customer_id=%s', (balance+1000,customer.customer_id))
        connection.commit()
        return {'id':review_id}


@router.post('',status_code=201)
def create_review(request:ReviewRequest,customer:CurrentCustomer=Depends(get_current_customer)):
    return save_review(request,customer,False)

@router.put('')
def update_review(request:ReviewRequest,customer:CurrentCustomer=Depends(get_current_customer)):
    return save_review(request,customer,True)

class ReviewDelete(BaseModel):
    orderNumber:str
    itemKey:str

@router.delete('')
def delete_review(request:ReviewDelete,customer:CurrentCustomer=Depends(get_current_customer)):
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            item=owned_item(cursor,customer.customer_id,request.orderNumber,request.itemKey)
            cursor.execute('UPDATE reviews SET deleted_at=NOW() WHERE order_item_id=%s AND customer_id=%s AND deleted_at IS NULL',(item['order_item_id'],customer.customer_id))
            if cursor.rowcount!=1: raise HTTPException(404,'Review not found')
        connection.commit()
        return {'deleted':True}
