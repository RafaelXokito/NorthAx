"""Unit tests for the pure metrics-assembly math (§9.3)."""
import datetime as dt

from app.services.metrics_assembly import (
    build_hrv_trend,
    compute_loads,
    compute_sleep_debt,
    rolling_mean,
)


def test_rolling_mean():
    assert rolling_mean([50, 52, 54]) == 52.0
    assert rolling_mean([50, None, 54]) == 52.0
    assert rolling_mean([]) is None
    assert rolling_mean([None]) is None


def test_build_hrv_trend_pads_to_seven():
    assert build_hrv_trend([55]) == [55] * 7
    assert build_hrv_trend([1, 2, 3]) == [1, 1, 1, 1, 1, 2, 3]


def test_build_hrv_trend_takes_last_seven_oldest_to_newest():
    assert build_hrv_trend([1, 2, 3, 4, 5, 6, 7, 8]) == [2, 3, 4, 5, 6, 7, 8]


def test_build_hrv_trend_empty():
    assert build_hrv_trend([]) == []


def test_compute_sleep_debt():
    # shortfalls vs 8h: 0.5 + 2.0 + 0 = 2.5
    assert compute_sleep_debt([7.5, 6.0, 8.0]) == 2.5
    assert compute_sleep_debt([9.0, 8.5]) == 0.0


def test_compute_loads_steady():
    ref = dt.date(2026, 6, 30)
    totals = {ref - dt.timedelta(days=i): 50.0 for i in range(7)}  # last 7 days @ 50
    acute, chronic, weekly = compute_loads(totals, ref)
    assert acute == 50.0          # 350 / 7
    assert chronic == round(350 / 42, 2)
    assert weekly == 0.0          # no prior-week load


def test_compute_loads_weekly_change():
    ref = dt.date(2026, 6, 30)
    totals = {}
    for i in range(7):                       # this week: 70/day
        totals[ref - dt.timedelta(days=i)] = 70.0
    for i in range(7, 14):                    # prior week: 50/day
        totals[ref - dt.timedelta(days=i)] = 50.0
    acute, chronic, weekly = compute_loads(totals, ref)
    assert acute == 70.0
    # this_week=490, prev_week=350 → (490-350)/350 = 0.4
    assert weekly == 0.4


def test_compute_loads_weekly_change_clamped():
    # Regression: a tiny prior week must not overflow NUMERIC(5,4) (|v| < 10).
    ref = dt.date(2026, 6, 30)
    totals = {ref - dt.timedelta(days=i): 70.0 for i in range(7)}  # this week
    totals[ref - dt.timedelta(days=10)] = 1.0                       # tiny prior week
    _, _, weekly = compute_loads(totals, ref)
    assert weekly == 9.9999  # clamped, would otherwise be 489.0
