import pytest
from fastapi import HTTPException
from app.checkout_benefits import coupon_discount
from app.schemas import PaymentCompleteRequest


def test_percentage_rounding_and_cap():
    coupon = dict(minimum_order_amount=1000, discount_type="PERCENT", discount_value=15, maximum_discount_amount=2000)
    assert coupon_discount(coupon, 10001) == 1500
    assert coupon_discount(coupon, 20000) == 2000
    with pytest.raises(HTTPException):
        coupon_discount(coupon, 999)


def test_fixed_discount_cannot_exceed_subtotal():
    assert coupon_discount(dict(minimum_order_amount=0, discount_type="FIXED", discount_value=5000, maximum_discount_amount=None), 1000) == 1000


def test_negative_points_rejected():
    with pytest.raises(ValueError):
        PaymentCompleteRequest(paymentMethod="CARD", transactionKey="test", pointsUsed=-1)
