-- 0010 — Strava segment efforts (per-activity fetch during sync + backfill).
-- Idempotent.

ALTER TABLE activities ADD COLUMN IF NOT EXISTS efforts_synced_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS segment_efforts (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_external_id TEXT NOT NULL,   -- Strava activity id (provenance)
  effort_id            TEXT NOT NULL,   -- Strava effort id
  segment_id           TEXT NOT NULL,
  name                 TEXT NOT NULL,
  distance_meters      NUMERIC(10,2),
  avg_grade            NUMERIC(5,2),
  climb_category       INTEGER,
  elapsed_seconds      INTEGER NOT NULL,
  moving_seconds       INTEGER,
  start_date           TIMESTAMPTZ NOT NULL,
  pr_rank              INTEGER,         -- 1–3 or NULL
  kom_rank             INTEGER,         -- 1–10 or NULL
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS segment_efforts_user_effort_uq ON segment_efforts(user_id, effort_id);
CREATE INDEX IF NOT EXISTS segment_efforts_user_segment_idx ON segment_efforts(user_id, segment_id, start_date DESC);
CREATE INDEX IF NOT EXISTS segment_efforts_user_start_idx ON segment_efforts(user_id, start_date);

ALTER TABLE segment_efforts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_isolation ON segment_efforts;
CREATE POLICY user_isolation ON segment_efforts
  USING (user_id = current_setting('app.current_user_id', true)::uuid);
