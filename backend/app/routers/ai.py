"""AI endpoints (§7.9, §7.10): coach chat (SSE), session suggestion, strength."""
from __future__ import annotations

import datetime as dt
import json
import uuid

from fastapi import APIRouter, Depends, Query, status
from fastapi.responses import StreamingResponse
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..db import session_scope
from ..deps import get_current_user_id, get_db
from ..engines import readiness as r_engine
from ..engines import strength as s_engine
from ..engines import workouts
from ..engines.enums import MuscleGroup, TrainingDomain
from ..engines.plan import monday_of
from ..errors import metrics_not_found
from ..models import Activity, CoachMessage, DailyMetrics, User, UserPreferences, WeeklyPlanRow
from ..rate_limit import limit
from ..services import ai, mappers

router = APIRouter(prefix="/ai", tags=["ai"])

_MAX_HISTORY = 50  # §8.5


# ── Context assembly (§8.2) ──────────────────────────────────────────────────
async def _today_metrics(session: AsyncSession, user_id: str) -> DailyMetrics | None:
    result = await session.execute(
        select(DailyMetrics).where(
            DailyMetrics.user_id == uuid.UUID(user_id), DailyMetrics.date == dt.date.today()
        )
    )
    return result.scalar_one_or_none()


async def _build_coach_system(session: AsyncSession, user_id: str) -> str:
    user = await session.get(User, uuid.UUID(user_id))
    name = user.name if user else "Athlete"

    row = await _today_metrics(session, user_id)
    if row is not None:
        m = mappers.metrics_from_row(row)
        result = r_engine.calculate(m)
        score, statuslabel = result.score, result.status.value
        hrv, hrv_pct = f"{m.hrv:g}", int(m.hrv_change * 100)
        sleep_dur, sleep_score = f"{m.sleep_duration:g}", m.sleep_score
        tsb = int(m.training_balance)
    else:
        score, statuslabel = "n/a", "unknown"
        hrv, hrv_pct, sleep_dur, sleep_score, tsb = "n/a", 0, "n/a", "n/a", "n/a"

    acts = await session.execute(
        select(Activity)
        .where(Activity.user_id == uuid.UUID(user_id))
        .order_by(Activity.start_time.desc())
        .limit(5)
    )
    recent = acts.scalars().all()
    recent_summary = (
        "; ".join(f"{a.name} ({a.domain}, {a.duration_seconds // 60} min)" for a in recent)
        or "none logged"
    )

    monday = dt.date.today() - dt.timedelta(days=dt.date.today().weekday())
    plan_row = await session.execute(
        select(WeeklyPlanRow).where(
            WeeklyPlanRow.user_id == uuid.UUID(user_id), WeeklyPlanRow.week_start == monday
        )
    )
    plan = plan_row.scalar_one_or_none()
    if plan:
        titles = [s["title"] for d in plan.days for s in d.get("sessions", [])]
        week_summary = ", ".join(titles) if titles else "all rest"
    else:
        week_summary = "no plan generated"

    return ai.COACH_SYSTEM_TEMPLATE.format(
        athlete_name=name,
        score=score,
        status=statuslabel,
        hrv=hrv,
        hrv_change_pct=hrv_pct,
        sleep_duration=sleep_dur,
        sleep_score=sleep_score,
        tsb=tsb,
        recent_activities=recent_summary,
        week_plan=week_summary,
    )


async def _history(session: AsyncSession, user_id: str, limit_: int) -> list[CoachMessage]:
    result = await session.execute(
        select(CoachMessage)
        .where(CoachMessage.user_id == uuid.UUID(user_id))
        .order_by(CoachMessage.created_at.desc())
        .limit(limit_)
    )
    return list(reversed(result.scalars().all()))  # chronological (oldest first)


# ── Coach chat ───────────────────────────────────────────────────────────────
@router.post("/coach/message", dependencies=[Depends(limit("ai_coach", 30, 3600))])
async def coach_message(
    body: schemas.CoachMessageRequest, user_id: str = Depends(get_current_user_id)
) -> StreamingResponse:
    async def event_stream():
        # Phase 1: persist the user turn and assemble context.
        async with session_scope(user_id) as session:
            session.add(CoachMessage(user_id=uuid.UUID(user_id), role="user", content=body.content))
            system_prompt = await _build_coach_system(session, user_id)
            history_rows = await _history(session, user_id, _MAX_HISTORY)
            history = [
                {"role": "assistant" if msg.role == "coach" else "user", "content": msg.content}
                for msg in history_rows
            ]

        # Phase 2: stream the model response (no DB transaction held open).
        chunks: list[str] = []
        try:
            async for text in ai.coach_stream(system_prompt, history):
                chunks.append(text)
                yield f"event: delta\ndata: {json.dumps({'text': text})}\n\n"
        except Exception:  # noqa: BLE001 — AI unavailable
            yield f"event: error\ndata: {json.dumps({'code': 'AI_UNAVAILABLE'})}\n\n"
            return

        # Phase 3: persist the coach turn and emit the terminal event (§8.2).
        full = "".join(chunks)
        async with session_scope(user_id) as session:
            msg = CoachMessage(user_id=uuid.UUID(user_id), role="coach", content=full)
            session.add(msg)
            await session.flush()
            message_id = str(msg.id)
        yield f"event: done\ndata: {json.dumps({'messageId': message_id, 'fullContent': full})}\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")


@router.get("/coach/history", response_model=list[schemas.CoachMessageDTO], dependencies=[Depends(limit("ai_get", 60, 3600))])
async def coach_history(
    limit_: int = Query(default=50, ge=1, le=200, alias="limit"),
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> list[schemas.CoachMessageDTO]:
    rows = await _history(session, user_id, limit_)
    return [schemas.CoachMessageDTO.model_validate(r) for r in rows]


@router.delete("/coach/history", status_code=status.HTTP_204_NO_CONTENT)
async def clear_history(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> None:
    await session.execute(delete(CoachMessage).where(CoachMessage.user_id == uuid.UUID(user_id)))


# ── Session suggestion (§8.3) ────────────────────────────────────────────────
@router.get("/session/suggest", response_model=schemas.SuggestedSessionDTO, dependencies=[Depends(limit("ai_get", 60, 3600))])
async def session_suggest(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> schemas.SuggestedSessionDTO:
    row = await _today_metrics(session, user_id)
    if row is None:
        raise metrics_not_found(dt.date.today().isoformat())
    m = mappers.metrics_from_row(row)
    result = r_engine.calculate(m)
    rationale = await ai.session_rationale(m, result)
    s = result.session
    return schemas.SuggestedSessionDTO(
        domain=s.domain.value,
        title=s.title,
        duration=s.duration,
        intensity_label=s.intensity_label,
        intensity_description=s.intensity_description,
        ai_rationale=rationale,
    )


# ── Strength generation (§8.4) ───────────────────────────────────────────────
@router.post("/strength/generate", response_model=schemas.StrengthSessionResponse, dependencies=[Depends(limit("ai_strength", 20, 3600))])
async def strength_generate(
    body: schemas.StrengthGenerateRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.StrengthSessionResponse:
    groups = [MuscleGroup(g) for g in body.muscle_groups if g in MuscleGroup._value2member_map_]

    # Readiness status drives intensity; prefer an explicit score, else today's metrics.
    if body.readiness_score is not None:
        score = body.readiness_score
        rstatus = r_engine.status_for_score(score)
    else:
        row = await _today_metrics(session, user_id)
        if row is None:
            raise metrics_not_found(dt.date.today().isoformat())
        result = r_engine.calculate(mappers.metrics_from_row(row))
        score, rstatus = result.score, result.status

    # Recent strength sessions for recovery-window checks.
    acts = await session.execute(
        select(Activity)
        .where(Activity.user_id == uuid.UUID(user_id), Activity.domain == "Strength")
        .order_by(Activity.start_time.desc())
        .limit(10)
    )
    now = dt.datetime.now(dt.timezone.utc)
    recent = [s_engine.RecentStrengthActivity(start_time=a.start_time) for a in acts.scalars().all()]

    built = s_engine.generate_session(groups, rstatus, score, recent, now)

    # AI augments rationale + recovery warnings; deterministic output is the fallback.
    exercise_list = "\n".join(
        f"- {e.name} ({e.muscle_group.value}): {e.sets}×{e.reps_range}" for e in built.exercises
    )
    recovery_map = ", ".join(f"{g.value}: {g.recovery_hours}h window" for g in groups)
    augment = await ai.strength_augment(
        score, [g.value for g in groups], exercise_list, "see DB", recovery_map
    )
    rationale = augment["rationale"] if augment else built.rationale
    warnings = augment["recoveryWarnings"] if augment else built.recovery_warnings

    return schemas.StrengthSessionResponse(
        muscle_groups=[g.value for g in built.muscle_groups],
        title=built.title,
        intensity_label=built.intensity_label,
        duration=built.duration,
        rationale=rationale,
        recovery_warnings=warnings,
        exercises=[
            schemas.ExerciseDTO(
                name=e.name,
                muscle_group=e.muscle_group.value,
                sets=e.sets,
                reps_range=e.reps_range,
                rest=e.rest,
                notes=e.notes,
            )
            for e in built.exercises
        ],
    )


# ── Switch suggestions (§9) ──────────────────────────────────────────────────
_SWITCH_INTENSITIES = {"Very Easy", "Easy", "Moderate", "Tempo", "Hard", "Threshold", "VO2"}


async def _switch_context(
    session: AsyncSession, user_id: str, body: schemas.SwitchSuggestionRequest
) -> str:
    uid = uuid.UUID(user_id)
    lines: list[str] = []

    # Today's readiness / metrics.
    row = await _today_metrics(session, user_id)
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
        lines.append("No health metrics today — assume an average, non-fatigued recreational athlete.")

    # Previous 7 days of training load.
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=7)
    acts = (await session.execute(
        select(Activity)
        .where(Activity.user_id == uid, Activity.start_time >= since)
        .order_by(Activity.start_time.desc())
    )).scalars().all()
    if acts:
        summary = "; ".join(
            f"{a.start_time:%a} {a.domain} {a.duration_seconds // 60}min"
            + (f" (load {float(a.training_load):.0f})" if a.training_load is not None else "")
            for a in acts
        )
        lines.append(f"Last 7 days trained: {summary}.")
    else:
        lines.append("No training logged in the last 7 days.")

    # Rest of this week's plan (sessions after the target day).
    monday = monday_of(body.date)
    plan_row = (await session.execute(
        select(WeeklyPlanRow).where(WeeklyPlanRow.user_id == uid, WeeklyPlanRow.week_start == monday)
    )).scalar_one_or_none()
    if plan_row:
        upcoming = [
            f"{d['date']} {s['domain']} ({s['intensityLabel']})"
            for d in plan_row.days if d["date"] > body.date.isoformat()
            for s in d.get("sessions", [])
        ]
        lines.append("Rest of week: " + (", ".join(upcoming) if upcoming else "nothing else planned") + ".")

    # Athlete thresholds + enrolled sports.
    prefs = await session.get(UserPreferences, uid)
    if prefs:
        t = prefs.thresholds or {}
        thr = ", ".join(f"{k} {v}" for k, v in t.items() if v is not None) or "none set"
        lines.append(f"Enrolled sports: {', '.join(prefs.enabled_domains) or 'none'}. Thresholds: {thr}.")

    return "\n".join(lines)


def _build_switch_dtos(parsed: dict, cycling_target: str) -> list[schemas.SwitchSuggestionDTO]:
    out: list[schemas.SwitchSuggestionDTO] = []
    for s in parsed.get("suggestions", [])[:4]:
        if not isinstance(s, dict):
            continue
        domain = s.get("domain")
        title = s.get("title")
        intensity = (s.get("intensityLabel") or "").strip()
        if domain not in TrainingDomain._value2member_map_ or not isinstance(title, str) or not title.strip():
            continue
        if intensity not in _SWITCH_INTENSITIES:
            intensity = "Moderate"
        try:
            duration = int(s.get("duration", 0))
        except (TypeError, ValueError):
            continue
        if not (15 <= duration <= 240):
            continue
        load = s.get("estimatedLoad")
        estimated_load = float(load) if isinstance(load, (int, float)) else None

        workout = None
        built = workouts.build_from_ai_blocks(domain, cycling_target, s.get("blocks"))
        if built is not None:
            workout = workouts.workout_to_dict(built)

        exercises = None
        groups_in = s.get("muscleGroups")
        if domain == "Strength" and isinstance(groups_in, list):
            groups = [MuscleGroup(g) for g in groups_in if g in MuscleGroup._value2member_map_]
            if groups:
                exercises = [
                    schemas.ExerciseDTO(
                        name=e.name, muscle_group=e.muscle_group.value, sets=e.sets,
                        reps_range=e.reps_range, rest=e.rest, notes=e.notes,
                    )
                    for e in s_engine.exercises_for(groups, intensity)
                ]

        out.append(schemas.SwitchSuggestionDTO(
            domain=domain,
            title=title.strip()[:80],
            duration=duration,
            intensity_label=intensity,
            description=(str(s.get("description") or "").strip()[:160]),
            rationale=(str(s.get("rationale") or "").strip()[:280]),
            estimated_load=estimated_load,
            workout=workout,
            exercises=exercises,
        ))
    return out


@router.post(
    "/switch-suggestions",
    response_model=schemas.SwitchSuggestionsResponse,
    dependencies=[Depends(limit("ai_switch", 40, 3600))],
)
async def switch_suggestions(
    body: schemas.SwitchSuggestionRequest,
    user_id: str = Depends(get_current_user_id),
) -> schemas.SwitchSuggestionsResponse:
    """AI alternatives for one planned session (§9). Best-effort: an empty list
    means the client should fall back to its deterministic switcher. Runs in
    read → AI → (no write) phases so the DB connection isn't held across the call."""
    async with session_scope(user_id) as session:
        context = await _switch_context(session, user_id, body)
        prefs = await session.get(UserPreferences, uuid.UUID(user_id))
        cycling_target = getattr(prefs, "cycling_target", "hr") if prefs else "hr"

    session_desc = f"{body.domain} — {body.title}, {body.duration} min, {body.intensity_label}."
    parsed = await ai.switch_suggestions(context, session_desc)
    suggestions = _build_switch_dtos(parsed, cycling_target) if parsed else []
    return schemas.SwitchSuggestionsResponse(suggestions=suggestions)
