"""Shared activity-stream normalization (§10 / §13).

Turns a provider's raw stream payload — intervals.icu (a list of {type, data}
objects) or Strava (a {type: [data]} dict, already flattened by
normalize_strava_streams) — into downsampled, index-aligned float arrays.
"""
from __future__ import annotations

from .. import schemas

_STREAM_MAX_POINTS = 200


def normalize_streams(activity_id: str, raw, source: str = "intervals.icu") -> schemas.ActivityStreamsDTO:
    streams: dict[str, list] = {}
    if isinstance(raw, list):
        for s in raw:
            if isinstance(s, dict) and s.get("type") is not None and isinstance(s.get("data"), list):
                streams[str(s["type"])] = s["data"]
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
    return dto
