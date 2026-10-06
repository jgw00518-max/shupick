from contextlib import contextmanager
from datetime import date
from decimal import Decimal
from unittest.mock import MagicMock

from app import staff_work
from app.auth import CurrentEmployee


def test_sql_decimal_aggregates_are_returned_as_json_integers(monkeypatch):
    cursor = MagicMock()
    cursor.__enter__.return_value = cursor
    cursor.fetchone.side_effect = [{'allowed': 1}, {'order_count': 1, 'revenue': Decimal('12345')}]
    cursor.fetchall.side_effect = [
        [{'product_id': 5, 'product_name': '운동화'}], [{'branch_id': 3, 'branch_name': '강남점'}],
        [{'day': date(2026, 10, 6), 'quantity': Decimal('2')}],
        [{'product_id': 5, 'product_name': '운동화', 'quantity': Decimal('2')}],
    ]
    connection = MagicMock(); connection.cursor.return_value = cursor
    @contextmanager
    def database(): yield connection
    monkeypatch.setattr(staff_work, 'mysql_connection', database)
    response = staff_work.staff_analytics(days=28, branch_id=None, product_id=None,
        employee=CurrentEmployee(7, 'uid', 'EMP-7', '본사 직원'))
    assert type(response['revenue']) is int
    assert type(response['orderCount']) is int
    assert type(response['byDay'][0]['quantity']) is int
    assert type(response['byProduct'][0]['quantity']) is int
    assert response['revenue'] == 12345 and response['quantity'] == 2
