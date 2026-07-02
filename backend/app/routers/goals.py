"""Latest AI goal-progress verdicts (one per targeted sport)."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..deps import get_current_user_id, get_db
from ..models import GoalProgress
from ..rate_limit import limit

router = APIRouter(prefix="/goals", tags=["goals"], dependencies=[Depends(limit("default", 300, 60))])


@router.get("/progress", response_model=list[schemas.GoalProgressDTO])
async def list_progress(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> list[schemas.GoalProgressDTO]:
    rows = (
        await session.execute(
            select(GoalProgress)
            .where(GoalProgress.user_id == uuid.UUID(user_id))
            .order_by(GoalProgress.domain)
        )
    ).scalars().all()
    return [
        schemas.GoalProgressDTO(
            domain=r.domain,
            verdict=r.verdict,
            summary=r.summary,
            recommend_replan=r.recommend_replan,
            analyzed_at=r.analyzed_at,
        )
        for r in rows
    ]
