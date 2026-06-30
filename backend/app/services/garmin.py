"""Garmin Health API OAuth proxy (§9).

The client secret never leaves the server. HMAC webhook verification and
encrypted token storage are fully implemented. The three calls that hit
Garmin's servers (request token, token exchange, activity fetch) are isolated
behind ``GarminClient`` and raise ``GarminNotConfigured`` until real
credentials and endpoint URLs are wired in — keeping the rest of the flow
testable and the integration surface obvious.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import hmac

from ..config import settings


class GarminNotConfigured(RuntimeError):
    """Raised when a live Garmin endpoint is invoked without configuration."""


def verify_webhook_signature(raw_body: bytes, signature_header: str | None) -> bool:
    """Validate the HMAC-SHA1 signature on a Garmin push notification (§9.2)."""
    if not signature_header or not settings.garmin_webhook_secret:
        return False
    digest = hmac.new(
        settings.garmin_webhook_secret.encode(), raw_body, hashlib.sha1
    ).hexdigest()
    return hmac.compare_digest(digest, signature_header.strip())


class GarminClient:
    """Thin wrapper around Garmin's OAuth + activity endpoints.

    NOTE: Garmin's Health API uses OAuth 1.0a. Fill in the request-token,
    access-token, and activity-list URLs and signing per Garmin's developer
    docs. Each method is intentionally a single integration point.
    """

    def __init__(self) -> None:
        self.consumer_key = settings.garmin_consumer_key
        self.consumer_secret = settings.garmin_consumer_secret
        self.callback_url = settings.garmin_callback_url

    def _require_config(self) -> None:
        if not self.consumer_key or not self.consumer_secret:
            raise GarminNotConfigured("GARMIN_CONSUMER_KEY/SECRET are not set")

    async def request_token(self) -> tuple[str, str]:
        """Obtain an unauthorized request token; return (oauth_token, secret)."""
        self._require_config()
        raise GarminNotConfigured("request_token endpoint not wired in")

    def authorization_url(self, oauth_token: str) -> str:
        return f"https://connect.garmin.com/oauthConfirm?oauth_token={oauth_token}"

    async def exchange_token(self, oauth_token: str, oauth_verifier: str) -> dict:
        """Exchange the verifier for access credentials and Garmin user id."""
        self._require_config()
        raise GarminNotConfigured("exchange_token endpoint not wired in")

    async def fetch_activities(self, access_token: str, access_secret: str, since: dt.datetime) -> list[dict]:
        """Fetch activities since `since` from the Garmin Health API."""
        self._require_config()
        raise GarminNotConfigured("fetch_activities endpoint not wired in")


def normalize_garmin_activity(raw: dict) -> dict:
    """Map a Garmin activity payload onto the columns of the activities table.

    Garmin's activity `activityType` maps onto a TrainingDomain (see
    GarminModels.swift). Unknown types fall back to 'Recovery'.
    """
    type_map = {
        "CYCLING": "Cycling",
        "RUNNING": "Running",
        "SWIMMING": "Swimming",
        "STRENGTH_TRAINING": "Strength",
        "YOGA": "Mobility",
    }
    activity_type = (raw.get("activityType") or "").upper()
    return {
        "external_id": str(raw["activityId"]),
        "source": "garmin",
        "name": raw.get("activityName") or "Garmin Activity",
        "domain": type_map.get(activity_type, "Recovery"),
        "start_time": raw["startTime"],
        "duration_seconds": int(raw.get("durationSeconds", 0)),
        "distance_meters": raw.get("distanceInMeters"),
        "elevation_gain": raw.get("elevationGainInMeters"),
        "avg_heart_rate": raw.get("averageHeartRateInBeatsPerMinute"),
        "max_heart_rate": raw.get("maxHeartRateInBeatsPerMinute"),
        "calories": raw.get("activeKilocalories"),
        "training_load": raw.get("trainingLoad"),
    }
