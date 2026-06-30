"""Async SQLAlchemy engine, session factory, and the RLS user-scoping helper (§4)."""
from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from .config import settings

engine = create_async_engine(settings.database_url, pool_pre_ping=True, future=True)
SessionFactory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


class Base(DeclarativeBase):
    pass


@asynccontextmanager
async def session_scope(user_id: str | None = None) -> AsyncIterator[AsyncSession]:
    """Yield a session whose transaction has `app.current_user_id` set so that
    PostgreSQL Row-Level Security policies (§4) scope every query to one user."""
    async with SessionFactory() as session:
        if user_id is not None:
            # set_config(..., true) is transaction-local; pair with the commit below.
            await session.execute(
                text("SELECT set_config('app.current_user_id', :uid, true)"),
                {"uid": str(user_id)},
            )
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
