"""Training plan endpoints (§7.6)."""
from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.attributes import flag_modified

from .. import schemas
from ..deps import get_current_user_id, get_db
from ..engines.plan import monday_of
from ..errors import AppError, plan_week_not_found
from ..models import WeeklyPlanRow
from ..rate_limit import limit
from ..services import mappers, plan_service

router = APIRouter(prefix="/plan", tags=["plan"], dependencies=[Depends(limit("default", 300, 60))])


def _require_monday(week_start: dt.date) -> None:
    if week_start.weekday() != 0:
        raise AppError("PLAN_WEEK_INVALID", "weekStart must be a Monday.", 400)


def _dto(row: WeeklyPlanRow, today: dt.date) -> schemas.WeeklyPlanDTO:
    return mappers.plan_dto_from_row(row.week_start, row.days, row.generated_at, row.id, today)


@router.get("/weeks", response_model=list[schemas.WeeklyPlanDTO])
async def list_weeks(
    from_: dt.date | None = Query(default=None, alias="from"),
    weeks: int = Query(default=4, ge=1, le=12),
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> list[schemas.WeeklyPlanDTO]:
    today = dt.date.today()
    rows = await plan_service.get_weeks(session, user_id, from_ or today, weeks)
    return [_dto(r, today) for r in rows]


@router.get("/week/{week_start}", response_model=schemas.WeeklyPlanDTO)
async def get_week(
    week_start: dt.date,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.WeeklyPlanDTO:
    _require_monday(week_start)
    result = await session.execute(
        select(WeeklyPlanRow).where(
            WeeklyPlanRow.user_id == uuid.UUID(user_id), WeeklyPlanRow.week_start == week_start
        )
    )
    row = result.scalar_one_or_none()
    if row is None:
        raise plan_week_not_found()
    return _dto(row, dt.date.today())


@router.post("/generate", response_model=list[schemas.WeeklyPlanDTO])
async def generate(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> list[schemas.WeeklyPlanDTO]:
    today = dt.date.today()
    rows = await plan_service.regenerate_plans(session, user_id, today, weeks=4)
    return [_dto(r, today) for r in rows]


@router.patch("/week/{week_start}/day/{date}", response_model=schemas.WeeklyPlanDTO)
async def override_day(
    week_start: dt.date,
    date: dt.date,
    body: schemas.DayOverrideRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.WeeklyPlanDTO:
    _require_monday(week_start)
    result = await session.execute(
        select(WeeklyPlanRow).where(
            WeeklyPlanRow.user_id == uuid.UUID(user_id), WeeklyPlanRow.week_start == week_start
        )
    )
    row = result.scalar_one_or_none()
    if row is None:
        raise plan_week_not_found()

    target = date.isoformat()
    found = False
    for entry in row.days:
        if entry["date"] == target:
            if body.session is None:  # clear → rest day
                entry["session"] = None
                entry["isRest"] = True
            else:
                entry["session"] = {
                    "domain": body.session.domain,
                    "title": body.session.title,
                    "subtitle": body.session.subtitle,
                    "duration": body.session.duration,
                    "intensityLabel": body.session.intensity_label,
                }
                entry["isRest"] = False
            found = True
            break
    if not found:
        raise AppError("PLAN_DAY_NOT_FOUND", f"{target} is not in this week.", 404)

    flag_modified(row, "days")  # JSONB mutated in place
    return _dto(row, dt.date.today())
