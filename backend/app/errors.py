"""Consistent error envelope and machine-readable error codes (§11)."""
from __future__ import annotations

from fastapi import Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class AppError(Exception):
    """A domain error that maps to the §11 JSON envelope."""

    def __init__(self, code: str, message: str, status: int):
        self.code = code
        self.message = message
        self.status = status
        super().__init__(message)

    def to_response(self) -> JSONResponse:
        return JSONResponse(
            status_code=self.status,
            content={"error": {"code": self.code, "message": self.message, "status": self.status}},
        )


# ── Error-code factories (the codes listed in §11) ──────────────────────────
def auth_invalid_credentials(msg="Email or password is incorrect."):
    return AppError("AUTH_INVALID_CREDENTIALS", msg, 401)


def auth_email_taken(msg="An account with this email already exists."):
    return AppError("AUTH_EMAIL_TAKEN", msg, 409)


def auth_token_expired(msg="Access token has expired."):
    return AppError("AUTH_TOKEN_EXPIRED", msg, 401)


def auth_token_revoked(msg="Refresh token has been revoked."):
    return AppError("AUTH_TOKEN_REVOKED", msg, 401)


def metrics_not_found(date: str):
    return AppError("METRICS_NOT_FOUND", f"No metrics found for {date}.", 404)


def metrics_already_exists(date: str):
    return AppError("METRICS_ALREADY_EXISTS", f"Metrics already exist for {date}; use PATCH.", 409)


def preferences_invalid_frequency(msg="totalTrainingDays must not exceed 6."):
    return AppError("PREFERENCES_INVALID_FREQUENCY", msg, 422)


def schedule_no_rest_day(msg="Schedules must leave at least one rest day (≤6 distinct training days)."):
    return AppError("SCHEDULE_NO_REST_DAY", msg, 400)


def schedule_invalid_weekday(msg="Each weekday must be in 0..6 and distinct within a sport."):
    return AppError("SCHEDULE_INVALID_WEEKDAY", msg, 400)


def preferences_invalid_split(msg="muscleGroupSplit must contain exactly 7 days."):
    return AppError("PREFERENCES_INVALID_SPLIT", msg, 422)


def activity_not_found():
    return AppError("ACTIVITY_NOT_FOUND", "Activity not found.", 404)


def activity_garmin_immutable():
    return AppError(
        "ACTIVITY_GARMIN_IMMUTABLE",
        "Garmin activities cannot be modified; disconnect the integration instead.",
        403,
    )


def intervals_not_connected():
    return AppError("INTERVALS_NOT_CONNECTED", "intervals.icu is not connected for this account.", 400)


def intervals_sync_in_progress():
    return AppError("INTERVALS_SYNC_IN_PROGRESS", "An intervals.icu sync is already running.", 409)


def ai_unavailable():
    return AppError("AI_UNAVAILABLE", "The AI provider is currently unavailable.", 503)


def plan_week_not_found():
    return AppError("PLAN_WEEK_NOT_FOUND", "No plan exists for the requested week.", 404)


def rate_limited(retry_after: int):
    err = AppError("RATE_LIMITED", "Rate limit exceeded.", 429)
    err.retry_after = retry_after  # type: ignore[attr-defined]
    return err


# ── Exception handlers ───────────────────────────────────────────────────────
async def app_error_handler(_: Request, exc: AppError) -> JSONResponse:
    resp = exc.to_response()
    if getattr(exc, "retry_after", None) is not None:
        resp.headers["Retry-After"] = str(exc.retry_after)
    return resp


async def validation_error_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
    return JSONResponse(
        status_code=400,
        content={
            "error": {
                "code": "VALIDATION_ERROR",
                "message": "Request validation failed.",
                "status": 400,
                # jsonable_encoder so a validator's raised ValueError (carried in
                # each error's `ctx`) is serialised rather than crashing the encoder.
                "details": jsonable_encoder(exc.errors()),
            }
        },
    )


async def http_exception_handler(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": "HTTP_ERROR",
                "message": str(exc.detail),
                "status": exc.status_code,
            }
        },
    )
