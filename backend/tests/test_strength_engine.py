"""Parity tests for the strength engine (StrengthEngine.swift)."""
import datetime as dt

from app.engines import strength as engine
from app.engines.enums import MuscleGroup
from app.engines.readiness import Status, status_for_score

NOW = dt.datetime(2026, 6, 29, 12, 0, tzinfo=dt.timezone.utc)
PUSH = [MuscleGroup.chest, MuscleGroup.shoulders, MuscleGroup.triceps]


def test_push_day_heavy():
    s = engine.generate_session(PUSH, status_for_score(90), 90, [], NOW)
    assert s.title == "Push Day"
    assert s.intensity_label == "Heavy"
    # 3 groups → 2 exercises each.
    assert len(s.exercises) == 6
    first = s.exercises[0]
    assert first.name == "Barbell Bench Press"
    assert first.sets == 4
    assert first.reps_range == "5–7"
    assert first.notes == "Control the descent, full range"
    # accessory uses primary_sets - 1
    assert s.exercises[1].sets == 3
    assert s.exercises[1].notes is None
    # duration: 21 sets → 10 + 21*3 = 73
    assert s.duration == 73
    assert s.recovery_warnings == []


def test_single_group_three_exercises():
    s = engine.generate_session([MuscleGroup.chest], status_for_score(60), 60, [], NOW)
    assert s.title == "Chest Day"
    assert len(s.exercises) == 3  # ≤2 groups → 3 per group
    assert s.intensity_label == "Moderate"


def test_recovery_warning_within_window():
    # Strength session 24h ago; chest needs 60h → warning expected.
    recent = [engine.RecentStrengthActivity(start_time=NOW - dt.timedelta(hours=24))]
    s = engine.generate_session([MuscleGroup.chest], Status.peak, 90, recent, NOW)
    assert len(s.recovery_warnings) == 1
    assert "Chest trained 24h ago" in s.recovery_warnings[0]


def test_leg_day_classification():
    legs = [MuscleGroup.quads, MuscleGroup.hamstrings, MuscleGroup.glutes]
    s = engine.generate_session(legs, Status.moderate, 60, [], NOW)
    assert s.title == "Leg Day"
