"""User profile endpoints (§7.2)."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..deps import get_current_user_id, get_db
from ..errors import AppError
from ..models import User
from ..rate_limit import limit

router = APIRouter(prefix="/user", tags=["user"], dependencies=[Depends(limit("default", 300, 60))])


async def _load(session: AsyncSession, user_id: str) -> User:
    user = await session.get(User, uuid.UUID(user_id))
    if user is None:
        raise AppError("USER_NOT_FOUND", "User not found.", 404)
    return user


@router.get("/profile", response_model=schemas.UserProfile)
async def get_profile(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> schemas.UserProfile:
    user = await _load(session, user_id)
    return schemas.UserProfile(id=user.id, name=user.name, email=user.email, created_at=user.created_at)


@router.patch("/profile", response_model=schemas.UserProfile)
async def update_profile(
    body: schemas.UpdateProfileRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.UserProfile:
    user = await _load(session, user_id)
    user.name = body.name
    return schemas.UserProfile(id=user.id, name=user.name, email=user.email, created_at=user.created_at)
