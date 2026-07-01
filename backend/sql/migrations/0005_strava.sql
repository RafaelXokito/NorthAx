-- 0005 — Strava integration (§13): a second activity source.
--
-- Adds 'strava' to the activity_source enum and a strava_connections table
-- (OAuth tokens, encrypted at rest) with RLS. Idempotent.

ALTER TYPE activity_source ADD VALUE IF NOT EXISTS 'strava';

CREATE TABLE IF NOT EXISTS strava_connections (
  user_id          UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  athlete_id       TEXT NOT NULL,
  access_token     TEXT NOT NULL,   -- AES-256-GCM
  refresh_token    TEXT NOT NULL,   -- AES-256-GCM
  token_expires_at TIMESTAMPTZ NOT NULL,
  display_name     TEXT,
  last_sync_at     TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE strava_connections ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_isolation ON strava_connections;
CREATE POLICY user_isolation ON strava_connections
  USING (user_id = current_setting('app.current_user_id', true)::uuid);
