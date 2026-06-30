"""Parity tests for the plan engine (Appendix B)."""
import datetime as dt

from app.engines.enums import (
    DaySplit,
    DomainFrequency,
    TrainingDomain,
    TrainingFrequency,
    WeeklyMuscleGroupSplit,
)
from app.engines.plan import generate_plans, monday_of

EMPTY_SPLIT = WeeklyMuscleGroupSplit(days=[DaySplit(is_rest_day=True) for _ in range(7)])
DEFAULT_FREQ = TrainingFrequency(
    domain_frequencies=[
        DomainFrequency(TrainingDomain.cycling, 3),
        DomainFrequency(TrainingDomain.strength, 2),
    ]
)


def test_monday_of():
    # 2026-06-29 is a Monday; 2026-07-01 (Wed) maps back to it.
    assert monday_of(dt.date(2026, 7, 1)) == dt.date(2026, 6, 29)
    assert monday_of(dt.date(2026, 6, 29)) == dt.date(2026, 6, 29)


def test_default_frequency_week():
    plans = generate_plans(dt.date(2026, 6, 29), 1, DEFAULT_FREQ, EMPTY_SPLIT)
    week = plans[0]
    assert week.week_start == dt.date(2026, 6, 29)
    assert len(week.days) == 7

    rest_indices = [i for i, d in enumerate(week.days) if d.is_rest]
    assert rest_indices == [3, 6]  # 5 sessions → rest at Thu, Sun

    # Greedy interleave avoids back-to-back same domain.
    assert week.days[0].session.domain == TrainingDomain.cycling
    assert week.days[0].session.title == "Zone 3 Intervals"
    assert week.days[1].session.domain == TrainingDomain.strength
    assert week.days[2].session.domain == TrainingDomain.cycling


def test_no_back_to_back_same_domain():
    plans = generate_plans(dt.date(2026, 6, 29), 1, DEFAULT_FREQ, EMPTY_SPLIT)
    sessions = [d.session.domain for d in plans[0].days if d.session]
    for a, b in zip(sessions, sessions[1:]):
        assert a != b


def test_four_weeks_consecutive_mondays():
    plans = generate_plans(dt.date(2026, 6, 29), 4, DEFAULT_FREQ, EMPTY_SPLIT)
    starts = [p.week_start for p in plans]
    assert starts == [
        dt.date(2026, 6, 29),
        dt.date(2026, 7, 6),
        dt.date(2026, 7, 13),
        dt.date(2026, 7, 20),
    ]
