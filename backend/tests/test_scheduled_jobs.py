from datetime import datetime,date
from app.scheduled_jobs import month_window

def test_month_window_uses_calendar_year_and_month_boundaries():
    assert month_window(datetime(2026,10,3))==(date(2026,10,1),date(2025,10,1),date(2026,11,1))
    assert month_window(datetime(2026,12,31))==(date(2026,12,1),date(2025,12,1),date(2027,1,1))
