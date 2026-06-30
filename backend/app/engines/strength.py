"""Strength session assembly — port of StrengthEngine.swift.

The exercise database, intensity ladder, exercise selection, duration estimate,
title classification, recovery warnings, and rationale copy all match Swift.
"""
from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field

from .enums import MuscleGroup
from .readiness import Status


# ── Intensity ladder ─────────────────────────────────────────────────────────
@dataclass(frozen=True)
class Intensity:
    label: str
    primary_sets: int
    primary_reps: str
    accessory_reps: str
    primary_rest: str
    accessory_rest: str

    @property
    def accessory_sets(self) -> int:
        return max(2, self.primary_sets - 1)


HEAVY = Intensity("Heavy", 4, "5–7", "8–12", "2–3 min", "90 sec")
MODERATE = Intensity("Moderate", 3, "8–12", "10–15", "90 sec", "60 sec")
LIGHT = Intensity("Light", 2, "15–20", "15–20", "60 sec", "45 sec")


def _intensity_for(status: Status) -> Intensity:
    if status in (Status.peak, Status.high):
        return HEAVY
    if status == Status.moderate:
        return MODERATE
    return LIGHT  # low, rest


# ── Exercise database ────────────────────────────────────────────────────────
# (name, is_compound, note)  — order matters; selection takes the prefix.
_DB: dict[MuscleGroup, list[tuple[str, bool, str | None]]] = {
    MuscleGroup.chest: [
        ("Barbell Bench Press", True, "Control the descent, full range"),
        ("Incline Dumbbell Press", True, None),
        ("Cable Chest Fly", False, "Squeeze at midpoint"),
        ("Dips", False, None),
    ],
    MuscleGroup.back: [
        ("Pull-Ups", True, "Drive elbows down, not hands"),
        ("Barbell Row", True, "Chest stays up, hinge at hips"),
        ("Seated Cable Row", False, None),
        ("Lat Pulldown", False, None),
    ],
    MuscleGroup.shoulders: [
        ("Overhead Press", True, "Full lockout at top"),
        ("Lateral Raise", False, "Lead with elbow, not wrist"),
        ("Face Pull", False, "External rotation at end range"),
        ("Arnold Press", False, None),
    ],
    MuscleGroup.biceps: [
        ("Barbell Curl", True, None),
        ("Hammer Curl", False, None),
        ("Incline Dumbbell Curl", False, "Stretch at bottom"),
    ],
    MuscleGroup.triceps: [
        ("Skull Crushers", True, "Keep elbows fixed"),
        ("Close-Grip Bench Press", True, None),
        ("Cable Pushdown", False, None),
    ],
    MuscleGroup.quads: [
        ("Back Squat", True, "Break parallel if mobility allows"),
        ("Leg Press", False, None),
        ("Hack Squat", False, None),
        ("Walking Lunge", False, None),
    ],
    MuscleGroup.hamstrings: [
        ("Romanian Deadlift", True, "Maintain neutral spine throughout"),
        ("Leg Curl", False, None),
        ("Nordic Curl", False, "Progress slowly — high injury risk if rushed"),
        ("Good Morning", False, None),
    ],
    MuscleGroup.glutes: [
        ("Hip Thrust", True, "Full hip extension at top"),
        ("Bulgarian Split Squat", True, None),
        ("Cable Kickback", False, None),
    ],
    MuscleGroup.calves: [
        ("Standing Calf Raise", True, "Full stretch at bottom"),
        ("Seated Calf Raise", False, None),
    ],
    MuscleGroup.core: [
        ("Dead Bug", True, "Lower back stays flat throughout"),
        ("Plank", False, None),
        ("Russian Twist", False, None),
        ("Hanging Leg Raise", False, None),
        ("Cable Crunch", False, None),
    ],
}

_PUSH = {MuscleGroup.chest, MuscleGroup.shoulders, MuscleGroup.triceps}
_PULL = {MuscleGroup.back, MuscleGroup.biceps}
_LEGS = {MuscleGroup.quads, MuscleGroup.hamstrings, MuscleGroup.glutes, MuscleGroup.calves}


@dataclass
class ExerciseSuggestion:
    name: str
    muscle_group: MuscleGroup
    sets: int
    reps_range: str
    rest: str
    notes: str | None


@dataclass
class RecentStrengthActivity:
    """A recent strength-training activity used for recovery-window checks."""

    start_time: dt.datetime

    def hours_ago(self, now: dt.datetime) -> float:
        return (now - self.start_time).total_seconds() / 3600


@dataclass
class StrengthSession:
    muscle_groups: list[MuscleGroup]
    title: str
    exercises: list[ExerciseSuggestion]
    duration: int
    intensity_label: str
    rationale: str
    recovery_warnings: list[str] = field(default_factory=list)


def _build_exercises(groups: list[MuscleGroup], intensity: Intensity) -> list[ExerciseSuggestion]:
    per_group = 3 if len(groups) <= 2 else 2
    result: list[ExerciseSuggestion] = []
    for group in groups:
        movements = _DB.get(group, [])
        for i, (name, _is_compound, note) in enumerate(movements[:per_group]):
            is_first = i == 0
            result.append(
                ExerciseSuggestion(
                    name=name,
                    muscle_group=group,
                    sets=intensity.primary_sets if is_first else intensity.accessory_sets,
                    reps_range=intensity.primary_reps if is_first else intensity.accessory_reps,
                    rest=intensity.primary_rest if is_first else intensity.accessory_rest,
                    notes=note if is_first else None,
                )
            )
    return result


def _estimate_duration(exercises: list[ExerciseSuggestion]) -> int:
    total_sets = sum(e.sets for e in exercises)
    return min(90, max(30, 10 + total_sets * 3))  # 10 min warmup + ~3 min/set


def _build_title(groups: list[MuscleGroup]) -> str:
    n = len(groups)
    if n == 0:
        return "Gym Session"
    if n == 1:
        return f"{groups[0].value} Day"
    if n == 2:
        return f"{groups[0].value} + {groups[1].value}"
    has_push = any(g in _PUSH for g in groups)
    has_pull = any(g in _PULL for g in groups)
    has_legs = any(g in _LEGS for g in groups)
    if has_push and not has_pull and not has_legs:
        return "Push Day"
    if not has_push and has_pull and not has_legs:
        return "Pull Day"
    if not has_push and not has_pull and has_legs:
        return "Leg Day"
    return "Full Body"


def _build_recovery_warnings(
    groups: list[MuscleGroup], recent: list[RecentStrengthActivity], now: dt.datetime
) -> list[str]:
    if not recent:
        return []
    last = max(recent, key=lambda a: a.start_time)  # most recent strength session
    hours_ago = last.hours_ago(now)
    warnings: list[str] = []
    for group in groups:
        if hours_ago < group.recovery_hours:
            remaining = int(group.recovery_hours - hours_ago)
            warnings.append(
                f"{group.value} trained {int(hours_ago)}h ago — ~{remaining}h until fully "
                "recovered. Reduce volume on these movements."
            )
    return warnings


def _build_rationale(
    groups: list[MuscleGroup], score: int, status: Status, warning_count: int
) -> str:
    joined = ", ".join(g.value for g in groups[:3])
    if status == Status.peak:
        text = (
            f"Readiness is at {score}/100 — an ideal window for heavy work. The {joined} "
            "session is loaded for strength adaptation: compound lifts first, heavier weights, "
            "longer rest intervals."
        )
    elif status == Status.high:
        text = (
            f"Readiness at {score}/100 supports solid strength work. Stick to your working "
            "weights and focus on controlled reps — no reason to max out today, but no reason "
            "to hold back either."
        )
    elif status == Status.moderate:
        text = (
            f"With readiness at {score}/100, the session is dialled back to moderate intensity. "
            "Prioritise technique and mind-muscle connection. The volume is enough to maintain "
            "strength without adding recovery debt."
        )
    else:  # low, rest
        text = (
            f"Readiness is low ({score}/100). If you train at all, keep loads very light — this "
            "is maintenance work only. Mobility or a walk may be a better investment of today's "
            "energy."
        )
    if warning_count > 0:
        text += " Recovery warnings are noted above — treat those muscle groups with care."
    return text


def generate_session(
    muscle_groups: list[MuscleGroup],
    readiness_status: Status,
    readiness_score: int,
    recent_strength: list[RecentStrengthActivity],
    now: dt.datetime,
) -> StrengthSession:
    intensity = _intensity_for(readiness_status)
    warnings = _build_recovery_warnings(muscle_groups, recent_strength, now)
    exercises = _build_exercises(muscle_groups, intensity)
    duration = _estimate_duration(exercises)
    title = _build_title(muscle_groups)
    rationale = _build_rationale(muscle_groups, readiness_score, readiness_status, len(warnings))

    return StrengthSession(
        muscle_groups=muscle_groups,
        title=title,
        exercises=exercises,
        duration=duration,
        intensity_label=intensity.label,
        rationale=rationale,
        recovery_warnings=warnings,
    )
