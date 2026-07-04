"""End-to-end API tests through the real FastAPI app (skipped without a DB)."""
from __future__ import annotations

import datetime as dt
import uuid

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db import session_scope
from app.models import Activity

VALID_METRICS = {
    "hrv": 58.0,
    "hrvBaseline": 54.0,
    "hrvTrend": [51, 49, 52, 54, 53, 56, 58],
    "restingHr": 46,
    "restingHrBaseline": 47,
    "sleepDuration": 7.5,
    "sleepScore": 84,
    "remSleep": 1.8,
    "deepSleep": 1.4,
    "sleepDebt": 0.3,
    "acuteLoad": 68.0,
    "chronicLoad": 72.0,
    "todayLoad": 0.0,
    "weeklyLoadChange": 0.08,
    "bodyWeight": 78.2,
}


async def test_health_is_public(api):
    client, _, _ = api
    r = await client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


async def test_protected_route_requires_auth(api):
    client, _, _ = api
    r = await client.get("/v1/user/profile")  # no headers
    assert r.status_code == 401
    assert r.json()["error"]["status"] == 401


async def test_profile(api):
    client, headers, _ = api
    r = await client.get("/v1/user/profile", headers=headers)
    assert r.status_code == 200
    assert r.json()["name"] == "ITest"


async def test_metrics_then_readiness(api):
    client, headers, _ = api
    today = dt.date.today().isoformat()

    # No metrics yet → 404 envelope.
    r = await client.get("/v1/metrics/daily", headers=headers)
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "METRICS_NOT_FOUND"

    # Submit → 201, then readable.
    r = await client.post("/v1/metrics/daily", headers=headers, json={**VALID_METRICS, "date": today})
    assert r.status_code == 201, r.text
    assert (await client.get("/v1/metrics/daily", headers=headers)).status_code == 200

    # Readiness computed deterministically (mock-fresh ≈ 88/Peak).
    r = await client.get("/v1/readiness/today", headers=headers)
    assert r.status_code == 200
    body = r.json()
    assert 0 <= body["score"] <= 100
    assert set(body["componentScores"]) == {"hrv", "sleep", "load", "recovery"}
    assert body["suggestedSession"]["domain"]


async def test_duplicate_metrics_conflict(api):
    client, headers, _ = api
    today = dt.date.today().isoformat()
    await client.post("/v1/metrics/daily", headers=headers, json={**VALID_METRICS, "date": today})
    r = await client.post("/v1/metrics/daily", headers=headers, json={**VALID_METRICS, "date": today})
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "METRICS_ALREADY_EXISTS"


async def test_preferences_drive_plan(api):
    client, headers, _ = api
    prefs = {
        "enabledDomains": ["Cycling", "Strength"],
        "domainSchedules": [
            {"domain": "Cycling", "weekdays": [0, 2, 4]},
            {"domain": "Strength", "weekdays": [1, 5]},
        ],
        "muscleGroupSplit": [],
    }
    r = await client.put("/v1/preferences", headers=headers, json=prefs)
    assert r.status_code == 200
    assert r.json()["domainSchedules"] == prefs["domainSchedules"]

    r = await client.get("/v1/plan/weeks?weeks=1", headers=headers)
    assert r.status_code == 200
    weeks = r.json()
    assert weeks, "expected a generated week"
    assert any(day.get("sessions") for day in weeks[0]["days"]), "expected training sessions"


async def test_schedule_no_rest_day_is_400(api):
    client, headers, _ = api
    bad = {"domainSchedules": [
        {"domain": "Cycling", "weekdays": [0, 1, 2, 3]},
        {"domain": "Strength", "weekdays": [4, 5, 6]},
    ]}
    r = await client.patch("/v1/preferences/schedule", headers=headers, json=bad)
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "SCHEDULE_NO_REST_DAY"


async def test_thresholds_merge_no_regen(api):
    client, headers, _ = api
    r = await client.patch(
        "/v1/preferences/thresholds", headers=headers, json={"ftpWatts": 250}
    )
    assert r.status_code == 200
    assert r.json()["thresholds"]["ftpWatts"] == 250

    # Partial merge keeps the prior field and adds the new one.
    r = await client.patch(
        "/v1/preferences/thresholds", headers=headers, json={"thresholdHr": 165}
    )
    assert r.status_code == 200
    t = r.json()["thresholds"]
    assert t["ftpWatts"] == 250 and t["thresholdHr"] == 165


async def test_sport_targets_roundtrip(api):
    client, headers, _ = api
    targets = {
        "sportTargets": {
            "Running": {"goalType": "raceTime", "targetDate": "2027-10-04", "distanceKm": 10, "finishTimeSec": 2400},
            "Cycling": {"goalType": "powerHold", "targetDate": "2027-09-01", "zone": 4, "holdMinutes": 20},
        }
    }
    r = await client.patch("/v1/preferences/sport-targets", headers=headers, json=targets)
    assert r.status_code == 200, r.text
    assert r.json()["sportTargets"]["Running"]["finishTimeSec"] == 2400

    # Echoed back on GET.
    r = await client.get("/v1/preferences", headers=headers)
    assert r.status_code == 200
    assert r.json()["sportTargets"]["Cycling"]["zone"] == 4

    # Full-replace semantics: an empty map clears all targets.
    r = await client.patch("/v1/preferences/sport-targets", headers=headers, json={"sportTargets": {}})
    assert r.status_code == 200
    assert r.json()["sportTargets"] == {}


async def test_sport_targets_invalid_is_422(api):
    client, headers, _ = api
    # Unsupported domain.
    bad = {"sportTargets": {"Strength": {"goalType": "raceTime", "targetDate": "2027-10-04", "distanceKm": 10, "finishTimeSec": 2400}}}
    r = await client.patch("/v1/preferences/sport-targets", headers=headers, json=bad)
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "PREFERENCES_INVALID_TARGET"

    # Missing required field for the goal type.
    bad = {"sportTargets": {"Running": {"goalType": "raceTime", "targetDate": "2027-10-04", "distanceKm": 10}}}
    r = await client.patch("/v1/preferences/sport-targets", headers=headers, json=bad)
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "PREFERENCES_INVALID_TARGET"


async def test_goal_progress_empty(api):
    client, headers, _ = api
    r = await client.get("/v1/goals/progress", headers=headers)
    assert r.status_code == 200
    assert r.json() == []


async def test_intervals_status_and_activities_empty(api):
    client, headers, _ = api
    r = await client.get("/v1/intervals/status", headers=headers)
    assert r.status_code == 200 and r.json()["connected"] is False

    r = await client.get("/v1/activities", headers=headers)
    assert r.status_code == 200
    assert r.json()["total"] == 0


async def test_create_manual_activity(api):
    # Exercises the activity_source ENUM insert — regression for the
    # String-vs-ENUM mismatch found on the first Pi deploy (schema.sql uses a
    # native enum; create_all-based tests had missed it).
    client, headers, _ = api
    body = {
        "name": "Test Ride",
        "domain": "Cycling",
        "startTime": "2026-06-30T07:00:00Z",
        "durationSeconds": 3600,
        "trainingLoad": 42.0,
    }
    r = await client.post("/v1/activities", headers=headers, json=body)
    assert r.status_code == 201, r.text
    assert r.json()["source"] == "manual"
    assert (await client.get("/v1/activities", headers=headers)).json()["total"] == 1


async def test_create_strength_activity_with_exercise_log(api):
    # The per-set strength log must round-trip through the JSONB column in
    # camelCase on both create and list.
    client, headers, _ = api
    exercises = [
        {
            "name": "Barbell Bench Press",
            "muscleGroup": "Chest",
            "sets": [{"weightKg": 60.0, "reps": 8}, {"weightKg": 62.5, "reps": 6}],
        },
        {
            "name": "Pull-Ups",
            "muscleGroup": "Back",
            "sets": [{"weightKg": None, "reps": 10}],  # bodyweight
        },
    ]
    body = {
        "name": "Push Day",
        "domain": "Strength",
        "startTime": "2026-07-01T18:00:00Z",
        "durationSeconds": 2700,
        "strengthExercises": exercises,
    }
    r = await client.post("/v1/activities", headers=headers, json=body)
    assert r.status_code == 201, r.text
    assert r.json()["strengthExercises"] == exercises

    items = (await client.get("/v1/activities", headers=headers)).json()["items"]
    logged = next(a for a in items if a["domain"] == "Strength")
    assert logged["strengthExercises"] == exercises


async def test_patch_strength_exercise_log(api):
    # Editing a done workout's exercises/weights rewrites the JSONB log while
    # leaving the rest of the activity untouched.
    client, headers, _ = api
    body = {
        "name": "Leg Day",
        "domain": "Strength",
        "startTime": "2026-07-02T18:00:00Z",
        "durationSeconds": 3000,
        "strengthExercises": [
            {"name": "Back Squat", "muscleGroup": "Legs", "sets": [{"weightKg": 80.0, "reps": 5}]},
        ],
    }
    created = (await client.post("/v1/activities", headers=headers, json=body)).json()

    edited = [
        {"name": "Front Squat", "muscleGroup": "Legs",
         "sets": [{"weightKg": 60.0, "reps": 8}, {"weightKg": 65.0, "reps": 6}]},
        {"name": "Leg Press", "muscleGroup": "Legs", "sets": [{"weightKg": 120.0, "reps": 10}]},
    ]
    r = await client.patch(
        f"/v1/activities/{created['id']}", headers=headers,
        json={"strengthExercises": edited},
    )
    assert r.status_code == 200, r.text
    assert r.json()["strengthExercises"] == edited
    assert r.json()["durationSeconds"] == 3000

    fetched = (await client.get(f"/v1/activities/{created['id']}", headers=headers)).json()
    assert fetched["strengthExercises"] == edited


async def test_garmin_activity_upsert(api):
    # Exercises the Garmin upsert ON CONFLICT against the *partial* unique index
    # (regression for the full-constraint vs partial-index mismatch found on the
    # Pi). Two upserts of the same external_id must collapse to one row.
    _, _, uid = api

    def stmt(load: float):
        values = {
            "user_id": uuid.UUID(uid), "external_id": "g-1", "source": "garmin",
            "name": "Ride", "domain": "Cycling",
            "start_time": dt.datetime(2026, 6, 30, 7, 0), "duration_seconds": 3600,
            "training_load": load,
        }
        return (
            pg_insert(Activity).values(**values).on_conflict_do_update(
                index_elements=[Activity.user_id, Activity.source, Activity.external_id],
                index_where=Activity.external_id.isnot(None),
                set_={"training_load": load},
            )
        )

    async with session_scope(uid) as s:
        await s.execute(stmt(10))
        await s.execute(stmt(20))
    async with session_scope(uid) as s:
        n = await s.scalar(select(func.count()).select_from(Activity).where(Activity.user_id == uuid.UUID(uid)))
        load = await s.scalar(select(Activity.training_load).where(Activity.user_id == uuid.UUID(uid)))
    assert n == 1
    assert float(load) == 20.0
