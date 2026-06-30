"""Assemble `daily_metrics` from Garmin wellness + stored history (§9.3).

Garmin supplies same-day readings (HRV, sleep, resting HR); the baselines,
7-day HRV trend, sleep debt, and ATL/CTL loads are *derived* from the user's
stored history so they ramp up over the first ~week. The pure math lives in
module-level helpers (unit-tested); `assemble_daily_metrics` does the DB I/O.
"""
from __future__ import annotations

import datetime as dt
import logging
import uuid

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import Activity, DailyMetrics

log = logging.getLogger("northax.metrics")

SLEEP_TARGET_HOURS = 8.0


# ── Pure helpers ─────────────────────────────────────────────────────────────
def rolling_mean(values: list[float]) -> float | None:
    vals = [v for v in values if v is not None]
    return round(sum(vals) / len(vals), 2) if vals else None


def build_hrv_trend(values_oldest_to_newest: list[float]) -> list[float]:
    """Return exactly 7 values, oldest→newest. Left-pad with the earliest value
    when fewer than 7 days of history exist (required length per §5.3)."""
    vals = [v for v in values_oldest_to_newest if v is not None]
    if not vals:
        return []
    last7 = vals[-7:]
    if len(last7) < 7:
        last7 = [last7[0]] * (7 - len(last7)) + last7
    return [round(v, 2) for v in last7]


def compute_sleep_debt(durations: list[float], target: float = SLEEP_TARGET_HOURS) -> float:
    """Cumulative shortfall vs `target` over the supplied recent days (≥ 0)."""
    return round(sum(max(0.0, target - d) for d in durations if d is not None), 2)


def compute_loads(
    daily_totals: dict[dt.date, float], ref_date: dt.date
) -> tuple[float, float, float]:
    """ATL (7-day mean), CTL (42-day mean), and weekly load change fraction,
    from per-day total training load. Means treat missing days as 0 load."""

    def window_sum(days: int) -> float:
        start = ref_date - dt.timedelta(days=days - 1)
        return sum(v for d, v in daily_totals.items() if start <= d <= ref_date)

    acute = round(window_sum(7) / 7, 2)
    chronic = round(window_sum(42) / 42, 2)

    this_week = window_sum(7)
    prev_start = ref_date - dt.timedelta(days=13)
    prev_end = ref_date - dt.timedelta(days=7)
    prev_week = sum(v for d, v in daily_totals.items() if prev_start <= d <= prev_end)
    weekly_change = round((this_week - prev_week) / prev_week, 4) if prev_week > 0 else 0.0
    # Clamp to the daily_metrics.weekly_load_change column range NUMERIC(5,4)
    # (|value| < 10); sparse early weeks can otherwise produce absurd ratios.
    weekly_change = max(-9.9999, min(9.9999, weekly_change))

    return acute, chronic, weekly_change


# ── DB orchestration ─────────────────────────────────────────────────────────
async def _daily_load_totals(
    session: AsyncSession, user_id: uuid.UUID, ref_date: dt.date
) -> dict[dt.date, float]:
    window_start = dt.datetime.combine(ref_date - dt.timedelta(days=41), dt.time.min)
    result = await session.execute(
        select(
            func.date(Activity.start_time),
            func.coalesce(func.sum(Activity.training_load), 0),
        )
        .where(Activity.user_id == user_id, Activity.start_time >= window_start)
        .group_by(func.date(Activity.start_time))
    )
    return {row[0]: float(row[1]) for row in result.all()}


async def _history(
    session: AsyncSession, user_id: uuid.UUID, before: dt.date, days: int = 6
):
    """Up to `days` prior daily_metrics rows, oldest→newest."""
    result = await session.execute(
        select(DailyMetrics)
        .where(DailyMetrics.user_id == user_id, DailyMetrics.date < before)
        .order_by(DailyMetrics.date.desc())
        .limit(days)
    )
    return list(reversed(result.scalars().all()))


async def assemble_daily_metrics(
    session: AsyncSession, user_id: str, date: dt.date, wellness: dict
) -> bool:
    """Merge a normalized intervals.icu wellness dict (see
    ``normalize_intervals_wellness``) with stored history and upsert daily_metrics.
    Returns False (and skips) if HRV is missing — readiness can't be computed."""
    uid = uuid.UUID(str(user_id))
    hrv = wellness.get("hrv")
    if hrv is None:
        log.info("skipping daily_metrics for %s %s — no HRV", user_id, date)
        return False

    prior = await _history(session, uid, date)
    hrv_series = [float(r.hrv) for r in prior] + [float(hrv)]
    rhr_series = [r.resting_hr for r in prior if r.resting_hr is not None]
    sleep_series = [float(r.sleep_duration) for r in prior if r.sleep_duration is not None]

    resting_hr = wellness.get("resting_hr")
    sleep_duration = wellness.get("sleep_duration")
    if resting_hr is not None:
        rhr_series.append(int(resting_hr))
    if sleep_duration is not None:
        sleep_series.append(float(sleep_duration))

    hrv_baseline = rolling_mean(hrv_series[-7:]) or float(hrv)
    if len(hrv_series) < 7 and wellness.get("hrv_baseline_hint"):
        hrv_baseline = float(wellness["hrv_baseline_hint"])
    resting_hr_baseline = rolling_mean([float(x) for x in rhr_series[-7:]]) or float(resting_hr or 0)

    totals = await _daily_load_totals(session, uid, date)
    computed_acute, computed_chronic, weekly_change = compute_loads(totals, date)
    # Prefer intervals.icu's own Fitness/Fatigue (CTL/ATL) when provided; it is
    # the authoritative impulse-response model. Fall back to local computation.
    acute = float(wellness["atl"]) if wellness.get("atl") is not None else computed_acute
    chronic = float(wellness["ctl"]) if wellness.get("ctl") is not None else computed_chronic

    values = {
        "user_id": uid,
        "date": date,
        "hrv": float(hrv),
        "hrv_baseline": round(hrv_baseline, 2),
        "hrv_trend": build_hrv_trend(hrv_series),
        "resting_hr": int(resting_hr) if resting_hr is not None else int(round(resting_hr_baseline)),
        "resting_hr_baseline": int(round(resting_hr_baseline)),
        "sleep_duration": float(sleep_duration) if sleep_duration is not None else 0.0,
        "sleep_score": int(wellness.get("sleep_score") or 0),
        "rem_sleep": float(wellness.get("rem_sleep") or 0.0),
        "deep_sleep": float(wellness.get("deep_sleep") or 0.0),
        "sleep_debt": compute_sleep_debt(sleep_series),
        "acute_load": acute,
        "chronic_load": chronic,
        "today_load": 0.0,
        "weekly_load_change": weekly_change,
    }

    # Upsert; a Garmin sync should not clobber the cached AI explanation, so we
    # update only the wellness/derived fields on conflict.
    stmt = (
        pg_insert(DailyMetrics)
        .values(**values)
        .on_conflict_do_update(
            index_elements=[DailyMetrics.user_id, DailyMetrics.date],
            set_={k: v for k, v in values.items() if k not in ("user_id", "date")},
        )
    )
    await session.execute(stmt)
    return True
