-- 0011 — Strava segment geometry (global reference data, no RLS: rows carry
-- no user_id — a segment's public shape is identical for every athlete).
-- Idempotent.

CREATE TABLE IF NOT EXISTS segments (
  segment_id      TEXT PRIMARY KEY,          -- Strava segment id
  name            TEXT NOT NULL,
  distance_meters NUMERIC(10,2),
  avg_grade       NUMERIC(5,2),
  climb_category  INTEGER,
  points          JSONB NOT NULL DEFAULT '[]'::jsonb,  -- [[lat,lng],...] <=200; [] = fetched, no polyline
  fetched_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
