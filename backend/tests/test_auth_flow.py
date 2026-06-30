"""End-to-end auth lifecycle through the real FastAPI app (skipped without a DB):
register → use access token → login → refresh-rotation → logout, plus the
credential/validation failure paths."""
from __future__ import annotations

import uuid

import pytest_asyncio
from sqlalchemy import delete

from app.db import session_scope
from app.models import User

PASSWORD = "correct-horse-battery"


@pytest_asyncio.fixture(autouse=True)
async def _reset_rate_limit():
    """The rate limiter counts per-IP across the whole process; reset it before
    each test so repeated register/login calls don't trip the 429 cap."""
    from app import rate_limit

    rate_limit._local.clear()
    r = rate_limit._redis  # only if a client already exists; don't force one
    if r is not None:
        try:
            keys = await r.keys("rl:*")
            if keys:
                await r.delete(*keys)
        except Exception:  # noqa: BLE001 — Redis absent/unreachable: local clear is enough
            pass
    yield


def _email() -> str:
    return f"flow-{uuid.uuid4()}@northax.test"


async def _cleanup(email: str) -> None:
    async with session_scope(None) as session:
        await session.execute(delete(User).where(User.email == email.lower()))


async def test_register_login_refresh_logout(client):
    email = _email()
    try:
        # Register → token pair + user summary.
        r = await client.post(
            "/v1/auth/register", json={"name": "Flow", "email": email, "password": PASSWORD}
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["user"]["email"] == email
        assert body["user"]["name"] == "Flow"
        access = body["accessToken"]

        # Access token authenticates a protected route.
        me = await client.get("/v1/user/profile", headers={"Authorization": f"Bearer {access}"})
        assert me.status_code == 200, me.text
        assert me.json()["email"] == email

        # Login with the same credentials → a fresh pair.
        r = await client.post("/v1/auth/login", json={"email": email, "password": PASSWORD})
        assert r.status_code == 200, r.text
        login_refresh = r.json()["refreshToken"]

        # Refresh rotates: new pair issued, and the old refresh token is now dead.
        r = await client.post("/v1/auth/refresh", json={"refreshToken": login_refresh})
        assert r.status_code == 200, r.text
        new_access = r.json()["accessToken"]
        new_refresh = r.json()["refreshToken"]
        assert new_refresh != login_refresh

        r = await client.post("/v1/auth/refresh", json={"refreshToken": login_refresh})
        assert r.status_code == 401
        assert r.json()["error"]["code"] == "AUTH_TOKEN_REVOKED"

        # Logout revokes all refresh tokens for the user.
        r = await client.delete(
            "/v1/auth/session", headers={"Authorization": f"Bearer {new_access}"}
        )
        assert r.status_code == 204

        # The rotated-in refresh token is signature-valid but now revoked.
        r = await client.post("/v1/auth/refresh", json={"refreshToken": new_refresh})
        assert r.status_code == 401
        assert r.json()["error"]["code"] == "AUTH_TOKEN_REVOKED"
    finally:
        await _cleanup(email)


async def test_login_wrong_password_is_401(client):
    email = _email()
    try:
        r = await client.post(
            "/v1/auth/register", json={"name": "Flow", "email": email, "password": PASSWORD}
        )
        assert r.status_code == 200, r.text
        r = await client.post("/v1/auth/login", json={"email": email, "password": "not-the-password"})
        assert r.status_code == 401
        assert r.json()["error"]["code"] == "AUTH_INVALID_CREDENTIALS"
    finally:
        await _cleanup(email)


async def test_login_unknown_email_is_401(client):
    r = await client.post(
        "/v1/auth/login", json={"email": _email(), "password": "whatever-long-enough"}
    )
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "AUTH_INVALID_CREDENTIALS"


async def test_register_duplicate_email_is_409(client):
    email = _email()
    try:
        r = await client.post(
            "/v1/auth/register", json={"name": "Flow", "email": email, "password": PASSWORD}
        )
        assert r.status_code == 200, r.text
        # Different case + surrounding space must still collide (email is normalised).
        r = await client.post(
            "/v1/auth/register",
            json={"name": "Other", "email": f"  {email.upper()} ", "password": PASSWORD},
        )
        assert r.status_code == 409
        assert r.json()["error"]["code"] == "AUTH_EMAIL_TAKEN"
    finally:
        await _cleanup(email)


async def test_register_validation_is_400(client):
    # Password below the 8-char minimum.
    r = await client.post(
        "/v1/auth/register", json={"name": "X", "email": "a@b.co", "password": "short"}
    )
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"

    # Malformed email.
    r = await client.post(
        "/v1/auth/register", json={"name": "X", "email": "not-an-email", "password": "longenough1"}
    )
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION_ERROR"
