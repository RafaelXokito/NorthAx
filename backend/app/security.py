"""Security primitives: RS256 JWTs, Scrypt password hashing, and AES-256-GCM
encryption for Garmin tokens at rest (§3, §5.8)."""
from __future__ import annotations

import base64
import datetime as dt
import hmac
import os
import uuid

import jwt
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

from .config import settings
from .errors import auth_token_expired

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


# ── Password hashing (Scrypt, via `cryptography`) ────────────────────────────
# Stored format: "scrypt$<n>$<r>$<p>$<salt_b64>$<hash_b64>". Scrypt is memory-
# hard and ships with our existing `cryptography` dependency, so no extra
# package is needed (§3.1).
_SCRYPT_N = 2**14  # CPU/memory cost
_SCRYPT_R = 8
_SCRYPT_P = 1
_SCRYPT_LEN = 32


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    derived = Scrypt(salt=salt, length=_SCRYPT_LEN, n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P).derive(
        password.encode()
    )
    return "scrypt${}${}${}${}${}".format(
        _SCRYPT_N,
        _SCRYPT_R,
        _SCRYPT_P,
        base64.b64encode(salt).decode(),
        base64.b64encode(derived).decode(),
    )


def verify_password(password: str, stored: str) -> bool:
    """Constant-time check of a plaintext password against a stored Scrypt hash."""
    try:
        scheme, n, r, p, salt_b64, hash_b64 = stored.split("$")
        if scheme != "scrypt":
            return False
        salt = base64.b64decode(salt_b64)
        expected = base64.b64decode(hash_b64)
        derived = Scrypt(
            salt=salt, length=len(expected), n=int(n), r=int(r), p=int(p)
        ).derive(password.encode())
    except Exception:  # noqa: BLE001 — a malformed hash never authenticates
        return False
    return hmac.compare_digest(derived, expected)


# A throwaway hash used to equalise login timing when no user matches, so a
# missing email can't be distinguished from a wrong password by response time.
DUMMY_PASSWORD_HASH = hash_password("northax-timing-equaliser")


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
