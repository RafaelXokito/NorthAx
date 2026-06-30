"""Security primitives: RS256 JWTs, Apple identity-token verification, and
AES-256-GCM encryption for Garmin tokens at rest (§3, §5.8)."""
from __future__ import annotations

import base64
import datetime as dt
import os
import uuid

import jwt
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from .config import settings
from .errors import auth_invalid_apple_token, auth_token_expired

_ALGO = "RS256"


# ── App JWTs ─────────────────────────────────────────────────────────────────
def _now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def issue_access_token(user_id: str) -> str:
    now = _now()
    payload = {
        "sub": str(user_id),
        "iat": int(now.timestamp()),
        "exp": int((now + dt.timedelta(minutes=settings.access_token_ttl_minutes)).timestamp()),
        "type": "access",
    }
    return jwt.encode(payload, settings.jwt_private_pem, algorithm=_ALGO)


def issue_refresh_token(user_id: str, jti: str | None = None) -> tuple[str, str, dt.datetime]:
    """Returns (token, jti, expires_at). Persist the jti in refresh_tokens (§3.2)."""
    now = _now()
    jti = jti or str(uuid.uuid4())
    expires_at = now + dt.timedelta(days=settings.refresh_token_ttl_days)
    payload = {
        "sub": str(user_id),
        "iat": int(now.timestamp()),
        "exp": int(expires_at.timestamp()),
        "type": "refresh",
        "jti": jti,
    }
    token = jwt.encode(payload, settings.jwt_private_pem, algorithm=_ALGO)
    return token, jti, expires_at


def decode_token(token: str, expected_type: str) -> dict:
    try:
        claims = jwt.decode(token, settings.jwt_public_pem, algorithms=[_ALGO])
    except jwt.ExpiredSignatureError as exc:
        raise auth_token_expired() from exc
    except jwt.InvalidTokenError as exc:
        raise auth_token_expired("Token is invalid.") from exc
    if claims.get("type") != expected_type:
        raise auth_token_expired(f"Expected a {expected_type} token.")
    return claims


# ── Sign in with Apple ───────────────────────────────────────────────────────
_apple_jwk_client: jwt.PyJWKClient | None = None


def _jwk_client() -> jwt.PyJWKClient:
    global _apple_jwk_client
    if _apple_jwk_client is None:
        _apple_jwk_client = jwt.PyJWKClient(settings.apple_jwks_url)
    return _apple_jwk_client


def verify_apple_identity_token(identity_token: str) -> dict:
    """Verify an Apple identity token against Apple's JWKS and return its claims
    ({sub, email, ...}). Raises AUTH_INVALID_APPLE_TOKEN on any failure (§3.1)."""
    try:
        signing_key = _jwk_client().get_signing_key_from_jwt(identity_token)
        claims = jwt.decode(
            identity_token,
            signing_key.key,
            algorithms=["RS256"],
            audience=settings.apple_client_id,
            issuer=settings.apple_issuer,
        )
    except Exception as exc:  # noqa: BLE001 — any verification failure is a 401
        raise auth_invalid_apple_token(str(exc)) from exc
    if not claims.get("sub"):
        raise auth_invalid_apple_token("Token has no subject.")
    return claims


# ── AES-256-GCM token encryption (§5.8) ──────────────────────────────────────
def encrypt_token(plaintext: str) -> str:
    """Encrypt with AES-256-GCM; returns base64(nonce || ciphertext)."""
    key = settings.encryption_key_bytes
    if len(key) != 32:
        raise RuntimeError("ENCRYPTION_KEY must be a 32-byte hex string")
    nonce = os.urandom(12)
    ct = AESGCM(key).encrypt(nonce, plaintext.encode(), None)
    return base64.b64encode(nonce + ct).decode()


def decrypt_token(blob: str) -> str:
    key = settings.encryption_key_bytes
    raw = base64.b64decode(blob)
    nonce, ct = raw[:12], raw[12:]
    return AESGCM(key).decrypt(nonce, ct, None).decode()
