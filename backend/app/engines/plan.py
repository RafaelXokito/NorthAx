"""Weekly plan generation — port of PlanEngine.swift (Appendix B).

Reproduces the rest-day placement table, the greedy interleaving queue (with
Swift's first-maximum tie-breaking), and the per-domain/per-slot session
variants exactly.
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
    session: PlannedSession | None
    is_rest: bool


@dataclass
class WeeklyPlan:
    week_start: dt.date
    days: list[PlannedDay] = field(default_factory=list)


# ── Calendar helper ──────────────────────────────────────────────────────────
def monday_of(date: dt.date) -> dt.date:
    """Monday of the week containing `date` (weekStart is always a Monday)."""
    return date - dt.timedelta(days=date.weekday())  # weekday(): Mon=0 … Sun=6


# ── Rest-day placement ───────────────────────────────────────────────────────
def _rest_day_positions(rest_count: int) -> set[int]:
    """Index 0 = Monday, 6 = Sunday. Maximises recovery gaps."""
    return {
        0: set(),
        1: {6},
        2: {3, 6},
        3: {1, 4, 6},
        4: {1, 3, 5, 6},
        5: {1, 2, 4, 5, 6},
        6: {1, 2, 3, 4, 5, 6},
    }.get(rest_count, set(range(7)))


# ── Greedy session queue (avoids back-to-back same sport) ────────────────────
@dataclass
class _Remaining:
    domain: TrainingDomain
    left: int


def _pick_next(remaining: list[_Remaining], avoid: TrainingDomain | None) -> int:
    """Index of the highest-remaining domain, preferring one different from
    `avoid`. Ties resolve to the first maximum (matching Swift `max(by:)`)."""
    if avoid is not None:
        candidates = [(i, r) for i, r in enumerate(remaining) if r.domain != avoid]
        if candidates:
            best = candidates[0]
            for cand in candidates[1:]:
                if best[1].left < cand[1].left:
                    best = cand
            return best[0]
    best_idx = 0
    for i in range(1, len(remaining)):
        if remaining[best_idx].left < remaining[i].left:
            best_idx = i
    return best_idx


def _make_session_queue(frequency: TrainingFrequency, target_count: int) -> list[TrainingDomain]:
    # Build remaining-count table, highest first (stable sort preserves input
    # order on ties, the deterministic reading of Swift's sort).
    remaining = sorted(
        (
            _Remaining(d.domain, min(d.days_per_week, target_count))
            for d in frequency.domain_frequencies
            if d.days_per_week > 0
        ),
        key=lambda r: r.left,
        reverse=True,
    )

    queue: list[TrainingDomain] = []
    last: TrainingDomain | None = None
    while len(queue) < target_count and remaining:
        idx = _pick_next(remaining, last)
        queue.append(remaining[idx].domain)
        last = remaining[idx].domain
        remaining[idx].left -= 1
        remaining = [r for r in remaining if r.left > 0]
    return queue


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
    start: dt.date, frequency: TrainingFrequency, split: WeeklyMuscleGroupSplit
) -> WeeklyPlan:
    total_sessions = min(frequency.total_training_days, 6)  # always ≥1 rest day
    rest_slots = _rest_day_positions(7 - total_sessions)
    queue = _make_session_queue(frequency, total_sessions)

    days: list[PlannedDay] = []
    for offset in range(7):
        date = start + dt.timedelta(days=offset)
        if offset in rest_slots or not queue:
            days.append(PlannedDay(date=date, session=None, is_rest=True))
        else:
            domain = queue.pop(0)
            session = _make_session(domain, offset, split)
            days.append(PlannedDay(date=date, session=session, is_rest=False))
    return WeeklyPlan(week_start=start, days=days)


def generate_plans(
    from_date: dt.date,
    weeks: int,
    frequency: TrainingFrequency,
    muscle_group_split: WeeklyMuscleGroupSplit,
) -> list[WeeklyPlan]:
    """Generate `weeks` consecutive weekly plans from the Monday of `from_date`."""
    monday = monday_of(from_date)
    return [
        _generate_week(monday + dt.timedelta(weeks=offset), frequency, muscle_group_split)
        for offset in range(weeks)
    ]
