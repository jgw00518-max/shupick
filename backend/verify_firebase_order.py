"""Real Firebase token verification with rollback-only MySQL test data."""
import json
from contextlib import contextmanager
from pathlib import Path
from urllib.request import Request, urlopen
from uuid import uuid4
from unittest.mock import patch

from fastapi.testclient import TestClient
from firebase_admin import auth
from app.auth import get_firebase_app
from app.database import mysql_connection
from app.main import app


def run():
    firebase_app = get_firebase_app()
    uid = 'integration-' + uuid4().hex
    firebase_user_created = False
    try:
        auth.create_user(uid=uid, email=uid + '@example.test', app=firebase_app)
        firebase_user_created = True
        config = json.loads((Path(__file__).parent.parent / 'android/app/google-services.json').read_text())
        api_key = config['client'][0]['api_key'][0]['current_key']
        custom_token = auth.create_custom_token(uid, app=firebase_app).decode()
        request = Request(
            'https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=' + api_key,
            data=json.dumps({'token': custom_token, 'returnSecureToken': True}).encode(),
            headers={'Content-Type': 'application/json'},
        )
        with urlopen(request, timeout=30) as response:
            token = json.load(response)['idToken']
        decoded = auth.verify_id_token(token, app=firebase_app, check_revoked=True)
        assert decoded['uid'] == uid
        print('real_firebase_id_token=verified')
        with mysql_connection() as connection:
            class RollbackConnection:
                def cursor(self):
                    return connection.cursor()
                def commit(self):
                    pass
                def rollback(self):
                    connection.rollback()
            @contextmanager
            def test_connection():
                yield RollbackConnection()
            try:
                with patch('app.auth.mysql_connection', test_connection), patch('app.orders.mysql_connection', test_connection):
                    client = TestClient(app)
                    headers = {'Authorization': 'Bearer ' + token}
                    sync = client.post('/auth/customer/sync', headers=headers, json={'customerName': 'Integration test'})
                    assert sync.status_code == 200, 'customer sync status=' + str(sync.status_code)
                    print('mysql_customer_sync=ok')
                    with connection.cursor() as cursor:
                        cursor.execute('SELECT branch_id FROM branches WHERE is_active=TRUE LIMIT 1')
                        branch_id = cursor.fetchone()['branch_id']
                        cursor.execute('SELECT product_variant_id,reserved_quantity FROM headquarters_inventory WHERE available_quantity>0 LIMIT 1')
                        inventory = cursor.fetchone()
                    assert inventory is not None, 'No available inventory'
                    reserved = client.post('/orders/reserve', headers=headers, json={
                        'pickupBranchId': branch_id, 'idempotencyKey': uid,
                        'items': [{'productVariantId': inventory['product_variant_id'], 'quantity': 1}],
                    })
                    assert reserved.status_code == 201, 'reserve status=' + str(reserved.status_code)
                    order = reserved.json()
                    assert order['orderStatus'] == 'PENDING_PAYMENT'
                    with connection.cursor() as cursor:
                        cursor.execute('SELECT reserved_quantity FROM headquarters_inventory WHERE product_variant_id=%s', (inventory['product_variant_id'],))
                        assert cursor.fetchone()['reserved_quantity'] == inventory['reserved_quantity'] + 1
                    print('order_created_and_inventory_reserved=ok')
                    cancelled = client.post('/orders/' + str(order['orderId']) + '/cancel', headers=headers, json={'reason': 'Integration verification'})
                    assert cancelled.status_code == 200
                    with connection.cursor() as cursor:
                        cursor.execute('SELECT reserved_quantity FROM headquarters_inventory WHERE product_variant_id=%s', (inventory['product_variant_id'],))
                        assert cursor.fetchone()['reserved_quantity'] == inventory['reserved_quantity']
                    print('cancel_releases_inventory=ok')
            finally:
                connection.rollback()
                print('mysql_test_data=rolled_back')
    finally:
        if firebase_user_created:
            auth.delete_user(uid, app=firebase_app)
            print('temporary_firebase_user=deleted')


if __name__ == '__main__':
    run()
