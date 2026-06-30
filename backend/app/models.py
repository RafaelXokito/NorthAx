"""SQLAlchemy ORM models mirroring sql/schema.sql (§5)."""
from __future__ import annotations

import datetime as dt
import uuid

from sqlalchemy import (
    ARRAY,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
)
from sqlalchemy import Enum as SAEnum
from sqlalchemy import (
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)

# Native Postgres enums (match sql/schema.sql). create_type defaults True so
# create_all builds them in dev/test; schema.sql creates them in prod.
ACTIVITY_SOURCE = SAEnum("manual", "garmin", name="activity_source")
MESSAGE_ROLE = SAEnum("user", "coach", name="message_role")
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


def _uuid_pk() -> Mapped[uuid.UUID]:
    return mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = _uuid_pk()
    email: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False, default="Athlete")
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    jti: Mapped[uuid.UUID] = _uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    issued_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expires_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)


class DailyMetrics(Base):
    __tablename__ = "daily_metrics"
    __table_args__ = (
        UniqueConstraint("user_id", "date", name="daily_metrics_user_date_uq"),
        CheckConstraint("sleep_score BETWEEN 0 AND 100", name="sleep_score_range"),
    )

    id: Mapped[uuid.UUID] = _uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    date: Mapped[dt.date] = mapped_column(Date, nullable=False)

    hrv: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
    hrv_baseline: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
    hrv_trend: Mapped[list[float]] = mapped_column(ARRAY(Numeric(6, 2)), nullable=False)

    resting_hr: Mapped[int] = mapped_column(Integer, nullable=False)
    resting_hr_baseline: Mapped[int] = mapped_column(Integer, nullable=False)

    sleep_duration: Mapped[float] = mapped_column(Numeric(4, 2), nullable=False)
    sleep_score: Mapped[int] = mapped_column(Integer, nullable=False)
    rem_sleep: Mapped[float] = mapped_column(Numeric(4, 2), nullable=False)
    deep_sleep: Mapped[float] = mapped_column(Numeric(4, 2), nullable=False)
    sleep_debt: Mapped[float] = mapped_column(Numeric(4, 2), nullable=False)

    acute_load: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
    chronic_load: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
    today_load: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False, default=0)
    weekly_load_change: Mapped[float] = mapped_column(Numeric(5, 4), nullable=False)

    body_weight: Mapped[float | None] = mapped_column(Numeric(5, 2), nullable=True)
    ai_explanation: Mapped[dict | None] = mapped_column(JSONB, nullable=True)

    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class UserPreferences(Base):
    __tablename__ = "user_preferences"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    enabled_domains: Mapped[list[str]] = mapped_column(
        ARRAY(Text), nullable=False, default=lambda: ["Cycling", "Strength"]
    )
    domain_frequencies: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    muscle_group_split: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    # Structured-workout target for cycling: "hr" (default) or "power".
    cycling_target: Mapped[str] = mapped_column(String, nullable=False, default="hr")
    updated_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Activity(Base):
    __tablename__ = "activities"
    __table_args__ = (
        # Partial unique index — matches sql/schema.sql exactly so create_all and
        # schema.sql agree, and ON CONFLICT (with index_where) can infer it.
        Index(
            "activities_external_uq", "user_id", "source", "external_id",
            unique=True, postgresql_where=text("external_id IS NOT NULL"),
        ),
    )

    id: Mapped[uuid.UUID] = _uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    external_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    source: Mapped[str] = mapped_column(ACTIVITY_SOURCE, nullable=False, default="manual")

    name: Mapped[str] = mapped_column(Text, nullable=False)
    domain: Mapped[str] = mapped_column(Text, nullable=False)
    start_time: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    duration_seconds: Mapped[int] = mapped_column(Integer, nullable=False)
    distance_meters: Mapped[float | None] = mapped_column(Numeric(10, 2), nullable=True)
    elevation_gain: Mapped[float | None] = mapped_column(Numeric(8, 2), nullable=True)
    avg_heart_rate: Mapped[int | None] = mapped_column(Integer, nullable=True)
    max_heart_rate: Mapped[int | None] = mapped_column(Integer, nullable=True)
    calories: Mapped[int | None] = mapped_column(Integer, nullable=True)
    training_load: Mapped[float | None] = mapped_column(Numeric(6, 2), nullable=True)

    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class WeeklyPlanRow(Base):
    __tablename__ = "weekly_plans"
    __table_args__ = (UniqueConstraint("user_id", "week_start", name="weekly_plans_user_week_uq"),)

    id: Mapped[uuid.UUID] = _uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    week_start: Mapped[dt.date] = mapped_column(Date, nullable=False)
    days: Mapped[list] = mapped_column(JSONB, nullable=False)
    generated_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class CoachMessage(Base):
    __tablename__ = "coach_messages"

    id: Mapped[uuid.UUID] = _uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    role: Mapped[str] = mapped_column(MESSAGE_ROLE, nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class IntervalsConnection(Base):
    """OAuth connection to intervals.icu (the man-in-the-middle data source)."""

    __tablename__ = "intervals_connections"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    athlete_id: Mapped[str] = mapped_column(Text, nullable=False)
    # "oauth" (access+refresh tokens) or "apikey" (personal key in access_token).
    auth_mode: Mapped[str] = mapped_column(String, nullable=False, default="oauth")
    access_token: Mapped[str] = mapped_column(Text, nullable=False)   # AES-256-GCM
    refresh_token: Mapped[str] = mapped_column(Text, nullable=False)  # AES-256-GCM
    token_expires_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    display_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_sync_at: Mapped[dt.datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
