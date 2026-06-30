"""Application configuration, loaded from environment / .env (see §13)."""
from __future__ import annotations

import base64
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Server
    port: int = 8080
    env: str = "development"
    log_level: str = "info"

    # Database / Redis
    database_url: str = "postgresql+asyncpg://northax:northax@localhost:5432/northax"
    redis_url: str = "redis://localhost:6379/0"

    # JWT (RS256). Keys are base64-encoded PEM blobs in the environment.
    jwt_private_key: str = ""
    jwt_public_key: str = ""
    access_token_ttl_minutes: int = 15
    refresh_token_ttl_days: int = 60

    # AI transport.
    # The AI layer shells out to the Hermes agent CLI (`hermes -z`) rather than
    # the Anthropic HTTP API, so no API key is required — the host just needs an
    # authenticated `hermes` on PATH (`hermes login` / `hermes setup`).
    anthropic_api_key: str = ""  # kept for a future swap back to the SDK
    hermes_cli_path: str = "hermes"
    hermes_provider: str = ""  # optional --provider override (e.g. "anthropic")
    # Per-invocation extra args (space-separated). "--ignore-rules" is
    # recommended so AGENTS.md/SOUL.md/memory aren't injected into coaching
    # prompts. Left empty by default to avoid surprising the operator.
    hermes_extra_args: str = ""
    # Model overrides as Hermes model strings (provider/model, e.g.
    # "anthropic/claude-haiku-4.5"). Empty → use Hermes' configured default.
    ai_model_fast: str = ""
    ai_model_default: str = ""
    # CLI timeouts (seconds). Generous to absorb the agent's cold start /
    # tool-loop; the §8.5 API timeouts assume the direct HTTP API.
    ai_cli_fast_timeout: float = 60.0
    ai_cli_default_timeout: float = 90.0

    # intervals.icu (OAuth 2.0) — the "man in the middle" that aggregates
    # Garmin/Strava/etc. and exposes wellness, activities, and a calendar for
    # pushing planned workouts. The client secret never leaves the server.
    intervals_client_id: str = ""
    intervals_client_secret: str = ""
    intervals_redirect_uri: str = "https://api.northax.app/v1/intervals/callback"
    intervals_oauth_authorize_url: str = "https://intervals.icu/oauth/authorize"
    intervals_oauth_token_url: str = "https://intervals.icu/api/oauth/token"
    intervals_api_base: str = "https://intervals.icu/api/v1"
    intervals_scopes: str = "WELLNESS:READ,ACTIVITY:READ,CALENDAR:WRITE"
    # Personal API key (HTTP Basic) — dev / single-athlete fallback. The normal
    # per-user connect flow stores keys in the DB; these let the backend use a
    # default key from the environment (e.g. for a dev seed).
    intervals_api_key: str = ""
    intervals_athlete_id: str = ""

    # Token-at-rest encryption (AES-256-GCM, 32-byte hex key)
    encryption_key: str = ""

    app_scheme: str = "northax://"
    sentry_dsn: str = ""

    # ── Derived helpers ──────────────────────────────────────────────────────
    @property
    def jwt_private_pem(self) -> bytes:
        return base64.b64decode(self.jwt_private_key) if self.jwt_private_key else b""

    @property
    def jwt_public_pem(self) -> bytes:
        return base64.b64decode(self.jwt_public_key) if self.jwt_public_key else b""

    @property
    def encryption_key_bytes(self) -> bytes:
        return bytes.fromhex(self.encryption_key) if self.encryption_key else b""


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
