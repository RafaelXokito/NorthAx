"""Dev seed: turn the env-provided intervals.icu API key into a live connection.

Creates a dev user + an `apikey`-mode intervals connection from
INTERVALS_API_KEY/INTERVALS_ATHLETE_ID, runs an initial sync (real intervals.icu
call → daily_metrics + activities), and generates plans. Run:

    python -m app.seed

Prints the dev user id so you can mint a token against it for local testing.
"""
from __future__ import annotations

import asyncio
import datetime as dt

from sqlalchemy import select

from .config import settings
from .db import Base, engine, session_scope
from .jobs.tasks import intervals_sync
from .models import IntervalsConnection, User, UserPreferences
from .security import encrypt_token
from .services.plan_service import regenerate_plans

DEV_APPLE_ID = "dev-seed-user"


async def main() -> None:
    if not settings.intervals_api_key:
        print("INTERVALS_API_KEY not set — nothing to seed.")
        return

    # Dev convenience: ensure tables exist.
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # 1. Upsert the dev user + preferences.
    async with session_scope(None) as session:
        res = await session.execute(select(User).where(User.apple_id == DEV_APPLE_ID))
        user = res.scalar_one_or_none()
        if user is None:
            user = User(apple_id=DEV_APPLE_ID, name="Rafael (dev)")
            session.add(user)
            await session.flush()
            session.add(UserPreferences(user_id=user.id))
        user_id = str(user.id)

    # 1b. Seed a sensible default frequency + split so plans populate.
    async with session_scope(user_id) as session:
        prefs = await session.get(UserPreferences, user.id)
        if prefs is None:
            prefs = UserPreferences(user_id=user.id)
            session.add(prefs)
        prefs.enabled_domains = ["Cycling", "Strength"]
        prefs.domain_frequencies = [
            {"domain": "Cycling", "daysPerWeek": 3},
            {"domain": "Strength", "daysPerWeek": 2},
        ]
        prefs.muscle_group_split = [
            {"muscleGroups": ["Chest", "Shoulders", "Triceps"], "isRestDay": False},
            {"muscleGroups": ["Back", "Biceps"], "isRestDay": False},
            {"muscleGroups": ["Quads", "Hamstrings", "Glutes", "Calves"], "isRestDay": False},
            {"muscleGroups": [], "isRestDay": True},
            {"muscleGroups": ["Chest", "Shoulders", "Triceps"], "isRestDay": False},
            {"muscleGroups": ["Back", "Biceps"], "isRestDay": False},
            {"muscleGroups": [], "isRestDay": True},
        ]

    # 2. Upsert the intervals.icu connection in API-key mode.
    far_future = dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=3650)
    async with session_scope(user_id) as session:
        conn = await session.get(IntervalsConnection, user.id)
        if conn is None:
            conn = IntervalsConnection(
                user_id=user.id, athlete_id=settings.intervals_athlete_id or "0",
                access_token="", refresh_token="", token_expires_at=far_future,
            )
            session.add(conn)
        conn.auth_mode = "apikey"
        conn.athlete_id = settings.intervals_athlete_id or "0"
        conn.access_token = encrypt_token(settings.intervals_api_key)
        conn.refresh_token = encrypt_token("")
        conn.token_expires_at = far_future
        conn.display_name = "intervals.icu"

    # 3. Initial sync (real intervals.icu data → daily_metrics + activities).
    result = await intervals_sync(user_id)
    print("sync result:", result)

    # 4. Generate plans.
    async with session_scope(user_id) as session:
        rows = await regenerate_plans(session, user_id, dt.date.today(), weeks=4)
    print("plans generated:", len(rows))
    print("dev user id:", user_id)


if __name__ == "__main__":
    asyncio.run(main())
