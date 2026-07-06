"""Segment endpoints (§13): the athlete's own Strava segment-effort history."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..deps import get_current_user_id, get_db
from ..errors import segment_not_found
from ..models import SegmentEffort
from ..rate_limit import limit

router = APIRouter(prefix="/segments", tags=["segments"], dependencies=[Depends(limit("default", 300, 60))])


@router.get("/{segment_id}/efforts", response_model=schemas.SegmentHistoryDTO)
async def segment_efforts(
    segment_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.SegmentHistoryDTO:
    """All of the athlete's efforts on one segment, newest first."""
    result = await session.execute(
        select(SegmentEffort)
        .where(
            SegmentEffort.user_id == uuid.UUID(user_id),
            SegmentEffort.segment_id == segment_id,
        )
        .order_by(SegmentEffort.start_date.desc())
    )
    rows = list(result.scalars().all())
    if not rows:
        raise segment_not_found()
    newest = rows[0]
    return schemas.SegmentHistoryDTO(
        segment_id=newest.segment_id,
        name=newest.name,
        distance_meters=float(newest.distance_meters) if newest.distance_meters is not None else None,
        avg_grade=float(newest.avg_grade) if newest.avg_grade is not None else None,
        climb_category=newest.climb_category,
        efforts=[schemas.SegmentEffortDTO.model_validate(r) for r in rows],
    )
