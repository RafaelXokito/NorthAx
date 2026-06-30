# NorthAx — App ↔ Backend Integration Plan

**Goal:** make the iOS app *not static* — replace its mock data and client-side
computation with live calls to the NorthAx backend (FastAPI, documented in
[`backend/docs/openapi.yaml`](backend/docs/openapi.yaml)).

This document is the research + design. It maps the current app to the API,
identifies the gaps, designs the iOS networking layer, and lays out a phased
rollout.

> **Status.** Data source is **intervals.icu (OAuth 2.0)** acting as the
> man-in-the-middle over Garmin/Strava — it aggregates wellness + activities,
> computes CTL/ATL, and brokers workout push back to Garmin. (Earlier mentions
> of "Garmin" below now mean "via intervals.icu"; endpoints are `/v1/intervals/*`.)
>
> Implemented + verified: backend intervals.icu integration (real httpx OAuth
> client, wellness→`daily_metrics`, workout push; 24 tests pass, OpenAPI valid)
> and client Phases 0–5 (networking, auth, intervals connect via
> `ASWebAuthenticationSession`, readiness/metrics/plan/preferences load, coach
> over SSE) — full-target `swiftc -typecheck` clean against the iOS 18 SDK. The
> app loads live data when authenticated and falls back to the client
> engines/mock offline. Remaining: Phase 6 polish; go-live prerequisites in §10.
> Not yet built/run in Xcode end-to-end.

---

## 1. Where the app is static today

Everything the app shows is computed on-device from mock seeds. There is **no
networking layer at all** — no `URLSession`, no API client.

| Concern | Today (static) | Source |
|---|---|---|
| Metrics | `TrainingMetrics.mockFresh` / `.mockFatigued` | `AthleteStore.metrics` (`Store/AthleteStore.swift:33,57`) |
| Readiness | `ReadinessEngine.calculate(from:)` on-device | `AthleteStore.recalculate()` (`:63,100`) |
| Weekly plan | `PlanEngine.generatePlans(...)` on-device | `AthleteStore.regeneratePlan()` (`:64,105`) |
| Coach replies | **Hardcoded keyword matching** (`buildResponse(for:)`) | `AthleteStore.respond(to:)` (`:171–246`) |
| Strength session | `StrengthEngine` on-device | "Switch Activity" flow |
| Garmin | Stubbed; returns `GarminActivity.mockActivities` after a fake delay | `Services/GarminService.swift:42–55` |
| Auth | Apple credential kept **locally only**; persisted to `UserDefaults`; **no server exchange** | `Services/AuthService.swift:20–53` |
| Frequency / split | `UserDefaults` JSON | `AthleteStore.loadFrequency()` (`:85–97`) |

The deterministic engines (`ReadinessEngine`, `PlanEngine`, `StrengthEngine`)
are the **same algorithms** the backend now mirrors, so client and server agree
by construction. That is the key enabler: we can move computation server-side
without changing results, and keep the client engines as an **offline fallback**.

---

## 2. Target architecture

```
┌────────────────────────── iOS app ──────────────────────────┐
│  Views (SwiftUI) → AthleteStore (@Observable)                │
│                         │                                    │
│                  Repository layer  ◄── offline fallback ──┐  │
│                         │                                 │  │
│                    APIClient (async/await)         client engines
│             ┌───────────┼───────────┐                        │
│        Keychain     401→refresh    SSE (URLSession bytes)     │
└─────────────────────────┼────────────────────────────────────┘
                          ▼  Authorization: Bearer <JWT>
              FastAPI backend  /v1/*   (deterministic engines + Claude)
                          ▼
              Postgres · Redis · Hermes CLI · Garmin
```

- **APIClient** — one typed async client generated against the OpenAPI spec (or
  hand-written). Injects the bearer token, decodes DTOs, maps errors.
- **Repository layer** — sits between the store and the client. Each feature
  (readiness, plan, coach, …) gets a repository that: calls the API, caches the
  result, and falls back to the on-device engine when offline.
- **AthleteStore** stays the single `@Observable` the views bind to, but its
  fields are now populated *asynchronously* from repositories instead of
  synchronously from mocks. Views need loading/empty/error states.
- **Client engines stay** — for optimistic/offline UI and as the documented
  parity reference. The server result wins when it arrives.

---

## 3. Endpoint ↔ feature mapping

| App surface | Store field / action | API endpoint(s) |
|---|---|---|
| Sign in | `AuthService.handleAppleSignIn` | `POST /auth/apple`, `POST /auth/refresh`, `DELETE /auth/session`, `DELETE /auth/account` |
| Profile | `athleteName` | `GET /user/profile`, `PATCH /user/profile` |
| Dashboard readiness | `readiness` | `GET /readiness/today` |
| Metrics ingest | `metrics` | `POST /metrics/daily` (submit), `GET /metrics/daily`, `GET /metrics/history` |
| Metrics view/history | charts | `GET /metrics/history` |
| Plan view | `weeklyPlans` | `GET /plan/weeks`, `GET /plan/week/{monday}` |
| Frequency change | `trainingFrequency` (didSet → regen) | `PATCH /preferences/frequency` → server regenerates → `GET /plan/weeks` |
| Muscle split | `muscleGroupSplit` | `PATCH /preferences/muscle-split` |
| Enabled domains | `enabledDomains` | `PATCH /preferences/domains` / `PUT /preferences` |
| Day override | plan edit | `PATCH /plan/week/{monday}/day/{date}` |
| Coach chat | `messages`, `respond(to:)` | `POST /ai/coach/message` (SSE), `GET /ai/coach/history`, `DELETE /ai/coach/history` |
| Session suggestion | dashboard suggested session | `GET /ai/session/suggest` |
| Switch Activity → strength | `switchSession(...)` | `POST /ai/strength/generate` |
| Activities list | (new) | `GET /activities`, `POST /activities`, … |
| Garmin connect/sync | `GarminService` | `POST /garmin/connect`, `GET /garmin/status`, `POST /garmin/sync`, `DELETE /garmin/disconnect` |

---

## 4. DTO mapping (API JSON ⇄ iOS models)

The API returns **camelCase** matching the iOS naming closely, but there are
shape mismatches that need adapter code (decode API DTO → map to existing model).

| iOS model | API schema | Mismatch / adapter needed |
|---|---|---|
| `DailyReadiness` (flat `suggested*`, `*Score`) | `DailyReadinessResponse` (nested `suggestedSession`, `componentScores`) | Flatten `suggestedSession.*` → `suggested*`; `componentScores.{hrv,sleep,load,recovery}` → `*Score`; new `verdict`, `aiExplanation` (use `verdict`/`coachingNote` from server instead of `Status.verdict`) |
| `MetricInsight.Trend` enum (no raw value) | `trend: "up"\|"down"\|"neutral"\|"warning"` | Map string → enum |
| `WeeklyPlan` / `PlannedDay` (computed `weekdayShort`, `isToday`, …) | `WeeklyPlanDTO` / `PlannedDayDTO` (server provides these fields) | Decode dates; can ignore server's presentation fields and keep client-computed, or trust server |
| `CoachMessage.isCoach: Bool` | `role: "user"\|"coach"` | `isCoach = (role == "coach")` |
| `AuthUser{id,name,email}` | `UserSummary{id(uuid),name,email}` | `id` becomes the **server** UUID, not Apple's `cred.user` |
| `StrengthSession` (`muscleGroups:[MuscleGroup]`) | `StrengthSessionResponse` (`muscleGroups:[String]`) | Map enum raw values |
| `TrainingFrequency` (Codable already) | `UserPreferences.domainFrequencies` | Field rename `daysPerWeek`; wrap/unwrap |

**Dates:** the API mixes `YYYY-MM-DD` (e.g. `date`, `weekStart`) and full
ISO-8601 datetimes (e.g. `startTime`, `createdAt`). A single
`JSONDecoder.dateDecodingStrategy` won't cover both — use a custom strategy that
tries date-only then datetime, or decode those fields as `String` and parse in
the adapter.

---

## 5. iOS networking layer (new)

New files under `ios/NorthAx/Networking/`:

- **`APIConfig`** — base URL per build config. `DEBUG` → `http://localhost:8080/v1`
  (requires an ATS exception for localhost), release → `https://api.northax.app/v1`.
- **`TokenStore`** — access + refresh tokens in the **Keychain** (not
  `UserDefaults`). Access TTL 15 min, refresh 60 days (per spec §3.2).
- **`APIClient`** — `func send<T: Decodable>(_ endpoint) async throws -> T`.
  Adds `Authorization: Bearer`, decodes DTOs, maps the `{error:{code,message,status}}`
  envelope to a typed `APIError` (carrying the machine code so the UI can react,
  e.g. `METRICS_NOT_FOUND` → show "log your morning metrics").
- **Auth interceptor** — on `401 AUTH_TOKEN_EXPIRED`, call `POST /auth/refresh`
  once, store the rotated pair, retry the original request; on refresh failure,
  sign out. Serialize concurrent refreshes (single-flight).
- **DTOs** — `Codable` structs mirroring the OpenAPI component schemas. Can be
  generated (e.g. `swift-openapi-generator` from `docs/openapi.yaml`) or
  hand-written; generation keeps them in sync with the spec.
- **SSE client** — for `POST /ai/coach/message`. Use
  `URLSession.bytes(for:)` and iterate `.lines`, parsing `event:`/`data:` frames
  (`delta` → append text, `done` → finalize with `messageId`, `error` → surface
  `AI_UNAVAILABLE`). This is what turns the Coach from canned text into a real
  streaming LLM conversation.

---

## 6. Auth flow rework (the first real dependency)

Current `AuthService` (`:20–53`) reads `ASAuthorizationAppleIDCredential` and
keeps `cred.user` locally. It must instead **exchange the Apple token with the
backend**:

1. Request scopes `[.fullName, .email]` (already typical).
2. On success, read `credential.identityToken` (`Data` → UTF-8 `String`) and
   `credential.authorizationCode` — **these aren't captured today**.
3. `POST /auth/apple { identityToken, authorizationCode, fullName }`.
4. Store the returned `accessToken` + `refreshToken` in Keychain; set
   `currentUser` from the response `user` (server UUID).
5. `AthleteStore.configure(with:)` then loads everything from the API.

**Backend prerequisite:** `APPLE_CLIENT_ID` (the JWKS audience the backend
verifies) must equal the app's Sign in with Apple client identifier, or
verification 401s. Confirm this matches the app's bundle/Services ID.

Keep the `#if DEBUG signInAsDebugUser` path, but point it at a backend dev-token
shortcut (or a seeded test user) so debug builds still reach live data.

---

## 7. Per-feature integration steps

**Readiness (Dashboard).** Replace `recalculate()`'s engine call with
`GET /readiness/today`. Map the DTO into `DailyReadiness`. On network failure,
fall back to `ReadinessEngine.calculate(from: cachedMetrics)`. The `aiExplanation`
narrative is new UI surface (show under the score).

**Metrics ingestion — via Garmin (decided).** Metrics come from the Garmin
connection, not HealthKit. The server pulls Garmin **wellness** data (HRV, sleep
stages + score, resting HR, stress/body-battery) *and* **activities**, then
assembles the `daily_metrics` row that drives readiness. This makes Garmin
**foundational** — it feeds Dashboard, Metrics, Coach, and recovery warnings —
so it moves earlier in the rollout. See §12 for the backend work this requires.

**Workout push — to Garmin (decided).** Planned sessions are pushed to Garmin as
scheduled workouts (the `GarminService.pushPlannedSession` stub at
`Services/GarminService.swift:61` anticipates this), via a new backend endpoint
backed by the Garmin **Training API**. See §12.

**Plan + preferences.** `trainingFrequency.didSet` currently regenerates locally.
Re-point it at `PATCH /preferences/frequency` (server regenerates 4 weeks), then
`GET /plan/weeks`. Same for `muscleGroupSplit` → `/preferences/muscle-split`.
Validation errors (`PREFERENCES_INVALID_FREQUENCY`, total > 6) now come from the
server — surface them instead of the client guard.

**Coach (headline change).** Replace `respond(to:)` / `buildResponse(for:)` with
the SSE client against `POST /ai/coach/message`; stream deltas into the message
bubble live. Load prior turns from `GET /ai/coach/history` on open; "clear chat"
→ `DELETE /ai/coach/history`. Removes ~75 lines of hardcoded responses.

**Strength ("Switch Activity").** `POST /ai/strength/generate { muscleGroups,
readinessScore }`; map `StrengthSessionResponse` → `StrengthSession`.

**Garmin (foundational).** Replace the stub: `POST /garmin/connect` → open the
returned `authorizationUrl` in `ASWebAuthenticationSession` (callback scheme
`northax`) → backend redirects to `northax://garmin/connected` → poll
`GET /garmin/status` → `POST /garmin/sync`. Sync now pulls **wellness + activity**
data and assembles `daily_metrics` (§12). `pushPlannedSession` →
`POST /garmin/workouts/push`. **Backend prerequisite:** the external Garmin calls
are currently stubbed (`GarminNotConfigured`); real sync/push needs them wired
with Garmin Developer credentials (§12).

---

## 8. Cross-cutting: state, errors, offline

- **Loading/empty/error states.** Views assume data is always present. Add
  `enum Loadable<T> { case idle, loading, loaded(T), failed(APIError) }` (or
  per-field flags on the store) and render spinners/retry/empty UI.
- **Optimistic + reconcile.** For instant feel, keep computing readiness/plan
  locally on a metrics change, show it immediately, then replace with the server
  result. Since the engines match, the swap is invisible on success.
- **Caching/offline.** Persist last-good readiness, plan, and metrics (Codable →
  disk) so the app opens with real data offline; refresh in the background.
- **Pull-to-refresh** on Dashboard/Plan.
- **Rate limits.** Respect `429` + `Retry-After` (coach 30/h, strength 20/h).

---

## 9. Decisions (resolved)

1. **Metrics source → Garmin.** Wellness + activities pulled server-side and
   assembled into `daily_metrics` (§12). HealthKit not used in this version.
2. **Workouts → pushed to Garmin** as scheduled workouts via the Training API (§12).
3. **Keep client engines → yes.** Offline fallback + optimistic UI; server is
   authoritative.
4. **AI transport → Hermes**, assumed authenticated and working on the host.

Still to confirm:
- **Environments** — a reachable dev backend with TLS for on-device testing
  (localhost only works in the simulator).
- **Coach history UX** for long histories (API caps the prompt at 50 msgs,
  stores all).

## 10. Backend prerequisites to close first

- **intervals.icu OAuth app**: register one at intervals.icu (Settings →
  Developer) to get `INTERVALS_CLIENT_ID`/`INTERVALS_CLIENT_SECRET` + the
  redirect URI, with scopes `WELLNESS:READ,ACTIVITY:READ,CALENDAR:WRITE`. This
  is the critical-path external dependency — without it, connect/sync/push
  return `INTERVALS_NOT_CONFIGURED` and the app stays on engine/mock fallback.
  (The athlete must also have linked Garmin→intervals.icu, outside the app.)
- Set **`APPLE_CLIENT_ID`** to the app's real Sign in with Apple client id.
- Generate **RS256 keys** + **`ENCRYPTION_KEY`**; run Postgres + Redis.
- Confirm **Hermes** is authenticated on the host (`hermes status`).
- Deploy a **reachable dev environment** with TLS for on-device builds.

---

## 11. Phased rollout

Garmin moves up — metrics depend on it, so the live Dashboard can't precede it.

| Phase | Deliverable | Unblocks |
|---|---|---|
| **0. Infra** | `APIConfig`, `TokenStore` (Keychain), `APIClient`, error model, DTOs, date decoding, ATS exception | everything |
| **1. Auth** | Apple→backend exchange, token storage + refresh, gate app on real auth | all authed calls |
| **2. Garmin connect + sync** | client OAuth via `ASWebAuthenticationSession`; **backend wellness+activity ingestion → `daily_metrics`** (§12) | real metrics |
| **3. Readiness + Metrics views** | `GET /readiness/today` + `/metrics/*` (data from Phase 2); engine fallback | live Dashboard |
| **4. Plan + Preferences + workout push** | sync frequency/split; load plans; **`POST /garmin/workouts/push`** (§12) | live Plan + Garmin workouts |
| **5. Coach (SSE)** | streaming LLM chat; history load/clear | real coach |
| **6. Polish** | strength gen, activities list, loading/offline/error states, pull-to-refresh | production-ready |

Phases 0–1 are pure infrastructure. Phase 2 is the linchpin (it produces the
metrics everything reads); phases 3 and 5 are the biggest "not static" wins
(real readiness from real Garmin data, real AI coach).

---

## 12. Backend additions for the Garmin-centric model

The current backend (per BACKEND_SPEC) ingests Garmin **activities** and
recomputes ATL/CTL (§9.2). The decisions above add two capabilities it does not
yet have. Both live in `app/services/garmin.py` + `app/jobs/tasks.py`, with the
external calls in `GarminClient` (today raising `GarminNotConfigured`).

**A. Wellness ingestion → `daily_metrics`.** Readiness needs HRV (+ baseline +
7-day trend), resting HR (+ baseline), sleep (duration, score, REM, deep, debt),
and ATL/CTL/weekly-change. Garmin supplies most via the Health API:
- HRV summary → `hrv`; **`hrv_baseline` + `hrv_trend`** are derived from the last
  7 stored days (so they populate after a short ramp-up; seed from Garmin's
  baseline if available).
- Sleep summary → `sleep_duration`, `sleep_score`, `rem_sleep`, `deep_sleep`;
  `sleep_debt` accumulated server-side.
- Daily summary → `resting_hr`; `resting_hr_baseline` from stored history.
- Activity training loads → `acute_load`/`chronic_load`/`weekly_load_change`
  (already in §9.2).

New work: a `garmin-wellness` fetch in `GarminClient`, a `assemble_daily_metrics`
service that merges wellness + computed baselines into an upsert on
`daily_metrics`, and an extension of the `garmin-sync` job. The
client-facing `POST /metrics/daily` stays (manual/debug + the contract the
engine reads); Garmin sync simply becomes another writer of that row.

**B. Workout push → Garmin Training API.** New endpoint
`POST /garmin/workouts/push` (and/or auto-push on plan generation) that maps a
`PlannedSession`/`PlannedDay` to a Garmin scheduled workout and calls the
Training/Workout API via `GarminClient.push_workout(...)`. Record the returned
Garmin workout id (consider a `garmin_workout_id` column on `weekly_plans` days
or a small `pushed_workouts` table for idempotency/unscheduling).

**C. OAuth + token lifecycle.** Implement the three stubbed `GarminClient`
methods (request token / exchange / fetch) plus `refresh-garmin-token` (§10)
against real endpoints once Developer Program credentials exist. Note Garmin's
newer Health API uses OAuth2 PKCE; reconcile with the §9 OAuth-1.0a description
when wiring (the encrypted-token storage and HMAC webhook code already in place
work for either).

These are spec changes — worth reflecting back into `BACKEND_SPEC.md` (§7.8/§9)
so the document stays the source of truth.

---

## Appendix — exact code touch-points

Verified against the current source. These are the precise edits per phase.
(The iOS app lives under `ios/` — paths like `Store/…`, `Services/…` below are
relative to `ios/NorthAx/`.)

**Phase 0 — infra (new files, no edits to existing):**
`ios/NorthAx/Networking/{APIConfig,TokenStore,APIClient,APIError,SSEClient}.swift`,
`ios/NorthAx/Networking/DTOs/*.swift`, and a `Repositories/` group. Add an ATS
exception for `localhost` in `Info.plist` for DEBUG.

**Phase 1 — auth:**
- `Services/AuthService.swift:20–53` `handleAppleSignIn` — capture
  `cred.identityToken` + `cred.authorizationCode` (not captured today), call
  `POST /auth/apple`, store tokens in Keychain, set `currentUser` from response.
- `Services/AuthService.swift:64–84` `restoreSession` — restore from Keychain
  tokens; refresh on launch instead of only checking Apple credential state.
- `Services/AuthService.swift:95–100` `signInAsDebugUser` — point at a backend
  dev token.
- `Views/Auth/SignInView.swift` — wire request scopes; surface `APIError`.
- `ContentView.swift:22` `store.configure(with:)` — trigger initial API loads.

**Phase 2 — Garmin connect + sync (foundational):**
- `Services/GarminService.swift:25–55` `connect()`/`syncActivities()` — replace
  `Task.sleep` + `mockActivities` with `POST /garmin/connect` +
  `ASWebAuthenticationSession` (scheme `northax`) + `GET /garmin/status` +
  `POST /garmin/sync`.
- Backend (§12.A): `GarminClient` wellness fetch + `assemble_daily_metrics` +
  `garmin-sync` job extension → writes `daily_metrics`.
- Consumer: `Settings/GarminConnectView.swift`.

**Phase 3 — readiness + metrics views:**
- `Store/AthleteStore.swift:99–101` `recalculate()` — call `GET /readiness/today`;
  map DTO → `DailyReadiness`; fall back to `ReadinessEngine` offline.
- `Store/AthleteStore.swift:33,55–60` `metrics` / `useFatiguedScenario` — replace
  the mock seed with `GET /metrics/daily` (data produced by Phase 2). Keep the
  fatigued toggle as a DEBUG-only local override.
- Consumers unchanged: `DashboardView.swift:65–114`, `MetricsView.swift:13–76`.

**Phase 4 — plan + preferences + workout push:**
- `Store/AthleteStore.swift:39–46,105–117` `trainingFrequency.didSet` /
  `regeneratePlan()` — `PATCH /preferences/frequency` then `GET /plan/weeks`
  instead of local `PlanEngine`.
- `Store/AthleteStore.swift:32` `muscleGroupSplit` — `PATCH /preferences/muscle-split`.
- `Store/AthleteStore.swift:30–31` `athleteName`/`enabledDomains` — back with
  `GET/PATCH /user/profile` + `/preferences/domains` (replaces UserDefaults).
- `Services/GarminService.swift:61` `pushPlannedSession` → `POST /garmin/workouts/push`
  (backend §12.B).
- Consumers unchanged: `PlanView.swift:73,102,160–181`,
  `Settings/*` (TrainingFrequencyView, MuscleGroupSplitView).

**Phase 5 — coach (SSE):**
- `Store/AthleteStore.swift:171–246` delete `respond(to:)` + `buildResponse(...)`;
  replace with `SSEClient` against `POST /ai/coach/message`, streaming into
  `messages`. Load `GET /ai/coach/history` on open; clear → `DELETE`.
- `Models/CoachMessage.swift` — add `role` mapping (`isCoach = role=="coach"`);
  `CoachMessage.opening`/`quickQuestions` can stay as client UI seeds.
- Consumer: `CoachView.swift:135–141` (send path) — stream deltas into the bubble.

**Phase 6 — strength + activities + polish:**
- `Store/AthleteStore.swift:121–135` `switchSession(...)` strength branch →
  `POST /ai/strength/generate` (currently `StrengthEngine` via
  `ActivitySwitcherView.swift:95`).
- New activities list view → `GET /activities` (replaces `garmin.syncedActivities`).
- Add `Loadable<T>` states across Dashboard/Plan/Metrics; pull-to-refresh.

---

*Companion docs: API reference in [`backend/docs/`](backend/docs/), backend
overview in [`backend/README.md`](backend/README.md), source spec in
[`BACKEND_SPEC.md`](BACKEND_SPEC.md).*
