"""Strava integration (§13): OAuth client + activity/stream mappers.

Mirrors the intervals.icu client shape. Secrets come from the environment
(`STRAVA_CLIENT_ID` / `STRAVA_CLIENT_SECRET`); nothing lives client-side.
"""
from __future__ import annotations

import datetime as dt

import httpx

from ..config import settings


class StravaNotConfigured(RuntimeError):
    """Raised when Strava OAuth credentials are absent from the environment."""


class StravaClient:
    def __init__(self) -> None:
        self.api_base = settings.strava_api_base

    def _require_config(self) -> None:
        if not settings.strava_client_id or not settings.strava_client_secret:
            raise StravaNotConfigured("Strava client id/secret not configured.")

    def authorization_url(self, state: str) -> str:
        self._require_config()
        from urllib.parse import urlencode

        params = {
            "client_id": settings.strava_client_id,
            "redirect_uri": settings.strava_redirect_uri,
            "response_type": "code",
            "approval_prompt": "auto",
            "scope": settings.strava_scopes,
            "state": state,
        }
        return f"{settings.strava_oauth_authorize_url}?{urlencode(params)}"

    async def _token_request(self, data: dict) -> dict:
        self._require_config()
        data = {
            "client_id": settings.strava_client_id,
            "client_secret": settings.strava_client_secret,
            **data,
        }
        async with httpx.AsyncClient(timeout=15) as http:
            resp = await http.post(settings.strava_oauth_token_url, data=data)
            resp.raise_for_status()
            return resp.json()

    async def exchange_code(self, code: str) -> dict:
        return await self._token_request({"code": code, "grant_type": "authorization_code"})

    async def refresh(self, refresh_token: str) -> dict:
        return await self._token_request(
            {"refresh_token": refresh_token, "grant_type": "refresh_token"}
        )

    async def fetch_activities(self, token: str, after: dt.datetime) -> list[dict]:
        url = f"{self.api_base}/athlete/activities"
        params = {"after": int(after.timestamp()), "per_page": 100}
        async with httpx.AsyncClient(timeout=20) as http:
            resp = await http.get(
                url, params=params, headers={"Authorization": f"Bearer {token}"}
            )
            resp.raise_for_status()
            return resp.json()

    async def fetch_activity_streams(self, token: str, activity_id: str) -> dict:
        url = f"{self.api_base}/activities/{activity_id}/streams"
        params = {
            "keys": "time,heartrate,velocity_smooth,watts,altitude,cadence",
            "key_by_type": "true",
        }
        async with httpx.AsyncClient(timeout=20) as http:
            resp = await http.get(
                url, params=params, headers={"Authorization": f"Bearer {token}"}
            )
            resp.raise_for_status()
            return resp.json()


# ── Pure mappers ─────────────────────────────────────────────────────────────
_TYPE_TO_DOMAIN = {
    "Run": "Running",
    "TrailRun": "Running",
    "VirtualRun": "Running",
    "Ride": "Cycling",
    "VirtualRide": "Cycling",
    "GravelRide": "Cycling",
    "MountainBikeRide": "Cycling",
    "Swim": "Swimming",
    "WeightTraining": "Strength",
    "Workout": "Strength",
    "Yoga": "Mobility",
}


def _parse_dt(value) -> dt.datetime | None:
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def normalize_strava_activity(raw: dict) -> dict:
    """Map a Strava activity to the activities table columns (source='strava')."""
    sport = raw.get("sport_type") or raw.get("type") or ""
    return {
        "external_id": str(raw.get("id")),
        "source": "strava",
        "name": raw.get("name") or sport or "Activity",
        "domain": _TYPE_TO_DOMAIN.get(sport, "Recovery"),
        "start_time": _parse_dt(raw.get("start_date")),
        "duration_seconds": int(raw.get("moving_time") or raw.get("elapsed_time") or 0),
        "distance_meters": float(raw["distance"]) if raw.get("distance") is not None else None,
        "elevation_gain": float(raw["total_elevation_gain"]) if raw.get("total_elevation_gain") is not None else None,
        "avg_heart_rate": int(raw["average_heartrate"]) if raw.get("average_heartrate") is not None else None,
        "max_heart_rate": int(raw["max_heartrate"]) if raw.get("max_heartrate") is not None else None,
        "calories": int(raw["calories"]) if raw.get("calories") is not None else None,
        # Strava's Suffer Score / relative effort is a rough load proxy.
        "training_load": float(raw["suffer_score"]) if raw.get("suffer_score") is not None else None,
    }


def normalize_strava_streams(raw: dict) -> dict:
    """Strava `key_by_type` streams → {type: [values]} of just the data arrays."""
    if not isinstance(raw, dict):
        return {}
    return {k: v.get("data", []) for k, v in raw.items() if isinstance(v, dict)}
