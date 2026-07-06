"""Strava segment efforts (§13): mapper unit tests + endpoint integration tests."""
import datetime as dt
import uuid

import httpx

from app.db import session_scope
from app.models import Activity, Segment, SegmentEffort
from app.services.strava import normalize_segment_detail, normalize_segment_efforts

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


# ── normalize_segment_detail (no DB) ─────────────────────────────────────────
def test_normalize_segment_detail_full():
    row = normalize_segment_detail({
        "id": 55, "name": "Serra Climb", "distance": 3200.5, "average_grade": 5.4,
        "climb_category": 3, "map": {"polyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@"},
    })
    assert row["segment_id"] == "55"
    assert row["name"] == "Serra Climb"
    assert row["points"] == [[38.5, -120.2], [40.7, -120.95], [43.252, -126.453]]


def test_normalize_segment_detail_no_polyline():
    row = normalize_segment_detail({"id": 55, "name": "S"})
    assert row["points"] == []


def test_normalize_segment_detail_no_id():
    assert normalize_segment_detail({}) is None
    assert normalize_segment_detail("nope") is None


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


# ── segment geometry (§13) ───────────────────────────────────────────────────
_GEOM = [[40.0, -8.0], [40.01, -8.01], [40.02, -8.02]]


async def _seed_geometry(segment_id: str = "55") -> None:
    # merge: the segments table is global (no per-user cleanup), so seeding
    # must be an upsert to survive earlier tests touching the same id.
    async with session_scope(None) as s:
        await s.merge(Segment(segment_id=segment_id, name="Serra Climb", points=_GEOM))


async def test_activity_segments_joins_points(api):
    client, headers, user_id = api
    await _seed(user_id)
    await _seed_geometry("55")  # 77 stays geometry-less (drain pending)
    r = await client.get("/v1/activities/stv-1/segments", headers=headers)
    body = r.json()
    by_seg = {e["segmentId"]: e["points"] for e in body}
    assert by_seg["55"] == _GEOM
    assert by_seg["77"] is None


async def test_activity_segments_carries_all_time_best_and_rank(api):
    """This ride's effort on 55 is 425; yesterday's e0 was 450 → 425 is the best."""
    client, headers, user_id = api
    await _seed(user_id)
    r = await client.get("/v1/activities/stv-1/segments", headers=headers)
    by_seg = {e["segmentId"]: e for e in r.json()}
    assert by_seg["55"]["bestElapsedSeconds"] == 425   # this effort IS the best
    assert by_seg["55"]["rank"] == 1
    assert by_seg["77"]["bestElapsedSeconds"] == 610
    assert by_seg["77"]["rank"] == 1                   # only effort on 77


async def test_activity_segments_rank_counts_later_efforts(api):
    """Yesterday's e0 (450) is now 2nd all-time behind today's 425."""
    client, headers, user_id = api
    await _seed(user_id)
    async with session_scope(None) as s:
        s.add(Activity(user_id=uuid.UUID(user_id), external_id="stv-0", source="strava",
                       name="Old ride", domain="Cycling",
                       start_time=START - dt.timedelta(days=1, seconds=1000),
                       duration_seconds=3600))
    r = await client.get("/v1/activities/stv-0/segments", headers=headers)
    body = r.json()
    assert len(body) == 1
    assert body[0]["elapsedSeconds"] == 450
    assert body[0]["rank"] == 2
    assert body[0]["bestElapsedSeconds"] == 425


async def test_segment_history_carries_points(api):
    client, headers, user_id = api
    await _seed(user_id)
    await _seed_geometry("55")
    r = await client.get("/v1/segments/55/efforts", headers=headers)
    assert r.json()["points"] == _GEOM


class _FakeSegmentClient:
    """fetch_segment_detail stub: canned payloads by id, or an httpx error."""
    def __init__(self, payloads: dict, error: Exception | None = None):
        self.payloads = payloads
        self.error = error

    async def fetch_segment_detail(self, token, segment_id):
        if self.error is not None:
            raise self.error
        return self.payloads[segment_id]


def _http_error(status: int) -> httpx.HTTPStatusError:
    req = httpx.Request("GET", "https://example/api")
    return httpx.HTTPStatusError("err", request=req, response=httpx.Response(status, request=req))


async def test_fetch_segment_geometry_upserts_idempotently(api):
    from sqlalchemy import select

    from app.jobs.tasks import _fetch_segment_geometry

    payload = {"u55": {"id": "u55", "name": "Serra", "map": {"polyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@"}}}
    async with session_scope(None) as s:
        assert await _fetch_segment_geometry(s, _FakeSegmentClient(payload), "tok", "u55")
        assert await _fetch_segment_geometry(s, _FakeSegmentClient(payload), "tok", "u55")  # idempotent
    async with session_scope(None) as s:
        seg = (await s.execute(select(Segment).where(Segment.segment_id == "u55"))).scalars().one()
        assert len(seg.points) == 3


async def test_fetch_segment_geometry_404_stores_stub(api):
    from sqlalchemy import select

    from app.jobs.tasks import _fetch_segment_geometry

    async with session_scope(None) as s:
        assert await _fetch_segment_geometry(s, _FakeSegmentClient({}, error=_http_error(404)), "tok", "gone")
    async with session_scope(None) as s:
        seg = (await s.execute(select(Segment).where(Segment.segment_id == "gone"))).scalars().one()
        assert seg.points == []


async def test_fetch_segment_geometry_other_error_returns_false(api):
    from app.jobs.tasks import _fetch_segment_geometry

    async with session_scope(None) as s:
        assert not await _fetch_segment_geometry(s, _FakeSegmentClient({}, error=_http_error(429)), "tok", "55")


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
