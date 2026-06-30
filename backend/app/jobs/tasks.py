"""Background job implementations (§10).

Jobs run on a privileged DB connection (the table owner bypasses RLS), so they
use an unscoped session and filter by user_id explicitly.
"""
from __future__ import annotations

import datetime as dt
import logging
import uuid

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from ..db import session_scope
from ..engines import readiness as r_engine
from ..models import Activity, CoachMessage, DailyMetrics, IntervalsConnection, User
from ..security import decrypt_token, encrypt_token
from ..services import ai, mappers
from ..services.intervals import (
    IntervalsClient,
    IntervalsNotConfigured,
    normalize_intervals_activity,
    normalize_intervals_wellness,
)
from ..services.metrics_assembly import assemble_daily_metrics
from ..services.plan_service import regenerate_plans

log = logging.getLogger("northax.jobs")


# ── generate-plans ───────────────────────────────────────────────────────────
async def generate_plans_job(user_id: str) -> int:
    async with session_scope(user_id) as session:
        rows = await regenerate_plans(session, user_id, dt.date.today(), weeks=4)
    return len(rows)


# ── compute-readiness (daily 07:00) ──────────────────────────────────────────
async def compute_readiness(user_id: str, date: dt.date | None = None) -> bool:
    date = date or dt.date.today()
    async with session_scope(user_id) as session:
        result = await session.execute(
            select(DailyMetrics).where(
                DailyMetrics.user_id == uuid.UUID(user_id), DailyMetrics.date == date
            )
        )
        row = result.scalar_one_or_none()
        if row is None:
            return False
        m = mappers.metrics_from_row(row)
        readiness = r_engine.calculate(m)
        if row.ai_explanation is None:
            explanation = await ai.readiness_explanation(m, readiness, dt.datetime.now(dt.timezone.utc))
            if explanation is not None:
                row.ai_explanation = explanation
    return True


async def compute_readiness_all() -> int:
    """Daily sweep: compute readiness for every user with metrics today."""
    count = 0
    async with session_scope(None) as session:
        users = (await session.execute(select(User.id))).scalars().all()
    for uid in users:
        if await compute_readiness(str(uid)):
            count += 1
    return count


# ── intervals-sync ───────────────────────────────────────────────────────────
async def _valid_access_token(session, conn: IntervalsConnection) -> str:
    """Return a usable token. Personal API keys never expire; OAuth tokens are
    refreshed if expired/expiring."""
    if conn.auth_mode == "apikey":
        return decrypt_token(conn.access_token)
    now = dt.datetime.now(dt.timezone.utc)
    if conn.token_expires_at <= now + dt.timedelta(minutes=2):
        token = await IntervalsClient().refresh(decrypt_token(conn.refresh_token))
        conn.access_token = encrypt_token(token["access_token"])
        if token.get("refresh_token"):
            conn.refresh_token = encrypt_token(token["refresh_token"])
        conn.token_expires_at = now + dt.timedelta(seconds=int(token.get("expires_in", 3600)))
    return decrypt_token(conn.access_token)


async def intervals_sync(user_id: str) -> dict:
    """Fetch intervals.icu wellness + activities and assemble the daily_metrics
    rows that drive readiness (§9.2 / §9.3). Returns {"activities", "metrics_days"}."""
    async with session_scope(user_id) as session:
        conn = await session.get(IntervalsConnection, uuid.UUID(user_id))
        if conn is None:
            return {"activities": 0, "metrics_days": 0}
        client = IntervalsClient()
        access = await _valid_access_token(session, conn)
        is_key = conn.auth_mode == "apikey"
        athlete = conn.athlete_id or "0"
        until = dt.date.today()
        since = (conn.last_sync_at.date() if conn.last_sync_at else until - dt.timedelta(days=30))

        # 1. Activities → activities table (before metrics so any fallback load is current).
        raw_activities = await client.fetch_activities(access, since, until, api_key=is_key, athlete_id=athlete)
        activities = 0
        for raw in raw_activities:
            values = normalize_intervals_activity(raw) | {"user_id": uuid.UUID(user_id)}
            if not values.get("start_time"):
                continue
            stmt = (
                pg_insert(Activity)
                .values(**values)
                .on_conflict_do_update(
                    index_elements=[Activity.user_id, Activity.source, Activity.external_id],
                    set_={k: values[k] for k in ("name", "start_time", "duration_seconds", "training_load")},
                )
            )
            await session.execute(stmt)
            activities += 1

        # 2. Wellness → daily_metrics (§9.3); ctl/atl come straight from intervals.icu.
        raw_wellness = await client.fetch_wellness(access, since, until, api_key=is_key, athlete_id=athlete)
        metrics_days = 0
        for raw in raw_wellness:
            wellness = normalize_intervals_wellness(raw)
            date_str = wellness.get("date")
            if not date_str:
                continue
            day = dt.date.fromisoformat(date_str) if isinstance(date_str, str) else date_str
            if await assemble_daily_metrics(session, user_id, day, wellness):
                metrics_days += 1

        conn.last_sync_at = dt.datetime.now(dt.timezone.utc)
    return {"activities": activities, "metrics_days": metrics_days}


# ── prune-coach-history (weekly) ─────────────────────────────────────────────
async def prune_coach_history(retention_days: int = 180) -> None:
    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=retention_days)
    async with session_scope(None) as session:
        await session.execute(delete(CoachMessage).where(CoachMessage.created_at < cutoff))


# ── refresh-intervals-token ──────────────────────────────────────────────────
async def refresh_intervals_tokens() -> None:
    """Refresh intervals.icu OAuth tokens expiring within the next hour (§10)."""
    horizon = dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=1)
    client = IntervalsClient()
    async with session_scope(None) as session:
        result = await session.execute(
            select(IntervalsConnection).where(IntervalsConnection.token_expires_at <= horizon)
        )
        connections = list(result.scalars().all())
        for conn in connections:
            try:
                token = await client.refresh(decrypt_token(conn.refresh_token))
                conn.access_token = encrypt_token(token["access_token"])
                if token.get("refresh_token"):
                    conn.refresh_token = encrypt_token(token["refresh_token"])
                conn.token_expires_at = dt.datetime.now(dt.timezone.utc) + dt.timedelta(
                    seconds=int(token.get("expires_in", 3600))
                )
            except IntervalsNotConfigured:
                log.warning("intervals.icu not configured; skipping token refresh")
            except Exception:  # noqa: BLE001
                log.warning("intervals.icu token refresh failed for %s", conn.user_id, exc_info=True)
