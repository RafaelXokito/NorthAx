"""Weekly plan generation — port of PlanEngine.swift (Appendix B).

Each enrolled sport places one session on each of its scheduled weekdays. Days
that several sports share carry multiple sessions (ordered by enabled-domain
priority). Days no sport schedules are rest days.
"""
from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field

from .enums import TrainingDomain, TrainingFrequency, WeeklyMuscleGroupSplit


@dataclass
class PlannedSession:
    domain: TrainingDomain
    title: str
    subtitle: str
    duration: int
    intensity_label: str


@dataclass
class PlannedDay:
    date: dt.date
    sessions: list[PlannedSession]
    is_rest: bool


@dataclass
class WeeklyPlan:
    week_start: dt.date
    days: list[PlannedDay] = field(default_factory=list)


# ── Calendar helper ──────────────────────────────────────────────────────────
def monday_of(date: dt.date) -> dt.date:
    """Monday of the week containing `date` (weekStart is always a Monday)."""
    return date - dt.timedelta(days=date.weekday())  # weekday(): Mon=0 … Sun=6


# ── Session building ─────────────────────────────────────────────────────────
def _make_session(
    domain: TrainingDomain, slot: int, split: WeeklyMuscleGroupSplit
) -> PlannedSession:
    if domain == TrainingDomain.cycling:
        variants = [
            ("Zone 3 Intervals", "70–85% FTP · 5×8 min efforts", 75, "Threshold"),
            ("Aerobic Endurance", "65–75% FTP · Steady state", 90, "Moderate"),
            ("Easy Recovery Ride", "55–65% FTP · Active recovery", 60, "Easy"),
        ]
        t, s, dur, lab = variants[slot % len(variants)]
        return PlannedSession(domain, t, s, dur, lab)

    if domain == TrainingDomain.running:
        variants = [
            ("Easy Run", "Zone 2 · Conversational pace", 45, "Easy"),
            ("Tempo Run", "Comfortably hard · ~80% max HR", 40, "Hard"),
            ("Long Run", "Zone 1–2 · Building endurance", 70, "Easy"),
        ]
        t, s, dur, lab = variants[slot % len(variants)]
        return PlannedSession(domain, t, s, dur, lab)

    if domain == TrainingDomain.strength:
        day_split = split.split_for_monday_index(slot)
        group_label = (
            "Full Body" if (day_split.is_rest_day or not day_split.muscle_groups) else day_split.display_name
        )
        return PlannedSession(domain, group_label, "Gym · Per your weekly split", 60, "Moderate")

    if domain == TrainingDomain.swimming:
        variants = [
            ("Interval Set", "8×100m at race pace", 55, "Hard"),
            ("Technique Session", "Drills + aerobic endurance", 45, "Moderate"),
        ]
        t, s, dur, lab = variants[slot % len(variants)]
        return PlannedSession(domain, t, s, dur, lab)

    if domain == TrainingDomain.triathlon:
        return PlannedSession(domain, "Brick Session", "60 min bike + 20 min run", 90, "Moderate")

    if domain == TrainingDomain.mobility:
        return PlannedSession(
            domain, "Mobility Flow", "Yoga · Hip flexors, hamstrings, spine", 40, "Easy"
        )

    # recovery
    return PlannedSession(domain, "Active Recovery", "Short walk or light stretching", 25, "Very Easy")


def _generate_week(
    start: dt.date,
    frequency: TrainingFrequency,
    split: WeeklyMuscleGroupSplit,
    priority: list[TrainingDomain],
) -> WeeklyPlan:
    # weekday → ordered list of domains training that day (enabled-domain order).
    by_weekday: dict[int, list[TrainingDomain]] = {i: [] for i in range(7)}
    rank = {d: i for i, d in enumerate(priority)}
    schedules = sorted(
        frequency.schedules, key=lambda s: rank.get(s.domain, len(priority))
    )
    for sched in schedules:
        for wd in sched.weekdays:
            if 0 <= wd <= 6:
                by_weekday[wd].append(sched.domain)

    days: list[PlannedDay] = []
    for offset in range(7):
        date = start + dt.timedelta(days=offset)
        domains = by_weekday[offset]
        sessions = [_make_session(d, offset, split) for d in domains]
        days.append(PlannedDay(date=date, sessions=sessions, is_rest=not sessions))
    return WeeklyPlan(week_start=start, days=days)


def generate_plans(
    from_date: dt.date,
    weeks: int,
    frequency: TrainingFrequency,
    muscle_group_split: WeeklyMuscleGroupSplit,
    priority: list[TrainingDomain] | None = None,
) -> list[WeeklyPlan]:
    """Generate `weeks` consecutive weekly plans from the Monday of `from_date`.

    `priority` is the enabled-domain order used to sort sessions that share a
    weekday; defaults to the order the schedules appear in.
    """
    if priority is None:
        priority = [s.domain for s in frequency.schedules]
    monday = monday_of(from_date)
    return [
        _generate_week(monday + dt.timedelta(weeks=offset), frequency, muscle_group_split, priority)
        for offset in range(weeks)
    ]
