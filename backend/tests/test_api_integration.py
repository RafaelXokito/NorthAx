"""End-to-end API tests through the real FastAPI app (skipped without a DB)."""
from __future__ import annotations

import datetime as dt

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
        "domainFrequencies": [
            {"domain": "Cycling", "daysPerWeek": 3},
            {"domain": "Strength", "daysPerWeek": 2},
        ],
        "muscleGroupSplit": [],
    }
    r = await client.put("/v1/preferences", headers=headers, json=prefs)
    assert r.status_code == 200

    r = await client.get("/v1/plan/weeks?weeks=1", headers=headers)
    assert r.status_code == 200
    weeks = r.json()
    assert weeks, "expected a generated week"
    assert any(day.get("session") for day in weeks[0]["days"]), "expected training sessions"


async def test_frequency_overload_is_422(api):
    client, headers, _ = api
    bad = {"domainFrequencies": [
        {"domain": "Cycling", "daysPerWeek": 5},
        {"domain": "Strength", "daysPerWeek": 5},
    ]}
    r = await client.patch("/v1/preferences/frequency", headers=headers, json=bad)
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "PREFERENCES_INVALID_FREQUENCY"


async def test_intervals_status_and_activities_empty(api):
    client, headers, _ = api
    r = await client.get("/v1/intervals/status", headers=headers)
    assert r.status_code == 200 and r.json()["connected"] is False

    r = await client.get("/v1/activities", headers=headers)
    assert r.status_code == 200
    assert r.json()["total"] == 0
