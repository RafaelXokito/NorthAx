"""Preferences endpoints (§7.5). Frequency/split changes regenerate plans (§7.6)."""
from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from .. import schemas
from ..deps import get_current_user_id, get_db
from ..errors import preferences_invalid_frequency, preferences_invalid_split
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
        domain_frequencies=[schemas.DomainFrequencyDTO(**f) for f in prefs.domain_frequencies],
        muscle_group_split=[schemas.DaySplitDTO(**d) for d in prefs.muscle_group_split],
        cycling_target=getattr(prefs, "cycling_target", "hr"),
    )


def _validate_frequency(freqs: list[schemas.DomainFrequencyDTO]) -> None:
    if sum(f.days_per_week for f in freqs) > 6:
        raise preferences_invalid_frequency()


def _validate_split(split: list[schemas.DaySplitDTO]) -> None:
    if len(split) != 7:
        raise preferences_invalid_split()


def _freq_json(freqs: list[schemas.DomainFrequencyDTO]) -> list[dict]:
    return [{"domain": f.domain, "daysPerWeek": f.days_per_week} for f in freqs]


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
    _validate_frequency(body.domain_frequencies)
    if body.muscle_group_split:
        _validate_split(body.muscle_group_split)
    prefs = await _get_or_create(session, user_id)
    prefs.enabled_domains = body.enabled_domains
    prefs.domain_frequencies = _freq_json(body.domain_frequencies)
    prefs.muscle_group_split = _split_json(body.muscle_group_split)
    if body.cycling_target in ("hr", "power"):
        prefs.cycling_target = body.cycling_target
    await session.flush()
    await regenerate_plans(session, user_id, dt.date.today(), weeks=4)
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


@router.patch("/frequency", response_model=schemas.UserPreferencesDTO)
async def patch_frequency(
    body: schemas.FrequencyPatch,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db),
) -> schemas.UserPreferencesDTO:
    _validate_frequency(body.domain_frequencies)
    prefs = await _get_or_create(session, user_id)
    prefs.domain_frequencies = _freq_json(body.domain_frequencies)
    await session.flush()
    await regenerate_plans(session, user_id, dt.date.today(), weeks=4)  # §7.6
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
