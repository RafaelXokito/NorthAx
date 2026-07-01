-- 0006 — activity-data source preference (§13).
--
-- Ordered list of activity sources (highest priority first) used to de-duplicate
-- the same workout reported by more than one integration. Idempotent.

ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS activity_priority JSONB NOT NULL DEFAULT '[]';
