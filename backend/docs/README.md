# API documentation

The NorthAx HTTP API is documented as an **OpenAPI 3.1** spec.

| File | Purpose |
|---|---|
| [`openapi.json`](openapi.json) | Canonical machine-readable spec |
| [`openapi.yaml`](openapi.yaml) | Same spec, YAML form (easier to diff/read) |

The spec is generated from the FastAPI app, so it always matches the code.

## Viewing

- **Live, while the server runs:**
  - Swagger UI — <http://localhost:8080/docs>
  - ReDoc — <http://localhost:8080/redoc>
  - Raw spec — <http://localhost:8080/openapi.json>
- **Without running the server:**
  - Paste `openapi.yaml` into <https://editor.swagger.io>
  - or `npx @redocly/cli preview-docs docs/openapi.yaml`
  - or `npx @redocly/cli build-docs docs/openapi.yaml -o docs/index.html` for a
    standalone HTML page.

## Regenerating

After changing routes or DTOs, regenerate from the `backend/` directory:

```bash
python -m scripts.export_openapi    # writes docs/openapi.{json,yaml}
```

## What's covered

All 38 operations across auth, user, metrics, readiness, preferences, plan,
activities, garmin, and ai — plus `GET /health`. The spec includes:

- the `bearerAuth` (JWT) security scheme, applied to every route except the four
  public ones (`POST /auth/apple`, `POST /auth/refresh`, `GET /garmin/callback`,
  `POST /garmin/webhook`) and `GET /health`;
- the shared `ApiError` envelope (§11) on the 4xx/5xx responses;
- request/response schemas for every DTO in BACKEND_SPEC §6 (camelCase);
- the coach-chat `text/event-stream` (SSE) response shape (§8.2) and the Garmin
  OAuth `307` redirect (§9.1).
