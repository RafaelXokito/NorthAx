# Multi-source metrics — conflict resolution

When more than one integration reports the same metric (HRV, resting HR, sleep,
body weight), NorthAx must pick **one** value deterministically and be able to
explain the choice. This documents the model, the resolution rule, and the
rollout.

## Background (what's true today)

- **intervals.icu is an aggregator.** It ingests Garmin/Strava/Apple Health
  upstream and hands the backend one reconciled wellness record per day. Most
  cross-device de-duplication already happens outside our code.
- The real client-side ambiguity today is **intervals.icu (server) vs Apple
  HealthKit (on-device)**. Both can report HRV, resting HR, sleep, weight.
  Training load (CTL/ATL) is **intervals-only** — HealthKit has no model for it.
- Existing precedence was **coarse and hard-coded**: backend won entirely;
  HealthKit was a whole-object fallback used only when no server data existed and
  intervals wasn't connected (`AthleteStore.loadMetricsAndReadiness`).
- There was **no provenance** on metrics — a value's origin was opaque.

## Decisions

1. **Per-metric priority** (not a single global ranking). Authority is
   metric-specific: intervals is the only training-load source; a dedicated
   wearable may be the best HRV/sleep source; a scale is best for weight. A
   per-metric ranking collapses to "global" if every metric uses the same order,
   so it's strictly more capable at little cost.
2. **Resolve in two layers (hybrid).** The backend stores each *server-side*
   source's raw readings (`metric_readings`: intervals + manual) and resolves
   them per priority into `daily_metrics`, recording provenance. The client then
   merges *on-device* HealthKit on top, per the same priority. **HealthKit is
   never uploaded** — the "data stays on device" promise holds. A HealthKit-sourced
   value is device-local; everything else is consistent across devices.
3. **Config syncs across devices.** The per-metric priority persists locally in
   `UserDefaults` (offline cache) **and** to the backend via
   `user_preferences.metric_priority` (`PATCH /preferences/metric-priority`,
   included in the `GET`/`PUT` payloads). The server is authoritative on load.

## Model

```
MetricSource     = intervals | healthkit | manual          // extensible
MergeableMetric  = hrv | restingHR | sleep | bodyWeight     // load is intervals-only, excluded
MetricSourcePriority = { metric -> [MetricSource] }         // ordered, highest first
```

- Each `MergeableMetric` declares its **candidate sources** (e.g. `bodyWeight`
  excludes `intervals`, which doesn't carry weight). The UI only ranks
  candidates; the resolver only considers sources that actually have a value.
- Default order = candidates in `[intervals, healthkit, manual]` order, i.e.
  **intervals wins** — identical to today's behavior. Nothing changes until the
  user reorders.

## Resolution rule (per metric)

```
manual override  >  per-metric priority  >  (recency)
```

- Walk the metric's priority list; the **first source that has a value today
  wins**. A source that can't produce the metric is simply absent from the
  contest.
- **Never average** — an averaged HRV is a number no device measured.
- Recency is a *non-issue under a strict ordering* (no ties), so it's not
  implemented; it only matters once two sources can share a rank.
- `manual` is in the enum for forward-compatibility but has no client provider
  yet (manual entry is a backend zone — see Out of scope).

The merged object keeps **training load, baselines, and trends from the backend
base** (HealthKit can't produce them). HealthKit can only override *today's raw
reading* for HRV / resting HR / sleep duration / weight.

## Provenance

The resolved `TrainingMetrics` carries `provenance: [metric -> MetricSource]`,
recording which source won each mergeable metric. The Metrics detail modal shows
it ("Source: Apple Health") so the choice is transparent and debuggable.

## UI

Settings → Integrations → **Data Priority**: one row per mergeable metric with a
menu to choose the primary source among its candidates. Selecting a source moves
it to the front of that metric's list. Defaults preserve current behavior.

## Implemented

- **Per-source storage + server-side resolution.** `metric_readings` holds each
  server source's raw contribution per day; `assemble_daily_metrics` resolves them
  against `user_preferences.metric_priority` into `daily_metrics` + `metric_sources`
  provenance. Intervals sync and manual entry both write readings and re-resolve.
- **Manual entry** — `POST /metrics/manual` (lean, all-optional body) + a "Log
  Metrics" sheet on the Metrics tab. This is what makes the manual-vs-sync
  precedence real, resolved by priority instead of last-write-wins.
- **Client HealthKit merge** layered on top, using backend provenance so a
  server value that was itself manually entered competes as `manual`.

## Out of scope (deferred)

- **Uploading HealthKit to the server.** Would enable cross-device consistency of
  HealthKit-sourced values, but reverses the "data stays on device" promise —
  needs an explicit consent flow + copy change. Held pending sign-off.
- **Recency / confidence tie-breaks** (need per-source timestamps/quality).
```
