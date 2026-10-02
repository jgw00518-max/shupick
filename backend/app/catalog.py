"""Database-managed taxonomy and brand membership for customer browsing."""
from fastapi import APIRouter
from .database import mysql_connection

router=APIRouter(tags=['catalog'])

def category_tree(rows):
    children={}
    for row in rows: children.setdefault(row['parent_category_id'],[]).append(row)
    groups=[]
    for root in children.get(None,[]):
        groups.extend(children.get(root['category_id'],[]) or [root])
    def descendants(identifier):
        result=[]
        for child in children.get(identifier,[]):
            result.append(child['category_name'])
            result.extend(descendants(child['category_id']))
        return result
    return {group['category_name']:descendants(group['category_id']) for group in groups}

@router.get('/catalog')
def get_catalog():
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute('SELECT category_id,parent_category_id,category_name FROM categories ORDER BY category_id')
            tree=category_tree(cursor.fetchall())
            cursor.execute('SELECT brand_id,brand_code,brand_name FROM brands ORDER BY brand_name,brand_id')
            brands=cursor.fetchall()
            cursor.execute('SELECT product_id,brand_id FROM products WHERE is_active=TRUE')
            products=cursor.fetchall()
            return {'categoryTree':tree,'brands':[{**brand,'productIds':[product['product_id'] for product in products if product['brand_id']==brand['brand_id']]} for brand in brands]}
