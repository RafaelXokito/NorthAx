"""Domain enums and value types shared by the engines.

Ports TrainingDomain.swift, MuscleGroup.swift, and TrainingFrequency.swift.
Raw values match the Swift `rawValue` strings exactly so JSON is interchangeable
with the iOS client.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class TrainingDomain(str, Enum):
    cycling = "Cycling"
    running = "Running"
    strength = "Strength"
    swimming = "Swimming"
    triathlon = "Triathlon"
    mobility = "Mobility"
    recovery = "Recovery"


class MuscleGroup(str, Enum):
    chest = "Chest"
    back = "Back"
    shoulders = "Shoulders"
    biceps = "Biceps"
    triceps = "Triceps"
    quads = "Quads"
    hamstrings = "Hamstrings"
    glutes = "Glutes"
    calves = "Calves"
    core = "Core"

    @property
    def recovery_hours(self) -> int:
        """Minimum recovery time (hours) before this group can be trained again."""
        return _RECOVERY_HOURS[self]


_RECOVERY_HOURS: dict[MuscleGroup, int] = {
    MuscleGroup.quads: 72,
    MuscleGroup.hamstrings: 72,
    MuscleGroup.glutes: 72,
    MuscleGroup.chest: 60,
    MuscleGroup.back: 60,
    MuscleGroup.shoulders: 48,
    MuscleGroup.biceps: 48,
    MuscleGroup.triceps: 48,
    MuscleGroup.calves: 36,
    MuscleGroup.core: 36,
}


# ── Training frequency (TrainingFrequency.swift) ─────────────────────────────
@dataclass
class DomainFrequency:
    domain: TrainingDomain
    days_per_week: int  # 0–6


@dataclass
class TrainingFrequency:
    domain_frequencies: list[DomainFrequency] = field(default_factory=list)

    @property
    def total_training_days(self) -> int:
        return sum(d.days_per_week for d in self.domain_frequencies)

    @property
    def is_overloaded(self) -> bool:
        return self.total_training_days > 6


# ── Muscle-group split (MuscleGroup.swift: DaySplit / WeeklyMuscleGroupSplit) ─
@dataclass
class DaySplit:
    muscle_groups: list[MuscleGroup] = field(default_factory=list)
    is_rest_day: bool = False

    @property
    def display_name(self) -> str:
        if self.is_rest_day or not self.muscle_groups:
            return "Rest"
        if len(self.muscle_groups) > 2:
            return f"{self.muscle_groups[0].value} + {len(self.muscle_groups) - 1} more"
        return " + ".join(g.value for g in self.muscle_groups)


@dataclass
class WeeklyMuscleGroupSplit:
    """Seven entries, index 0 = Monday, 6 = Sunday."""

    days: list[DaySplit]

    def __post_init__(self) -> None:
        if len(self.days) != 7:
            raise ValueError("WeeklyMuscleGroupSplit requires exactly 7 days")

    def split_for_monday_index(self, idx: int) -> DaySplit:
        return self.days[idx]
