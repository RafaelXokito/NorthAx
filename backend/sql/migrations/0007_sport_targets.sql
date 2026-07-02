-- 0007 — per-sport goal targets + latest AI goal-progress analysis.
-- Idempotent.

ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS sport_targets JSONB NOT NULL DEFAULT '{}';

CREATE TABLE IF NOT EXISTS goal_progress (
  user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  domain             TEXT NOT NULL,
  verdict            TEXT NOT NULL,              -- 'on_track' | 'behind' | 'ahead'
  summary            TEXT NOT NULL,
  recommend_replan   BOOLEAN NOT NULL DEFAULT false,
  latest_activity_at TIMESTAMPTZ,                -- newest activity considered (dedupe)
  analyzed_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, domain)
);

ALTER TABLE goal_progress ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_isolation ON goal_progress;
CREATE POLICY user_isolation ON goal_progress
  USING (user_id = current_setting('app.current_user_id', true)::uuid);
