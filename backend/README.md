# NorthAx Backend

Python/FastAPI implementation of [`BACKEND_SPEC.md`](../BACKEND_SPEC.md) — the
training OS backend for the NorthAx iOS app.

It has two layers (§1):

- **Deterministic engines** — readiness scoring, weekly plan generation, and
  strength-session assembly, ported line-for-line from the iOS Swift engines so
  the backend produces *identical* outputs for identical inputs. These are the
  source of truth and are pinned by parity tests.
- **AI explanation layer** — Claude wraps each deterministic output with a
  natural-language explanation, coaching note, and chat. The AI never overrides
  the deterministic score; it only explains it (§8).

## AI transport — Hermes CLI (`hermes -z`)

The AI layer shells out to the **Hermes agent CLI** in one-shot mode
(`hermes -z`) instead of the Anthropic HTTP API. This means **no API key is
required** — the host just needs an authenticated `hermes` binary on `PATH`
(run `hermes login` / `hermes setup` once).

- Hermes has no `--system-prompt` flag, so the persona/system instructions are
  **prepended to the prompt**. `--ignore-rules` is recommended (via
  `HERMES_EXTRA_ARGS`) to keep `AGENTS.md`/`SOUL.md`/memory out of coaching
  prompts.
- Hermes one-shot is non-streaming, so coach chat fetches the full reply and
  re-emits it as SSE deltas to preserve the §8.2 streaming contract.
- Models via `-m provider/model` (e.g. `anthropic/claude-haiku-4.5`); empty →
  Hermes' configured default. Set `AI_MODEL_FAST` / `AI_MODEL_DEFAULT` to map
  the low-latency vs chat paths.
- Failure detection: Hermes writes errors to stderr and leaves stdout empty, so
  an empty stdout is treated as failure.
- Per §8.5, AI is best-effort: any failure/timeout returns the deterministic
  result without an `aiExplanation`. Coach chat emits an `AI_UNAVAILABLE` SSE
  event if the call fails.

All AI logic is isolated in [`app/services/ai.py`](app/services/ai.py); swapping
back to the Anthropic SDK (`pip install '.[api]'`) is a change to that one file.

## Stack

FastAPI · SQLAlchemy 2 (async/asyncpg) · PostgreSQL 16 (Row-Level Security) ·
Redis (rate limiting) · PyJWT (RS256) · APScheduler (jobs) · Hermes agent CLI.

## Layout

```
app/
  main.py            FastAPI app; mounts routers under /v1; error envelope (§11)
  config.py          Settings from env/.env (§13)
  db.py              Async engine + RLS-scoped session_scope() (§4)
  models.py          SQLAlchemy ORM (§5)
  schemas.py         Pydantic DTOs, camelCase wire format (§6)
  security.py        RS256 JWTs, Apple token verify, AES-256-GCM (§3, §5.8)
  deps.py            Bearer auth + RLS-scoped DB dependencies
  rate_limit.py      Per-user / per-IP fixed-window limits (§12)
  errors.py          AppError + machine-readable codes (§11)
  engines/           Deterministic engines (ports of the Swift engines)
    enums.py         TrainingDomain, MuscleGroup, frequency/split value types
    readiness.py     ReadinessEngine  (Appendix A)
    plan.py          PlanEngine       (Appendix B)
    strength.py      StrengthEngine
  services/
    ai.py            Claude AI layer via Hermes CLI (`hermes -z`) (§8)
    intervals.py     intervals.icu OAuth client + wellness/activity/event mapping (§9)
    metrics_assembly.py  intervals.icu wellness → daily_metrics (§9.3)
    plan_service.py  Plan regeneration shared by routers + jobs
    mappers.py       ORM ⇄ engine ⇄ DTO conversions
  routers/           auth, user, metrics, readiness, preferences, plan,
                     activities, intervals, ai
  jobs/
    tasks.py         generate-plans, compute-readiness, intervals-sync, prune (§10)
    worker.py        APScheduler entrypoint
sql/schema.sql       Full schema + RLS policies (§5, §4)
tests/               Engine parity tests
```

## Run

### Docker (everything)

```bash
cp .env.example .env        # fill in JWT keys + ENCRYPTION_KEY (see below)
docker compose up --build
```

Brings up Postgres (schema auto-applied), Redis, the API on `:8080`, and the
jobs worker. For AI inside the container, install/authenticate the `claude` CLI
in the image (see the note in the `Dockerfile`).

### Local

```bash
python3.12 -m venv .venv && source .venv/bin/activate
pip install -e '.[dev]'
# Postgres + Redis running locally; apply the schema:
psql "$DATABASE_URL" -f sql/schema.sql
uvicorn app.main:app --reload --port 8080
python -m app.jobs.worker     # in another shell, for scheduled jobs
```

Interactive docs at `http://localhost:8080/docs` (Swagger) and `/redoc`; health
at `/health`.

## API docs

The OpenAPI 3.1 spec is committed at [`docs/openapi.yaml`](docs/openapi.yaml) /
[`docs/openapi.json`](docs/openapi.json) and is generated from the app, so it
always matches the code. Regenerate after route/DTO changes:

```bash
python -m scripts.export_openapi
```

See [`docs/README.md`](docs/README.md) for viewing options. The spec covers all
38 operations, the `bearerAuth` JWT scheme, the shared `ApiError` envelope, the
coach-chat SSE response, and every §6 DTO.

### Required secrets

```bash
# RS256 JWT keys (base64-encode the PEMs into JWT_PRIVATE_KEY / JWT_PUBLIC_KEY)
openssl genrsa -out jwt_private.pem 2048
openssl rsa -in jwt_private.pem -pubout -out jwt_public.pem
base64 -i jwt_private.pem | tr -d '\n'   # → JWT_PRIVATE_KEY
base64 -i jwt_public.pem  | tr -d '\n'   # → JWT_PUBLIC_KEY

# AES-256-GCM key for Garmin tokens at rest
openssl rand -hex 32                     # → ENCRYPTION_KEY
```

## Tests

```bash
pytest                       # engine parity tests (no DB required)
```

The parity tests pin the reference outputs from the Swift engines — e.g. the
"fresh" mock athlete scores **88/100 (Peak)** with component scores HRV 81 /
sleep 87 / load 100, and the default 3×cycling + 2×strength frequency produces
rest days on Thu/Sun with no back-to-back same-sport days.

## Implementation status

Fully implemented: auth (Apple verify + RS256 + refresh rotation), all CRUD
routes, the three deterministic engines, the AI layer over `hermes -z`, RLS,
rate limiting, the error envelope, and the job logic + scheduler.

Data source: **intervals.icu** (OAuth 2.0, `services/intervals.py`) as the
man-in-the-middle over Garmin/Strava — wellness + activities in, CTL/ATL
computed by intervals.icu, planned workouts pushed out as calendar events. The
OAuth + REST calls are fully implemented (real `httpx`); they raise
`INTERVALS_NOT_CONFIGURED` until `INTERVALS_CLIENT_ID/SECRET` are set.

Remaining: per-user-local-time job triggers (the worker schedules in UTC; §10).
