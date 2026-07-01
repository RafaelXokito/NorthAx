-- NorthAx database schema (PostgreSQL 16)
-- Mirrors §5 of BACKEND_SPEC.md. Row-Level Security (§4) is enabled on every
-- table carrying a user_id as a defence-in-depth backstop on top of the
-- application-layer WHERE user_id = $userId filter.

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid()

-- ─────────────────────────────────────────────────────────────────────────────
-- users
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email         TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  name          TEXT NOT NULL DEFAULT 'Athlete',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- refresh_tokens
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS refresh_tokens (
  jti        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  issued_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked    BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS refresh_tokens_user_idx ON refresh_tokens(user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- daily_metrics  (one row per user per calendar day)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS daily_metrics (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date                 DATE NOT NULL,

  hrv                  NUMERIC(6,2) NOT NULL,
  hrv_baseline         NUMERIC(6,2) NOT NULL,
  hrv_trend            NUMERIC(6,2)[] NOT NULL,

  resting_hr           INTEGER NOT NULL,
  resting_hr_baseline  INTEGER NOT NULL,

  sleep_duration       NUMERIC(4,2) NOT NULL,
  sleep_score          INTEGER NOT NULL CHECK (sleep_score BETWEEN 0 AND 100),
  rem_sleep            NUMERIC(4,2) NOT NULL,
  deep_sleep           NUMERIC(4,2) NOT NULL,
  sleep_debt           NUMERIC(4,2) NOT NULL,

  acute_load           NUMERIC(6,2) NOT NULL,
  chronic_load         NUMERIC(6,2) NOT NULL,
  today_load           NUMERIC(6,2) NOT NULL DEFAULT 0,
  weekly_load_change   NUMERIC(5,4) NOT NULL,

  body_weight          NUMERIC(5,2),
  vo2max               NUMERIC(5,2),   -- §12 — intervals.icu VO2Max estimate

  -- Cached AI readiness explanation (§8.1). NULL until first computed.
  ai_explanation       JSONB,

  -- Which source won each mergeable metric: { metric -> source } (provenance).
  metric_sources       JSONB NOT NULL DEFAULT '{}',

  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (user_id, date)
);
CREATE INDEX IF NOT EXISTS daily_metrics_user_date_idx ON daily_metrics(user_id, date DESC);
ALTER TABLE daily_metrics ADD COLUMN IF NOT EXISTS metric_sources JSONB NOT NULL DEFAULT '{}';
ALTER TABLE daily_metrics ADD COLUMN IF NOT EXISTS vo2max NUMERIC(5,2);

-- ─────────────────────────────────────────────────────────────────────────────
-- metric_readings — one source's raw wellness contribution per day; daily_metrics
-- is derived from these by resolving conflicts against the user's priority.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS metric_readings (
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date         DATE NOT NULL,
  source       TEXT NOT NULL,               -- 'intervals' | 'manual'
  values       JSONB NOT NULL DEFAULT '{}',
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, date, source)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- user_preferences
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_preferences (
  user_id              UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  enabled_domains      TEXT[] NOT NULL DEFAULT ARRAY['Cycling','Strength'],
  domain_frequencies   JSONB NOT NULL DEFAULT '[]',   -- legacy, retained but unused
  domain_schedules     JSONB NOT NULL DEFAULT '[]',
  thresholds           JSONB NOT NULL DEFAULT '{}',
  muscle_group_split   JSONB NOT NULL DEFAULT '[]',
  cycling_target       TEXT NOT NULL DEFAULT 'hr',   -- 'hr' (default) | 'power'
  metric_priority      JSONB NOT NULL DEFAULT '{}',  -- { metric -> [source,...] } conflict resolution
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Migration for existing DBs (idempotent):
ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS cycling_target TEXT NOT NULL DEFAULT 'hr';
ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS domain_schedules JSONB NOT NULL DEFAULT '[]';
ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS thresholds JSONB NOT NULL DEFAULT '{}';
ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS metric_priority JSONB NOT NULL DEFAULT '{}';

-- ─────────────────────────────────────────────────────────────────────────────
-- activities
-- ─────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE activity_source AS ENUM ('manual', 'garmin', 'strava');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
ALTER TYPE activity_source ADD VALUE IF NOT EXISTS 'strava';

CREATE TABLE IF NOT EXISTS activities (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  external_id       TEXT,
  source            activity_source NOT NULL DEFAULT 'manual',

  name              TEXT NOT NULL,
  domain            TEXT NOT NULL,
  start_time        TIMESTAMPTZ NOT NULL,
  duration_seconds  INTEGER NOT NULL,
  distance_meters   NUMERIC(10,2),
  elevation_gain    NUMERIC(8,2),
  avg_heart_rate    INTEGER,
  max_heart_rate    INTEGER,
  calories          INTEGER,
  training_load     NUMERIC(6,2),

  notes             TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS activities_external_uq
  ON activities(user_id, source, external_id) WHERE external_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS activities_user_start_idx ON activities(user_id, start_time DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- weekly_plans
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS weekly_plans (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  week_start   DATE NOT NULL,
  days         JSONB NOT NULL,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, week_start)
);
CREATE INDEX IF NOT EXISTS weekly_plans_user_week_idx ON weekly_plans(user_id, week_start);

-- ─────────────────────────────────────────────────────────────────────────────
-- coach_messages
-- ─────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE message_role AS ENUM ('user', 'coach');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS coach_messages (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role        message_role NOT NULL,
  content     TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS coach_messages_user_created_idx ON coach_messages(user_id, created_at DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- intervals_connections  (OAuth to intervals.icu — the MITM data source)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS intervals_connections (
  user_id          UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  athlete_id       TEXT NOT NULL,
  auth_mode        TEXT NOT NULL DEFAULT 'oauth',   -- 'oauth' | 'apikey'
  access_token     TEXT NOT NULL,   -- AES-256-GCM ciphertext
  refresh_token    TEXT NOT NULL,   -- AES-256-GCM ciphertext
  token_expires_at TIMESTAMPTZ NOT NULL,
  display_name     TEXT,
  last_sync_at     TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- strava_connections  (OAuth to Strava — a second activity source, §13)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS strava_connections (
  user_id          UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  athlete_id       TEXT NOT NULL,
  access_token     TEXT NOT NULL,   -- AES-256-GCM ciphertext
  refresh_token    TEXT NOT NULL,   -- AES-256-GCM ciphertext
  token_expires_at TIMESTAMPTZ NOT NULL,
  display_name     TEXT,
  last_sync_at     TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Row-Level Security (§4) — defence in depth.
-- The application sets `app.current_user_id` at the start of each transaction.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'refresh_tokens', 'daily_metrics', 'user_preferences',
    'activities', 'weekly_plans', 'coach_messages', 'intervals_connections',
    'metric_readings', 'strava_connections'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS user_isolation ON %I', t);
    EXECUTE format(
      'CREATE POLICY user_isolation ON %I USING (user_id = current_setting(''app.current_user_id'', true)::uuid)',
      t
    );
  END LOOP;
END $$;
