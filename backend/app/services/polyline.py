"""Route-geometry helpers: Google encoded-polyline decoding + downsampling.

Strava activity lists carry `map.summary_polyline` (encoded); intervals.icu
streams carry raw [[lat, lng], ...] pairs. Both funnel through
`downsample_route` into the coarse `activities.route_points` column.
"""
from __future__ import annotations


def decode_polyline(encoded: str) -> list[list[float]]:
    """Decode a Google encoded polyline (precision 1e5) to [[lat, lng], ...]."""
    if not encoded:
        return []
    points: list[list[float]] = []
    lat = lng = 0
    i = 0
    try:
        while i < len(encoded):
            for is_lng in (False, True):
                shift = result = 0
                while True:
                    b = ord(encoded[i]) - 63
                    i += 1
                    result |= (b & 0x1F) << shift
                    shift += 5
                    if b < 0x20:
                        break
                delta = ~(result >> 1) if result & 1 else result >> 1
                if is_lng:
                    lng += delta
                else:
                    lat += delta
            points.append([lat / 1e5, lng / 1e5])
    except IndexError:  # truncated/corrupt input — keep what decoded cleanly
        pass
    return points


def downsample_route(points: list, max_points: int = 75) -> list[list[float]]:
    """Stride-downsample a route to ≤ max_points + 1, always keeping the final
    point so the trace ends where the activity ended. Malformed entries are
    dropped."""
    if not isinstance(points, list):
        return []
    clean = [
        [float(p[0]), float(p[1])]
        for p in points
        if isinstance(p, (list, tuple)) and len(p) == 2
        and all(isinstance(c, (int, float)) for c in p)
    ]
    if len(clean) <= max_points:
        return clean
    stride = -(-len(clean) // max_points)  # ceil: guarantees ≤ max_points strided
    out = clean[::stride]
    if out[-1] != clean[-1]:
        out.append(clean[-1])
    return out
