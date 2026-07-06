"""Shared activity-stream normalization (§10 / §13).

Turns a provider's raw stream payload — intervals.icu (a list of {type, data}
objects) or Strava (a {type: [data]} dict, already flattened by
normalize_strava_streams) — into downsampled, index-aligned float arrays.
"""
from __future__ import annotations

from .. import schemas

_STREAM_MAX_POINTS = 200
# Routes get a denser cap than the scalar charts: 200 points makes a long ride
# visibly jagged on a map, and the pairs aren't index-aligned with the charts.
_ROUTE_MAX_POINTS = 1000


def normalize_streams(activity_id: str, raw, source: str = "intervals.icu") -> schemas.ActivityStreamsDTO:
    streams: dict[str, list] = {}
    if isinstance(raw, list):
        for s in raw:
            if isinstance(s, dict) and s.get("type") is not None and isinstance(s.get("data"), list):
                data = s["data"]
                # intervals.icu splits latlng: data = latitudes, data2 = longitudes.
                if isinstance(s.get("data2"), list):
                    data = [[a, b] for a, b in zip(data, s["data2"])]
                streams[str(s["type"])] = data
    elif isinstance(raw, dict):
        streams = {k: v for k, v in raw.items() if isinstance(v, list)}

    n = max((len(v) for v in streams.values()), default=0)
    dto = schemas.ActivityStreamsDTO(activity_id=str(activity_id), source=source)
    if n == 0:
        return dto
    stride = max(1, n // _STREAM_MAX_POINTS)

    def clean(key: str) -> list[float]:
        data = streams.get(key)
        if not isinstance(data, list) or not any(isinstance(x, (int, float)) for x in data):
            return []
        out: list[float] = []
        last = 0.0
        for i, x in enumerate(data):
            if i % stride:
                continue
            if isinstance(x, (int, float)):
                last = float(x)
            out.append(last)
        return out

    dto.heart_rate = clean("heartrate")
    dto.power = clean("watts")
    dto.velocity = clean("velocity_smooth")
    dto.altitude = clean("altitude")
    dto.cadence = clean("cadence")
    dto.time = clean("time") or [float(i) for i in range(0, n, stride)]
    dto.lat_lng = _clean_latlng(streams.get("latlng"))
    return dto


def _clean_latlng(data) -> list[list[float]]:
    """GPS pairs get their own (denser) stride — `clean()` handles scalars only."""
    if not isinstance(data, list) or not data:
        return []
    stride = max(1, len(data) // _ROUTE_MAX_POINTS)
    return [
        [float(p[0]), float(p[1])]
        for i, p in enumerate(data)
        if i % stride == 0
        and isinstance(p, (list, tuple)) and len(p) == 2
        and all(isinstance(c, (int, float)) for c in p)
    ]
