"""Unit tests for the pure metrics-assembly math (§9.3)."""
import datetime as dt

from app.services.metrics_assembly import (
    build_hrv_trend,
    compute_loads,
    compute_sleep_debt,
    resolve_readings,
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


# ── resolve_readings (multi-source conflict resolution) ──────────────────────
def test_resolve_default_prefers_intervals():
    rows = {"intervals": {"hrv": 55, "atl": 40, "ctl": 60}, "manual": {"hrv": 48}}
    merged, prov = resolve_readings(rows, priority={})
    assert merged["hrv"] == 55
    assert prov["hrv"] == "intervals"
    assert merged["atl"] == 40 and merged["ctl"] == 60  # load passthrough (intervals-only)


def test_resolve_priority_prefers_manual():
    rows = {"intervals": {"hrv": 55}, "manual": {"hrv": 48}}
    merged, prov = resolve_readings(rows, priority={"hrv": ["manual", "intervals"]})
    assert merged["hrv"] == 48
    assert prov["hrv"] == "manual"


def test_resolve_skips_source_without_value():
    # Manual is preferred but has no HRV → falls through to intervals.
    rows = {"intervals": {"hrv": 55}, "manual": {"body_weight": 78}}
    merged, prov = resolve_readings(rows, priority={"hrv": ["manual", "intervals"]})
    assert merged["hrv"] == 55 and prov["hrv"] == "intervals"
    assert merged["body_weight"] == 78 and prov["bodyWeight"] == "manual"


def test_resolve_healthkit_in_priority_is_ignored_server_side():
    # HealthKit never reaches the server; it's filtered out of the order.
    rows = {"intervals": {"hrv": 55}}
    merged, prov = resolve_readings(rows, priority={"hrv": ["healthkit", "intervals"]})
    assert merged["hrv"] == 55 and prov["hrv"] == "intervals"


def test_resolve_sleep_takes_all_fields_from_winner():
    rows = {
        "intervals": {"sleep_duration": 7.0, "sleep_score": 80},
        "manual": {"sleep_duration": 6.5},
    }
    merged, prov = resolve_readings(rows, priority={"sleep": ["manual", "intervals"]})
    assert merged["sleep_duration"] == 6.5 and prov["sleep"] == "manual"
    assert "sleep_score" not in merged  # manual didn't supply it
