"""Parity tests for the plan engine (Appendix B)."""
import datetime as dt

from app.engines.enums import (
    DaySplit,
    DomainSchedule,
    TrainingDomain,
    TrainingFrequency,
    WeeklyMuscleGroupSplit,
)
from app.engines.plan import generate_plans, monday_of

EMPTY_SPLIT = WeeklyMuscleGroupSplit(days=[DaySplit(is_rest_day=True) for _ in range(7)])
# Cycling on Mon/Wed/Fri (0,2,4), Strength on Tue/Sat (1,5) → Thu & Sun rest.
DEFAULT_FREQ = TrainingFrequency(
    schedules=[
        DomainSchedule(TrainingDomain.cycling, {0, 2, 4}),
        DomainSchedule(TrainingDomain.strength, {1, 5}),
    ]
)
PRIORITY = [TrainingDomain.cycling, TrainingDomain.strength]


def test_monday_of():
    # 2026-06-29 is a Monday; 2026-07-01 (Wed) maps back to it.
    assert monday_of(dt.date(2026, 7, 1)) == dt.date(2026, 6, 29)
    assert monday_of(dt.date(2026, 6, 29)) == dt.date(2026, 6, 29)


def test_total_training_days_is_union():
    # Cycling Mon/Wed/Fri + Strength Tue/Sat = 5 distinct days.
    assert DEFAULT_FREQ.total_training_days == 5
    # Overlapping days collapse in the union.
    overlap = TrainingFrequency(
        schedules=[
            DomainSchedule(TrainingDomain.cycling, {0, 2}),
            DomainSchedule(TrainingDomain.running, {0, 3}),
        ]
    )
    assert overlap.total_training_days == 3  # {0,2,3}


def test_default_schedule_week():
    plans = generate_plans(dt.date(2026, 6, 29), 1, DEFAULT_FREQ, EMPTY_SPLIT, PRIORITY)
    week = plans[0]
    assert week.week_start == dt.date(2026, 6, 29)
    assert len(week.days) == 7

    rest_indices = [i for i, d in enumerate(week.days) if d.is_rest]
    assert rest_indices == [3, 6]  # Thu, Sun have no enrolled sport

    # Sessions land on exactly the scheduled weekdays.
    assert week.days[0].sessions[0].domain == TrainingDomain.cycling
    assert week.days[0].sessions[0].title == "Zone 3 Intervals"
    assert week.days[1].sessions[0].domain == TrainingDomain.strength
    assert week.days[2].sessions[0].domain == TrainingDomain.cycling
    assert week.days[3].sessions == []  # rest


def test_multiple_sports_same_day_ordered_by_priority():
    freq = TrainingFrequency(
        schedules=[
            DomainSchedule(TrainingDomain.strength, {0}),
            DomainSchedule(TrainingDomain.cycling, {0}),
        ]
    )
    # Priority puts cycling first even though strength's schedule comes first.
    plans = generate_plans(dt.date(2026, 6, 29), 1, freq, EMPTY_SPLIT, PRIORITY)
    monday = plans[0].days[0]
    assert [s.domain for s in monday.sessions] == [
        TrainingDomain.cycling,
        TrainingDomain.strength,
    ]
    assert monday.is_rest is False


def test_four_weeks_consecutive_mondays():
    plans = generate_plans(dt.date(2026, 6, 29), 4, DEFAULT_FREQ, EMPTY_SPLIT, PRIORITY)
    starts = [p.week_start for p in plans]
    assert starts == [
        dt.date(2026, 6, 29),
        dt.date(2026, 7, 6),
        dt.date(2026, 7, 13),
        dt.date(2026, 7, 20),
    ]
