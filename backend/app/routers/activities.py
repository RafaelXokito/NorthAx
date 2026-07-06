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
from ..models import Activity, Segment, SegmentEffort, UserPreferences
from ..rate_limit import limit

router = APIRouter(prefix="/activities", tags=["activities"], dependencies=[Depends(limit("default", 300, 60))])

# Default activity-source order when the user hasn't set one (garmin = intervals.icu).
_DEFAULT_ACTIVITY_PRIORITY = ["garmin", "strava", "manual"]
_DEDUPE_DURATION_TOLERANCE = 300  # seconds — same workout across sources


_MERGE_FILL_INT = ("avg_heart_rate", "max_heart_rate", "calories")
_MERGE_FILL_FLOAT = ("distance_meters", "elevation_gain", "training_load")


def _merge_by_priority(rows: list[Activity], priority: list[str]) -> list[schemas.ActivityDTO]:
    """Collapse the same workout reported by more than one source (same day +
    domain + near-equal duration) into one record: the highest-priority source
    wins, and any field it lacks is gap-filled from the next source that has it."""
    rank = {s: i for i, s in enumerate(priority)}

    def r(src: str) -> int:
        return rank.get(src, len(priority))

    groups: list[list[Activity]] = []
    for row in rows:
        placed = False
        for g in groups:
            k = g[0]
            if (
                k.domain == row.domain
                and k.start_time.date() == row.start_time.date()
                and abs(k.duration_seconds - row.duration_seconds) <= _DEDUPE_DURATION_TOLERANCE
                and all(m.source != row.source for m in g)  # one row per source per group
            ):
                g.append(row)
                placed = True
                break
        if not placed:
            groups.append([row])

    out: list[schemas.ActivityDTO] = []
    for g in groups:
        g.sort(key=lambda x: r(x.source))  # winner first
        dto = _dto(g[0])
        for other in g[1:]:
            for field in _MERGE_FILL_INT:
                if getattr(dto, field) is None and getattr(other, field) is not None:
                    setattr(dto, field, int(getattr(other, field)))
            for field in _MERGE_FILL_FLOAT:
                if getattr(dto, field) is None and getattr(other, field) is not None:
                    setattr(dto, field, float(getattr(other, field)))
            # A manually logged strength session merged under a watch-synced
            # duplicate keeps its exercise log.
            if dto.strength_exercises is None and other.strength_exercises is not None:
                dto.strength_exercises = [
                    schemas.LoggedExerciseDTO.model_validate(e) for e in other.strength_exercises
                ]
            # Keep whichever source had GPS for the route thumbnail.
            if dto.route_points is None and other.route_points is not None:
                dto.route_points = other.route_points
        out.append(dto)
    return out


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
    rows = list(result.scalars().all())

    # Cross-source merge by the user's activity-source preference (§13). Only when
    # not filtered to a single source (the per-source views want raw rows).
    if source is None:
        prefs = await session.get(UserPreferences, uuid.UUID(user_id))
        priority = (getattr(prefs, "activity_priority", None) or _DEFAULT_ACTIVITY_PRIORITY)
        items = _merge_by_priority(rows, priority)
    else:
        items = [_dto(r) for r in rows]
    return schemas.PaginatedActivities(
        items=items, total=total or 0, limit=limit_, offset=offset, has_more=offset + len(items) < (total or 0)
    )


@router.get("/{external_id}/streams", response_model=schemas.ActivityStreamsDTO)
async def activity_streams(
    external_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.ActivityStreamsDTO:
    """Source-aware time-series streams for a completed activity (§10 / §13):
    resolves the activity's source and fetches from intervals.icu or Strava.
    Empty arrays when not connected or no streams exist."""
    from ..services.streams import normalize_streams

    row = (await session.execute(
        select(Activity).where(
            Activity.user_id == uuid.UUID(user_id), Activity.external_id == external_id
        )
    )).scalars().first()
    src = row.source if row else "garmin"

    if src == "strava":
        from ..jobs.tasks import _valid_strava_token
        from ..models import StravaConnection
        from ..services.strava import StravaClient, normalize_strava_streams

        conn = await session.get(StravaConnection, uuid.UUID(user_id))
        if conn is None:
            return schemas.ActivityStreamsDTO(activity_id=external_id, source="Strava")
        try:
            token = await _valid_strava_token(session, conn)
            raw = await StravaClient().fetch_activity_streams(token, external_id)
        except Exception:  # noqa: BLE001
            return schemas.ActivityStreamsDTO(activity_id=external_id, source="Strava")
        return normalize_streams(external_id, normalize_strava_streams(raw), source="Strava")

    from ..jobs.tasks import _valid_access_token
    from ..models import IntervalsConnection
    from ..services.intervals import IntervalsClient

    conn = await session.get(IntervalsConnection, uuid.UUID(user_id))
    if conn is None:
        return schemas.ActivityStreamsDTO(activity_id=external_id, source="intervals.icu")
    try:
        token = await _valid_access_token(session, conn)
        raw = await IntervalsClient().fetch_activity_streams(
            token, external_id, api_key=(conn.auth_mode == "apikey")
        )
    except Exception:  # noqa: BLE001
        return schemas.ActivityStreamsDTO(activity_id=external_id, source="intervals.icu")
    return normalize_streams(external_id, raw, source="intervals.icu")


@router.get("/{external_id}/segments", response_model=list[schemas.SegmentEffortDTO])
async def activity_segments(
    external_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> list[schemas.SegmentEffortDTO]:
    """Strava segment efforts for a completed activity (§13), resolved by time
    window rather than id: the client usually holds the intervals.icu external
    id (merge winner) while efforts are keyed to the Strava twin."""
    row = (await session.execute(
        select(Activity).where(
            Activity.user_id == uuid.UUID(user_id), Activity.external_id == external_id
        )
    )).scalars().first()
    if row is None:
        return []
    tolerance = dt.timedelta(seconds=_DEDUPE_DURATION_TOLERANCE)
    result = await session.execute(
        select(SegmentEffort)
        .where(
            SegmentEffort.user_id == uuid.UUID(user_id),
            SegmentEffort.start_date >= row.start_time - tolerance,
            SegmentEffort.start_date <= row.start_time + dt.timedelta(seconds=row.duration_seconds) + tolerance,
        )
        .order_by(SegmentEffort.start_date)  # course order
    )
    efforts = list(result.scalars().all())
    geom: dict[str, list] = {}
    best: dict[str, int] = {}
    if efforts:
        seg_ids = {e.segment_id for e in efforts}
        rows = (await session.execute(
            select(Segment).where(Segment.segment_id.in_(seg_ids))
        )).scalars().all()
        geom = {s.segment_id: s.points for s in rows if len(s.points or []) >= 2}
        best_rows = await session.execute(
            select(SegmentEffort.segment_id, func.min(SegmentEffort.elapsed_seconds))
            .where(SegmentEffort.user_id == uuid.UUID(user_id), SegmentEffort.segment_id.in_(seg_ids))
            .group_by(SegmentEffort.segment_id)
        )
        best = {sid: int(m) for sid, m in best_rows.all()}
    return [
        schemas.SegmentEffortDTO.model_validate(e).model_copy(
            update={"points": geom.get(e.segment_id), "best_elapsed_seconds": best.get(e.segment_id)}
        )
        for e in efforts
    ]


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
        strength_exercises=(
            [e.model_dump(by_alias=True) for e in body.strength_exercises]
            if body.strength_exercises
            else None
        ),
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
    data = body.model_dump(exclude_unset=True)
    if "strength_exercises" in data:
        # Stored JSONB is camelCase (matches create + the DTO round-trip).
        data["strength_exercises"] = (
            [e.model_dump(by_alias=True) for e in body.strength_exercises]
            if body.strength_exercises
            else None
        )
    for field, value in data.items():
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
