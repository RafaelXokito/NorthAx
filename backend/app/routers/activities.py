"""Activity endpoints (§7.7)."""
from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..deps import get_current_user_id, get_db
from ..errors import activity_garmin_immutable, activity_not_found
from ..models import Activity
from ..rate_limit import limit

router = APIRouter(prefix="/activities", tags=["activities"], dependencies=[Depends(limit("default", 300, 60))])


def _dto(row: Activity) -> schemas.ActivityDTO:
    return schemas.ActivityDTO.model_validate(row)


async def _load(session: AsyncSession, user_id: str, activity_id: uuid.UUID) -> Activity:
    row = await session.get(Activity, activity_id)
    if row is None or row.user_id != uuid.UUID(user_id):
        raise activity_not_found()
    return row


@router.get("", response_model=schemas.PaginatedActivities)
async def list_activities(
    limit_: int = Query(default=20, ge=1, le=100, alias="limit"),
    offset: int = Query(default=0, ge=0),
    domain: str | None = Query(default=None),
    source: str | None = Query(default=None),
    from_: dt.date | None = Query(default=None, alias="from"),
    to: dt.date | None = Query(default=None),
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.PaginatedActivities:
    filters = [Activity.user_id == uuid.UUID(user_id)]
    if domain:
        filters.append(Activity.domain == domain)
    if source:
        filters.append(Activity.source == source)
    if from_:
        filters.append(Activity.start_time >= dt.datetime.combine(from_, dt.time.min))
    if to:
        filters.append(Activity.start_time <= dt.datetime.combine(to, dt.time.max))

    total = await session.scalar(select(func.count()).select_from(Activity).where(*filters))
    result = await session.execute(
        select(Activity).where(*filters).order_by(Activity.start_time.desc()).limit(limit_).offset(offset)
    )
    items = [_dto(r) for r in result.scalars().all()]
    return schemas.PaginatedActivities(
        items=items, total=total or 0, limit=limit_, offset=offset, has_more=offset + len(items) < (total or 0)
    )


@router.post("", response_model=schemas.ActivityDTO, status_code=201)
async def create_activity(
    body: schemas.ActivityInput,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.ActivityDTO:
    row = Activity(
        user_id=uuid.UUID(user_id),
        source="manual",
        name=body.name,
        domain=body.domain,
        start_time=body.start_time,
        duration_seconds=body.duration_seconds,
        distance_meters=body.distance_meters,
        elevation_gain=body.elevation_gain,
        avg_heart_rate=body.avg_heart_rate,
        max_heart_rate=body.max_heart_rate,
        calories=body.calories,
        training_load=body.training_load,
        notes=body.notes,
    )
    session.add(row)
    await session.flush()
    return _dto(row)


@router.get("/{activity_id}", response_model=schemas.ActivityDTO)
async def get_activity(
    activity_id: uuid.UUID,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.ActivityDTO:
    return _dto(await _load(session, user_id, activity_id))


@router.patch("/{activity_id}", response_model=schemas.ActivityDTO)
async def update_activity(
    activity_id: uuid.UUID,
    body: schemas.ActivityPatch,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.ActivityDTO:
    row = await _load(session, user_id, activity_id)
    if row.source == "garmin":
        raise activity_garmin_immutable()
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(row, field, value)
    return _dto(row)


@router.delete("/{activity_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_activity(
    activity_id: uuid.UUID,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> None:
    row = await _load(session, user_id, activity_id)
    if row.source == "garmin":
        raise activity_garmin_immutable()
    await session.delete(row)
