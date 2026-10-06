from datetime import datetime, timedelta
import pytest
from fastapi import HTTPException
from app.returns import ReturnRequest, validate_return

def test_simple_return_requires_pickup_and_condition_and_seven_days():
    request = ReturnRequest(reason='반품',unworn=True,undamaged=True,completePackaging=True)
    validate_return(request, datetime.now()-timedelta(days=6))
    for picked in [None, datetime.now()-timedelta(days=8)]:
        with pytest.raises(HTTPException): validate_return(request,picked)
    with pytest.raises(HTTPException): validate_return(ReturnRequest(reason='반품'),datetime.now())

def test_defect_exception_still_requires_pickup():
    validate_return(ReturnRequest(reason='불량',reasonCode='PRODUCT_DEFECT'),datetime.now()-timedelta(days=8))
