"""NorthAx API application. Mounts all routers under /v1 and wires the §11
error envelope. Base URL in production: https://api.northax.app/v1.

Interactive docs:
  - Swagger UI: /docs
  - ReDoc:      /redoc
  - OpenAPI:    /openapi.json
A committed copy of the spec lives in docs/openapi.{json,yaml}; regenerate it
with `python -m scripts.export_openapi`.
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.openapi.utils import get_openapi
from starlette.exceptions import HTTPException as StarletteHTTPException

from .config import settings
from .errors import (
    AppError,
    app_error_handler,
    http_exception_handler,
    validation_error_handler,
)
from .routers import activities, ai, auth, intervals, metrics, plan, preferences, readiness, user

logging.basicConfig(level=settings.log_level.upper())

DESCRIPTION = """
NorthAx training-OS backend.

Two layers (see BACKEND_SPEC.md §1):

* **Deterministic engines** — readiness scoring, weekly plan generation, and
  strength-session assembly. Ported from the iOS Swift engines; identical inputs
  produce identical outputs.
* **AI explanation layer** — Claude (via the Hermes agent CLI) wraps each
  deterministic output with a natural-language explanation, coaching note, and
  chat. The AI never overrides the deterministic score; it only explains it.

**Auth.** All routes except `POST /auth/apple`, `POST /auth/refresh`, and
`GET /intervals/callback` require `Authorization: Bearer <accessToken>`.

**Errors.** Every error returns the envelope
`{ "error": { "code", "message", "status" } }` (§11).
"""

TAGS_METADATA = [
    {"name": "auth", "description": "Sign in with Apple, token rotation, sign-out, account deletion (§7.1)."},
    {"name": "user", "description": "User profile (§7.2)."},
    {"name": "metrics", "description": "Daily morning metrics that drive readiness (§7.3)."},
    {"name": "readiness", "description": "Deterministic readiness score + cached AI explanation (§7.4)."},
    {"name": "preferences", "description": "Domains, frequency, and muscle-group split (§7.5)."},
    {"name": "plan", "description": "Weekly training plans (§7.6)."},
    {"name": "activities", "description": "Manual + Garmin-synced activities (§7.7)."},
    {"name": "intervals", "description": "intervals.icu OAuth connection + sync + workout push (§7.8 / §9)."},
    {"name": "ai", "description": "Coach chat (SSE), session suggestion, strength generation (§7.9–7.10)."},
    {"name": "meta", "description": "Health and service metadata."},
]


@asynccontextmanager
async def lifespan(app: FastAPI):
    # In development, create tables from the ORM if the schema isn't applied.
    if settings.env == "development":
        from .db import Base, engine

        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
    yield


app = FastAPI(
    title="NorthAx API",
    version="0.1.0",
    description=DESCRIPTION,
    openapi_tags=TAGS_METADATA,
    contact={"name": "NorthAx", "email": "api@northax.app"},
    license_info={"name": "Proprietary"},
    servers=[
        {"url": "https://api.northax.app/v1", "description": "Production"},
        {"url": "http://localhost:8080/v1", "description": "Local development"},
    ],
    lifespan=lifespan,
)

app.add_exception_handler(AppError, app_error_handler)
app.add_exception_handler(RequestValidationError, validation_error_handler)
app.add_exception_handler(StarletteHTTPException, http_exception_handler)

V1 = "/v1"
for module in (auth, user, metrics, readiness, preferences, plan, activities, intervals, ai):
    app.include_router(module.router, prefix=V1)


@app.get("/health", tags=["meta"])
async def health() -> dict:
    return {"status": "ok", "version": app.version}


# ── OpenAPI customisation: bearer security scheme + shared error schema ──────
def custom_openapi() -> dict:
    if app.openapi_schema:
        return app.openapi_schema

    schema = get_openapi(
        title=app.title,
        version=app.version,
        description=app.description,
        routes=app.routes,
        tags=TAGS_METADATA,
        servers=app.servers,
        contact=app.contact,
        license_info=app.license_info,
    )

    components = schema.setdefault("components", {})
    components.setdefault("securitySchemes", {})["bearerAuth"] = {
        "type": "http",
        "scheme": "bearer",
        "bearerFormat": "JWT",
        "description": "RS256 access token from POST /auth/apple or /auth/refresh.",
    }

    # Shared §11 error envelope schema.
    components.setdefault("schemas", {})["ApiError"] = {
        "type": "object",
        "properties": {
            "error": {
                "type": "object",
                "properties": {
                    "code": {"type": "string", "example": "METRICS_NOT_FOUND"},
                    "message": {"type": "string", "example": "No metrics found for 2026-06-29."},
                    "status": {"type": "integer", "example": 404},
                },
                "required": ["code", "message", "status"],
            }
        },
        "required": ["error"],
    }

    # Apply bearer auth globally; clear it on the public endpoints.
    public = {
        ("/v1/auth/apple", "post"),
        ("/v1/auth/refresh", "post"),
        ("/v1/intervals/callback", "get"),
        ("/health", "get"),
    }
    error_ref = {"$ref": "#/components/schemas/ApiError"}
    for path, methods in schema.get("paths", {}).items():
        for method, op in methods.items():
            if (path, method) in public:
                op["security"] = []
            else:
                op.setdefault("security", [{"bearerAuth": []}])
            # Attach the error envelope to the common error statuses.
            responses = op.setdefault("responses", {})
            for code in ("400", "401", "403", "404", "409", "422", "429", "503"):
                responses.setdefault(
                    code,
                    {
                        "description": "Error",
                        "content": {"application/json": {"schema": error_ref}},
                    },
                )

    # SSE stream (§8.2): document the event-stream response shape explicitly.
    coach = schema["paths"].get("/v1/ai/coach/message", {}).get("post")
    if coach is not None:
        coach["responses"]["200"] = {
            "description": (
                "Server-Sent Events stream. Emits `event: delta` frames with "
                '`data: {"text": "..."}`, then a terminal `event: done` frame with '
                '`data: {"messageId": "uuid", "fullContent": "..."}`. On AI failure, '
                'emits `event: error` with `data: {"code": "AI_UNAVAILABLE"}`.'
            ),
            "content": {
                "text/event-stream": {
                    "schema": {"type": "string"},
                    "example": (
                        'event: delta\ndata: {"text": "Based on your"}\n\n'
                        'event: done\ndata: {"messageId": "…", "fullContent": "Based on your…"}\n\n'
                    ),
                }
            },
        }

    # intervals.icu OAuth callback (§9.1) is a redirect into the app via universal link.
    callback = schema["paths"].get("/v1/intervals/callback", {}).get("get")
    if callback is not None:
        callback["responses"] = {
            "307": {"description": "Redirect to `northax://intervals/connected` (or `/error`)."}
        }

    app.openapi_schema = schema
    return schema


app.openapi = custom_openapi
