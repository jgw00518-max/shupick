from app.outbox import retry_delay_seconds


def test_retry_delay_uses_capped_exponential_backoff() -> None:
    assert retry_delay_seconds(1) == 30
    assert retry_delay_seconds(2) == 60
    assert retry_delay_seconds(3) == 120
    assert retry_delay_seconds(20) == 3600
