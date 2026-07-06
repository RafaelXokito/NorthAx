"""Unit tests for route geometry (polyline decode/downsample) and the latlng
stream normalization feeding the route-map feature."""
from app.services.polyline import decode_polyline, downsample_route
from app.services.strava import normalize_strava_activity, normalize_strava_streams
from app.services.streams import normalize_streams


# ── decode_polyline ──────────────────────────────────────────────────────────
def test_decode_polyline_google_reference_vector():
    assert decode_polyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@") == [
        [38.5, -120.2],
        [40.7, -120.95],
        [43.252, -126.453],
    ]


def test_decode_polyline_empty():
    assert decode_polyline("") == []


def test_decode_polyline_truncated_input_keeps_clean_prefix():
    full = decode_polyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
    truncated = decode_polyline("_p~iF~ps|U_ulLnnqC_mqN")
    assert truncated == full[:2]


# ── downsample_route ─────────────────────────────────────────────────────────
def test_downsample_route_caps_and_keeps_endpoints():
    pts = [[float(i), float(-i)] for i in range(5000)]
    out = downsample_route(pts)
    assert len(out) <= 76
    assert out[0] == [0.0, 0.0]
    assert out[-1] == [4999.0, -4999.0]


def test_downsample_route_short_route_untouched():
    pts = [[1.0, 2.0], [3.0, 4.0]]
    assert downsample_route(pts) == pts


def test_downsample_route_filters_malformed():
    assert downsample_route([[1.0, 2.0], None, [3.0], "x", [5.0, 6.0]]) == [[1.0, 2.0], [5.0, 6.0]]
    assert downsample_route(None) == []


# ── normalize_streams latlng ─────────────────────────────────────────────────
def _intervals_raw(n: int, with_latlng: bool = True) -> list[dict]:
    raw = [
        {"type": "time", "data": list(range(n))},
        {"type": "heartrate", "data": [120] * n},
    ]
    if with_latlng:
        # intervals.icu splits latlng: data = latitudes, data2 = longitudes.
        raw.append({
            "type": "latlng",
            "data": [40.0 + i * 1e-4 for i in range(n)],
            "data2": [-8.0 - i * 1e-4 for i in range(n)],
        })
    return raw


def test_normalize_streams_intervals_latlng():
    dto = normalize_streams("a1", _intervals_raw(400))
    assert len(dto.lat_lng) == 400  # under the 1000-pt route cap: kept whole
    assert dto.lat_lng[0] == [40.0, -8.0]
    assert len(dto.heart_rate) == 200  # scalar cap unchanged
    assert len(dto.time) == 200


def test_normalize_streams_latlng_denser_than_scalars():
    dto = normalize_streams("a1", _intervals_raw(4000))
    assert len(dto.lat_lng) <= 1001
    assert len(dto.lat_lng) > 500
    assert len(dto.heart_rate) <= 201


def test_normalize_streams_no_latlng():
    dto = normalize_streams("a1", _intervals_raw(100, with_latlng=False))
    assert dto.lat_lng == []
    assert len(dto.heart_rate) == 100


def test_normalize_streams_strava_shaped_latlng():
    # Strava streams carry latlng as ready-made [lat, lng] pairs.
    raw = {
        "heartrate": {"data": [130] * 50},
        "latlng": {"data": [[41.0, -8.5]] * 50},
    }
    dto = normalize_streams("s1", normalize_strava_streams(raw), source="Strava")
    assert dto.lat_lng == [[41.0, -8.5]] * 50
    assert dto.heart_rate == [130.0] * 50


def test_normalize_streams_latlng_gps_dropouts_filtered():
    raw = [{"type": "latlng", "data": [40.0, None, 40.2], "data2": [-8.0, -8.1, None]}]
    assert normalize_streams("a1", raw).lat_lng == [[40.0, -8.0]]


# ── normalize_strava_activity route_points ───────────────────────────────────
def test_strava_activity_with_polyline_gets_route_points():
    values = normalize_strava_activity(
        {"id": 1, "type": "Ride", "moving_time": 60,
         "map": {"summary_polyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@"}}
    )
    assert values["route_points"] == [[38.5, -120.2], [40.7, -120.95], [43.252, -126.453]]


def test_strava_activity_without_polyline_is_none():
    assert normalize_strava_activity({"id": 2, "type": "VirtualRide", "moving_time": 60})["route_points"] is None
    assert normalize_strava_activity({"id": 3, "type": "Ride", "map": {}, "moving_time": 60})["route_points"] is None
