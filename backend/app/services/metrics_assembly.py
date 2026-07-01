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

from ..models import Activity, DailyMetrics, MetricReading, UserPreferences

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


# ── Multi-source resolution (pure) ───────────────────────────────────────────
# Representative field (first) decides the winning source; the winner supplies all
# its fields for that metric. Keyed by MergeableMetric (matches the iOS/priority keys).
MERGEABLE_FIELDS: dict[str, list[str]] = {
    "hrv": ["hrv"],
    "restingHR": ["resting_hr"],
    "sleep": ["sleep_duration", "sleep_score", "rem_sleep", "deep_sleep"],
    "bodyWeight": ["body_weight"],
}
# Server-side sources only; HealthKit stays on-device and is resolved by the client.
_DEFAULT_ORDER = ["intervals", "manual"]


def resolve_readings(
    rows: dict[str, dict], priority: dict[str, list[str]]
) -> tuple[dict, dict]:
    """Given ``{source: values}`` for a day and the user's per-metric priority,
    pick the winning source per mergeable metric. Returns ``(merged, provenance)``
    where provenance is ``{metric: source}``. Load fields (atl/ctl) are
    intervals-only and passed through."""
    merged: dict = {}
    provenance: dict = {}
    for metric, fields in MERGEABLE_FIELDS.items():
        order = [s for s in (priority.get(metric) or _DEFAULT_ORDER) if s != "healthkit"]
        order = order or _DEFAULT_ORDER
        rep = fields[0]
        winner = next((s for s in order if rows.get(s, {}).get(rep) is not None), None)
        if winner is None:
            continue
        for f in fields:
            if rows[winner].get(f) is not None:
                merged[f] = rows[winner][f]
        provenance[metric] = winner
    iv = rows.get("intervals", {})
    for f in ("atl", "ctl", "hrv_baseline_hint", "vo2max"):
        if iv.get(f) is not None:
            merged[f] = iv[f]
    return merged, provenance


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


async def record_source_readings(
    session: AsyncSession, user_id: str, date: dt.date, source: str, values: dict
) -> None:
    """Upsert one source's raw wellness contribution for a day (non-None fields
    only). ``daily_metrics`` is then (re)assembled from all a day's sources."""
    clean = {k: v for k, v in values.items() if v is not None and k != "date"}
    stmt = (
        pg_insert(MetricReading)
        .values(user_id=uuid.UUID(str(user_id)), date=date, source=source, values=clean)
        .on_conflict_do_update(
            index_elements=[MetricReading.user_id, MetricReading.date, MetricReading.source],
            set_={"values": clean},
        )
    )
    await session.execute(stmt)


async def _load_priority(session: AsyncSession, user_id: str) -> dict:
    prefs = await session.get(UserPreferences, uuid.UUID(str(user_id)))
    return dict(prefs.metric_priority) if prefs and prefs.metric_priority else {}


async def assemble_daily_metrics(session: AsyncSession, user_id: str, date: dt.date) -> bool:
    """Resolve the day's stored per-source readings against the user's priority,
    derive baselines/trends/loads from history, and upsert daily_metrics (with
    provenance). Returns False (and skips) when no source provides HRV — readiness
    can't be computed without it."""
    uid = uuid.UUID(str(user_id))
    result = await session.execute(
        select(MetricReading).where(MetricReading.user_id == uid, MetricReading.date == date)
    )
    rows = {r.source: dict(r.values) for r in result.scalars().all()}
    if not rows:
        return False

    priority = await _load_priority(session, user_id)
    merged, provenance = resolve_readings(rows, priority)

    hrv = merged.get("hrv")
    if hrv is None:
        log.info("skipping daily_metrics for %s %s — no HRV", user_id, date)
        return False

    prior = await _history(session, uid, date)
    hrv_series = [float(r.hrv) for r in prior] + [float(hrv)]
    rhr_series = [r.resting_hr for r in prior if r.resting_hr is not None]
    sleep_series = [float(r.sleep_duration) for r in prior if r.sleep_duration is not None]

    resting_hr = merged.get("resting_hr")
    sleep_duration = merged.get("sleep_duration")
    if resting_hr is not None:
        rhr_series.append(int(resting_hr))
    if sleep_duration is not None:
        sleep_series.append(float(sleep_duration))

    hrv_baseline = rolling_mean(hrv_series[-7:]) or float(hrv)
    if len(hrv_series) < 7 and merged.get("hrv_baseline_hint"):
        hrv_baseline = float(merged["hrv_baseline_hint"])
    resting_hr_baseline = rolling_mean([float(x) for x in rhr_series[-7:]]) or float(resting_hr or 0)

    totals = await _daily_load_totals(session, uid, date)
    computed_acute, computed_chronic, weekly_change = compute_loads(totals, date)
    # Prefer intervals.icu's own Fitness/Fatigue (CTL/ATL) when provided; it is
    # the authoritative impulse-response model. Fall back to local computation.
    acute = float(merged["atl"]) if merged.get("atl") is not None else computed_acute
    chronic = float(merged["ctl"]) if merged.get("ctl") is not None else computed_chronic

    values = {
        "user_id": uid,
        "date": date,
        "hrv": float(hrv),
        "hrv_baseline": round(hrv_baseline, 2),
        "hrv_trend": build_hrv_trend(hrv_series),
        "resting_hr": int(resting_hr) if resting_hr is not None else int(round(resting_hr_baseline)),
        "resting_hr_baseline": int(round(resting_hr_baseline)),
        "sleep_duration": float(sleep_duration) if sleep_duration is not None else 0.0,
        "sleep_score": int(merged.get("sleep_score") or 0),
        "rem_sleep": float(merged.get("rem_sleep") or 0.0),
        "deep_sleep": float(merged.get("deep_sleep") or 0.0),
        "sleep_debt": compute_sleep_debt(sleep_series),
        "acute_load": acute,
        "chronic_load": chronic,
        "today_load": 0.0,
        "weekly_load_change": weekly_change,
        "body_weight": float(merged["body_weight"]) if merged.get("body_weight") is not None else None,
        "vo2max": float(merged["vo2max"]) if merged.get("vo2max") is not None else None,
        "metric_sources": provenance,
    }

    # Upsert; a sync should not clobber the cached AI explanation, so we update
    # only the wellness/derived fields on conflict (ai_explanation is absent here).
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
