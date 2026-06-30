"""Auth endpoints (§7.1): email/password register + login, refresh rotation,
sign out, delete."""
from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, status
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..deps import get_current_user_id, get_db, get_unscoped_db
from ..errors import auth_email_taken, auth_invalid_credentials, auth_token_revoked
from ..models import RefreshToken, User, UserPreferences
from ..rate_limit import limit
from ..security import (
    DUMMY_PASSWORD_HASH,
    decode_token,
    hash_password,
    issue_access_token,
    issue_refresh_token,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["auth"])


async def _issue_pair(session: AsyncSession, user_id: uuid.UUID) -> tuple[str, str]:
    access = issue_access_token(str(user_id))
    refresh, jti, expires_at = issue_refresh_token(str(user_id))
    session.add(RefreshToken(jti=uuid.UUID(jti), user_id=user_id, expires_at=expires_at))
    return access, refresh


def _auth_response(user: User, access: str, refresh: str) -> schemas.AuthResponse:
    return schemas.AuthResponse(
        access_token=access,
        refresh_token=refresh,
        user=schemas.UserSummary(id=user.id, name=user.name, email=user.email),
    )


@router.post("/register", response_model=schemas.AuthResponse, dependencies=[Depends(limit("auth_register", 5, 60, by="ip"))])
async def register(
    body: schemas.EmailSignUpRequest, session: AsyncSession = Depends(get_unscoped_db)
) -> schemas.AuthResponse:
    existing = await session.execute(select(User.id).where(User.email == body.email))
    if existing.scalar_one_or_none() is not None:
        raise auth_email_taken()

    user = User(email=body.email, password_hash=hash_password(body.password), name=body.name)
    session.add(user)
    await session.flush()
    session.add(UserPreferences(user_id=user.id))

    access, refresh = await _issue_pair(session, user.id)

    # No plan is generated here: a new user hasn't defined a training frequency
    # yet, so there's nothing to plan. Plans are created when they first set
    # their frequency (POST/PATCH /preferences regenerates forward weeks). This
    # keeps the app's "create a plan" prompt honest instead of showing an
    # assumed all-rest schedule.

    return _auth_response(user, access, refresh)


@router.post("/login", response_model=schemas.AuthResponse, dependencies=[Depends(limit("auth_login", 10, 60, by="ip"))])
async def login(
    body: schemas.EmailSignInRequest, session: AsyncSession = Depends(get_unscoped_db)
) -> schemas.AuthResponse:
    result = await session.execute(select(User).where(User.email == body.email))
    user = result.scalar_one_or_none()
    if user is None:
        # Hash anyway so a missing email and a wrong password take the same time.
        verify_password(body.password, DUMMY_PASSWORD_HASH)
        raise auth_invalid_credentials()
    if not verify_password(body.password, user.password_hash):
        raise auth_invalid_credentials()

    access, refresh = await _issue_pair(session, user.id)
    return _auth_response(user, access, refresh)


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
