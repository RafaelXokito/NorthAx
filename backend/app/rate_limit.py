"""Per-user / per-IP fixed-window rate limiting (§12).

Uses Redis when reachable so limits hold across replicas; falls back to an
in-process counter otherwise (fine for a single dev instance).
"""
from __future__ import annotations

import time

from fastapi import Depends, Request
from redis.asyncio import Redis

from .config import settings
from .deps import get_current_user_id
from .errors import rate_limited

_redis: Redis | None = None
_local: dict[str, tuple[int, float]] = {}  # key -> (count, window_start)


def _get_redis() -> Redis | None:
    global _redis
    if _redis is None and settings.redis_url:
        try:
            _redis = Redis.from_url(settings.redis_url, decode_responses=True)
        except Exception:  # noqa: BLE001
            _redis = None
    return _redis


async def _hit(key: str, limit: int, window: int) -> None:
    """Increment the window counter for `key`; raise 429 if over `limit`."""
    r = _get_redis()
    if r is not None:
        try:
            count = await r.incr(key)
            if count == 1:
                await r.expire(key, window)
            if count > limit:
                ttl = await r.ttl(key)
                raise rate_limited(max(ttl, 1))
            return
        except Exception:  # noqa: BLE001 — Redis down: degrade to local counter
            pass

    now = time.monotonic()
    count, start = _local.get(key, (0, now))
    if now - start >= window:
        count, start = 0, now
    count += 1
    _local[key] = (count, start)
    if count > limit:
        raise rate_limited(int(window - (now - start)) + 1)


def limit(group: str, limit_count: int, window_seconds: int, by: str = "user"):
    """Build a dependency enforcing `limit_count` requests per `window_seconds`,
    keyed by authenticated user (`by="user"`) or client IP (`by="ip"`)."""

    if by == "user":
        async def _user_dep(user_id: str = Depends(get_current_user_id)) -> None:
            await _hit(f"rl:{group}:{user_id}", limit_count, window_seconds)

        return _user_dep

    async def _ip_dep(request: Request) -> None:
        ident = request.client.host if request.client else "unknown"
        await _hit(f"rl:{group}:{ident}", limit_count, window_seconds)

    return _ip_dep
