"""intervals.icu integration (OAuth 2.0) — the man-in-the-middle data source.

The athlete connects Garmin/Strava/etc. to intervals.icu once; intervals.icu
aggregates wellness + activities, computes Fitness/Fatigue (CTL/ATL), and exposes
a calendar for pushing planned workouts (which it syncs back to Garmin). This
client talks to intervals.icu so the backend never touches Garmin directly.

API: https://intervals.icu/api/v1 (athlete id "0" = the authenticated athlete).
Auth: OAuth 2.0 Bearer. The client secret stays server-side.
"""
from __future__ import annotations

import datetime as dt
import logging
import urllib.parse

import httpx

from ..config import settings

log = logging.getLogger("northax.intervals")


class IntervalsNotConfigured(RuntimeError):
    """Raised when an intervals.icu call is made without OAuth credentials."""


class IntervalsClient:
    """Async client for intervals.icu OAuth + REST API."""

    def __init__(self) -> None:
        self.client_id = settings.intervals_client_id
        self.client_secret = settings.intervals_client_secret
        self.redirect_uri = settings.intervals_redirect_uri
        self.api_base = settings.intervals_api_base

    def _require_config(self) -> None:
        if not self.client_id or not self.client_secret:
            raise IntervalsNotConfigured("INTERVALS_CLIENT_ID/SECRET are not set")

    # ── OAuth ────────────────────────────────────────────────────────────────
    def authorization_url(self, state: str) -> str:
        self._require_config()
        params = {
            "client_id": self.client_id,
            "redirect_uri": self.redirect_uri,
            "scope": settings.intervals_scopes,
            "response_type": "code",
            "state": state,
        }
        return f"{settings.intervals_oauth_authorize_url}?{urllib.parse.urlencode(params)}"

    async def exchange_code(self, code: str) -> dict:
        """Exchange an authorization code for tokens. Returns the token payload
        (access_token, refresh_token, expires_in, athlete_id)."""
        self._require_config()
        data = {
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": self.redirect_uri,
            "client_id": self.client_id,
            "client_secret": self.client_secret,
        }
        async with httpx.AsyncClient(timeout=15) as http:
            resp = await http.post(settings.intervals_oauth_token_url, data=data)
            resp.raise_for_status()
            return resp.json()

    async def refresh(self, refresh_token: str) -> dict:
        self._require_config()
        data = {
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": self.client_id,
            "client_secret": self.client_secret,
        }
        async with httpx.AsyncClient(timeout=15) as http:
            resp = await http.post(settings.intervals_oauth_token_url, data=data)
            resp.raise_for_status()
            return resp.json()

    # ── REST ───────────────────────────────────────────────────────────────
    # Two auth modes: OAuth Bearer token, or a personal API key via HTTP Basic
    # ("API_KEY":key). `api_key=True` selects Basic. Personal-key calls do not
    # require server OAuth config, so they skip `_require_config()`.
    def _auth_kwargs(self, token: str, api_key: bool) -> dict:
        if api_key:
            return {"auth": ("API_KEY", token)}
        return {"headers": {"Authorization": f"Bearer {token}"}}

    async def validate_api_key(self, athlete_id: str, api_key: str) -> dict:
        """Confirm a personal API key works; return {athlete_id, display_name}."""
        url = f"{self.api_base}/athlete/{athlete_id}/profile"
        async with httpx.AsyncClient(timeout=15) as http:
            resp = await http.get(url, auth=("API_KEY", api_key))
            resp.raise_for_status()
            data = resp.json()
        athlete = data.get("athlete", data)
        return {
            "athlete_id": str(athlete.get("id", athlete_id)),
            "display_name": athlete.get("name") or athlete.get("firstname"),
        }

    async def fetch_wellness(
        self, token: str, since: dt.date, until: dt.date, *, api_key: bool = False, athlete_id: str = "0"
    ) -> list[dict]:
        url = f"{self.api_base}/athlete/{athlete_id}/wellness"
        params = {"oldest": since.isoformat(), "newest": until.isoformat()}
        async with httpx.AsyncClient(timeout=20) as http:
            resp = await http.get(url, params=params, **self._auth_kwargs(token, api_key))
            resp.raise_for_status()
            return resp.json()

    async def fetch_activities(
        self, token: str, since: dt.date, until: dt.date, *, api_key: bool = False, athlete_id: str = "0"
    ) -> list[dict]:
        url = f"{self.api_base}/athlete/{athlete_id}/activities"
        params = {"oldest": since.isoformat(), "newest": until.isoformat()}
        async with httpx.AsyncClient(timeout=20) as http:
            resp = await http.get(url, params=params, **self._auth_kwargs(token, api_key))
            resp.raise_for_status()
            return resp.json()

    async def fetch_activity_streams(
        self, token: str, activity_id: str, *, api_key: bool = False
    ) -> list | dict:
        """Time-series streams for one activity (§10). Requests only the metrics we
        chart to keep the payload small."""
        url = f"{self.api_base}/activity/{activity_id}/streams"
        params = {"types": "time,heartrate,watts,velocity_smooth,altitude,cadence"}
        async with httpx.AsyncClient(timeout=20) as http:
            resp = await http.get(url, params=params, **self._auth_kwargs(token, api_key))
            resp.raise_for_status()
            return resp.json()

    async def create_event(
        self, token: str, event: dict, *, api_key: bool = False, athlete_id: str = "0"
    ) -> dict:
        """Create a calendar event (planned workout). Returns the created event."""
        url = f"{self.api_base}/athlete/{athlete_id}/events"
        async with httpx.AsyncClient(timeout=20) as http:
            resp = await http.post(url, json=event, **self._auth_kwargs(token, api_key))
            resp.raise_for_status()
            return resp.json()

    async def list_events(
        self, token: str, oldest: str, newest: str, *, api_key: bool = False, athlete_id: str = "0"
    ) -> list[dict]:
        """List calendar events in [oldest, newest] (ISO dates, inclusive)."""
        url = f"{self.api_base}/athlete/{athlete_id}/events"
        async with httpx.AsyncClient(timeout=20) as http:
            resp = await http.get(
                url, params={"oldest": oldest, "newest": newest}, **self._auth_kwargs(token, api_key)
            )
            resp.raise_for_status()
            return resp.json()

    async def delete_event(
        self, token: str, event_id: str, *, api_key: bool = False, athlete_id: str = "0"
    ) -> None:
        """Delete one calendar event."""
        url = f"{self.api_base}/athlete/{athlete_id}/events/{event_id}"
        async with httpx.AsyncClient(timeout=20) as http:
            resp = await http.delete(url, **self._auth_kwargs(token, api_key))
            resp.raise_for_status()


# ── Pure mappers (unit-tested) ───────────────────────────────────────────────
def _hours(seconds) -> float | None:
    return round(seconds / 3600, 2) if seconds is not None else None


def normalize_intervals_wellness(raw: dict) -> dict:
    """Map an intervals.icu wellness record to the wellness-derived subset of
    daily_metrics. intervals.icu provides ctl/atl directly, so acute/chronic
    load come straight from it (no activity summation needed)."""
    return {
        "date": raw.get("id") or raw.get("date"),  # wellness record id is the date
        "hrv": raw.get("hrv") or raw.get("hrvSDNN"),
        "resting_hr": raw.get("restingHR"),
        "sleep_duration": _hours(raw.get("sleepSecs")),
        "sleep_score": raw.get("sleepScore"),
        # intervals.icu doesn't break out REM/deep; readiness scoring uses
        # duration + score, so these are informational only.
        "rem_sleep": None,
        "deep_sleep": None,
        # Fitness/Fatigue computed by intervals.icu.
        "atl": raw.get("atl"),   # acute load (fatigue)
        "ctl": raw.get("ctl"),   # chronic load (fitness)
        "vo2max": raw.get("vo2max"),  # §12 — estimate, when present
    }


_TYPE_TO_DOMAIN = {
    "Ride": "Cycling",
    "VirtualRide": "Cycling",
    "Run": "Running",
    "Swim": "Swimming",
    "WeightTraining": "Strength",
    "Workout": "Strength",
    "Yoga": "Mobility",
}


def _parse_dt(value) -> dt.datetime | None:
    """Parse an intervals.icu ISO datetime string to a datetime (None if absent)."""
    if not value:
        return None
    if isinstance(value, dt.datetime):
        return value
    try:
        return dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def normalize_intervals_activity(raw: dict) -> dict:
    """Map an intervals.icu activity to the activities table columns."""
    icu_type = raw.get("type") or ""
    return {
        "external_id": str(raw.get("id")),
        "source": "garmin",  # ultimately Garmin-sourced via intervals.icu
        "name": raw.get("name") or "Activity",
        "domain": _TYPE_TO_DOMAIN.get(icu_type, "Recovery"),
        "start_time": _parse_dt(raw.get("start_date_local") or raw.get("start_date")),
        "duration_seconds": int(raw.get("moving_time") or raw.get("elapsed_time") or 0),
        "distance_meters": raw.get("distance"),
        "elevation_gain": raw.get("total_elevation_gain"),
        "avg_heart_rate": raw.get("average_heartrate"),
        "max_heart_rate": raw.get("max_heartrate"),
        "calories": raw.get("calories"),
        "training_load": raw.get("icu_training_load") or raw.get("trainingLoad"),
    }


_DOMAIN_TO_ICU_TYPE = {
    "Cycling": "Ride",
    "Running": "Run",
    "Swimming": "Swim",
    "Strength": "WeightTraining",
    "Triathlon": "Ride",
    "Mobility": "Yoga",
    "Recovery": "Workout",
}


def planned_session_to_intervals_event(session: dict, date: str, external_id: str | None = None) -> dict:
    """Map a PlannedSession (§6.7) to an intervals.icu calendar WORKOUT event,
    which intervals.icu schedules to Garmin. `external_id` marks the event as
    NorthAx-owned so a plan regeneration can replace it."""
    icu_type = _DOMAIN_TO_ICU_TYPE.get(session.get("domain", ""), "Workout")
    minutes = int(session.get("duration", 0))
    description = session.get("subtitle") or session.get("intensityLabel") or ""
    event = {
        "category": "WORKOUT",
        "start_date_local": f"{date}T00:00:00",
        "type": icu_type,
        "name": session.get("title") or "NorthAx Session",
        "description": description,
        "moving_time": minutes * 60,
    }
    if external_id:
        event["external_id"] = external_id
    return event
