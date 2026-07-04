-- 0008 — per-exercise strength log (weight × reps per set) on activities.
-- Idempotent.

ALTER TABLE activities ADD COLUMN IF NOT EXISTS strength_exercises JSONB;
