# NorthAx — Gaps & Roadmap

A living checklist of gaps between the two source documents
([`BACKEND_SPEC.md`](../BACKEND_SPEC.md), [`INTEGRATION.md`](../INTEGRATION.md))
and the implementation, with the suggested approach for each. Grouped by area;
ordered roughly by priority within each group.

Status: ✅ done · 🟡 partial · ❌ not started

---

## A. Documentation drift (docs no longer match reality)

The Garmin→intervals.icu pivot and the Swift rename left the source-of-truth
docs internally inconsistent.

- [ ] ❌ **`BACKEND_SPEC.md` §9** still describes Garmin OAuth 1.0a as primary.
  → Rewrite §9 with intervals.icu OAuth 2.0 first-class; keep Garmin only as a
  historical note.
- [ ] ❌ **§11 error codes** list `GARMIN_*`; code uses `INTERVALS_*`.
  → Rename `GARMIN_NOT_CONNECTED`/`GARMIN_SYNC_IN_PROGRESS` → `INTERVALS_*`
  (keep `ACTIVITY_GARMIN_IMMUTABLE` — the source enum value is still `garmin`).
- [ ] ❌ **§10 jobs table** lists `garmin-sync` / `refresh-garmin-token` and a
  Garmin webhook trigger. → Update to `intervals-sync` / `refresh-intervals-token`;
  drop the webhook (intervals.icu has no third-party push).
- [ ] ❌ **§7.8** still lists `POST /garmin/webhook`. → Remove.
- [ ] ❌ **Personal-API-key connect path** and the `auth_mode` column are
  undocumented. → Add §9.5 (API-key connect) + note in INTEGRATION.
- [ ] 🟡 **`INTEGRATION.md` appendix** references `GarminService.swift`,
  `GarminConnectView.swift`, `/garmin/*`, "Garmin Developer credentials".
  → Update to `IntervalsService.swift`, `IntervalsConnectView.swift`,
  `/intervals/*`, "intervals.icu OAuth app".

## B. Backend vs BACKEND_SPEC (functional)

- [x] ✅ **§8.5 AI contradiction guardrail** — `check_contradiction()` in
  `services/ai.py` logs when the AI narrative states an `N/100` that contradicts
  the deterministic score (±5 tolerance); called from the readiness flow. Unit-tested.
- [ ] 🟡 **§11 `422` vs `400`** — DTO-schema violations (e.g. `hrvTrend != 7`)
  return 400; spec wants 422 for semantic invalidity. → Move the `hrvTrend`
  length check to the route and raise 422, or map body-schema errors to 422.
- [ ] 🟡 **`DELETE /auth/session`** revokes all refresh tokens, not "the current"
  one (access token has no `jti`). → Accept the refresh token in the body, or
  document the all-sessions behavior.
- [ ] 🟡 **Data fidelity** — REM/deep sleep are 0 (intervals.icu omits them);
  HRV baseline/trend are derived; `weekly_load_change` is clamped. → Document
  derivations; use intervals.icu `hrvBaseline` hint when present.

## C. iOS vs INTEGRATION (Phase 6 + runtime config)

- [x] ✅ **Strength generation wired** — `ActivitySwitcherView` shows the engine
  session instantly, then refines via `store.generateStrengthSession`
  (`POST /ai/strength/generate`) with engine fallback.
- [ ] ❌ **ATS exception** — no `NSAppTransportSecurity`; DEBUG can't reach
  `http://localhost:8080`. → Add `NSAllowsLocalNetworking` (DEBUG) or use an HTTPS dev URL.
- [ ] ❌ **Phase 6 polish** — no `Loadable<T>` loading/empty/error states, no
  pull-to-refresh, no activities list view. → Per INTEGRATION §8/appendix.

## D. Cross-cutting / production-readiness

- [ ] 🔴 **AI layer non-functional** — Hermes auth fails (`Codex token refresh
  failed`); all AI paths return deterministic-only. → Re-auth Hermes **or** flip
  `services/ai.py` to the Anthropic SDK via `ANTHROPIC_API_KEY` (`pip install '.[api]'`).
  *(Needs a provider credential — owner action.)*
- [x] ✅ **API/integration tests** — `tests/test_api_integration.py` + `conftest.py`
  drive the real app via `httpx.ASGITransport` against Postgres: auth required,
  metrics→readiness, 404/409 envelopes, preferences→plan, 422 frequency overload,
  intervals status, activities. Skip cleanly without a DB (8 tests).
  *(Apple token exchange not covered — needs a real Apple identity token.)*
- [ ] 🟡 **No migrations** — `alembic` is a dep but there's no migrations dir;
  schema is `sql/schema.sql` + dev `create_all`. → `alembic init` + initial
  migration, or formally drop Alembic and own `schema.sql`.
- [ ] 🟡 **Secrets in env** — §5.8 wants a secrets manager; `ENCRYPTION_KEY` is
  in `.env`. → Document env as dev-only; wire a secrets manager for prod.
- [ ] 🟡 **Observability** — `SENTRY_DSN` unwired; minimal logging. → Init Sentry
  in `main.py`; structured request logging.
- [ ] 🟡 **Deployment / CI** — no CI; the `worker` container can't run the Hermes
  CLI. → GitHub Actions (lint + tests + spec validation); decide container AI transport.
- [ ] 🟡 **intervals.icu OAuth app** — only the personal-API-key path is usable.
  → Register an OAuth app for multi-user.

---

## Suggested order
1. Make AI real (provider cred) — core value. *(owner)*
2. API/integration tests — lock the verified end-to-end.
3. Reconcile the docs (intervals.icu first-class; error codes; appendix).
4. iOS runtime config + Phase 6 (ATS, strength wiring, loading states).
5. Migrations + observability + CI.
6. OAuth app + secrets manager.

## Changelog
- _2026-06-30_: doc created from the gap analysis.
- _2026-06-30_: implemented §8.5 contradiction guardrail (B), strength-generation
  wiring (C), and API integration tests (D #2). Backend: 30 unit + 8 integration
  tests pass; iOS type-checks.
