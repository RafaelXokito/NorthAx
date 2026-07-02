"""AI-authored plan generation (§7.6 + §8).

Builds the deterministic weekly skeleton — which sport trains on which day is a
fixed user preference — then asks the AI to personalise each session's content
and its two-week progression from the athlete's recent activities and current
metrics. The AI is best-effort (§8.5): on any failure the deterministic session
is kept, so the endpoint always returns a valid plan.
"""
from __future__ import annotations

import datetime as dt
import uuid

from sqlalchemy import delete, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from ..engines import readiness as r_engine
from ..engines import workouts
from ..engines.plan import generate_plans, monday_of
from ..models import Activity, DailyMetrics, UserPreferences, WeeklyPlanRow
from . import ai, goal_progress, mappers

_ALLOWED_INTENSITIES = set(ai.PLAN_INTENSITIES)
_WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


async def _load_prefs(session: AsyncSession, user_id: str) -> UserPreferences | None:
    return await session.get(UserPreferences, uuid.UUID(str(user_id)))


async def _athlete_context(
    session: AsyncSession, user_id: str, prefs: UserPreferences | None
) -> str:
    """Human-readable athlete profile: current recovery state + training history,
    with explicit average-person fallbacks when either is missing."""
    lines: list[str] = []

    today = dt.date.today()
    row = (
        await session.execute(
            select(DailyMetrics).where(
                DailyMetrics.user_id == uuid.UUID(user_id), DailyMetrics.date == today
            )
        )
    ).scalar_one_or_none()
    if row is not None:
        m = mappers.metrics_from_row(row)
        result = r_engine.calculate(m)
        lines.append(
            f"Readiness today: {result.score}/100 ({result.status.value}). "
            f"HRV {m.hrv:g} ms ({int(m.hrv_change * 100):+d}% vs baseline). "
            f"Sleep {m.sleep_duration:g} h (score {m.sleep_score}/100). "
            f"Training balance TSB {int(m.training_balance)} (ATL {m.acute_load:g}, CTL {m.chronic_load:g}). "
            f"Resting HR {m.resting_hr} bpm ({m.resting_hr_change:+d} vs baseline)."
        )
    else:
        lines.append(
            "No recent health metrics available — assume a healthy recreational "
            "athlete of average fitness with no acute fatigue."
        )

    acts = (
        await session.execute(
            select(Activity)
            .where(Activity.user_id == uuid.UUID(user_id))
            .order_by(Activity.start_time.desc())
            .limit(20)
        )
    ).scalars().all()
    if acts:
        summary = "; ".join(
            f"{a.start_time:%b %d} {a.name} ({a.domain}, {a.duration_seconds // 60} min"
            + (f", load {float(a.training_load):.0f}" if a.training_load is not None else "")
            + ")"
            for a in acts
        )
        lines.append(f"Recent activities (most recent first): {summary}.")
    else:
        lines.append(
            "No training history on file — assume an average recreationally active "
            "person as the baseline and progress load conservatively."
        )

    targets = (getattr(prefs, "sport_targets", {}) if prefs else {}) or {}
    for domain, t in targets.items():
        desc = goal_progress.describe_target(domain, t) if isinstance(t, dict) else None
        if desc:
            lines.append(f"Athlete goal ({domain}): {desc}.")
    return "\n".join(lines)


def _enumerate_sessions(plans):
    """Assign a stable id to every session across the block. Returns
    (id -> PlannedSession, prompt block). Strength sessions carry their muscle
    focus (the deterministic title) so the AI keeps the split."""
    id_map = {}
    lines: list[str] = []
    sid = 0
    for week_index, plan in enumerate(plans):
        for day in plan.days:
            for s in day.sessions:
                id_map[sid] = s
                focus = f' — muscle focus: {s.title}' if s.domain.value == "Strength" else ""
                lines.append(
                    f"id {sid}: Week {week_index + 1}, {_WEEKDAYS[day.date.weekday()]} "
                    f"{day.date.isoformat()} — {s.domain.value}{focus}"
                )
                sid += 1
    return id_map, "\n".join(lines)


def apply_overrides(id_map: dict, parsed: dict, cycling_target: str) -> None:
    """Merge validated AI fields into the skeleton sessions in place. Unknown ids,
    out-of-range durations, off-vocabulary intensities, and malformed blocks are
    ignored so a partial or noisy response still yields a valid plan."""
    for entry in parsed.get("sessions", []):
        if not isinstance(entry, dict):
            continue
        try:
            sid = int(entry["id"])
        except (KeyError, ValueError, TypeError):
            continue
        s = id_map.get(sid)
        if s is None:
            continue
        title, subtitle = entry.get("title"), entry.get("subtitle")
        duration, intensity = entry.get("duration"), entry.get("intensityLabel")
        if isinstance(title, str) and title.strip():
            s.title = title.strip()[:80]
        if isinstance(subtitle, str) and subtitle.strip():
            s.subtitle = subtitle.strip()[:120]
        if isinstance(duration, (int, float)) and 15 <= int(duration) <= 240:
            s.duration = int(duration)
        if isinstance(intensity, str) and intensity.strip() in _ALLOWED_INTENSITIES:
            s.intensity_label = intensity.strip()
        # Endurance sessions: adopt the AI's structured blocks when they validate
        # (zones → intervals.icu tokens happen in build_from_ai_blocks). Malformed
        # or non-endurance → None, and plan_days_to_json falls back deterministically.
        built = workouts.build_from_ai_blocks(s.domain.value, cycling_target, entry.get("blocks"))
        if built is not None:
            s.workout_override = workouts.workout_to_dict(built)


async def prepare(
    session: AsyncSession, user_id: str, from_date: dt.date, weeks: int
):
    """Read phase: build the deterministic skeleton and the AI prompt inputs from
    the stored preferences + athlete context. Returns plain values (no ORM state
    bound to `session`) so the caller can close the connection before the slow AI
    call — important under multi-user load. Returns
    (plans, id_map, prompt_block, athlete_context, cycling_target)."""
    prefs = await _load_prefs(session, user_id)
    frequency = mappers.schedules_from_prefs(prefs.domain_schedules if prefs else [])
    split = mappers.split_from_prefs(prefs.muscle_group_split if prefs else [])
    cycling_target = getattr(prefs, "cycling_target", "hr") if prefs else "hr"
    priority = mappers.priority_from_prefs(prefs.enabled_domains if prefs else [])

    plans = generate_plans(from_date, weeks, frequency, split, priority)
    id_map, block = _enumerate_sessions(plans)
    context = await _athlete_context(session, user_id, prefs) if id_map else ""
    return plans, id_map, block, context, cycling_target


async def persist(
    session: AsyncSession,
    user_id: str,
    from_date: dt.date,
    weeks: int,
    plans,
    cycling_target: str,
) -> list[WeeklyPlanRow]:
    """Write phase: upsert the (possibly AI-enriched) plans and drop any future
    weeks beyond the block (the AI horizon is `weeks` only)."""
    rows: list[WeeklyPlanRow] = []
    for plan in plans:
        days_json = mappers.plan_days_to_json(plan, cycling_target)
        stmt = (
            pg_insert(WeeklyPlanRow)
            .values(user_id=uuid.UUID(str(user_id)), week_start=plan.week_start, days=days_json)
            .on_conflict_do_update(
                index_elements=[WeeklyPlanRow.user_id, WeeklyPlanRow.week_start],
                set_={"days": days_json, "generated_at": func.now()},
            )
            .returning(WeeklyPlanRow)
        )
        rows.append((await session.execute(stmt)).scalar_one())

    horizon = monday_of(from_date) + dt.timedelta(weeks=weeks)
    await session.execute(
        delete(WeeklyPlanRow).where(
            WeeklyPlanRow.user_id == uuid.UUID(str(user_id)),
            WeeklyPlanRow.week_start >= horizon,
        )
    )
    return rows
