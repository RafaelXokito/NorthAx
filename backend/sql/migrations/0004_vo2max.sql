-- 0004 — VO2Max estimate on daily_metrics (§12).
--
-- intervals.icu wellness records carry a vo2max estimate; capture it so the app
-- can chart a VO2Max trend. Idempotent; no-op on a fresh DB that schema.sql
-- already built with the column.

ALTER TABLE daily_metrics ADD COLUMN IF NOT EXISTS vo2max NUMERIC(5, 2);
