"""Fixtures for API integration tests.

These exercise the real FastAPI app in-process (auth dependency, RLS-scoped DB
session, engines, error envelope) against a Postgres instance. They SKIP cleanly
when no database is reachable, so the default unit-test run needs no DB:

    # unit only (no DB):      pytest
    # incl. integration:      DATABASE_URL=postgresql+asyncpg://northax@localhost:5544/northax pytest
"""
from __future__ import annotations

import uuid

import httpx
import pytest
import pytest_asyncio
from sqlalchemy import delete

from app.db import Base, engine, session_scope
from app.main import app
from app.models import User, UserPreferences
from app.security import issue_access_token


@pytest_asyncio.fixture
async def _db():
    # pytest-asyncio gives each test its own event loop; dispose the async
    # engine's pool so connections are (re)created on the current loop.
    await engine.dispose()
    try:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
    except Exception as exc:  # noqa: BLE001
        pytest.skip(f"Postgres not reachable ({type(exc).__name__}); set DATABASE_URL to run integration tests")
    yield


@pytest_asyncio.fixture
async def api(_db):
    """Yield (client, auth_headers, user_id) for a fresh throwaway user."""
    apple_id = f"itest-{uuid.uuid4()}"
    async with session_scope(None) as session:
        user = User(apple_id=apple_id, name="ITest")
        session.add(user)
        await session.flush()
        session.add(UserPreferences(user_id=user.id))
        user_id = str(user.id)

    headers = {"Authorization": f"Bearer {issue_access_token(user_id)}"}
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://itest") as client:
        yield client, headers, user_id

    async with session_scope(None) as session:
        await session.execute(delete(User).where(User.apple_id == apple_id))
