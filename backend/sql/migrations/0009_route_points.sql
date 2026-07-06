-- 0009 — coarse GPS trace [[lat, lng], ...] on activities for route thumbnails.
-- Idempotent.

ALTER TABLE activities ADD COLUMN IF NOT EXISTS route_points JSONB;
