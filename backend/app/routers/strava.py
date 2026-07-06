"""Strava endpoints (§13): OAuth connect + activity sync. Mirrors the
intervals.icu router; secrets stay server-side, tokens are encrypted at rest."""
from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, status
from fastapi.responses import RedirectResponse
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..config import settings
from ..db import session_scope
from ..deps import get_current_user_id, get_db
from ..errors import AppError
from ..models import StravaConnection
from ..rate_limit import limit
from ..security import decrypt_token, encrypt_token
from ..services.strava import StravaClient, StravaNotConfigured

router = APIRouter(prefix="/integrations/strava", tags=["strava"])
_authed = [Depends(limit("default", 300, 60))]


def _not_configured() -> AppError:
    return AppError(
        "STRAVA_NOT_CONFIGURED",
        "Strava integration is not configured on this server.",
        503,
    )


@router.get("/status", response_model=schemas.StravaStatus, dependencies=_authed)
async def status_(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> schemas.StravaStatus:
    conn = await session.get(StravaConnection, uuid.UUID(user_id))
    if conn is None:
        return schemas.StravaStatus(connected=False)
    return schemas.StravaStatus(
        connected=True, display_name=conn.display_name, last_sync_at=conn.last_sync_at
    )


@router.post("/connect", response_model=schemas.StravaConnectResponse, dependencies=_authed)
async def connect(user_id: str = Depends(get_current_user_id)) -> schemas.StravaConnectResponse:
    try:
        url = StravaClient().authorization_url(state=user_id)
    except StravaNotConfigured as exc:
        raise _not_configured() from exc
    return schemas.StravaConnectResponse(authorization_url=url)


@router.post("/connect/personal", response_model=schemas.StravaStatus, dependencies=_authed)
async def connect_personal(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> schemas.StravaStatus:
    """Connect using the server's personal STRAVA_REFRESH_TOKEN (single athlete,
    no redirect) — mirrors intervals' api-key connect."""
    if not settings.strava_refresh_token:
        raise _not_configured()
    client = StravaClient()
    try:
        token = await client.refresh(settings.strava_refresh_token)
        access = token["access_token"]
        athlete = await client.fetch_athlete(access)
    except StravaNotConfigured as exc:
        raise _not_configured() from exc
    except Exception as exc:  # noqa: BLE001
        raise AppError("STRAVA_CONNECT_FAILED", "Could not connect Strava with the configured token.", 400) from exc

    now = dt.datetime.now(dt.timezone.utc)
    if token.get("expires_at"):
        expires_at = dt.datetime.fromtimestamp(int(token["expires_at"]), tz=dt.timezone.utc)
    else:
        expires_at = now + dt.timedelta(seconds=int(token.get("expires_in", 21600)))
    name = " ".join(p for p in (athlete.get("firstname"), athlete.get("lastname")) if p) or None

    conn = await session.get(StravaConnection, uuid.UUID(user_id))
    if conn is None:
        conn = StravaConnection(user_id=uuid.UUID(user_id), athlete_id=str(athlete.get("id") or "0"),
                                access_token="", refresh_token="", token_expires_at=expires_at)
        session.add(conn)
    conn.athlete_id = str(athlete.get("id") or "0")
    conn.access_token = encrypt_token(access)
    conn.refresh_token = encrypt_token(token.get("refresh_token") or settings.strava_refresh_token)
    conn.token_expires_at = expires_at
    conn.display_name = name
    return schemas.StravaStatus(connected=True, display_name=name, last_sync_at=conn.last_sync_at)


@router.get("/callback")
async def callback(code: str | None = None, state: str | None = None, error: str | None = None):
    """OAuth redirect handler (no bearer token). Exchanges the code, stores
    encrypted tokens scoped to the user in `state`, bounces back into the app."""
    if error or not code or not state:
        return RedirectResponse(url=f"{settings.app_scheme}strava/error")
    try:
        token = await StravaClient().exchange_code(code)
        async with session_scope(state) as session:  # RLS-scoped to this user
            await _store_tokens(session, user_id=state, token=token)
        return RedirectResponse(url=f"{settings.app_scheme}strava/connected")
    except Exception:  # noqa: BLE001
        return RedirectResponse(url=f"{settings.app_scheme}strava/error")


async def _store_tokens(session: AsyncSession, user_id: str, token: dict) -> None:
    now = dt.datetime.now(dt.timezone.utc)
    if token.get("expires_at"):
        expires_at = dt.datetime.fromtimestamp(int(token["expires_at"]), tz=dt.timezone.utc)
    else:
        expires_at = now + dt.timedelta(seconds=int(token.get("expires_in", 21600)))
    athlete = token.get("athlete") or {}
    athlete_id = str(athlete.get("id") or "0")
    name = " ".join(p for p in (athlete.get("firstname"), athlete.get("lastname")) if p) or None

    conn = await session.get(StravaConnection, uuid.UUID(user_id))
    if conn is None:
        conn = StravaConnection(user_id=uuid.UUID(user_id), athlete_id=athlete_id,
                                access_token="", refresh_token="", token_expires_at=expires_at)
        session.add(conn)
    conn.athlete_id = athlete_id
    conn.access_token = encrypt_token(token["access_token"])
    conn.refresh_token = encrypt_token(token.get("refresh_token", ""))
    conn.token_expires_at = expires_at
    if name:
        conn.display_name = name


@router.post("/sync", dependencies=_authed)
async def sync(user_id: str = Depends(get_current_user_id)):
    from ..jobs.tasks import strava_sync

    try:
        return await strava_sync(user_id)
    except StravaNotConfigured as exc:
        raise _not_configured() from exc


@router.post("/segments/backfill", response_model=schemas.StravaSegmentsBackfill, dependencies=_authed)
async def segments_backfill(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> schemas.StravaSegmentsBackfill:
    """Fetch segment efforts for existing Strava rides/runs not yet checked, one
    bounded batch per call (Strava rate limits). The client repeats until
    remaining == 0."""
    from sqlalchemy import func, select

    from ..jobs.tasks import _SEGMENT_DOMAINS, _fetch_strava_segments, _valid_strava_token
    from ..models import Activity

    conn = await session.get(StravaConnection, uuid.UUID(user_id))
    if conn is None:
        return schemas.StravaSegmentsBackfill(processed=0, remaining=0)

    candidate_filter = (
        Activity.user_id == uuid.UUID(user_id),
        Activity.source == "strava",
        Activity.domain.in_(_SEGMENT_DOMAINS),
        Activity.external_id.isnot(None),
        Activity.efforts_synced_at.is_(None),
    )
    rows = (await session.execute(
        select(Activity.external_id).where(*candidate_filter).order_by(Activity.start_time.desc()).limit(25)
    )).scalars().all()

    client = StravaClient()
    access = await _valid_strava_token(session, conn)
    processed = 0
    for external_id in rows:
        if not await _fetch_strava_segments(session, client, access, user_id, external_id):
            break  # a 429/network error shouldn't be hammered — resume next call
        processed += 1

    remaining = await session.scalar(select(func.count()).select_from(Activity).where(*candidate_filter))
    return schemas.StravaSegmentsBackfill(processed=processed, remaining=remaining or 0)


@router.delete("/disconnect", status_code=status.HTTP_204_NO_CONTENT, dependencies=_authed)
async def disconnect(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> None:
    conn = await session.get(StravaConnection, uuid.UUID(user_id))
    if conn is not None:
        await session.delete(conn)
