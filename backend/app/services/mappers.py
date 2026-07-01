"""Conversions between ORM rows, engine value types, and wire DTOs."""
from __future__ import annotations

import datetime as dt

from ..engines.enums import (
    DaySplit,
    DomainSchedule,
    MuscleGroup,
    TrainingDomain,
    TrainingFrequency,
    WeeklyMuscleGroupSplit,
)
from ..engines import strength as s_engine
from ..engines import workouts
from ..engines.plan import WeeklyPlan, monday_of
from ..engines.readiness import Metrics, ReadinessResult
from ..models import DailyMetrics
from .. import schemas


# ── Metrics ──────────────────────────────────────────────────────────────────
def metrics_from_row(row: DailyMetrics) -> Metrics:
    return Metrics(
        hrv=float(row.hrv),
        hrv_baseline=float(row.hrv_baseline),
        hrv_trend=[float(x) for x in row.hrv_trend],
        resting_hr=row.resting_hr,
        resting_hr_baseline=row.resting_hr_baseline,
        sleep_duration=float(row.sleep_duration),
        sleep_score=row.sleep_score,
        rem_sleep=float(row.rem_sleep),
        deep_sleep=float(row.deep_sleep),
        sleep_debt=float(row.sleep_debt),
        acute_load=float(row.acute_load),
        chronic_load=float(row.chronic_load),
        today_load=float(row.today_load),
        weekly_load_change=float(row.weekly_load_change),
        body_weight=float(row.body_weight) if row.body_weight is not None else None,
    )


def readiness_response(
    date: dt.date,
    result: ReadinessResult,
    ai_explanation: dict | None,
    ai_rationale: str | None = None,
) -> schemas.DailyReadinessResponse:
    s = result.session
    return schemas.DailyReadinessResponse(
        date=date,
        score=result.score,
        status=result.status.value,
        verdict=result.verdict,
        explanation=result.explanation,
        coaching_note=result.coaching_note,
        component_scores=schemas.ComponentScores(
            hrv=result.hrv_score,
            sleep=result.sleep_score,
            load=result.load_score,
            recovery=result.recovery_score,
        ),
        suggested_session=schemas.SuggestedSessionDTO(
            domain=s.domain.value,
            title=s.title,
            duration=s.duration,
            intensity_label=s.intensity_label,
            intensity_description=s.intensity_description,
            ai_rationale=ai_rationale,
        ),
        key_insights=[
            schemas.KeyInsight(
                label=i.label,
                value=i.value,
                unit=i.unit,
                trend=i.trend.value,
                explanation=i.explanation,
                context=i.context,
            )
            for i in result.key_insights
        ],
        ai_explanation=schemas.AiExplanation(**ai_explanation) if ai_explanation else None,
    )


# ── Preferences → engine inputs ──────────────────────────────────────────────
def schedules_from_prefs(domain_schedules: list[dict]) -> TrainingFrequency:
    scheds: list[DomainSchedule] = []
    for entry in domain_schedules:
        try:
            domain = TrainingDomain(entry["domain"])
            weekdays = {int(w) for w in entry.get("weekdays", []) if 0 <= int(w) <= 6}
        except (KeyError, ValueError):
            continue
        scheds.append(DomainSchedule(domain, weekdays))
    return TrainingFrequency(schedules=scheds)


def priority_from_prefs(enabled_domains: list[str]) -> list[TrainingDomain]:
    """Enabled-domain order, used to sort sessions that share a weekday."""
    out: list[TrainingDomain] = []
    for d in enabled_domains:
        try:
            out.append(TrainingDomain(d))
        except ValueError:
            continue
    return out


def split_from_prefs(muscle_group_split: list[dict]) -> WeeklyMuscleGroupSplit:
    if len(muscle_group_split) != 7:
        # Default to a 7-day all-rest split; strength sessions become "Full Body".
        return WeeklyMuscleGroupSplit(days=[DaySplit(is_rest_day=True) for _ in range(7)])
    days: list[DaySplit] = []
    for entry in muscle_group_split:
        groups = [MuscleGroup(g) for g in entry.get("muscleGroups", []) if g in MuscleGroup._value2member_map_]
        days.append(DaySplit(muscle_groups=groups, is_rest_day=bool(entry.get("isRestDay", False))))
    return WeeklyMuscleGroupSplit(days=days)


# ── Plan serialization ───────────────────────────────────────────────────────
def _exercise_to_json(e: s_engine.ExerciseSuggestion) -> dict:
    return {
        "name": e.name,
        "muscleGroup": e.muscle_group.value,
        "sets": e.sets,
        "repsRange": e.reps_range,
        "rest": e.rest,
        "notes": e.notes,
    }


def plan_days_to_json(plan: WeeklyPlan, cycling_target: str = "hr") -> list[dict]:
    out: list[dict] = []
    for day in plan.days:
        sessions = []
        for s in day.sessions:
            # Prefer the AI-authored structured workout; else derive it deterministically.
            workout = s.workout_override or workouts.workout_to_dict(
                workouts.build_workout(
                    s.domain.value, s.title, s.intensity_label, s.duration, cycling_target
                )
            )
            entry = {
                "domain": s.domain.value,
                "title": s.title,
                "subtitle": s.subtitle,
                "duration": s.duration,
                "intensityLabel": s.intensity_label,
                "workout": workout,
            }
            # Strength sessions carry a movement-by-movement breakdown (curated DB,
            # loaded per the session's intensity) instead of an effort graph. When
            # the day's split has no groups (a "Full Body" day) exercises_for falls
            # back to a full-body selection, so there's always a list.
            if s.domain.value == "Strength":
                groups = getattr(s, "muscle_groups", None) or []
                exercises = s_engine.exercises_for(groups, s.intensity_label)
                entry["exercises"] = [_exercise_to_json(e) for e in exercises]
            sessions.append(entry)
        out.append({"date": day.date.isoformat(), "isRest": day.is_rest, "sessions": sessions})
    return out


def _week_label(week_start: dt.date) -> str:
    end = week_start + dt.timedelta(days=6)
    return f"{week_start:%b} {week_start.day} – {end:%b} {end.day}"


def plan_dto_from_row(
    week_start: dt.date, days_json: list[dict], generated_at: dt.datetime, row_id, today: dt.date
) -> schemas.WeeklyPlanDTO:
    day_dtos: list[schemas.PlannedDayDTO] = []
    for entry in days_json:
        date = dt.date.fromisoformat(entry["date"])
        session_dtos = [
            schemas.PlannedSessionDTO(
                domain=s["domain"],
                title=s["title"],
                subtitle=s.get("subtitle"),
                duration=s["duration"],
                intensity_label=s["intensityLabel"],
                workout=s.get("workout"),
                exercises=(
                    [schemas.ExerciseDTO.model_validate(e) for e in s["exercises"]]
                    if s.get("exercises")
                    else None
                ),
            )
            for s in entry.get("sessions", [])
        ]
        day_dtos.append(
            schemas.PlannedDayDTO(
                date=date,
                weekday_short=f"{date:%a}",
                day_number=str(date.day),
                is_rest=bool(entry.get("isRest", not session_dtos)),
                is_today=date == today,
                is_past=date < today,
                sessions=session_dtos,
            )
        )
    return schemas.WeeklyPlanDTO(
        id=row_id,
        week_start=week_start,
        week_label=_week_label(week_start),
        is_current_week=monday_of(today) == week_start,
        days=day_dtos,
        generated_at=generated_at,
    )
