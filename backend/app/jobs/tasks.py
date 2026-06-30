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
from ..models import Activity, CoachMessage, DailyMetrics, GarminConnection, User
from ..security import decrypt_token
from ..services import ai, mappers
from ..services.garmin import GarminClient, GarminNotConfigured, normalize_garmin_activity
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


# ── garmin-sync ──────────────────────────────────────────────────────────────
async def garmin_sync(user_id: str) -> int:
    """Fetch and upsert Garmin activities, then recompute training loads (§9.2)."""
    async with session_scope(user_id) as session:
        conn = await session.get(GarminConnection, uuid.UUID(user_id))
        if conn is None:
            return 0
        client = GarminClient()
        since = conn.last_sync_at or (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=30))
        access = decrypt_token(conn.access_token)
        secret = decrypt_token(conn.refresh_token)

        raw_activities = await client.fetch_activities(access, secret, since)  # GarminNotConfigured until wired

        synced = 0
        for raw in raw_activities:
            values = normalize_garmin_activity(raw) | {"user_id": uuid.UUID(user_id)}
            stmt = (
                pg_insert(Activity)
                .values(**values)
                .on_conflict_do_update(
                    index_elements=[Activity.user_id, Activity.source, Activity.external_id],
                    set_={k: values[k] for k in ("name", "start_time", "duration_seconds", "training_load")},
                )
            )
            await session.execute(stmt)
            synced += 1

        conn.last_sync_at = dt.datetime.now(dt.timezone.utc)
    return synced


# ── prune-coach-history (weekly) ─────────────────────────────────────────────
async def prune_coach_history(retention_days: int = 180) -> None:
    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=retention_days)
    async with session_scope(None) as session:
        await session.execute(delete(CoachMessage).where(CoachMessage.created_at < cutoff))


# ── refresh-garmin-token ─────────────────────────────────────────────────────
async def refresh_garmin_tokens() -> None:
    """Refresh OAuth tokens that expire within the next hour (§10)."""
    horizon = dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=1)
    async with session_scope(None) as session:
        result = await session.execute(
            select(GarminConnection).where(GarminConnection.token_expires_at <= horizon)
        )
        connections = result.scalars().all()
    for conn in connections:
        try:
            # Real impl: call Garmin refresh, re-encrypt, persist.
            log.info("garmin token refresh due for user %s", conn.user_id)
        except GarminNotConfigured:
            log.warning("garmin not configured; skipping token refresh")
