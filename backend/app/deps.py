"""FastAPI dependencies: bearer-token auth and RLS-scoped DB sessions (§3.3, §4)."""
from __future__ import annotations

from collections.abc import AsyncIterator

from fastapi import Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession

from .db import session_scope
from .errors import AppError
from .security import decode_token


async def get_current_user_id(authorization: str | None = Header(default=None)) -> str:
    """Extract and verify the `sub` (userId) from the Bearer access token."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise AppError("AUTH_TOKEN_EXPIRED", "Missing bearer token.", 401)
    token = authorization.split(" ", 1)[1].strip()
    claims = decode_token(token, expected_type="access")
    return claims["sub"]


async def get_db(user_id: str = Depends(get_current_user_id)) -> AsyncIterator[AsyncSession]:
    """A DB session whose transaction is scoped to the authenticated user via RLS."""
    async with session_scope(user_id) as session:
        yield session


async def get_unscoped_db() -> AsyncIterator[AsyncSession]:
    """A DB session with no RLS user binding — for the auth endpoints only."""
    async with session_scope(None) as session:
        yield session
