-- 0003 — multi-source metrics: per-source raw readings + provenance + priority.
--
-- Brings an EXISTING database forward for the multi-source wellness feature
-- (see docs/multi-source-metrics.md). Fully idempotent: safe to re-run, and a
-- no-op on a fresh DB that schema.sql already built with these objects.

ALTER TABLE daily_metrics    ADD COLUMN IF NOT EXISTS metric_sources  JSONB NOT NULL DEFAULT '{}';
ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS metric_priority JSONB NOT NULL DEFAULT '{}';

CREATE TABLE IF NOT EXISTS metric_readings (
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date         DATE NOT NULL,
  source       TEXT NOT NULL,               -- 'intervals' | 'manual'
  values       JSONB NOT NULL DEFAULT '{}',
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, date, source)
);

-- Row-Level Security to match the other user-scoped tables (§4, defence in depth).
ALTER TABLE metric_readings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_isolation ON metric_readings;
CREATE POLICY user_isolation ON metric_readings
  USING (user_id = current_setting('app.current_user_id', true)::uuid);
