"""Unit tests for the intervals.icu mappings (§9.3, §9.4)."""
from app.services.intervals import (
    IntervalsClient,
    normalize_intervals_activity,
    normalize_intervals_wellness,
    planned_session_to_intervals_event,
)


def test_normalize_wellness_maps_fields_and_ctl_atl():
    raw = {
        "id": "2026-06-29",
        "hrv": 58,
        "restingHR": 46,
        "sleepSecs": 27000,   # 7.5 h
        "sleepScore": 84,
        "ctl": 72.0,          # fitness (chronic)
        "atl": 68.0,          # fatigue (acute)
    }
    out = normalize_intervals_wellness(raw)
    assert out["date"] == "2026-06-29"
    assert out["hrv"] == 58
    assert out["resting_hr"] == 46
    assert out["sleep_duration"] == 7.5
    assert out["sleep_score"] == 84
    assert out["ctl"] == 72.0
    assert out["atl"] == 68.0


def test_normalize_wellness_falls_back_to_hrvSDNN():
    out = normalize_intervals_wellness({"date": "2026-06-29", "hrvSDNN": 51})
    assert out["hrv"] == 51
    assert out["sleep_duration"] is None  # no sleepSecs → None, no crash


def test_normalize_activity():
    raw = {
        "id": 9911,
        "name": "Morning Ride",
        "type": "Ride",
        "start_date_local": "2026-06-28T07:15:00",
        "moving_time": 4500,
        "distance": 32000,
        "icu_training_load": 72,
    }
    out = normalize_intervals_activity(raw)
    assert out["external_id"] == "9911"
    assert out["domain"] == "Cycling"
    assert out["source"] == "garmin"
    assert out["duration_seconds"] == 4500
    assert out["training_load"] == 72


def test_normalize_activity_parses_start_time_to_datetime():
    # Regression: start_time must be a datetime (timestamptz), not a string.
    import datetime as dt

    out = normalize_intervals_activity({"id": 1, "type": "Run", "start_date_local": "2026-06-30T07:35:47"})
    assert isinstance(out["start_time"], dt.datetime)
    assert out["start_time"].year == 2026 and out["start_time"].hour == 7
    # Missing start → None (skipped by the sync), not a crash.
    assert normalize_intervals_activity({"id": 2, "type": "Run"})["start_time"] is None


def test_planned_session_to_event():
    session = {
        "domain": "Cycling",
        "title": "Zone 3 Intervals",
        "subtitle": "70–85% FTP",
        "duration": 75,
        "intensityLabel": "Threshold",
    }
    e = planned_session_to_intervals_event(session, "2026-06-30")
    assert e["category"] == "WORKOUT"
    assert e["type"] == "Ride"
    assert e["name"] == "Zone 3 Intervals"
    assert e["start_date_local"] == "2026-06-30T00:00:00"
    assert e["moving_time"] == 75 * 60


def test_authorization_url_contains_params(monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, "intervals_client_id", "abc")
    monkeypatch.setattr(settings, "intervals_client_secret", "secret")
    url = IntervalsClient().authorization_url(state="user-123")
    assert "client_id=abc" in url
    assert "state=user-123" in url
    assert "response_type=code" in url
