"""Background job implementations (§10).

Jobs run on a privileged DB connection (the table owner bypasses RLS), so they
use an unscoped session and filter by user_id explicitly.
"""
from __future__ import annotations

import datetime as dt
import logging
import uuid

import httpx
from sqlalchemy import delete, func, literal_column, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from ..db import session_scope
from ..engines import readiness as r_engine
from ..models import Activity, CoachMessage, DailyMetrics, IntervalsConnection, Segment, SegmentEffort, StravaConnection, User
from ..security import decrypt_token, encrypt_token
from ..services import ai, goal_progress, mappers
from ..services.intervals import (
    IntervalsClient,
    IntervalsNotConfigured,
    normalize_intervals_activity,
    normalize_intervals_wellness,
)
from ..services.polyline import downsample_route
from ..services.strava import (
    StravaClient,
    normalize_segment_detail,
    normalize_segment_efforts,
    normalize_strava_activity,
)
from ..services.streams import normalize_streams
from ..services.metrics_assembly import assemble_daily_metrics, record_source_readings
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


async def _upsert_activity(session, values: dict, merge_fields: tuple[str, ...]) -> bool:
    """Blind activity upsert; returns True when the row was newly INSERTed
    (Postgres leaves xmax = 0 on inserts, non-zero on conflict updates)."""
    stmt = (
        pg_insert(Activity)
        .values(**values)
        .on_conflict_do_update(
            index_elements=[Activity.user_id, Activity.source, Activity.external_id],
            index_where=Activity.external_id.isnot(None),  # matches the partial unique index
            set_={k: values[k] for k in merge_fields},
        )
        .returning(literal_column("(xmax = 0)"))
    )
    return bool((await session.execute(stmt)).scalar_one())


# ── intervals-sync ───────────────────────────────────────────────────────────
# Sports whose activities can carry a GPS route worth fetching at sync time.
_ROUTE_DOMAINS = {"Cycling", "Running", "Swimming", "Triathlon"}
_ROUTE_FETCH_CAP = 20  # route-only streams calls per sync run


async def _fetch_intervals_route(session, client, access, is_key, user_id, external_id) -> None:
    """Best-effort: fetch the latlng stream for one activity and store a coarse
    trace in route_points. Never fails the sync — routes are decorative."""
    try:
        raw = await client.fetch_activity_streams(access, external_id, api_key=is_key, types="latlng")
        # normalize_streams zips intervals.icu's split latlng (data/data2) into pairs.
        if pts := downsample_route(normalize_streams(external_id, raw).lat_lng):
            await session.execute(
                update(Activity)
                .where(
                    Activity.user_id == uuid.UUID(user_id),
                    Activity.source == "garmin",
                    Activity.external_id == external_id,
                )
                .values(route_points=pts)
            )
    except Exception:  # noqa: BLE001
        log.warning("route fetch failed for intervals activity %s", external_id, exc_info=True)


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
        # Overlap a few days back so activities that land in intervals.icu after a
        # sync (but dated on/before it) still get picked up. Upsert makes re-fetching
        # the window idempotent.
        since = (conn.last_sync_at.date() - dt.timedelta(days=3) if conn.last_sync_at else until - dt.timedelta(days=30))

        # 1. Activities → activities table (before metrics so any fallback load is current).
        raw_activities = await client.fetch_activities(access, since, until, api_key=is_key, athlete_id=athlete)
        activities = 0
        new_domains: set[str] = set()
        route_fetches = 0
        for raw in raw_activities:
            values = normalize_intervals_activity(raw) | {"user_id": uuid.UUID(user_id)}
            if not values.get("start_time"):
                continue
            if await _upsert_activity(session, values, ("name", "start_time", "duration_seconds", "training_load")):
                new_domains.add(values["domain"])
                # The intervals.icu list response carries no GPS, so newly seen
                # outdoor activities get one route-only streams call (capped so a
                # first backfill can't fan out; missed routes are cosmetic).
                if (
                    values["domain"] in _ROUTE_DOMAINS
                    and (values.get("distance_meters") or 0) > 0
                    and route_fetches < _ROUTE_FETCH_CAP
                ):
                    route_fetches += 1
                    await _fetch_intervals_route(session, client, access, is_key, user_id, values["external_id"])
            activities += 1

        # 2. Wellness → daily_metrics (§9.3); ctl/atl come straight from intervals.icu.
        # Fetched for the full 90-day trend-graph window (not the incremental activity
        # window): it's one small object per day and the upserts are idempotent, so this
        # backfills history for existing connections and heals late-arriving readings.
        wellness_since = until - dt.timedelta(days=90)
        raw_wellness = await client.fetch_wellness(access, wellness_since, until, api_key=is_key, athlete_id=athlete)
        metrics_days = 0
        for raw in raw_wellness:
            wellness = normalize_intervals_wellness(raw)
            date_str = wellness.get("date")
            if not date_str:
                continue
            day = dt.date.fromisoformat(date_str) if isinstance(date_str, str) else date_str
            await record_source_readings(session, user_id, day, "intervals", wellness)
            if await assemble_daily_metrics(session, user_id, day):
                metrics_days += 1

        conn.last_sync_at = dt.datetime.now(dt.timezone.utc)
    if new_domains:
        goal_progress.schedule_analysis(user_id, new_domains)  # best-effort, non-blocking
    return {"activities": activities, "metrics_days": metrics_days}


# ── strava-sync (§13) ────────────────────────────────────────────────────────
_ACTIVITY_MERGE_FIELDS = (
    "name", "start_time", "duration_seconds", "distance_meters", "elevation_gain",
    "avg_heart_rate", "max_heart_rate", "calories", "training_load", "route_points",
)


# Sports whose Strava activities can carry segment efforts worth fetching.
_SEGMENT_DOMAINS = {"Cycling", "Running"}
_SEGMENT_FETCH_CAP = 20  # activity-detail calls per sync run
_SEGMENT_GEOMETRY_CAP = 15  # segment-detail calls per sync run


async def _fetch_segment_geometry(session, client, access, segment_id) -> bool:
    """Best-effort: fetch one segment's detail and upsert its geometry (global
    table). A 404 (deleted/hazardous segment) stores an empty stub so the drain
    doesn't wedge on it; other errors return False so the caller stops."""
    values = None
    try:
        raw = await client.fetch_segment_detail(access, segment_id)
        values = normalize_segment_detail(raw)
    except httpx.HTTPStatusError as exc:
        if exc.response.status_code != 404:
            log.warning("segment geometry fetch failed for %s", segment_id, exc_info=True)
            return False
    except Exception:  # noqa: BLE001
        log.warning("segment geometry fetch failed for %s", segment_id, exc_info=True)
        return False
    if values is None:  # 404 or unusable payload — stub it so the drain moves on
        values = {"segment_id": segment_id, "name": "Segment", "points": [],
                  "fetched_at": dt.datetime.now(dt.timezone.utc)}
    async with session.begin_nested():
        await session.execute(
            pg_insert(Segment)
            .values(**values)
            .on_conflict_do_update(
                index_elements=[Segment.segment_id],
                set_={k: v for k, v in values.items() if k != "segment_id"},
            )
        )
    return True


async def _fetch_strava_segments(session, client, access, user_id, external_id) -> bool:
    """Best-effort: fetch one Strava activity's detail (include_all_efforts) and
    upsert its segment efforts, marking the activity checked (even with zero
    efforts) so the backfill doesn't retry it. Returns False on failure — the
    sync ignores it, the backfill stops (a 429 shouldn't be hammered)."""
    try:
        raw = await client.fetch_activity_detail(access, external_id)
        # Savepoint: a failed statement must not abort the caller's transaction
        # (it would take the rest of the sync/backfill down with it).
        async with session.begin_nested():
            for effort in normalize_segment_efforts(raw):
                stmt = (
                    pg_insert(SegmentEffort)
                    .values(**effort, user_id=uuid.UUID(user_id))
                    .on_conflict_do_update(
                        index_elements=[SegmentEffort.user_id, SegmentEffort.effort_id],
                        set_={k: effort[k] for k in ("name", "elapsed_seconds", "moving_seconds", "pr_rank", "kom_rank")},
                    )
                )
                await session.execute(stmt)
            await session.execute(
                update(Activity)
                .where(
                    Activity.user_id == uuid.UUID(user_id),
                    Activity.source == "strava",
                    Activity.external_id == external_id,
                )
                .values(efforts_synced_at=dt.datetime.now(dt.timezone.utc))
            )
        return True
    except Exception:  # noqa: BLE001
        log.warning("segment fetch failed for strava activity %s", external_id, exc_info=True)
        return False


async def _valid_strava_token(session, conn: StravaConnection) -> str:
    """Return a usable Strava access token, refreshing if it's expired/expiring."""
    now = dt.datetime.now(dt.timezone.utc)
    if conn.token_expires_at <= now + dt.timedelta(minutes=2):
        token = await StravaClient().refresh(decrypt_token(conn.refresh_token))
        conn.access_token = encrypt_token(token["access_token"])
        if token.get("refresh_token"):
            conn.refresh_token = encrypt_token(token["refresh_token"])
        if token.get("expires_at"):
            conn.token_expires_at = dt.datetime.fromtimestamp(int(token["expires_at"]), tz=dt.timezone.utc)
        else:
            conn.token_expires_at = now + dt.timedelta(seconds=int(token.get("expires_in", 21600)))
    return decrypt_token(conn.access_token)


async def strava_sync(user_id: str) -> dict:
    """Fetch Strava activities into the activities table (source='strava'). On
    first connect pulls the last 8 weeks; then incrementally from last_sync."""
    async with session_scope(user_id) as session:
        conn = await session.get(StravaConnection, uuid.UUID(user_id))
        if conn is None:
            return {"activities": 0}
        client = StravaClient()
        access = await _valid_strava_token(session, conn)
        # Overlap a few days so late-arriving/backfilled activities aren't skipped
        # (upsert makes the re-fetch idempotent).
        after = (conn.last_sync_at - dt.timedelta(days=3)) if conn.last_sync_at else (dt.datetime.now(dt.timezone.utc) - dt.timedelta(weeks=8))
        raw_activities = await client.fetch_activities(access, after)
        activities = 0
        new_domains: set[str] = set()
        segment_fetches = 0
        for raw in raw_activities:
            values = normalize_strava_activity(raw) | {"user_id": uuid.UUID(user_id)}
            if not values.get("start_time"):
                continue
            if await _upsert_activity(session, values, _ACTIVITY_MERGE_FIELDS):
                new_domains.add(values["domain"])
                # New rides/runs get one detail call for segment efforts (capped;
                # over-cap activities are picked up by the segments backfill).
                if values["domain"] in _SEGMENT_DOMAINS and segment_fetches < _SEGMENT_FETCH_CAP:
                    segment_fetches += 1
                    await _fetch_strava_segments(session, client, access, user_id, values["external_id"])
            activities += 1

        # Older activities not yet checked drain within the same per-sync cap —
        # the app syncs on launch, so segment history imports in the background
        # a batch at a time (no manual backfill needed).
        if segment_fetches < _SEGMENT_FETCH_CAP:
            pending = (await session.execute(
                select(Activity.external_id).where(
                    Activity.user_id == uuid.UUID(user_id),
                    Activity.source == "strava",
                    Activity.domain.in_(_SEGMENT_DOMAINS),
                    Activity.external_id.isnot(None),
                    Activity.efforts_synced_at.is_(None),
                ).order_by(Activity.start_time.desc()).limit(_SEGMENT_FETCH_CAP - segment_fetches)
            )).scalars().all()
            for external_id in pending:
                if not await _fetch_strava_segments(session, client, access, user_id, external_id):
                    break  # a 429/network error shouldn't be hammered — resume next sync

        # Segment geometry (global table): fetch shapes for segments this user's
        # efforts reference but that aren't stored yet — covers both segments
        # seen this sync (efforts upserted above in the same transaction) and
        # the pre-geometry backlog, newest-ridden first.
        missing = (await session.execute(
            select(SegmentEffort.segment_id)
            .where(
                SegmentEffort.user_id == uuid.UUID(user_id),
                ~select(Segment.segment_id).where(Segment.segment_id == SegmentEffort.segment_id).exists(),
            )
            .group_by(SegmentEffort.segment_id)
            .order_by(func.max(SegmentEffort.start_date).desc())
            .limit(_SEGMENT_GEOMETRY_CAP)
        )).scalars().all()
        for sid in missing:
            if not await _fetch_segment_geometry(session, client, access, sid):
                break  # a 429/network error shouldn't be hammered — resume next sync

        conn.last_sync_at = dt.datetime.now(dt.timezone.utc)
    if new_domains:
        goal_progress.schedule_analysis(user_id, new_domains)  # best-effort, non-blocking
    return {"activities": activities}


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
