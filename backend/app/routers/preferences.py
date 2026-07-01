"""Preferences endpoints (§7.5). Frequency/split changes regenerate plans (§7.6)."""
from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..deps import get_current_user_id, get_db
from ..errors import (
    preferences_invalid_split,
    schedule_invalid_weekday,
    schedule_no_rest_day,
)
from ..models import UserPreferences
from ..rate_limit import limit
from ..services.plan_service import regenerate_plans

router = APIRouter(prefix="/preferences", tags=["preferences"], dependencies=[Depends(limit("default", 300, 60))])


async def _get_or_create(session: AsyncSession, user_id: str) -> UserPreferences:
    prefs = await session.get(UserPreferences, uuid.UUID(user_id))
    if prefs is None:
        prefs = UserPreferences(user_id=uuid.UUID(user_id))
        session.add(prefs)
        await session.flush()
    return prefs


def _to_dto(prefs: UserPreferences) -> schemas.UserPreferencesDTO:
    return schemas.UserPreferencesDTO(
        enabled_domains=list(prefs.enabled_domains),
        domain_schedules=[
            schemas.DomainScheduleDTO.model_validate(s) for s in prefs.domain_schedules
        ],
        thresholds=schemas.AthleteThresholdsDTO.model_validate(prefs.thresholds or {}),
        muscle_group_split=[schemas.DaySplitDTO(**d) for d in prefs.muscle_group_split],
        cycling_target=getattr(prefs, "cycling_target", "hr"),
        metric_priority=dict(getattr(prefs, "metric_priority", {}) or {}),
    )


def _validate_schedules(scheds: list[schemas.DomainScheduleDTO]) -> None:
    union: set[int] = set()
    for s in scheds:
        if any(w < 0 or w > 6 for w in s.weekdays) or len(set(s.weekdays)) != len(s.weekdays):
            raise schedule_invalid_weekday()
        union |= set(s.weekdays)
    if len(union) >= 7:
        raise schedule_no_rest_day()


def _validate_split(split: list[schemas.DaySplitDTO]) -> None:
    if len(split) != 7:
        raise preferences_invalid_split()


def _schedules_json(scheds: list[schemas.DomainScheduleDTO]) -> list[dict]:
    return [{"domain": s.domain, "weekdays": sorted(s.weekdays)} for s in scheds]


def _thresholds_json(t: schemas.AthleteThresholdsDTO) -> dict:
    return t.model_dump(by_alias=True)


def _split_json(split: list[schemas.DaySplitDTO]) -> list[dict]:
    return [{"muscleGroups": d.muscle_groups, "isRestDay": d.is_rest_day} for d in split]


@router.get("", response_model=schemas.UserPreferencesDTO)
async def get_preferences(
    user_id: str = Depends(get_current_user_id), session: AsyncSession = Depends(get_db)
) -> schemas.UserPreferencesDTO:
    return _to_dto(await _get_or_create(session, user_id))


@router.put("", response_model=schemas.UserPreferencesDTO)
async def replace_preferences(
    body: schemas.UserPreferencesDTO,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.UserPreferencesDTO:
    _validate_schedules(body.domain_schedules)
    if body.muscle_group_split:
        _validate_split(body.muscle_group_split)
    prefs = await _get_or_create(session, user_id)
    prefs.enabled_domains = body.enabled_domains
    prefs.domain_schedules = _schedules_json(body.domain_schedules)
    prefs.thresholds = _thresholds_json(body.thresholds)
    prefs.muscle_group_split = _split_json(body.muscle_group_split)
    if body.cycling_target in ("hr", "power"):
        prefs.cycling_target = body.cycling_target
    prefs.metric_priority = dict(body.metric_priority)
    await session.flush()
    await regenerate_plans(session, user_id, dt.date.today(), weeks=4)
    return _to_dto(prefs)


@router.patch("/metric-priority", response_model=schemas.UserPreferencesDTO)
async def patch_metric_priority(
    body: schemas.MetricPriorityPatch,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.UserPreferencesDTO:
    prefs = await _get_or_create(session, user_id)
    prefs.metric_priority = dict(body.metric_priority)
    await session.flush()  # no plan regeneration — priority only affects metric reads
    return _to_dto(prefs)


@router.patch("/target", response_model=schemas.UserPreferencesDTO)
async def patch_cycling_target(
    body: schemas.CyclingTargetPatch,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.UserPreferencesDTO:
    if body.cycling_target not in ("hr", "power"):
        from ..errors import AppError

        raise AppError("PREFERENCES_INVALID_TARGET", "cyclingTarget must be 'hr' or 'power'.", 422)
    prefs = await _get_or_create(session, user_id)
    prefs.cycling_target = body.cycling_target
    await session.flush()
    await regenerate_plans(session, user_id, dt.date.today(), weeks=4)  # rebuild structured workouts
    return _to_dto(prefs)


@router.patch("/domains", response_model=schemas.UserPreferencesDTO)
async def patch_domains(
    body: schemas.DomainsPatch,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.UserPreferencesDTO:
    prefs = await _get_or_create(session, user_id)
    prefs.enabled_domains = body.enabled_domains
    return _to_dto(prefs)


@router.patch("/schedule", response_model=schemas.UserPreferencesDTO)
async def patch_schedule(
    body: schemas.SchedulePatch,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.UserPreferencesDTO:
    _validate_schedules(body.domain_schedules)
    prefs = await _get_or_create(session, user_id)
    prefs.domain_schedules = _schedules_json(body.domain_schedules)
    await session.flush()
    await regenerate_plans(session, user_id, dt.date.today(), weeks=4)  # §7.6
    return _to_dto(prefs)


@router.patch("/thresholds", response_model=schemas.UserPreferencesDTO)
async def patch_thresholds(
    body: schemas.ThresholdsPatch,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.UserPreferencesDTO:
    prefs = await _get_or_create(session, user_id)
    merged = dict(prefs.thresholds or {})
    merged.update(body.model_dump(by_alias=True, exclude_none=True))
    prefs.thresholds = merged
    await session.flush()  # no plan regeneration — thresholds don't affect placement
    return _to_dto(prefs)


@router.patch("/muscle-split", response_model=schemas.UserPreferencesDTO)
async def patch_muscle_split(
    body: schemas.MuscleSplitPatch,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.UserPreferencesDTO:
    _validate_split(body.muscle_group_split)
    prefs = await _get_or_create(session, user_id)
    prefs.muscle_group_split = _split_json(body.muscle_group_split)
    await session.flush()
    await regenerate_plans(session, user_id, dt.date.today(), weeks=4)  # §7.6
    return _to_dto(prefs)
