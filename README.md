# NorthAx

An intelligent training OS: a **SwiftUI iOS app** backed by a **Python/FastAPI service**.
NorthAx reads an athlete's body every morning (HRV, sleep, resting HR, training
load), computes a daily **readiness** score, builds a weekly **plan**, and wraps
every number in a plain-language **AI coach** explanation.

Data comes from **intervals.icu** acting as a man-in-the-middle aggregator over
Garmin/Strava — the athlete links those to intervals.icu once, and NorthAx talks
only to intervals.icu.

```
NorthAx/
├── ios/                 SwiftUI iOS app   →  open ios/NorthAx.xcodeproj
│   └── NorthAx/         Engine · Models · Networking · Services · Store · Views
├── backend/             FastAPI service   →  see backend/README.md
│   ├── app/             engines · routers · services · jobs · models
│   ├── docs/            OpenAPI 3.1 spec (openapi.yaml / .json)
│   ├── sql/schema.sql   Postgres schema + Row-Level Security
│   └── tests/           engine-parity + mapping tests
├── BACKEND_SPEC.md      source-of-truth spec for the backend
└── INTEGRATION.md       app ↔ backend integration plan + status
```

## Architecture

Two layers, on both client and server:

- **Deterministic engines** — readiness scoring, weekly-plan generation, and
  strength-session assembly. The iOS Swift engines are the source of truth; the
  backend engines are a faithful port, pinned by parity tests, so client and
  server agree by construction. The client keeps its engines as an **offline
  fallback** and for optimistic UI.
- **AI explanation layer** — Claude (via the Hermes CLI on the server) wraps each
  deterministic output with a natural-language explanation, coaching note, and a
  streaming chat. The AI never overrides the deterministic score; it only
  explains it, and degrades gracefully (deterministic-only) if unavailable.

```
 Garmin / Strava
       │  (athlete links once, outside the app)
       ▼
  intervals.icu ──OAuth2 / API key──► NorthAx backend ──Bearer JWT (RS256)──► iOS app
  wellness, activities,               FastAPI · engines · Claude          SwiftUI
  CTL/ATL (Fitness/Fatigue)           Postgres + RLS · Redis
```

## The iOS app (`ios/`)

SwiftUI, `@Observable` `AthleteStore` as the single source of UI state. Tabs:
**Today** (readiness ring + insights + suggested session), **Coach** (streaming
LLM chat), **Metrics** (HRV/sleep/load history), **Plan** (weekly plan), and
**Settings** (intervals.icu connect, training frequency, muscle split).

Networking lives in `ios/NorthAx/Networking/`: an `APIClient` (bearer auth with
single-flight 401→refresh), Keychain token storage, an SSE client for coach
chat, DTOs + mappers, and a `NorthAxAPI` facade returning domain models. When a
backend session exists the store loads live data; offline it falls back to the
client engines and a mock seed, so the UI always has something to show.

Open `ios/NorthAx.xcodeproj` in Xcode 16+ and run on a simulator or device.
Point it at a backend with the `NORTHAX_API_BASE_URL` launch env var (defaults to
`http://localhost:8080/v1` in DEBUG).

## The backend (`backend/`)

FastAPI + SQLAlchemy (async) + PostgreSQL (Row-Level Security) + Redis. It
implements [`BACKEND_SPEC.md`](BACKEND_SPEC.md):

- Sign in with Apple → RS256 JWT access/refresh with rotation
- `/readiness`, `/metrics`, `/plan`, `/preferences`, `/activities`, `/user`
- `/ai/*` — coach chat (SSE), session suggestion, strength generation (Claude via Hermes)
- `/intervals/*` — OAuth 2.0 **or** personal-API-key connect, sync (wellness +
  activities → `daily_metrics`, using intervals.icu's own CTL/ATL), and pushing
  planned workouts to the intervals.icu calendar (which syncs them to Garmin)
- background jobs, rate limiting, a consistent error envelope

Full setup, the AI transport, and the run commands are in
[`backend/README.md`](backend/README.md); the API reference is in
[`backend/docs/`](backend/docs/).

### Quick start (backend)

```bash
cd backend
cp .env.example .env          # fill JWT keys, ENCRYPTION_KEY, intervals.icu creds
docker compose up -d db redis # Postgres (schema auto-applied) + Redis
pip install -e '.[dev]'
uvicorn app.main:app --reload --port 8080
python -m app.seed            # optional: seed a dev user from INTERVALS_API_KEY + sync
pytest                        # engine-parity + mapping tests
```

Interactive docs at `http://localhost:8080/docs`; health at `/health`.

## intervals.icu connection

Two ways to connect (both keep secrets server-side):

- **OAuth 2.0** — register an app at intervals.icu (Settings → Developer), set
  `INTERVALS_CLIENT_ID/SECRET`; the app opens the web flow.
- **Personal API key** — paste an intervals.icu API key + athlete id in the app
  (Settings → intervals.icu), or set `INTERVALS_API_KEY` / `INTERVALS_ATHLETE_ID`
  in the backend `.env` for the dev seed.

## Status

The backend is feature-complete to the spec and was **verified end-to-end on
real intervals.icu data** (sync → `daily_metrics` → `GET /readiness/today`
through the running FastAPI stack). Backend tests pass; the iOS target
type-checks against the iOS 18 SDK. See [`INTEGRATION.md`](INTEGRATION.md) for
the phased plan, what's done, and remaining polish.

> **Note:** the AI explanation layer needs an authenticated Hermes CLI on the
> server; without it, readiness/coach responses return the deterministic result
> without the AI narrative.
