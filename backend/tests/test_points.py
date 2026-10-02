from app.schemas import PointCreditRequest, PointUseRequest


def test_point_requests_reject_non_positive_amounts() -> None:
    for model, payload in (
        (PointCreditRequest, {"customerId": 1, "amount": 0, "idempotencyKey": "credit-1"}),
        (PointUseRequest, {"amount": -1, "idempotencyKey": "use-1"}),
    ):
        try:
            model(**payload)
        except ValueError:
            pass
        else:
            raise AssertionError("Non-positive point amount was accepted")
