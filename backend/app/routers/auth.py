"""Auth endpoints (§7.1): Sign in with Apple, refresh rotation, sign out, delete."""
from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, status
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..deps import get_current_user_id, get_db, get_unscoped_db
from ..errors import auth_token_revoked
from ..models import RefreshToken, User, UserPreferences
from ..rate_limit import limit
from ..security import (
    decode_token,
    issue_access_token,
    issue_refresh_token,
    verify_apple_identity_token,
)
from ..services.plan_service import regenerate_plans

router = APIRouter(prefix="/auth", tags=["auth"])


async def _issue_pair(session: AsyncSession, user_id: uuid.UUID) -> tuple[str, str]:
    access = issue_access_token(str(user_id))
    refresh, jti, expires_at = issue_refresh_token(str(user_id))
    session.add(RefreshToken(jti=uuid.UUID(jti), user_id=user_id, expires_at=expires_at))
    return access, refresh


@router.post("/apple", response_model=schemas.AuthResponse, dependencies=[Depends(limit("auth_apple", 10, 60, by="ip"))])
async def sign_in_with_apple(
    body: schemas.AppleSignInRequest, session: AsyncSession = Depends(get_unscoped_db)
) -> schemas.AuthResponse:
    claims = verify_apple_identity_token(body.identity_token)
    apple_id = claims["sub"]
    email = claims.get("email")

    result = await session.execute(select(User).where(User.apple_id == apple_id))
    user = result.scalar_one_or_none()
    created = False
    if user is None:
        # fullName is only sent by Apple on first sign-in (§3.1).
        name = "Athlete"
        if body.full_name and (body.full_name.given_name or body.full_name.family_name):
            name = " ".join(
                p for p in [body.full_name.given_name, body.full_name.family_name] if p
            ).strip()
        user = User(apple_id=apple_id, name=name, email=email)
        session.add(user)
        await session.flush()
        session.add(UserPreferences(user_id=user.id))
        created = True

    access, refresh = await _issue_pair(session, user.id)

    if created:
        # generate-plans job (§10): 4 weeks from the current Monday.
        await session.flush()
        await regenerate_plans(session, str(user.id), dt.date.today(), weeks=4)

    return schemas.AuthResponse(
        access_token=access,
        refresh_token=refresh,
        user=schemas.UserSummary(id=user.id, name=user.name, email=user.email),
    )


@router.post("/refresh", response_model=schemas.RefreshResponse, dependencies=[Depends(limit("auth_refresh", 20, 60, by="ip"))])
async def refresh_tokens(
    body: schemas.RefreshRequest, session: AsyncSession = Depends(get_unscoped_db)
) -> schemas.RefreshResponse:
    claims = decode_token(body.refresh_token, expected_type="refresh")
    jti = uuid.UUID(claims["jti"])
    user_id = uuid.UUID(claims["sub"])

    row = await session.get(RefreshToken, jti)
    if row is None or row.revoked or row.expires_at < dt.datetime.now(dt.timezone.utc):
        raise auth_token_revoked()

    # Rotate: delete the old row, issue a fresh pair.
    await session.execute(delete(RefreshToken).where(RefreshToken.jti == jti))
    access, refresh = await _issue_pair(session, user_id)
    return schemas.RefreshResponse(access_token=access, refresh_token=refresh)


@router.delete("/session", status_code=status.HTTP_204_NO_CONTENT)
async def sign_out(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> None:
    # Revoke all refresh tokens for this user (full sign-out).
    await session.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == uuid.UUID(user_id))
        .values(revoked=True)
    )


@router.delete("/account", status_code=status.HTTP_204_NO_CONTENT)
async def delete_account(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> None:
    # Hard-delete the user; all child rows cascade (§3.2, GDPR).
    await session.execute(delete(User).where(User.id == uuid.UUID(user_id)))
