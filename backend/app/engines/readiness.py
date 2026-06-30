"""Readiness scoring engine — port of ReadinessEngine.swift (Appendix A).

The scoring and all generated copy match the Swift implementation exactly.
Swift's `Int(Double)` truncates toward zero; Python's `int()` does the same, so
the arithmetic is reproduced faithfully.
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from .enums import TrainingDomain


class Status(str, Enum):
    peak = "Peak"
    high = "High"
    moderate = "Moderate"
    low = "Low"
    rest = "Rest Day"


class Trend(str, Enum):
    up = "up"
    down = "down"
    neutral = "neutral"
    warning = "warning"


@dataclass
class Metrics:
    """Port of TrainingMetrics.swift, including its derived properties."""

    hrv: float
    hrv_baseline: float
    hrv_trend: list[float]
    resting_hr: int
    resting_hr_baseline: int
    sleep_duration: float
    sleep_score: int
    rem_sleep: float
    deep_sleep: float
    sleep_debt: float
    acute_load: float
    chronic_load: float
    today_load: float = 0.0
    weekly_load_change: float = 0.0
    body_weight: float | None = None

    @property
    def training_balance(self) -> float:  # TSB — positive = fresh
        return self.chronic_load - self.acute_load

    @property
    def hrv_change(self) -> float:
        return (self.hrv - self.hrv_baseline) / max(1.0, self.hrv_baseline)

    @property
    def resting_hr_change(self) -> int:
        return self.resting_hr - self.resting_hr_baseline


@dataclass
class MetricInsight:
    label: str
    value: str
    unit: str
    trend: Trend
    explanation: str
    context: str


@dataclass
class SuggestedSession:
    domain: TrainingDomain
    title: str
    duration: int
    intensity_label: str
    intensity_description: str


@dataclass
class ReadinessResult:
    score: int
    status: Status
    verdict: str
    explanation: str
    coaching_note: str
    hrv_score: int
    sleep_score: int
    load_score: int
    recovery_score: int
    session: SuggestedSession
    key_insights: list[MetricInsight]


def _clamp(v: int) -> int:
    return max(0, min(100, v))


# ── Component scores ─────────────────────────────────────────────────────────
def _hrv_score(m: Metrics) -> int:
    deviation = m.hrv_change
    score = int(70 + deviation * 150) if deviation >= 0 else int(70 + deviation * 220)
    return _clamp(score)


def _sleep_score(m: Metrics) -> int:
    d = m.sleep_duration
    if d >= 8:
        duration_score = 100
    elif d >= 7:
        duration_score = 90
    elif d >= 6:
        duration_score = 65
    elif d >= 5:
        duration_score = 40
    else:
        duration_score = 20
    return (duration_score + m.sleep_score) // 2


def _load_score(m: Metrics) -> int:
    tsb = m.training_balance
    if tsb >= 20:
        return 58
    if tsb >= 5:
        return 95
    if tsb >= -5:
        return 100
    if tsb >= -15:
        return 82
    if tsb >= -25:
        return 62
    if tsb >= -35:
        return 42
    return 22


def _status_for(score: int) -> Status:
    if score >= 85:
        return Status.peak
    if score >= 70:
        return Status.high
    if score >= 55:
        return Status.moderate
    if score >= 35:
        return Status.low
    return Status.rest


def status_for_score(score: int) -> Status:
    """Public alias for the status threshold mapping (Appendix A)."""
    return _status_for(score)


def verdict_for(status: Status) -> str:
    """A one-line verdict for the DTO (§6.4). Deterministic from status."""
    return {
        Status.peak: "Prime day — push hard.",
        Status.high: "Good day to train.",
        Status.moderate: "Train, but stay disciplined.",
        Status.low: "Keep it light today.",
        Status.rest: "Rest is the training today.",
    }[status]


# ── Text generation ──────────────────────────────────────────────────────────
def _build_explanation(m: Metrics, status: Status) -> str:
    c = m.hrv_change
    if c > 0.05:
        hrv = (
            f"Your HRV is {int(c * 100)}% above your baseline — your autonomic "
            "nervous system has recovered well."
        )
    elif c < -0.10:
        hrv = (
            f"Your HRV has dropped {int(abs(c) * 100)}% below your "
            f"{int(m.hrv_baseline)} ms baseline, a key signal of accumulated stress."
        )
    else:
        hrv = f"Your HRV is sitting at baseline ({int(m.hrv)} ms), indicating normal recovery."

    if m.sleep_duration >= 7.5:
        sleep = f"Last night's {m.sleep_duration:.1f} hours of sleep was high quality."
    elif m.sleep_duration >= 6.0:
        sleep = (
            f"You got {m.sleep_duration:.1f} hours — adequate, but below the optimal "
            "7.5–9 hours for full recovery."
        )
    else:
        sleep = (
            f"Only {m.sleep_duration:.1f} hours of sleep is insufficient. "
            "Muscle repair and hormonal recovery are compromised."
        )

    tsb = m.training_balance
    if abs(tsb) <= 5:
        load = (
            "Your training load is perfectly balanced — enough fitness base "
            "without carrying excess fatigue."
        )
    elif tsb > 5:
        load = (
            f"You're well-rested with {int(tsb)} points of surplus fitness. "
            "This is an excellent window for quality work."
        )
    elif tsb > -15:
        load = (
            f"You're carrying moderate fatigue (TSB {int(tsb)}). "
            "This is normal mid-block — stay within your structure."
        )
    else:
        load = (
            f"Accumulated fatigue is high (TSB {int(tsb)}). "
            "Your body needs time to absorb the recent training stress."
        )

    return f"{hrv} {sleep} {load}"


def _build_coaching_note(status: Status) -> str:
    return {
        Status.peak: (
            "Conditions are optimal. Push the intensity — your body is primed to "
            "respond to a quality training stimulus today."
        ),
        Status.high: (
            "Good conditions for training. Stay within your planned structure and "
            "you'll have a productive session."
        ),
        Status.moderate: (
            "Train if your plan calls for it, but stay disciplined. Reduce effort if "
            "your body signals resistance."
        ),
        Status.low: (
            "Light movement only. Prioritize movement quality over any fitness output today."
        ),
        Status.rest: (
            "Rest is the training today. Forcing intensity now costs more than it earns. "
            "Let the adaptation happen."
        ),
    }[status]


def _build_insights(m: Metrics) -> list[MetricInsight]:
    c = m.hrv_change
    hrv_trend = Trend.up if c > 0.03 else (Trend.warning if c < -0.05 else Trend.neutral)
    sleep_trend = (
        Trend.neutral if m.sleep_score >= 80 else (Trend.warning if m.sleep_score < 60 else Trend.down)
    )
    tsb = m.training_balance
    tsb_trend = Trend.neutral if abs(tsb) < 10 else (Trend.warning if tsb < -15 else Trend.down)
    hr_diff = m.resting_hr_change
    hr_trend = Trend.up if hr_diff <= 0 else (Trend.warning if hr_diff > 5 else Trend.down)

    if c > 0.03:
        hrv_ctx = f"{int(c * 100)}% above your {int(m.hrv_baseline)} ms average — strong nervous system recovery."
    elif c < -0.05:
        hrv_ctx = f"{int(abs(c) * 100)}% below your {int(m.hrv_baseline)} ms average — autonomic stress is elevated."
    else:
        hrv_ctx = f"Within normal range of your {int(m.hrv_baseline)} ms baseline."

    sleep_debt_txt = (
        " Sleep debt is minimal." if m.sleep_debt < 1 else f" Sleep debt: {m.sleep_debt:.1f} h."
    )

    if abs(tsb) < 10:
        load_ctx = "You're in the optimal zone — sufficient fitness without excessive fatigue."
    elif tsb < -15:
        load_ctx = "High accumulated fatigue. Recovery should be the priority this week."
    else:
        load_ctx = "Moderate fatigue is normal during a build block."

    return [
        MetricInsight(
            label="HRV",
            value=str(int(m.hrv)),
            unit="ms",
            trend=hrv_trend,
            explanation="Above baseline" if c > 0.03 else ("Below baseline" if c < -0.05 else "At baseline"),
            context=hrv_ctx,
        ),
        MetricInsight(
            label="Sleep",
            value=f"{m.sleep_duration:.1f}",
            unit="hrs",
            trend=sleep_trend,
            explanation="Well rested" if m.sleep_score >= 80 else ("Poor sleep" if m.sleep_score < 60 else "Adequate"),
            context=f"Sleep score {m.sleep_score}/100.{sleep_debt_txt}",
        ),
        MetricInsight(
            label="Load",
            value=f"{'+' if tsb >= 0 else ''}{int(tsb)}",
            unit="TSB",
            trend=tsb_trend,
            explanation="Balanced" if abs(tsb) < 10 else ("Fatigued" if tsb < 0 else "Fresh"),
            context=load_ctx,
        ),
        MetricInsight(
            label="Resting HR",
            value=str(m.resting_hr),
            unit="bpm",
            trend=hr_trend,
            explanation=f"{abs(hr_diff)} below baseline" if hr_diff <= 0 else f"{hr_diff} above baseline",
            context=(
                "Your cardiovascular system is efficient today."
                if hr_diff <= 0
                else "Elevated resting HR signals your heart is working harder to maintain recovery."
            ),
        ),
    ]


def _build_session(status: Status) -> SuggestedSession:
    table = {
        Status.peak: SuggestedSession(
            TrainingDomain.cycling, "Zone 3 Intervals", 75, "Threshold",
            "70–85% FTP · Hold power steady through each interval",
        ),
        Status.high: SuggestedSession(
            TrainingDomain.cycling, "Aerobic Endurance", 90, "Moderate",
            "65–75% FTP · Conversational pace throughout",
        ),
        Status.moderate: SuggestedSession(
            TrainingDomain.running, "Easy Run", 45, "Easy",
            "Zone 2 · Keep heart rate below 75% max HR",
        ),
        Status.low: SuggestedSession(
            TrainingDomain.mobility, "Mobility & Stretching", 30, "Very Easy",
            "Focus on hip flexors, hamstrings, and thoracic spine",
        ),
        Status.rest: SuggestedSession(
            TrainingDomain.recovery, "Active Recovery", 20, "Minimal",
            "Short walk or light stretching only",
        ),
    }
    return table[status]


def calculate(m: Metrics) -> ReadinessResult:
    hrv = _hrv_score(m)
    sleep = _sleep_score(m)
    load = _load_score(m)
    recovery = (hrv + sleep + load) // 3
    total = int(hrv * 0.35 + sleep * 0.35 + load * 0.30)
    status = _status_for(total)

    return ReadinessResult(
        score=total,
        status=status,
        verdict=verdict_for(status),
        explanation=_build_explanation(m, status),
        coaching_note=_build_coaching_note(status),
        hrv_score=hrv,
        sleep_score=sleep,
        load_score=load,
        recovery_score=recovery,
        session=_build_session(status),
        key_insights=_build_insights(m),
    )
