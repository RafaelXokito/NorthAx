"""Readiness endpoints (§7.4). Score is deterministic; the AI explanation is
generated once and cached in daily_metrics.ai_explanation (§8.1)."""
from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..deps import get_current_user_id, get_db
from ..engines import readiness as engine
from ..errors import metrics_not_found
from ..models import DailyMetrics
from ..rate_limit import limit
from ..services import ai, mappers

router = APIRouter(prefix="/readiness", tags=["readiness"], dependencies=[Depends(limit("default", 300, 60))])


async def _compute(session: AsyncSession, user_id: str, date: dt.date) -> schemas.DailyReadinessResponse:
    result_row = await session.execute(
        select(DailyMetrics).where(
            DailyMetrics.user_id == uuid.UUID(user_id), DailyMetrics.date == date
        )
    )
    row = result_row.scalar_one_or_none()
    if row is None:
        raise metrics_not_found(date.isoformat())

    metrics = mappers.metrics_from_row(row)
    readiness_result = engine.calculate(metrics)

    ai_explanation = row.ai_explanation
    if ai_explanation is None:
        ai_explanation = await ai.readiness_explanation(
            metrics, readiness_result, dt.datetime.now(dt.timezone.utc)
        )
        if ai_explanation is not None:
            row.ai_explanation = ai_explanation  # cached for subsequent requests

    return mappers.readiness_response(date, readiness_result, ai_explanation)


@router.get("/today", response_model=schemas.DailyReadinessResponse)
async def readiness_today(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> schemas.DailyReadinessResponse:
    return await _compute(session, user_id, dt.date.today())


@router.get("/{date}", response_model=schemas.DailyReadinessResponse)
async def readiness_for_date(
    date: dt.date,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.DailyReadinessResponse:
    return await _compute(session, user_id, date)
