"""intervals.icu endpoints (§7.8 / §9): OAuth connect + sync + workout push."""
from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, Query, status
from fastapi.responses import RedirectResponse
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..config import settings
from ..db import session_scope
from ..deps import get_current_user_id, get_db
from ..errors import AppError, intervals_not_connected
from ..models import IntervalsConnection
from ..rate_limit import limit
from ..security import decrypt_token, encrypt_token
from ..services.intervals import (
    IntervalsClient,
    IntervalsNotConfigured,
    planned_session_to_intervals_event,
)

router = APIRouter(prefix="/intervals", tags=["intervals"])
_authed = [Depends(limit("default", 300, 60))]


def _not_configured() -> AppError:
    return AppError(
        "INTERVALS_NOT_CONFIGURED",
        "intervals.icu integration is not configured on this server.",
        503,
    )


@router.get("/status", response_model=schemas.IntervalsStatus, dependencies=_authed)
async def status_(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> schemas.IntervalsStatus:
    conn = await session.get(IntervalsConnection, uuid.UUID(user_id))
    if conn is None:
        return schemas.IntervalsStatus(connected=False)
    return schemas.IntervalsStatus(
        connected=True, display_name=conn.display_name, last_sync_at=conn.last_sync_at
    )


@router.post("/connect", response_model=schemas.IntervalsConnectResponse, dependencies=_authed)
async def connect(user_id: str = Depends(get_current_user_id)) -> schemas.IntervalsConnectResponse:
    client = IntervalsClient()
    try:
        # `state` carries the user id so the (unauthenticated) callback can
        # attribute the tokens. A production impl should sign/encrypt this.
        url = client.authorization_url(state=user_id)
    except IntervalsNotConfigured as exc:
        raise _not_configured() from exc
    return schemas.IntervalsConnectResponse(authorization_url=url)


@router.post("/connect/apikey", response_model=schemas.IntervalsStatus, dependencies=_authed)
async def connect_with_api_key(
    body: schemas.IntervalsApiKeyConnect,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.IntervalsStatus:
    """Connect using a personal intervals.icu API key (HTTP Basic). Validates the
    key, then stores it encrypted with auth_mode='apikey'."""
    client = IntervalsClient()
    try:
        info = await client.validate_api_key(body.athlete_id, body.api_key)
    except Exception as exc:  # noqa: BLE001
        raise AppError("INTERVALS_KEY_INVALID", "Could not validate that API key.", 400) from exc

    conn = await session.get(IntervalsConnection, uuid.UUID(user_id))
    far_future = dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=3650)
    if conn is None:
        conn = IntervalsConnection(
            user_id=uuid.UUID(user_id), athlete_id=info["athlete_id"],
            access_token="", refresh_token="", token_expires_at=far_future,
        )
        session.add(conn)
    conn.auth_mode = "apikey"
    conn.athlete_id = info["athlete_id"]
    conn.access_token = encrypt_token(body.api_key)
    conn.refresh_token = encrypt_token("")
    conn.token_expires_at = far_future
    conn.display_name = info.get("display_name")
    return schemas.IntervalsStatus(connected=True, display_name=conn.display_name, last_sync_at=conn.last_sync_at)


@router.get("/callback")
async def callback(code: str | None = None, state: str | None = None):
    """OAuth redirect handler (no bearer token). Exchanges the code, stores
    encrypted tokens scoped to the user in `state`, then bounces back into the
    app via the universal link (§9.1)."""
    if not code or not state:
        return RedirectResponse(url=f"{settings.app_scheme}intervals/error")
    client = IntervalsClient()
    try:
        token = await client.exchange_code(code)
        async with session_scope(state) as session:  # RLS-scoped to this user
            await _store_tokens(session, user_id=state, token=token)
        return RedirectResponse(url=f"{settings.app_scheme}intervals/connected")
    except Exception:  # noqa: BLE001
        return RedirectResponse(url=f"{settings.app_scheme}intervals/error")


async def _store_tokens(session: AsyncSession, user_id: str, token: dict) -> None:
    expires_in = int(token.get("expires_in", 3600))
    expires_at = dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=expires_in)
    conn = await session.get(IntervalsConnection, uuid.UUID(user_id))
    athlete_id = str(token.get("athlete_id") or token.get("athlete", {}).get("id") or "0")
    if conn is None:
        conn = IntervalsConnection(user_id=uuid.UUID(user_id), athlete_id=athlete_id,
                                   access_token="", refresh_token="", token_expires_at=expires_at)
        session.add(conn)
    conn.auth_mode = "oauth"
    conn.athlete_id = athlete_id
    conn.access_token = encrypt_token(token["access_token"])
    conn.refresh_token = encrypt_token(token.get("refresh_token", ""))
    conn.token_expires_at = expires_at


@router.post("/sync", dependencies=_authed)
async def sync(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
):
    conn = await session.get(IntervalsConnection, uuid.UUID(user_id))
    if conn is None:
        raise intervals_not_connected()
    try:
        from ..jobs.tasks import intervals_sync

        result = await intervals_sync(user_id)
    except IntervalsNotConfigured as exc:
        raise _not_configured() from exc
    return result


@router.delete("/disconnect", status_code=status.HTTP_204_NO_CONTENT, dependencies=_authed)
async def disconnect(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> None:
    conn = await session.get(IntervalsConnection, uuid.UUID(user_id))
    if conn is not None:
        await session.delete(conn)


@router.post("/workouts/push", response_model=schemas.IntervalsWorkoutPushResponse, dependencies=_authed)
async def push_workout(
    body: schemas.IntervalsWorkoutPushRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.IntervalsWorkoutPushResponse:
    """Push a planned session to intervals.icu as a calendar workout, which it
    schedules to Garmin (§9.4)."""
    conn = await session.get(IntervalsConnection, uuid.UUID(user_id))
    if conn is None:
        raise intervals_not_connected()
    event = planned_session_to_intervals_event(
        body.session.model_dump(by_alias=True), body.date.isoformat()
    )
    from ..engines.workouts import to_intervals_text

    # If the session carries structured steps, push them as an executable
    # intervals.icu workout (their workout-builder syntax in `description`).
    workout = body.session.model_dump(by_alias=True).get("workout")
    if workout and workout.get("targetMode") not in (None, "none"):
        text = to_intervals_text(workout)
        if text:
            event["description"] = text

    from ..jobs.tasks import _valid_access_token

    client = IntervalsClient()
    try:
        token = await _valid_access_token(session, conn)
        created = await client.create_event(
            token, event, api_key=(conn.auth_mode == "apikey"), athlete_id=conn.athlete_id or "0"
        )
    except IntervalsNotConfigured as exc:
        raise _not_configured() from exc
    return schemas.IntervalsWorkoutPushResponse(
        workout_id=str(created.get("id", "")), scheduled_date=body.date
    )
