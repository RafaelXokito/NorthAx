-- 0002 — per-sport weekly schedules + athlete thresholds.
--
-- Brings an EXISTING database forward to the Phase 2 user_preferences shape.
-- Fully idempotent: safe to re-run, and a no-op on a fresh DB that schema.sql
-- already built with the new columns.
--
-- The legacy domain_frequencies column is retained (physically present) but is
-- no longer read. No spread backfill is attempted — domain_schedules resets to
-- empty; athletes re-pick their per-sport days via the app.

ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS domain_schedules JSONB NOT NULL DEFAULT '[]';
ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS thresholds JSONB NOT NULL DEFAULT '{}';
