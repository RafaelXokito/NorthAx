"""Strava segment efforts (§13): mapper unit tests + endpoint integration tests."""
import datetime as dt
import uuid

from app.db import session_scope
from app.models import Activity, SegmentEffort
from app.services.strava import normalize_segment_efforts

UTC = dt.timezone.utc


# ── normalize_segment_efforts (no DB) ────────────────────────────────────────
def _detail(efforts) -> dict:
    return {"id": 987654, "segment_efforts": efforts}


def _effort(**overrides) -> dict:
    base = {
        "id": 111,
        "elapsed_time": 425,
        "moving_time": 420,
        "start_date": "2026-07-01T10:15:00Z",
        "pr_rank": None,
        "kom_rank": None,
        "segment": {
            "id": 55, "name": "Serra Climb", "distance": 3200.5,
            "average_grade": 5.4, "climb_category": 3,
        },
    }
    return base | overrides


def test_normalize_segment_efforts_full_payload():
    rows = normalize_segment_efforts(_detail([_effort(pr_rank=1, kom_rank=7)]))
    assert rows == [{
        "activity_external_id": "987654",
        "effort_id": "111",
        "segment_id": "55",
        "name": "Serra Climb",
        "distance_meters": 3200.5,
        "avg_grade": 5.4,
        "climb_category": 3,
        "elapsed_seconds": 425,
        "moving_seconds": 420,
        "start_date": dt.datetime(2026, 7, 1, 10, 15, tzinfo=UTC),
        "pr_rank": 1,
        "kom_rank": 7,
    }]


def test_normalize_segment_efforts_skips_malformed():
    rows = normalize_segment_efforts(_detail([
        _effort(),
        _effort(id=None),                      # no effort id
        _effort(segment={}),                   # no segment id
        _effort(start_date=None),              # no start date
        _effort(elapsed_time=None),            # no time
        "not-a-dict",
    ]))
    assert len(rows) == 1


def test_normalize_segment_efforts_empty():
    assert normalize_segment_efforts(_detail([])) == []
    assert normalize_segment_efforts({"id": 1}) == []


# ── endpoints (DB via the api fixture) ───────────────────────────────────────
START = dt.datetime(2026, 7, 1, 10, 0, tzinfo=UTC)


async def _seed(user_id: str) -> None:
    """A Strava ride + its intervals.icu twin, with two segments (one ridden twice)."""
    uid = uuid.UUID(user_id)
    async with session_scope(None) as s:
        s.add(Activity(user_id=uid, external_id="stv-1", source="strava", name="Ride",
                       domain="Cycling", start_time=START, duration_seconds=3600))
        s.add(Activity(user_id=uid, external_id="icu-1", source="garmin", name="Ride",
                       domain="Cycling", start_time=START + dt.timedelta(seconds=30),
                       duration_seconds=3590))
        for effort_id, seg, offset, elapsed, pr in (
            ("e1", "55", 900, 425, 1),
            ("e2", "77", 2400, 610, None),
            ("e0", "55", -86400, 450, None),  # yesterday's effort on segment 55
        ):
            s.add(SegmentEffort(
                user_id=uid, activity_external_id="stv-1" if offset > 0 else "stv-0",
                effort_id=effort_id, segment_id=seg, name=f"Segment {seg}",
                distance_meters=3200.5, avg_grade=5.4, elapsed_seconds=elapsed,
                start_date=START + dt.timedelta(seconds=offset), pr_rank=pr,
            ))


async def test_activity_segments_course_order(api):
    client, headers, user_id = api
    await _seed(user_id)
    r = await client.get("/v1/activities/stv-1/segments", headers=headers)
    assert r.status_code == 200
    body = r.json()
    # course order (segment 55 then 77), yesterday's e0 excluded by the window
    assert [(e["segmentId"], e["elapsedSeconds"]) for e in body] == [("55", 425), ("77", 610)]
    assert body[0]["prRank"] == 1


async def test_activity_segments_resolves_cross_source_twin(api):
    """The merge winner is the intervals.icu row — its id must find the efforts."""
    client, headers, user_id = api
    await _seed(user_id)
    r = await client.get("/v1/activities/icu-1/segments", headers=headers)
    assert r.status_code == 200
    assert [(e["segmentId"], e["elapsedSeconds"]) for e in r.json()] == [("55", 425), ("77", 610)]


async def test_activity_segments_unknown_activity_empty(api):
    client, headers, user_id = api
    r = await client.get("/v1/activities/nope/segments", headers=headers)
    assert r.status_code == 200
    assert r.json() == []


async def test_segment_history_newest_first(api):
    client, headers, user_id = api
    await _seed(user_id)
    r = await client.get("/v1/segments/55/efforts", headers=headers)
    assert r.status_code == 200
    body = r.json()
    assert body["name"] == "Segment 55"
    assert body["distanceMeters"] == 3200.5
    assert [e["elapsedSeconds"] for e in body["efforts"]] == [425, 450]  # newest first


async def test_segment_history_unknown_404(api):
    client, headers, _ = api
    r = await client.get("/v1/segments/does-not-exist/efforts", headers=headers)
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "SEGMENT_NOT_FOUND"


async def test_backfill_without_connection(api):
    client, headers, _ = api
    r = await client.post("/v1/integrations/strava/segments/backfill", headers=headers)
    assert r.status_code == 200
    assert r.json() == {"processed": 0, "remaining": 0}


class _FakeStravaClient:
    def __init__(self, payload):
        self.payload = payload

    async def fetch_activity_detail(self, token, activity_id):
        return self.payload


async def test_fetch_strava_segments_upserts_and_marks_checked(api):
    """Real INSERT ... ON CONFLICT against the actual unique index, twice
    (idempotent re-fetch), plus the efforts_synced_at stamp."""
    from sqlalchemy import select

    from app.jobs.tasks import _fetch_strava_segments

    _, _, user_id = api
    uid = uuid.UUID(user_id)
    payload = {
        "id": 42,
        "segment_efforts": [_effort(), _effort(id=222, elapsed_time=500,
                                             segment={"id": 77, "name": "Flat Sprint"})],
    }
    async with session_scope(None) as s:
        s.add(Activity(user_id=uid, external_id="42", source="strava", name="Ride",
                       domain="Cycling", start_time=START, duration_seconds=3600))

    async with session_scope(None) as s:
        assert await _fetch_strava_segments(s, _FakeStravaClient(payload), "tok", user_id, "42")
        assert await _fetch_strava_segments(s, _FakeStravaClient(payload), "tok", user_id, "42")  # idempotent

    async with session_scope(None) as s:
        efforts = (await s.execute(select(SegmentEffort).where(SegmentEffort.user_id == uid))).scalars().all()
        assert sorted(e.effort_id for e in efforts) == ["111", "222"]
        row = (await s.execute(select(Activity).where(Activity.user_id == uid))).scalars().one()
        assert row.efforts_synced_at is not None
