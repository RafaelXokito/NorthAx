"""Plan generation orchestration shared by routers and background jobs (§7.6, §10)."""
from __future__ import annotations

import datetime as dt
import uuid

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from ..engines.plan import generate_plans, monday_of
from ..models import UserPreferences, WeeklyPlanRow
from . import mappers


async def _load_prefs(session: AsyncSession, user_id: str) -> UserPreferences | None:
    return await session.get(UserPreferences, uuid.UUID(str(user_id)))


async def regenerate_plans(
    session: AsyncSession, user_id: str, from_date: dt.date, weeks: int = 4
) -> list[WeeklyPlanRow]:
    """Generate `weeks` of plans from the current Monday and upsert them,
    overwriting any existing future plans for those weeks."""
    prefs = await _load_prefs(session, user_id)
    frequency = mappers.frequency_from_prefs(prefs.domain_frequencies if prefs else [])
    split = mappers.split_from_prefs(prefs.muscle_group_split if prefs else [])

    plans = generate_plans(from_date, weeks, frequency, split)
    rows: list[WeeklyPlanRow] = []
    for plan in plans:
        days_json = mappers.plan_days_to_json(plan)
        stmt = (
            pg_insert(WeeklyPlanRow)
            .values(
                user_id=uuid.UUID(str(user_id)),
                week_start=plan.week_start,
                days=days_json,
            )
            .on_conflict_do_update(
                index_elements=[WeeklyPlanRow.user_id, WeeklyPlanRow.week_start],
                set_={"days": days_json},
            )
            .returning(WeeklyPlanRow)
        )
        result = await session.execute(stmt)
        rows.append(result.scalar_one())
    return rows


async def get_weeks(
    session: AsyncSession, user_id: str, from_date: dt.date, weeks: int
) -> list[WeeklyPlanRow]:
    start = monday_of(from_date)
    end = start + dt.timedelta(weeks=weeks)
    result = await session.execute(
        select(WeeklyPlanRow)
        .where(
            WeeklyPlanRow.user_id == uuid.UUID(str(user_id)),
            WeeklyPlanRow.week_start >= start,
            WeeklyPlanRow.week_start < end,
        )
        .order_by(WeeklyPlanRow.week_start)
    )
    return list(result.scalars().all())
