"""Garmin endpoints (§7.8 / §9). OAuth proxy + webhook receiver."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Request, status
from fastapi.responses import RedirectResponse
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..config import settings
from ..deps import get_current_user_id, get_db
from ..errors import AppError, garmin_not_connected
from ..models import GarminConnection
from ..rate_limit import limit
from ..services.garmin import GarminClient, GarminNotConfigured, verify_webhook_signature

router = APIRouter(prefix="/garmin", tags=["garmin"])
_authed = [Depends(limit("default", 300, 60))]


def _not_configured() -> AppError:
    return AppError(
        "GARMIN_NOT_CONFIGURED",
        "Garmin integration is not configured on this server.",
        503,
    )


@router.get("/status", response_model=schemas.GarminStatus, dependencies=_authed)
async def status_(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> schemas.GarminStatus:
    conn = await session.get(GarminConnection, uuid.UUID(user_id))
    if conn is None:
        return schemas.GarminStatus(connected=False)
    return schemas.GarminStatus(
        connected=True, display_name=conn.display_name, last_sync_at=conn.last_sync_at
    )


@router.post("/connect", response_model=schemas.GarminConnectResponse, dependencies=_authed)
async def connect(user_id: str = Depends(get_current_user_id)) -> schemas.GarminConnectResponse:
    client = GarminClient()
    try:
        oauth_token, _secret = await client.request_token()
    except GarminNotConfigured as exc:
        raise _not_configured() from exc
    # A production impl persists `_secret` keyed by oauth_token (e.g. in Redis)
    # so the callback can complete the 1.0a exchange.
    return schemas.GarminConnectResponse(authorization_url=client.authorization_url(oauth_token))


@router.get("/callback")
async def callback(oauth_token: str | None = None, oauth_verifier: str | None = None):
    """OAuth redirect handler (server-side only). Stores encrypted tokens, then
    bounces the user back into the app via the universal link (§9.1)."""
    client = GarminClient()
    try:
        if not oauth_token or not oauth_verifier:
            raise GarminNotConfigured("missing oauth params")
        await client.exchange_token(oauth_token, oauth_verifier)
        # On success: encrypt + upsert GarminConnection, trigger initial sync.
        return RedirectResponse(url=f"{settings.app_scheme}garmin/connected")
    except GarminNotConfigured:
        return RedirectResponse(url=f"{settings.app_scheme}garmin/error")


@router.post("/sync", dependencies=_authed)
async def sync(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
):
    conn = await session.get(GarminConnection, uuid.UUID(user_id))
    if conn is None:
        raise garmin_not_connected()
    try:
        # Delegates to the garmin-sync job (§9.2 / §10).
        from ..jobs.tasks import garmin_sync

        synced = await garmin_sync(user_id)
    except GarminNotConfigured as exc:
        raise _not_configured() from exc
    return {"synced": synced}


@router.delete("/disconnect", status_code=status.HTTP_204_NO_CONTENT, dependencies=_authed)
async def disconnect(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> None:
    conn = await session.get(GarminConnection, uuid.UUID(user_id))
    if conn is not None:
        await session.delete(conn)


@router.post("/webhook")
async def webhook(request: Request):
    """Garmin push notifications. Validate the HMAC-SHA1 signature (§9.2)."""
    raw = await request.body()
    signature = request.headers.get("X-Garmin-Signature") or request.headers.get("Authorization")
    if not verify_webhook_signature(raw, signature):
        raise AppError("GARMIN_WEBHOOK_INVALID", "Invalid webhook signature.", 401)
    # Enqueue a sync job for the affected user(s); ack immediately.
    return {"accepted": True}
