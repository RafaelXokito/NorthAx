"""Post-sync AI goal-progress analysis (best-effort — never blocks or fails a sync)."""
from __future__ import annotations

import asyncio
import datetime as dt
import logging
import uuid

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from ..db import session_scope
from ..models import Activity, GoalProgress, UserPreferences
from . import ai

log = logging.getLogger("northax.goals")

_tasks: set[asyncio.Task] = set()  # keep refs so fire-and-forget tasks aren't GC'd


def schedule_analysis(user_id: str, domains: set[str]) -> None:
    """Fire-and-forget: analyse each domain after a sync lands new activities."""
    task = asyncio.create_task(_analyze_domains(user_id, domains))
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)


async def _analyze_domains(user_id: str, domains: set[str]) -> None:
    for domain in sorted(domains):
        try:
            await analyze_domain(user_id, domain)
        except Exception:  # noqa: BLE001 — best-effort, never propagate
            log.warning("goal analysis failed for %s/%s", user_id, domain, exc_info=True)


def _fmt_hms(total_sec: int) -> str:
    h, rem = divmod(int(total_sec), 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def describe_target(domain: str, t: dict) -> str | None:
    """One-liner for a stored target dict, e.g. 'run 10 km in 40:00 by 2026-10-04'.
    Returns None for malformed dicts. Shared by the analysis prompt and the
    plan-generation athlete context."""
    try:
        date = t["targetDate"]
        kind = t["goalType"]
        if kind == "raceTime":
            return f"run {float(t['distanceKm']):g} km in {_fmt_hms(t['finishTimeSec'])} by {date}"
        if kind == "powerHold":
            return f"hold power zone Z{int(t['zone'])} for {int(t['holdMinutes'])} min on the bike by {date}"
        if kind == "distanceAvgSpeed":
            return f"ride {float(t['distanceKm']):g} km at {float(t['avgSpeedKmh']):g} km/h average by {date}"
    except (KeyError, TypeError, ValueError):
        return None
    return None


def _activity_line(a: Activity) -> str:
    parts = [f"{a.start_time:%b %d} {a.name} — {a.duration_seconds // 60} min"]
    if a.distance_meters:
        km = float(a.distance_meters) / 1000
        parts.append(f"{km:.1f} km")
        if a.duration_seconds and km > 0:
            if a.domain == "Running":
                parts.append(f"{_fmt_hms(int(a.duration_seconds / km))} min/km")
            elif a.domain == "Cycling":
                parts.append(f"{km / (a.duration_seconds / 3600):.1f} km/h avg")
    if a.avg_heart_rate:
        parts.append(f"avg HR {a.avg_heart_rate}")
    if a.training_load is not None:
        parts.append(f"load {float(a.training_load):.0f}")
    return ", ".join(parts)


def _thresholds_line(thresholds: dict, domain: str) -> str:
    parts: list[str] = []
    if domain == "Cycling" and thresholds.get("ftpWatts"):
        parts.append(f"FTP {thresholds['ftpWatts']} W")
    if domain == "Running" and thresholds.get("runThresholdPaceSecPerKm"):
        parts.append(f"threshold pace {_fmt_hms(thresholds['runThresholdPaceSecPerKm'])} min/km")
    if thresholds.get("thresholdHr"):
        parts.append(f"threshold HR {thresholds['thresholdHr']} bpm")
    return ", ".join(parts)


async def analyze_domain(user_id: str, domain: str) -> bool:
    """Assess progress toward one sport's target and upsert the verdict.
    Returns False when there is no target, no activities, nothing new since the
    last analysis, or the AI call fails."""
    # Phase 1 — read (session released before the slow AI call, like plan generate-ai).
    async with session_scope(user_id) as session:
        prefs = await session.get(UserPreferences, uuid.UUID(user_id))
        target = (getattr(prefs, "sport_targets", {}) or {}).get(domain) if prefs else None
        desc = describe_target(domain, target) if isinstance(target, dict) else None
        if desc is None:
            return False
        acts = (
            await session.execute(
                select(Activity)
                .where(Activity.user_id == uuid.UUID(user_id), Activity.domain == domain)
                .order_by(Activity.start_time.desc())
                .limit(10)
            )
        ).scalars().all()
        if not acts:
            return False
        newest = acts[0].start_time
        row = await session.get(GoalProgress, (uuid.UUID(user_id), domain))
        if row is not None and row.latest_activity_at is not None and row.latest_activity_at >= newest:
            return False  # nothing new since the last analysis
        block = "\n".join(_activity_line(a) for a in acts)
        thresholds = _thresholds_line(dict(getattr(prefs, "thresholds", {}) or {}), domain)
        days_left = (dt.date.fromisoformat(str(target["targetDate"])) - dt.date.today()).days

    # Phase 2 — AI (no DB connection held).
    parsed = await ai.goal_progress_analysis(desc, days_left, block, thresholds)
    if parsed is None:
        return False

    # Phase 3 — write.
    async with session_scope(user_id) as session:
        stmt = (
            pg_insert(GoalProgress)
            .values(
                user_id=uuid.UUID(user_id),
                domain=domain,
                verdict=parsed["verdict"],
                summary=parsed["summary"][:600],
                recommend_replan=parsed["recommendReplan"],
                latest_activity_at=newest,
            )
            .on_conflict_do_update(
                index_elements=[GoalProgress.user_id, GoalProgress.domain],
                set_={
                    "verdict": parsed["verdict"],
                    "summary": parsed["summary"][:600],
                    "recommend_replan": parsed["recommendReplan"],
                    "latest_activity_at": newest,
                    "analyzed_at": func.now(),
                },
            )
        )
        await session.execute(stmt)
    return True
