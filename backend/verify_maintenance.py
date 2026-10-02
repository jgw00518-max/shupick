"""Exercise live MySQL maintenance without committing business data."""
from contextlib import contextmanager
from datetime import datetime
from uuid import uuid4
from unittest.mock import patch
from app.database import mysql_connection
from app.scheduled_jobs import run_once

def main():
    with mysql_connection() as connection:
        class Transaction:
            def cursor(self):return connection.cursor()
            def commit(self):pass
        @contextmanager
        def transaction():yield Transaction()
        try:
            with connection.cursor() as cursor:
                cursor.execute('SELECT customer_id FROM point_wallets LIMIT 1')
                customer_id=cursor.fetchone()['customer_id']
                cursor.execute('UPDATE point_wallets SET point_balance=point_balance+100 WHERE customer_id=%s',(customer_id,))
                cursor.execute('SELECT point_balance FROM point_wallets WHERE customer_id=%s',(customer_id,))
                balance=cursor.fetchone()['point_balance']
                cursor.execute("INSERT INTO point_transactions (customer_id,transaction_type,point_amount,balance_after,idempotency_key,created_at,expires_at) VALUES (%s,'EARN',100,%s,%s,DATE_SUB(NOW(),INTERVAL 2 YEAR),DATE_SUB(NOW(),INTERVAL 1 YEAR))",(customer_id,balance,str(uuid4())))
                source=cursor.lastrowid
                cursor.execute("INSERT INTO point_lots (customer_id,source_transaction_id,original_amount,remaining_amount,earned_at,expires_at) VALUES (%s,%s,100,100,DATE_SUB(NOW(),INTERVAL 2 YEAR),DATE_SUB(NOW(),INTERVAL 1 YEAR))",(customer_id,source))
            with patch('app.scheduled_jobs.mysql_connection',transaction):
                first=run_once(datetime.now())
                assert first['expiredPoints']>=100
                second=run_once(datetime.now())
                assert second['assessed']==0 and second['issuedCoupons']==0
                assert second['expiredPoints']==0 and second['expiredOrders']==0
                print('maintenance_first='+str(first))
                print('maintenance_retry_idempotent=ok')
        finally:
            connection.rollback()
            print('verification_changes=rolled_back')

if __name__=='__main__':main()
