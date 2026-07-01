"""Daily metrics endpoints (§7.3)."""
from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..deps import get_current_user_id, get_db
from ..errors import metrics_already_exists, metrics_not_found
from ..models import DailyMetrics
from ..rate_limit import limit

router = APIRouter(prefix="/metrics", tags=["metrics"], dependencies=[Depends(limit("default", 300, 60))])


def _to_response(
    row: DailyMetrics, series: dict | None = None
) -> schemas.DailyMetricsResponse:
    return schemas.DailyMetricsResponse(
        date=row.date,
        hrv=float(row.hrv),
        hrv_baseline=float(row.hrv_baseline),
        hrv_trend=[float(x) for x in row.hrv_trend],
        resting_hr=row.resting_hr,
        resting_hr_baseline=row.resting_hr_baseline,
        sleep_duration=float(row.sleep_duration),
        sleep_score=row.sleep_score,
        rem_sleep=float(row.rem_sleep),
        deep_sleep=float(row.deep_sleep),
        sleep_debt=float(row.sleep_debt),
        acute_load=float(row.acute_load),
        chronic_load=float(row.chronic_load),
        today_load=float(row.today_load),
        weekly_load_change=float(row.weekly_load_change),
        body_weight=float(row.body_weight) if row.body_weight is not None else None,
        metric_sources=dict(getattr(row, "metric_sources", {}) or {}),
        **(series or {}),
    )


async def _series(
    session: AsyncSession, user_id: str, end_date: dt.date, days: int = 90
) -> dict:
    """Aligned daily series ending on `end_date` (oldest→newest) for the detail
    graphs. TSB is Fitness − Fatigue (chronic − acute), matching the client."""
    result = await session.execute(
        select(DailyMetrics)
        .where(DailyMetrics.user_id == uuid.UUID(user_id), DailyMetrics.date <= end_date)
        .order_by(DailyMetrics.date.desc())
        .limit(days)
    )
    rows = list(reversed(result.scalars().all()))
    return {
        "trend_dates": [r.date for r in rows],
        "hrv_series": [float(r.hrv) for r in rows],
        "resting_hr_series": [float(r.resting_hr) for r in rows],
        "sleep_series": [float(r.sleep_duration) for r in rows],
        "tsb_series": [float(r.chronic_load) - float(r.acute_load) for r in rows],
    }


async def _get_by_date(session: AsyncSession, user_id: str, date: dt.date) -> DailyMetrics | None:
    result = await session.execute(
        select(DailyMetrics).where(
            DailyMetrics.user_id == uuid.UUID(user_id), DailyMetrics.date == date
        )
    )
    return result.scalar_one_or_none()


@router.post("/daily", response_model=schemas.DailyMetricsResponse, status_code=201)
async def submit_daily(
    body: schemas.DailyMetricsInput,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.DailyMetricsResponse:
    row = DailyMetrics(
        user_id=uuid.UUID(user_id),
        date=body.date,
        hrv=body.hrv,
        hrv_baseline=body.hrv_baseline,
        hrv_trend=body.hrv_trend,
        resting_hr=body.resting_hr,
        resting_hr_baseline=body.resting_hr_baseline,
        sleep_duration=body.sleep_duration,
        sleep_score=body.sleep_score,
        rem_sleep=body.rem_sleep,
        deep_sleep=body.deep_sleep,
        sleep_debt=body.sleep_debt,
        acute_load=body.acute_load,
        chronic_load=body.chronic_load,
        today_load=body.today_load,
        weekly_load_change=body.weekly_load_change,
        body_weight=body.body_weight,
    )
    session.add(row)
    try:
        await session.flush()
    except IntegrityError as exc:
        raise metrics_already_exists(body.date.isoformat()) from exc
    return _to_response(row)


@router.post("/manual", response_model=schemas.DailyMetricsResponse, status_code=201)
async def submit_manual(
    body: schemas.ManualMetricsInput,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.DailyMetricsResponse:
    """Record user-entered values as a `manual` source reading, then re-resolve the
    day's metrics against all sources (per the user's priority)."""
    from ..services.metrics_assembly import assemble_daily_metrics, record_source_readings

    values = body.model_dump(exclude={"date"}, exclude_none=True)
    await record_source_readings(session, user_id, body.date, "manual", values)
    if not await assemble_daily_metrics(session, user_id, body.date):
        # No source (incl. this entry) supplies HRV yet — readiness needs it.
        raise metrics_not_found(body.date.isoformat())
    row = await _get_by_date(session, user_id, body.date)
    return _to_response(row, await _series(session, user_id, body.date))


@router.get("/daily", response_model=schemas.DailyMetricsResponse)
async def get_today(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> schemas.DailyMetricsResponse:
    today = dt.date.today()
    row = await _get_by_date(session, user_id, today)
    if row is None:
        raise metrics_not_found(today.isoformat())
    return _to_response(row, await _series(session, user_id, today))


@router.get("/daily/{date}", response_model=schemas.DailyMetricsResponse)
async def get_for_date(
    date: dt.date,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.DailyMetricsResponse:
    row = await _get_by_date(session, user_id, date)
    if row is None:
        raise metrics_not_found(date.isoformat())
    return _to_response(row, await _series(session, user_id, date))


@router.get("/history", response_model=list[schemas.DailyMetricsResponse])
async def get_history(
    from_: dt.date | None = Query(default=None, alias="from"),
    to: dt.date | None = Query(default=None),
    limit_: int = Query(default=42, le=90, alias="limit"),
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> list[schemas.DailyMetricsResponse]:
    today = dt.date.today()
    from_date = from_ or (today - dt.timedelta(days=42))
    to_date = to or today
    result = await session.execute(
        select(DailyMetrics)
        .where(
            DailyMetrics.user_id == uuid.UUID(user_id),
            DailyMetrics.date >= from_date,
            DailyMetrics.date <= to_date,
        )
        .order_by(DailyMetrics.date.desc())
        .limit(limit_)
    )
    return [_to_response(r) for r in result.scalars().all()]
