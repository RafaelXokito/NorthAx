"""Mirror the training plan to the intervals.icu calendar (best-effort).

Every pushed event carries an external_id starting with "northax-", so a plan
regeneration deletes and recreates NorthAx's own events without touching
anything the athlete scheduled themselves. Failures are logged, never raised —
the plan endpoint must not fail because the calendar push did.
"""
from __future__ import annotations

import asyncio
import datetime as dt
import logging
import uuid

from sqlalchemy import select

from ..db import session_scope
from ..engines.workouts import to_intervals_text
from ..models import IntervalsConnection, WeeklyPlanRow
from .intervals import IntervalsClient, planned_session_to_intervals_event

log = logging.getLogger("northax.plan_push")

EXTERNAL_ID_PREFIX = "northax-"

_tasks: set[asyncio.Task] = set()  # keep refs so fire-and-forget tasks aren't GC'd


def schedule_push(user_id: str) -> None:
    """Fire-and-forget: mirror the freshly generated plan to intervals.icu."""
    task = asyncio.create_task(_push_safe(user_id))
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)


async def _push_safe(user_id: str) -> None:
    try:
        await push_plans(user_id)
    except Exception:  # noqa: BLE001 — best-effort, never propagate
        log.warning("plan push to intervals.icu failed for %s", user_id, exc_info=True)


def event_external_id(date: str, domain: str, index: int = 0) -> str:
    """Stable id for a plan slot, e.g. 'northax-2026-07-06-cycling'."""
    suffix = f"-{index}" if index else ""
    return f"{EXTERNAL_ID_PREFIX}{date}-{domain.lower()}{suffix}"


def workout_description(session: dict) -> str | None:
    """intervals.icu workout-builder text for a structured session, else None."""
    workout = session.get("workout")
    if workout and workout.get("targetMode") not in (None, "none"):
        return to_intervals_text(workout) or None
    return None


async def push_plans(user_id: str) -> int:
    """Replace NorthAx events on the athlete's calendar with the current plan
    (today → horizon). Returns the number of events created; 0 when intervals
    isn't connected."""
    today = dt.date.today()

    async with session_scope(user_id) as session:
        conn = await session.get(IntervalsConnection, uuid.UUID(user_id))
        if conn is None:
            return 0
        from ..jobs.tasks import _valid_access_token

        token = await _valid_access_token(session, conn)
        api_key = conn.auth_mode == "apikey"
        athlete = conn.athlete_id or "0"

        rows = (
            await session.execute(
                select(WeeklyPlanRow)
                .where(WeeklyPlanRow.user_id == uuid.UUID(user_id))
                .order_by(WeeklyPlanRow.week_start)
            )
        ).scalars().all()
        horizon = today
        entries: list[tuple[str, dict]] = []  # (iso date, session json)
        for row in rows:
            for day in row.days:
                date = dt.date.fromisoformat(day["date"])
                horizon = max(horizon, date)
                if date < today or day.get("isRest"):
                    continue
                for s in day.get("sessions") or []:
                    entries.append((day["date"], s))

    client = IntervalsClient()

    # Delete previously pushed NorthAx events in the window (an emptied plan
    # still clears its old events), then recreate from the current plan.
    existing = await client.list_events(
        token, today.isoformat(), horizon.isoformat(), api_key=api_key, athlete_id=athlete
    )
    for ev in existing:
        ext = str(ev.get("external_id") or "")
        if ext.startswith(EXTERNAL_ID_PREFIX) and ev.get("id") is not None:
            await client.delete_event(token, str(ev["id"]), api_key=api_key, athlete_id=athlete)

    created = 0
    slot_counts: dict[tuple[str, str], int] = {}
    for date, s in entries:
        domain = str(s.get("domain", ""))
        index = slot_counts.get((date, domain), 0)
        slot_counts[(date, domain)] = index + 1
        event = planned_session_to_intervals_event(
            s, date, external_id=event_external_id(date, domain, index)
        )
        if text := workout_description(s):
            event["description"] = text
        await client.create_event(token, event, api_key=api_key, athlete_id=athlete)
        created += 1
    log.info("pushed %d plan events to intervals.icu for %s", created, user_id)
    return created
