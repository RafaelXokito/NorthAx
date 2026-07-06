"""Pydantic DTOs (§6). All wire JSON is camelCase; Python attributes are
snake_case via an alias generator so either form is accepted on input."""
from __future__ import annotations

import datetime as dt
import re
import uuid

from pydantic import BaseModel, ConfigDict, Field, field_validator
from pydantic.alias_generators import to_camel

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _normalize_email(value: str) -> str:
    value = value.strip().lower()
    if not _EMAIL_RE.match(value):
        raise ValueError("Enter a valid email address.")
    return value


class _Base(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel, populate_by_name=True, from_attributes=True
    )


# ── Auth (§6.1, §6.2) ────────────────────────────────────────────────────────
class EmailSignInRequest(_Base):
    email: str
    password: str

    @field_validator("email")
    @classmethod
    def _norm_email(cls, v: str) -> str:
        return _normalize_email(v)


class EmailSignUpRequest(_Base):
    name: str = Field(min_length=1, max_length=100)
    email: str
    password: str = Field(min_length=8, max_length=128)

    @field_validator("email")
    @classmethod
    def _norm_email(cls, v: str) -> str:
        return _normalize_email(v)


class UserSummary(_Base):
    id: uuid.UUID
    name: str
    email: str | None = None


class AuthResponse(_Base):
    access_token: str
    refresh_token: str
    user: UserSummary


class RefreshRequest(_Base):
    refresh_token: str


class RefreshResponse(_Base):
    access_token: str
    refresh_token: str


class UserProfile(_Base):
    id: uuid.UUID
    name: str
    email: str | None = None
    created_at: dt.datetime


class UpdateProfileRequest(_Base):
    name: str = Field(min_length=1, max_length=100)


# ── Metrics (§6.3) ───────────────────────────────────────────────────────────
class DailyMetricsInput(_Base):
    date: dt.date
    hrv: float = Field(gt=0)
    hrv_baseline: float = Field(gt=0)
    hrv_trend: list[float]
    resting_hr: int
    resting_hr_baseline: int
    sleep_duration: float = Field(ge=0)
    sleep_score: int = Field(ge=0, le=100)
    rem_sleep: float = Field(ge=0)
    deep_sleep: float = Field(ge=0)
    sleep_debt: float = Field(ge=0)
    acute_load: float = Field(ge=0)
    chronic_load: float = Field(ge=0)
    today_load: float = 0.0
    weekly_load_change: float = 0.0
    body_weight: float | None = None

    @field_validator("date")
    @classmethod
    def _not_future(cls, v: dt.date) -> dt.date:
        if v > dt.date.today():
            raise ValueError("date must not be in the future")
        return v

    @field_validator("hrv_trend")
    @classmethod
    def _trend_length(cls, v: list[float]) -> list[float]:
        if len(v) != 7:
            raise ValueError("hrvTrend must contain exactly 7 elements")
        return v


class ManualMetricsInput(_Base):
    """User-entered raw wellness values for a day (all optional). Stored as a
    `manual` source reading and resolved against other sources by priority."""
    date: dt.date
    hrv: float | None = Field(default=None, gt=0)
    resting_hr: int | None = Field(default=None, gt=0)
    sleep_duration: float | None = Field(default=None, ge=0)
    sleep_score: int | None = Field(default=None, ge=0, le=100)
    body_weight: float | None = Field(default=None, gt=0)

    @field_validator("date")
    @classmethod
    def _not_future(cls, v: dt.date) -> dt.date:
        if v > dt.date.today():
            raise ValueError("date must not be in the future")
        return v


class DailyMetricsResponse(_Base):
    date: dt.date
    hrv: float
    hrv_baseline: float
    hrv_trend: list[float]
    resting_hr: int
    resting_hr_baseline: int
    sleep_duration: float
    sleep_score: int
    rem_sleep: float
    deep_sleep: float
    sleep_debt: float
    acute_load: float
    chronic_load: float
    today_load: float
    weekly_load_change: float
    body_weight: float | None = None
    vo2max: float | None = None   # §12 — estimate, when present
    # Aligned daily series (oldest→newest, up to 90 days) for the metric detail
    # graphs. Computed on read for the by-date GET endpoints; empty elsewhere.
    trend_dates: list[dt.date] = []
    hrv_series: list[float] = []
    resting_hr_series: list[float] = []
    sleep_series: list[float] = []
    tsb_series: list[float] = []
    ctl_series: list[float] = []      # §12 — fitness (chronic load)
    atl_series: list[float] = []      # §12 — fatigue (acute load)
    vo2max_series: list[float] = []   # §12
    # Which source won each mergeable metric: { metric -> source } (provenance).
    metric_sources: dict[str, str] = {}


# ── Readiness (§6.4) ─────────────────────────────────────────────────────────
class ComponentScores(_Base):
    hrv: int
    sleep: int
    load: int
    recovery: int


class SuggestedSessionDTO(_Base):
    domain: str
    title: str
    duration: int
    intensity_label: str
    intensity_description: str
    ai_rationale: str | None = None


class KeyInsight(_Base):
    label: str
    value: str
    unit: str
    trend: str
    explanation: str
    context: str


class AiExplanation(_Base):
    narrative: str
    generated_at: dt.datetime
    model: str


class DailyReadinessResponse(_Base):
    date: dt.date
    score: int
    status: str
    verdict: str
    explanation: str
    coaching_note: str
    component_scores: ComponentScores
    suggested_session: SuggestedSessionDTO
    key_insights: list[KeyInsight]
    ai_explanation: AiExplanation | None = None


# ── Preferences (§6.5) ───────────────────────────────────────────────────────
class DomainScheduleDTO(_Base):
    domain: str
    weekdays: list[int] = Field(default_factory=list)  # 0=Mon … 6=Sun, sorted asc


class AthleteThresholdsDTO(_Base):
    ftp_watts: int | None = None
    threshold_hr: int | None = None
    max_hr: int | None = None
    run_threshold_pace_sec_per_km: int | None = None
    pace_unit: str = "km"  # "km" | "mile"
    # to_camel would yield ...Per100M; the contract wants a lowercase trailing m.
    swim_threshold_pace_sec_per100m: int | None = Field(
        default=None, alias="swimThresholdPaceSecPer100m"
    )
    pool_unit: str = "pool25m"  # "pool25m" | "pool50m" | "openWater"


class DaySplitDTO(_Base):
    muscle_groups: list[str] = Field(default_factory=list)
    is_rest_day: bool = False


class SportTargetDTO(_Base):
    """One structured goal for a sport (flat + goalType discriminator)."""

    goal_type: str  # "raceTime" | "powerHold" | "distanceAvgSpeed"
    target_date: dt.date
    distance_km: float | None = None    # raceTime, distanceAvgSpeed
    finish_time_sec: int | None = None  # raceTime
    zone: int | None = None             # powerHold (1-5)
    hold_minutes: int | None = None     # powerHold
    avg_speed_kmh: float | None = None  # distanceAvgSpeed


class UserPreferencesDTO(_Base):
    enabled_domains: list[str] = Field(default_factory=lambda: ["Cycling", "Strength"])
    domain_schedules: list[DomainScheduleDTO] = Field(default_factory=list)
    thresholds: AthleteThresholdsDTO = Field(default_factory=AthleteThresholdsDTO)
    muscle_group_split: list[DaySplitDTO] = Field(default_factory=list)
    cycling_target: str = "hr"  # "hr" | "power"
    # Per-metric source ranking: { metric -> [source, ...] } (highest first).
    metric_priority: dict[str, list[str]] = Field(default_factory=dict)
    # Ordered activity-data source preference (§13): [source, ...] (highest first).
    activity_priority: list[str] = Field(default_factory=list)
    # Per-sport goal target: { domain -> target } (one per sport).
    sport_targets: dict[str, SportTargetDTO] = Field(default_factory=dict)


class CyclingTargetPatch(_Base):
    cycling_target: str  # "hr" | "power"


class MetricPriorityPatch(_Base):
    metric_priority: dict[str, list[str]]


class ActivityPriorityPatch(_Base):
    activity_priority: list[str]


class DomainsPatch(_Base):
    enabled_domains: list[str]


class SchedulePatch(_Base):
    domain_schedules: list[DomainScheduleDTO]


class ThresholdsPatch(_Base):
    """Partial thresholds — only non-null fields are merged in."""

    ftp_watts: int | None = None
    threshold_hr: int | None = None
    max_hr: int | None = None
    run_threshold_pace_sec_per_km: int | None = None
    pace_unit: str | None = None
    swim_threshold_pace_sec_per100m: int | None = Field(
        default=None, alias="swimThresholdPaceSecPer100m"
    )
    pool_unit: str | None = None


class MuscleSplitPatch(_Base):
    muscle_group_split: list[DaySplitDTO]


class SportTargetsPatch(_Base):
    """Full replacement of the per-sport targets map (omit a domain to clear it)."""

    sport_targets: dict[str, SportTargetDTO]


# ── Goal progress (post-sync AI analysis) ────────────────────────────────────
class GoalProgressDTO(_Base):
    domain: str
    verdict: str  # "on_track" | "behind" | "ahead"
    summary: str
    recommend_replan: bool = False
    analyzed_at: dt.datetime


# ── Activities (§6.6, §6.12) ─────────────────────────────────────────────────
class LoggedSetDTO(_Base):
    weight_kg: float | None = None  # None = bodyweight
    reps: int = Field(gt=0)


class LoggedExerciseDTO(_Base):
    name: str = Field(min_length=1)
    muscle_group: str
    sets: list[LoggedSetDTO] = Field(min_length=1)


class ActivityDTO(_Base):
    id: uuid.UUID
    external_id: str | None = None
    source: str
    name: str
    domain: str
    start_time: dt.datetime
    duration_seconds: int
    distance_meters: float | None = None
    elevation_gain: float | None = None
    avg_heart_rate: int | None = None
    max_heart_rate: int | None = None
    calories: int | None = None
    training_load: float | None = None
    notes: str | None = None
    strength_exercises: list[LoggedExerciseDTO] | None = None
    # Coarse GPS trace [[lat, lng], ...] for list thumbnails; None when indoor.
    route_points: list[list[float]] | None = None
    created_at: dt.datetime


class ActivityInput(_Base):
    name: str = Field(min_length=1)
    domain: str
    start_time: dt.datetime
    duration_seconds: int = Field(gt=0)
    distance_meters: float | None = None
    elevation_gain: float | None = None
    avg_heart_rate: int | None = None
    max_heart_rate: int | None = None
    calories: int | None = None
    training_load: float | None = None
    notes: str | None = None
    strength_exercises: list[LoggedExerciseDTO] | None = None


class ActivityPatch(_Base):
    name: str | None = None
    domain: str | None = None
    start_time: dt.datetime | None = None
    duration_seconds: int | None = Field(default=None, gt=0)
    distance_meters: float | None = None
    elevation_gain: float | None = None
    avg_heart_rate: int | None = None
    max_heart_rate: int | None = None
    calories: int | None = None
    training_load: float | None = None
    notes: str | None = None
    strength_exercises: list[LoggedExerciseDTO] | None = None


class PaginatedActivities(_Base):
    items: list[ActivityDTO]
    total: int
    limit: int
    offset: int
    has_more: bool


# ── Plan (§6.7) ──────────────────────────────────────────────────────────────
class ExerciseDTO(_Base):
    name: str
    muscle_group: str
    sets: int
    reps_range: str
    rest: str
    notes: str | None = None


class WorkoutStepDTO(_Base):
    cue: str
    minutes: int
    target: str          # human label, e.g. "Z2 endurance (HR)"
    icu: str             # intervals.icu token, e.g. "Z2 HR"


class WorkoutBlockDTO(_Base):
    repeat: int
    steps: list[WorkoutStepDTO]


class StructuredWorkoutDTO(_Base):
    target_mode: str     # "hr" | "power" | "pace" | "none"
    blocks: list[WorkoutBlockDTO]


class PlannedSessionDTO(_Base):
    domain: str
    title: str
    subtitle: str | None = None
    duration: int
    intensity_label: str
    workout: StructuredWorkoutDTO | None = None
    exercises: list[ExerciseDTO] | None = None  # strength: movement breakdown


class PlannedDayDTO(_Base):
    date: dt.date
    weekday_short: str
    day_number: str
    is_rest: bool
    is_today: bool
    is_past: bool
    sessions: list[PlannedSessionDTO] = Field(default_factory=list)


class WeeklyPlanDTO(_Base):
    id: uuid.UUID | None = None
    week_start: dt.date
    week_label: str
    is_current_week: bool
    days: list[PlannedDayDTO]
    generated_at: dt.datetime


class DayOverrideRequest(_Base):
    session: PlannedSessionDTO | None = None  # null → mark as rest day


# ── Switch suggestions (§9) ──────────────────────────────────────────────────
class SwitchSuggestionRequest(_Base):
    """The planned session the athlete may want to swap. The backend assembles
    the surrounding context (metrics, recent load, rest of week, thresholds)."""
    domain: str
    title: str
    duration: int
    intensity_label: str
    date: dt.date


class SwitchSuggestionDTO(_Base):
    domain: str
    title: str
    duration: int
    intensity_label: str
    description: str
    rationale: str
    estimated_load: float | None = None
    workout: StructuredWorkoutDTO | None = None   # endurance block structure
    exercises: list[ExerciseDTO] | None = None    # strength movement list


class SwitchSuggestionsResponse(_Base):
    suggestions: list[SwitchSuggestionDTO]


# ── Coach (§6.8, §6.9) ───────────────────────────────────────────────────────
class CoachMessageDTO(_Base):
    id: uuid.UUID
    role: str
    content: str
    created_at: dt.datetime


class CoachMessageRequest(_Base):
    content: str = Field(min_length=1, max_length=4000)


# ── Strength (§6.10) ─────────────────────────────────────────────────────────
class StrengthSessionResponse(_Base):
    muscle_groups: list[str]
    title: str
    intensity_label: str
    duration: int
    rationale: str
    recovery_warnings: list[str]
    exercises: list[ExerciseDTO]


class StrengthGenerateRequest(_Base):
    muscle_groups: list[str]
    readiness_score: int | None = None
    recent_activity_ids: list[uuid.UUID] = Field(default_factory=list)


# ── intervals.icu (§6.11) ────────────────────────────────────────────────────
class IntervalsStatus(_Base):
    connected: bool
    display_name: str | None = None
    last_sync_at: dt.datetime | None = None


class IntervalsConnectResponse(_Base):
    authorization_url: str


# ── Strava (§13) ─────────────────────────────────────────────────────────────
class StravaStatus(_Base):
    connected: bool
    display_name: str | None = None
    last_sync_at: dt.datetime | None = None


class StravaConnectResponse(_Base):
    authorization_url: str


class IntervalsApiKeyConnect(_Base):
    athlete_id: str
    api_key: str


class IntervalsWorkoutPushRequest(_Base):
    date: dt.date
    session: PlannedSessionDTO


class IntervalsWorkoutPushResponse(_Base):
    workout_id: str
    scheduled_date: dt.date


# ── Activity streams (§10) ───────────────────────────────────────────────────
class ActivityStreamsDTO(_Base):
    """Downsampled time-series for a completed activity. Arrays are index-aligned
    with `time` (seconds from start); any metric absent in the source is empty."""
    activity_id: str
    time: list[float] = Field(default_factory=list)
    heart_rate: list[float] = Field(default_factory=list)
    power: list[float] = Field(default_factory=list)
    velocity: list[float] = Field(default_factory=list)   # m/s (client → pace)
    altitude: list[float] = Field(default_factory=list)
    cadence: list[float] = Field(default_factory=list)
    # GPS route as [[lat, lng], ...]; denser than the scalar arrays and NOT
    # index-aligned with `time`. Empty for indoor/virtual activities.
    lat_lng: list[list[float]] = Field(default_factory=list)
    source: str = "intervals.icu"
