"""Unit tests for the goal-progress target descriptions (no DB)."""
from __future__ import annotations

from app.services.goal_progress import describe_target


def test_describe_race_time():
    t = {"goalType": "raceTime", "targetDate": "2026-10-04", "distanceKm": 10, "finishTimeSec": 2400}
    assert describe_target("Running", t) == "run 10 km in 40:00 by 2026-10-04"


def test_describe_race_time_over_an_hour():
    t = {"goalType": "raceTime", "targetDate": "2026-10-04", "distanceKm": 21.1, "finishTimeSec": 5400}
    assert describe_target("Running", t) == "run 21.1 km in 1:30:00 by 2026-10-04"


def test_describe_power_hold():
    t = {"goalType": "powerHold", "targetDate": "2026-09-01", "zone": 4, "holdMinutes": 20}
    assert describe_target("Cycling", t) == "hold power zone Z4 for 20 min on the bike by 2026-09-01"


def test_describe_distance_avg_speed():
    t = {"goalType": "distanceAvgSpeed", "targetDate": "2026-09-01", "distanceKm": 100, "avgSpeedKmh": 30}
    assert describe_target("Cycling", t) == "ride 100 km at 30 km/h average by 2026-09-01"


def test_describe_malformed_returns_none():
    assert describe_target("Running", {}) is None
    assert describe_target("Running", {"goalType": "raceTime", "targetDate": "2026-10-04"}) is None
    assert describe_target("Running", {"goalType": "unknown", "targetDate": "2026-10-04"}) is None
    assert describe_target("Running", {"goalType": "raceTime", "targetDate": "2026-10-04", "distanceKm": "x", "finishTimeSec": 2400}) is None
