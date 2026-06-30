# NorthAx — Backend Specification

> **Meta-prompt.** This document is the single source of truth for implementing the NorthAx backend. Every entity, DTO, route, authorization rule, and AI interaction pattern is defined here. An implementation agent or developer should be able to build the complete backend from this document alone without referencing the iOS client code.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Technology Stack](#2-technology-stack)
3. [Authentication](#3-authentication)
4. [Authorization](#4-authorization)
5. [Database Schema](#5-database-schema)
6. [DTOs](#6-dtos)
7. [API Reference](#7-api-reference)
8. [AI Features](#8-ai-features)
9. [Garmin OAuth Proxy](#9-garmin-oauth-proxy)
10. [Background Jobs](#10-background-jobs)
11. [Error Handling](#11-error-handling)
12. [Rate Limiting](#12-rate-limiting)
13. [Environment Variables](#13-environment-variables)

---

## 1. Architecture Overview

```
iOS App
  │
  ├─ POST /auth/apple          ← Exchange Apple identity token → app JWT
  │
  ├─ /metrics/*                ← HRV, sleep, training load
  ├─ /readiness/*              ← Deterministic score + AI explanation
  ├─ /plan/*                   ← Weekly training plans
  ├─ /activities/*             ← Manual + Garmin-synced activities
  ├─ /preferences/*            ← Frequency, muscle split, domains
  ├─ /ai/*                     ← Coach chat, session suggestions (LLM)
  └─ /garmin/*                 ← OAuth proxy + webhook receiver
```

The backend has two layers:

- **Deterministic engine** — Readiness scoring (HRV/sleep/load algorithm), plan generation (greedy interleave), strength session assembly. These run server-side and mirror the client engine exactly. The client engines are the source of truth for algorithm logic; the backend must produce identical outputs given the same inputs.
- **AI explanation layer** — A large language model (Claude) wraps every deterministic output with a natural-language explanation, coaching note, and conversational interface. The AI never overrides the deterministic score; it only explains it.

---

## 2. Technology Stack

| Concern | Recommendation |
|---|---|
| Runtime | Node.js 20+ with TypeScript, or Python 3.12+ with FastAPI |
| Database | PostgreSQL 16 |
| Cache / queues | Redis 7 |
| Auth tokens | JWT (RS256, asymmetric keys) |
| AI provider | Anthropic Claude API (`claude-sonnet-4-6` default, `claude-haiku-4-5` for low-latency paths) |
| Garmin integration | Garmin Health API (server-side OAuth 2.0 — client secret **must never leave the server**) |
| File storage | Not required for v1 |
| Deployment | Containerised (Docker); any cloud provider |

---

## 3. Authentication

### 3.1 Sign in with Apple flow

```
Client                        Backend                      Apple
  │                              │                            │
  │── POST /auth/apple ─────────►│                            │
  │   { identityToken, authCode }│                            │
  │                              │── Verify JWT signature ───►│
  │                              │   (JWKS endpoint)          │
  │                              │◄── {sub, email, name} ─────│
  │                              │                            │
  │                              │  Upsert user row           │
  │                              │  Issue access + refresh JWT│
  │◄── { accessToken,            │                            │
  │      refreshToken,           │                            │
  │      user } ─────────────────│                            │
```

**`POST /auth/apple`**

Request body:
```json
{
  "identityToken": "<Apple JWT>",
  "authorizationCode": "<one-time code>",
  "fullName": { "givenName": "Rafael", "familyName": "Pereira" }
}
```

- Verify `identityToken` against Apple's JWKS (`https://appleid.apple.com/auth/keys`).
- The `sub` claim of the verified token is the stable Apple user ID — store it as `apple_id`.
- `fullName` is only sent by Apple on first sign-in; persist it on user creation and ignore it on subsequent calls.
- On success, upsert the user and return the token pair (see §6.1).

### 3.2 Token format

| Token | Algorithm | TTL | Claims |
|---|---|---|---|
| Access token | RS256 | 15 minutes | `sub` (userId), `iat`, `exp`, `type: "access"` |
| Refresh token | RS256 | 60 days | `sub` (userId), `iat`, `exp`, `type: "refresh"`, `jti` (UUID) |

Store refresh token `jti` values in a `refresh_tokens` table. On refresh, verify the `jti` exists and is not revoked; rotate by deleting the old row and inserting a new one.

**`POST /auth/refresh`**
```json
// Request
{ "refreshToken": "<token>" }

// Response
{ "accessToken": "<token>", "refreshToken": "<new rotated token>" }
```

**`DELETE /auth/session`** — Revoke the current refresh token (sign out).

**`DELETE /auth/account`** — Hard-delete the user and all associated rows (GDPR compliance).

### 3.3 Request authentication

Every protected endpoint requires:
```
Authorization: Bearer <accessToken>
```

Middleware extracts `sub` (userId) from the verified JWT and injects it into the request context. No route may access another user's data by any path.

---

## 4. Authorization

**Rule: a user may only read and write their own rows.**

Enforce this at two levels:

1. **Application layer** — Every query includes `WHERE user_id = $userId` from the JWT. Never accept a `userId` from the request body or URL for ownership — always use the JWT claim.
2. **Database layer** — Enable PostgreSQL Row-Level Security (RLS) on all user-data tables as a defence-in-depth backstop.

RLS policy template (apply to every table that has `user_id`):
```sql
ALTER TABLE <table> ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_isolation ON <table>
  USING (user_id = current_setting('app.current_user_id')::uuid);
```

Set `app.current_user_id` at the start of each database transaction from the verified JWT.

---

## 5. Database Schema

### 5.1 `users`
```sql
CREATE TABLE users (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  apple_id       TEXT UNIQUE NOT NULL,
  name           TEXT NOT NULL DEFAULT 'Athlete',
  email          TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 5.2 `refresh_tokens`
```sql
CREATE TABLE refresh_tokens (
  jti        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  issued_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked    BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX ON refresh_tokens(user_id);
```

### 5.3 `daily_metrics`
One row per user per calendar day. The morning reading that drives readiness.

```sql
CREATE TABLE daily_metrics (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date                 DATE NOT NULL,

  -- HRV (ms)
  hrv                  NUMERIC(6,2) NOT NULL,
  hrv_baseline         NUMERIC(6,2) NOT NULL,   -- 7-day rolling average at time of reading
  hrv_trend            NUMERIC(6,2)[] NOT NULL,  -- last 7 values, oldest→newest (length=7)

  -- Heart rate
  resting_hr           INTEGER NOT NULL,
  resting_hr_baseline  INTEGER NOT NULL,

  -- Sleep
  sleep_duration       NUMERIC(4,2) NOT NULL,    -- hours
  sleep_score          INTEGER NOT NULL CHECK (sleep_score BETWEEN 0 AND 100),
  rem_sleep            NUMERIC(4,2) NOT NULL,     -- hours
  deep_sleep           NUMERIC(4,2) NOT NULL,     -- hours
  sleep_debt           NUMERIC(4,2) NOT NULL,     -- cumulative hours shortfall

  -- Training load (Banister impulse-response model)
  acute_load           NUMERIC(6,2) NOT NULL,     -- 7-day ATL
  chronic_load         NUMERIC(6,2) NOT NULL,     -- 42-day CTL
  today_load           NUMERIC(6,2) NOT NULL DEFAULT 0,
  weekly_load_change   NUMERIC(5,4) NOT NULL,     -- fraction vs previous week

  -- Optional
  body_weight          NUMERIC(5,2),              -- kg

  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE(user_id, date)
);
CREATE INDEX ON daily_metrics(user_id, date DESC);
```

### 5.4 `user_preferences`
One row per user; upserted when preferences change.

```sql
CREATE TABLE user_preferences (
  user_id              UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,

  -- Enabled training domains (array of domain enum values)
  enabled_domains      TEXT[] NOT NULL DEFAULT ARRAY['Cycling','Strength'],

  -- Training frequency: JSON array of { domain: string, daysPerWeek: int }
  domain_frequencies   JSONB NOT NULL DEFAULT '[]',

  -- Muscle group split: JSON array of 7 DaySplit objects (index 0 = Monday)
  -- Each DaySplit: { muscleGroups: string[], isRestDay: boolean }
  muscle_group_split   JSONB NOT NULL DEFAULT '[]',

  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 5.5 `activities`

```sql
CREATE TYPE activity_source AS ENUM ('manual', 'garmin');

CREATE TABLE activities (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  external_id       TEXT,                         -- Garmin activity ID (null for manual)
  source            activity_source NOT NULL DEFAULT 'manual',

  name              TEXT NOT NULL,
  domain            TEXT NOT NULL,               -- TrainingDomain enum value
  start_time        TIMESTAMPTZ NOT NULL,
  duration_seconds  INTEGER NOT NULL,
  distance_meters   NUMERIC(10,2),
  elevation_gain    NUMERIC(8,2),
  avg_heart_rate    INTEGER,
  max_heart_rate    INTEGER,
  calories          INTEGER,
  training_load     NUMERIC(6,2),               -- TSS equivalent

  notes             TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE(user_id, source, external_id) WHERE external_id IS NOT NULL
);
CREATE INDEX ON activities(user_id, start_time DESC);
```

### 5.6 `weekly_plans`

```sql
CREATE TABLE weekly_plans (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  week_start  DATE NOT NULL,                    -- always a Monday

  -- JSON array of 7 PlannedDay objects
  -- PlannedDay: { date, isRest, session?: { domain, title, subtitle, duration, intensityLabel } }
  days        JSONB NOT NULL,

  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE(user_id, week_start)
);
CREATE INDEX ON weekly_plans(user_id, week_start);
```

### 5.7 `coach_messages`

```sql
CREATE TYPE message_role AS ENUM ('user', 'coach');

CREATE TABLE coach_messages (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role        message_role NOT NULL,
  content     TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON coach_messages(user_id, created_at DESC);
```

### 5.8 `garmin_connections`

```sql
CREATE TABLE garmin_connections (
  user_id          UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  garmin_user_id   TEXT NOT NULL,
  access_token     TEXT NOT NULL,       -- encrypted at rest
  refresh_token    TEXT NOT NULL,       -- encrypted at rest
  token_expires_at TIMESTAMPTZ NOT NULL,
  display_name     TEXT,
  last_sync_at     TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

> **Security:** Encrypt `access_token` and `refresh_token` at rest using AES-256-GCM with a key stored in your secrets manager (not in the database or environment variables).

---

## 6. DTOs

All dates are ISO 8601 strings. All numeric fields that are percentages or ratios are floating point (not multiplied by 100).

### 6.1 `AuthResponse`
```json
{
  "accessToken": "eyJ...",
  "refreshToken": "eyJ...",
  "user": {
    "id": "uuid",
    "name": "Rafael Pereira",
    "email": "rafael@example.com"
  }
}
```

### 6.2 `UserProfile`
```json
{
  "id": "uuid",
  "name": "Rafael Pereira",
  "email": "rafael@example.com",
  "createdAt": "2026-01-15T08:00:00Z"
}
```

### 6.3 `DailyMetricsInput` (POST body)
```json
{
  "date": "2026-06-29",
  "hrv": 58.0,
  "hrvBaseline": 54.0,
  "hrvTrend": [51, 49, 52, 54, 53, 56, 58],
  "restingHr": 46,
  "restingHrBaseline": 47,
  "sleepDuration": 7.5,
  "sleepScore": 84,
  "remSleep": 1.8,
  "deepSleep": 1.4,
  "sleepDebt": 0.3,
  "acuteLoad": 68.0,
  "chronicLoad": 72.0,
  "todayLoad": 0.0,
  "weeklyLoadChange": 0.08,
  "bodyWeight": 78.2
}
```

Validation:
- `date`: required, not in the future
- `hrv`: required, > 0
- `hrvTrend`: required, exactly 7 elements
- `sleepScore`: 0–100
- `acuteLoad`, `chronicLoad`: >= 0

### 6.4 `DailyReadinessResponse`
```json
{
  "date": "2026-06-29",
  "score": 82,
  "status": "High",
  "verdict": "Good day to train.",
  "explanation": "Your HRV is 7% above your baseline...",
  "coachingNote": "Good conditions for training...",
  "componentScores": {
    "hrv": 80,
    "sleep": 87,
    "load": 79,
    "recovery": 82
  },
  "suggestedSession": {
    "domain": "Cycling",
    "title": "Aerobic Endurance",
    "duration": 90,
    "intensityLabel": "Moderate",
    "intensityDescription": "65–75% FTP · Conversational pace throughout"
  },
  "keyInsights": [
    {
      "label": "HRV",
      "value": "58",
      "unit": "ms",
      "trend": "up",
      "explanation": "Above baseline",
      "context": "7% above your 54 ms average — strong nervous system recovery."
    }
  ],
  "aiExplanation": {
    "narrative": "...",
    "generatedAt": "2026-06-29T07:32:11Z",
    "model": "claude-haiku-4-5-20251001"
  }
}
```

`status` values: `"Peak"` | `"High"` | `"Moderate"` | `"Low"` | `"Rest Day"`
`trend` values: `"up"` | `"down"` | `"neutral"` | `"warning"`

### 6.5 `UserPreferences`
```json
{
  "enabledDomains": ["Cycling", "Strength", "Running"],
  "domainFrequencies": [
    { "domain": "Cycling",  "daysPerWeek": 3 },
    { "domain": "Strength", "daysPerWeek": 2 }
  ],
  "muscleGroupSplit": [
    { "muscleGroups": ["Chest", "Shoulders", "Triceps"], "isRestDay": false },
    { "muscleGroups": ["Back", "Biceps"],                "isRestDay": false },
    { "muscleGroups": ["Quads", "Hamstrings", "Glutes", "Calves"], "isRestDay": false },
    { "muscleGroups": [],                                "isRestDay": true  },
    { "muscleGroups": ["Chest", "Shoulders", "Triceps"], "isRestDay": false },
    { "muscleGroups": ["Back", "Biceps"],                "isRestDay": false },
    { "muscleGroups": [],                                "isRestDay": true  }
  ]
}
```

`muscleGroupSplit` is always a 7-element array, index 0 = Monday, 6 = Sunday.

Valid `domain` values: `"Cycling"` | `"Running"` | `"Strength"` | `"Swimming"` | `"Triathlon"` | `"Mobility"` | `"Recovery"`

Valid `muscleGroups` values: `"Chest"` | `"Back"` | `"Shoulders"` | `"Biceps"` | `"Triceps"` | `"Quads"` | `"Hamstrings"` | `"Glutes"` | `"Calves"` | `"Core"`

### 6.6 `Activity`
```json
{
  "id": "uuid",
  "externalId": "garmin-activity-1234",
  "source": "garmin",
  "name": "Morning Ride",
  "domain": "Cycling",
  "startTime": "2026-06-28T07:15:00Z",
  "durationSeconds": 4500,
  "distanceMeters": 32000,
  "elevationGain": 380,
  "avgHeartRate": 142,
  "maxHeartRate": 168,
  "calories": 820,
  "trainingLoad": 72.0,
  "notes": null,
  "createdAt": "2026-06-28T09:00:00Z"
}
```

### 6.7 `WeeklyPlan`
```json
{
  "id": "uuid",
  "weekStart": "2026-06-29",
  "weekLabel": "Jun 29 – Jul 5",
  "isCurrentWeek": true,
  "days": [
    {
      "date": "2026-06-29",
      "weekdayShort": "Mon",
      "dayNumber": "29",
      "isRest": false,
      "isToday": true,
      "isPast": false,
      "session": {
        "domain": "Cycling",
        "title": "Zone 3 Intervals",
        "subtitle": "70–85% FTP · 5×8 min efforts",
        "duration": 75,
        "intensityLabel": "Threshold"
      }
    }
  ],
  "generatedAt": "2026-06-29T06:00:00Z"
}
```

### 6.8 `CoachMessage`
```json
{
  "id": "uuid",
  "role": "coach",
  "content": "Based on your data...",
  "createdAt": "2026-06-29T08:00:00Z"
}
```

### 6.9 `CoachMessageRequest`
```json
{
  "content": "Should I train hard today?"
}
```

### 6.10 `StrengthSessionResponse`
```json
{
  "muscleGroups": ["Chest", "Shoulders", "Triceps"],
  "title": "Push Day",
  "intensityLabel": "Moderate",
  "duration": 60,
  "rationale": "Based on your readiness score of 74/100...",
  "recoveryWarnings": ["Chest was last trained 46 hours ago — approaching minimum recovery window."],
  "exercises": [
    {
      "name": "Bench Press",
      "muscleGroup": "Chest",
      "sets": 4,
      "repsRange": "8–12",
      "rest": "90 sec",
      "notes": "Control the eccentric phase"
    }
  ]
}
```

### 6.11 `GarminStatus`
```json
{
  "connected": true,
  "displayName": "Rafael Pereira",
  "lastSyncAt": "2026-06-29T06:45:00Z"
}
```

### 6.12 `PaginatedActivities`
```json
{
  "items": [ /* Activity[] */ ],
  "total": 142,
  "limit": 20,
  "offset": 0,
  "hasMore": true
}
```

---

## 7. API Reference

Base URL: `https://api.northax.app/v1`

All protected routes require `Authorization: Bearer <accessToken>`.

### 7.1 Auth

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/auth/apple` | None | Sign in with Apple |
| POST | `/auth/refresh` | None | Rotate refresh token |
| DELETE | `/auth/session` | Bearer | Sign out (revoke refresh token) |
| DELETE | `/auth/account` | Bearer | Delete account and all data |

### 7.2 User Profile

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/user/profile` | Bearer | Get own profile |
| PATCH | `/user/profile` | Bearer | Update name |

**`PATCH /user/profile`** body: `{ "name": "Rafael" }`

### 7.3 Metrics

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/metrics/daily` | Bearer | Submit today's morning metrics |
| GET | `/metrics/daily` | Bearer | Get today's metrics |
| GET | `/metrics/daily/:date` | Bearer | Get metrics for a specific date (YYYY-MM-DD) |
| GET | `/metrics/history` | Bearer | Get historical metrics |

**`GET /metrics/history`** query params:
- `from` — ISO date string (default: 42 days ago)
- `to` — ISO date string (default: today)
- `limit` — max 90

If today's metrics have not been submitted, `GET /metrics/daily` returns `404`.

### 7.4 Readiness

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/readiness/today` | Bearer | Get today's readiness score + AI explanation |
| GET | `/readiness/:date` | Bearer | Get readiness for a specific date |

Readiness is computed server-side from the daily metrics row using the deterministic engine. The AI explanation is generated once and cached; re-requesting the same date returns the cached result.

If no daily metrics exist for the requested date, returns `404`.

### 7.5 Preferences

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/preferences` | Bearer | Get all preferences |
| PUT | `/preferences` | Bearer | Replace all preferences |
| PATCH | `/preferences/domains` | Bearer | Update enabled domains only |
| PATCH | `/preferences/frequency` | Bearer | Update domain frequencies only |
| PATCH | `/preferences/muscle-split` | Bearer | Update muscle group split only |

When frequency or split is updated via PATCH, the backend **automatically regenerates forward weekly plans** (see §7.6).

Validation for `PATCH /preferences/frequency`:
- `domainFrequencies[].daysPerWeek`: 0–6
- `totalTrainingDays` (sum of all daysPerWeek): must not exceed 6

### 7.6 Training Plan

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/plan/weeks` | Bearer | Get list of weekly plans |
| GET | `/plan/week/:weekStart` | Bearer | Get one week (YYYY-MM-DD, must be a Monday) |
| POST | `/plan/generate` | Bearer | Trigger plan regeneration |
| PATCH | `/plan/week/:weekStart/day/:date` | Bearer | Override or clear one day |

**`GET /plan/weeks`** query params:
- `from` — ISO date string (default: current Monday)
- `weeks` — number of weeks to return (default: 4, max: 12)

**`POST /plan/generate`** — Generates 4 weeks of plans from the current Monday using the user's current preferences. Overwrites existing future plans. Returns the generated plans array.

**`PATCH /plan/week/:weekStart/day/:date`** body:
```json
{
  "session": {                  // null to mark as rest day
    "domain": "Strength",
    "title": "Push Day",
    "subtitle": "Gym · Per your weekly split",
    "duration": 60,
    "intensityLabel": "Moderate"
  }
}
```

### 7.7 Activities

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/activities` | Bearer | List activities (paginated) |
| POST | `/activities` | Bearer | Log a manual activity |
| GET | `/activities/:id` | Bearer | Get a specific activity |
| PATCH | `/activities/:id` | Bearer | Update a manual activity |
| DELETE | `/activities/:id` | Bearer | Delete a manual activity |

**`GET /activities`** query params:
- `limit` — default 20, max 100
- `offset` — default 0
- `domain` — filter by domain
- `source` — `"manual"` | `"garmin"`
- `from`, `to` — ISO date range

Deleting a Garmin-sourced activity returns `403` — Garmin activities can only be removed by disconnecting the integration.

### 7.8 Garmin

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/garmin/status` | Bearer | Get connection state |
| POST | `/garmin/connect` | Bearer | Begin OAuth flow — returns authorization URL |
| GET | `/garmin/callback` | None | OAuth redirect handler (server-side only) |
| POST | `/garmin/sync` | Bearer | Trigger manual activity sync |
| DELETE | `/garmin/disconnect` | Bearer | Disconnect and delete tokens |
| POST | `/garmin/webhook` | HMAC | Receive push notifications from Garmin |

See §9 for the full Garmin OAuth proxy implementation.

### 7.9 AI — Coach

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/ai/coach/message` | Bearer | Send a message, receive a streaming response |
| GET | `/ai/coach/history` | Bearer | Get recent conversation history |
| DELETE | `/ai/coach/history` | Bearer | Clear conversation history |

**`POST /ai/coach/message`** — Streams the response using Server-Sent Events (SSE). See §8.2 for the full prompt contract.

**`GET /ai/coach/history`** query params:
- `limit` — default 50, max 200

### 7.10 AI — Session & Strength

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/ai/session/suggest` | Bearer | AI-adjusted session suggestion for today |
| POST | `/ai/strength/generate` | Bearer | Generate a strength workout |

**`POST /ai/strength/generate`** body:
```json
{
  "muscleGroups": ["Chest", "Shoulders", "Triceps"],
  "readinessScore": 74,
  "recentActivityIds": ["uuid1", "uuid2"]
}
```

---

## 8. AI Features

All AI calls use the Anthropic Claude API. The deterministic engines always run first. AI is called after to add language, context, and nuance. The AI must never contradict the deterministic score.

### 8.1 Readiness Explanation

**When:** Triggered once per day when `GET /readiness/today` is first requested after today's metrics have been submitted. The result is cached in the `daily_metrics` row (`ai_explanation` JSONB column).

**Model:** `claude-haiku-4-5-20251001` (low latency, this runs on every app open)

**System prompt:**
```
You are the NorthAx AI coach. Your role is to explain an athlete's daily readiness
in plain, direct language. You never invent data — you only interpret the numbers
provided. You are confident, concise, and science-literate. Maximum 3 sentences.
Do not greet the user. Do not use bullet points. Start with the most important signal.
```

**User message template:**
```
Readiness score: {{score}}/100 ({{status}})
HRV: {{hrv}} ms (baseline {{hrvBaseline}} ms, change {{hrvChangePct}}%)
Sleep: {{sleepDuration}} hrs, score {{sleepScore}}/100, sleep debt {{sleepDebt}} hrs
Training balance (TSB): {{tsb}} (ATL {{acuteLoad}}, CTL {{chronicLoad}})
Resting HR: {{restingHr}} bpm ({{restingHrDelta}} vs baseline)

Explain why this athlete's readiness is {{status}} today.
```

**Response stored as:**
```json
{
  "narrative": "...",
  "generatedAt": "2026-06-29T07:32:11Z",
  "model": "claude-haiku-4-5-20251001"
}
```

### 8.2 Coach Chat

**When:** User sends a message via `POST /ai/coach/message`. Response streams via SSE.

**Model:** `claude-sonnet-4-6`

**Context assembly (built fresh per request):**

1. Fetch the user's last 50 `coach_messages` rows (ordered oldest→newest).
2. Fetch today's readiness summary (score, status, HRV change, sleep duration, TSB).
3. Fetch the last 5 activities from the database.
4. Fetch the current week's plan.

**System prompt:**
```
You are the NorthAx AI coach — a calm, direct, science-backed athletic coach
embedded in a training OS. You have access to the athlete's real biometric data
and training history.

Athlete: {{athleteName}}
Today's readiness: {{score}}/100 ({{status}})
HRV: {{hrv}} ms ({{hrvChangePct}}% vs baseline)
Sleep last night: {{sleepDuration}} hrs (score {{sleepScore}}/100)
Training balance (TSB): {{tsb}}
Recent activities: {{recentActivitiesSummary}}
This week's plan: {{weekPlanSummary}}

Rules:
- Be direct. Answer in 2–4 sentences unless the question requires more detail.
- Never invent biometric data. Only reference numbers provided above.
- If the user asks something outside your data, say so honestly.
- Recommend specific, actionable decisions — not generic advice.
- Never use bullet points in a conversational reply.
- Never start a sentence with "I".
```

**SSE stream format:**
```
event: delta
data: {"text": "Based on your..."}

event: delta
data: {"text": " HRV sitting 7%..."}

event: done
data: {"messageId": "uuid", "fullContent": "Based on your HRV sitting 7%..."}
```

On `done`, the backend persists the full response to `coach_messages`.

**`GET /ai/coach/history`** returns messages in chronological order (oldest first) to render in the chat view.

### 8.3 Session Suggestion

**When:** `GET /ai/session/suggest` is called. The deterministic engine provides the base recommendation; the AI adds a short justification sentence.

**Model:** `claude-haiku-4-5-20251001`

**System prompt:**
```
You are a terse athletic coach. Given the athlete's biometrics and the deterministic
session recommendation, write one sentence (max 20 words) that explains why this
specific session was chosen for today. Do not repeat the session name.
```

**User message:**
```
Readiness: {{score}}/100. Suggested: {{sessionTitle}} ({{intensityLabel}}, {{duration}} min).
HRV change: {{hrvChangePct}}%. Sleep: {{sleepDuration}} hrs. TSB: {{tsb}}.
Why is this the right session today?
```

**Response merged into `DailyReadinessResponse.suggestedSession`:**
```json
{
  "domain": "Cycling",
  "title": "Aerobic Endurance",
  "duration": 90,
  "intensityLabel": "Moderate",
  "intensityDescription": "65–75% FTP · Conversational pace throughout",
  "aiRationale": "Your balanced load and good HRV make this the ideal window for sustained aerobic work."
}
```

### 8.4 Strength Session Generation

**When:** `POST /ai/strength/generate`. The deterministic `StrengthEngine` builds the exercise list; the AI adds a rationale paragraph and flags any recovery warnings in natural language.

**Model:** `claude-haiku-4-5-20251001`

**System prompt:**
```
You are a strength and conditioning coach. Given a workout plan and the athlete's
current readiness, write:
1. A one-paragraph rationale (3–4 sentences) explaining the session design.
2. Any recovery warnings as short, direct sentences. If none, return an empty array.
Be specific about muscle groups and loading principles. No generic fitness advice.
```

**User message:**
```
Today's readiness: {{score}}/100.
Muscle groups: {{muscleGroups}}.
Exercises:
{{exerciseList}}
Recent strength activities: {{recentStrengthSummary}}
Hours since last worked each group: {{recoveryHoursMap}}
```

**Response structure** — The AI response augments the deterministic output:
```json
{
  "rationale": "...",
  "recoveryWarnings": ["Chest was trained 46 hours ago, below the 60-hour minimum."]
}
```

These fields are merged into the `StrengthSessionResponse` DTO (§6.10).

### 8.5 AI Guardrails

- All AI responses are persisted before being returned. A failed AI call does not fail the overall request — the deterministic result is returned without an `aiExplanation` field.
- Implement a 5-second timeout on all AI calls for the `haiku` model, 15 seconds for `sonnet`.
- If the AI returns content that contains numeric values that contradict the deterministic score (e.g., says "readiness is 90" when the score is 42), log it for review but still return the response — do not block on this.
- Cap coach conversation history sent to the model at 50 messages. Older messages are stored in the database but not included in the prompt.

---

## 9. Garmin OAuth Proxy

The Garmin Health API uses OAuth 1.0a. The client secret **must never be in the iOS app**.

### 9.1 Connect flow

```
iOS App                     NorthAx Backend              Garmin
  │                              │                          │
  │── POST /garmin/connect ─────►│                          │
  │                              │── Request token ────────►│
  │                              │◄── oauth_token ──────────│
  │◄── { authorizationUrl } ─────│                          │
  │                              │                          │
  │  (user opens Safari/WebView) │                          │
  │  User authorizes on Garmin's UI                         │
  │                              │◄── callback?oauth_token  │
  │                              │    &oauth_verifier ──────│
  │                              │── Exchange for           │
  │                              │   access token ─────────►│
  │                              │◄── access_token ─────────│
  │                              │   access_token_secret    │
  │                              │                          │
  │                              │  Store encrypted tokens  │
  │                              │  Trigger initial sync    │
  │◄── { connected: true } ──────│                          │
```

**`POST /garmin/connect`** — Generates the request token and returns:
```json
{
  "authorizationUrl": "https://connect.garmin.com/oauthConfirm?oauth_token=..."
}
```

**`GET /garmin/callback`** — Handles the redirect from Garmin. After storing tokens, redirects the user back to the app via a universal link: `northax://garmin/connected`.

### 9.2 Sync

On manual sync (`POST /garmin/sync`) or webhook notification, the backend:
1. Fetches activities from the Garmin Health API for the last 30 days (or since `last_sync_at`).
2. Upserts each activity into the `activities` table with `source = 'garmin'`.
3. Recomputes `acute_load` and `chronic_load` from all synced activity `training_load` values and updates today's `daily_metrics` row.
4. Updates `last_sync_at` in `garmin_connections`.

**`POST /garmin/webhook`** — Receives Garmin push notifications. Validate the HMAC-SHA1 signature using the consumer secret before processing.

---

## 10. Background Jobs

Use a Redis-backed job queue (e.g., BullMQ, Celery, or similar).

| Job | Trigger | Action |
|---|---|---|
| `generate-plans` | On user creation; on `PUT /preferences` (frequency or split changed) | Run plan generation for 4 weeks from current Monday; upsert into `weekly_plans` |
| `garmin-sync` | Daily at 06:00 user-local-time; on Garmin webhook; on manual request | Fetch and upsert Garmin activities |
| `compute-readiness` | Daily at 07:00 user-local-time (if metrics exist) | Run readiness engine + trigger AI explanation generation; cache result |
| `prune-coach-history` | Weekly | Delete `coach_messages` older than 180 days |
| `refresh-garmin-token` | 1 hour before `token_expires_at` | Refresh OAuth token; update encrypted stored tokens |

---

## 11. Error Handling

All errors return a consistent JSON body:

```json
{
  "error": {
    "code": "METRICS_NOT_FOUND",
    "message": "No metrics found for 2026-06-29.",
    "status": 404
  }
}
```

| HTTP Status | When |
|---|---|
| 400 | Validation failure (malformed body, invalid enum value, constraint violation) |
| 401 | Missing or expired access token |
| 403 | Valid token but accessing another user's resource; deleting a Garmin activity |
| 404 | Resource does not exist for the authenticated user |
| 409 | Unique constraint conflict (e.g., submitting metrics for a date that already exists — client should use PATCH) |
| 422 | Semantically invalid data (e.g., `hrvTrend` with != 7 elements) |
| 429 | Rate limit exceeded |
| 503 | AI provider unavailable — deterministic result returned without `aiExplanation` |

Error codes (machine-readable `code` field):

```
AUTH_INVALID_APPLE_TOKEN
AUTH_TOKEN_EXPIRED
AUTH_TOKEN_REVOKED
METRICS_NOT_FOUND
METRICS_ALREADY_EXISTS
PREFERENCES_INVALID_FREQUENCY   (totalTrainingDays > 6)
PREFERENCES_INVALID_SPLIT        (muscleGroupSplit.length != 7)
ACTIVITY_NOT_FOUND
ACTIVITY_GARMIN_IMMUTABLE
GARMIN_NOT_CONNECTED
GARMIN_SYNC_IN_PROGRESS
AI_UNAVAILABLE
PLAN_WEEK_NOT_FOUND
```

---

## 12. Rate Limiting

Applied per `userId` (authenticated) or per IP (unauthenticated).

| Endpoint group | Limit |
|---|---|
| `POST /auth/apple` | 10 requests / minute per IP |
| `POST /auth/refresh` | 20 requests / minute per IP |
| `POST /ai/coach/message` | 30 requests / hour per user |
| `POST /ai/strength/generate` | 20 requests / hour per user |
| `GET /ai/*` (non-streaming) | 60 requests / hour per user |
| All other authenticated routes | 300 requests / minute per user |

Return `429 Too Many Requests` with header `Retry-After: <seconds>`.

---

## 13. Environment Variables

```env
# Server
PORT=8080
NODE_ENV=production

# Database
DATABASE_URL=postgresql://user:pass@host:5432/northax

# Redis
REDIS_URL=redis://host:6379

# JWT (RS256 — generate with openssl)
JWT_PRIVATE_KEY=<base64-encoded PEM>
JWT_PUBLIC_KEY=<base64-encoded PEM>

# Anthropic
ANTHROPIC_API_KEY=sk-ant-...

# Garmin Health API
GARMIN_CONSUMER_KEY=...
GARMIN_CONSUMER_SECRET=...          # Never expose to clients
GARMIN_CALLBACK_URL=https://api.northax.app/v1/garmin/callback
GARMIN_WEBHOOK_SECRET=...

# Token encryption (for Garmin OAuth tokens at rest)
ENCRYPTION_KEY=<32-byte hex string>

# App deep link
APP_SCHEME=northax://

# Optional
SENTRY_DSN=...
LOG_LEVEL=info
```

---

## Appendix A — Readiness Scoring Algorithm

The deterministic engine must be implemented identically to the iOS `ReadinessEngine.swift`. Reference values:

**HRV score** (base 70):
```
deviation = (hrv - hrvBaseline) / hrvBaseline
score = deviation >= 0 ? 70 + deviation × 150 : 70 + deviation × 220
clamped to [0, 100]
```

**Sleep score:**
```
durationScore:
  >= 8 hrs → 100
  7–8 hrs  → 90
  6–7 hrs  → 65
  5–6 hrs  → 40
  < 5 hrs  → 20
sleepScore = (durationScore + sleepScoreInput) / 2
```

**Load score (TSB = CTL − ATL):**
```
TSB >= 20         → 58   (too fresh / detrained)
5 ≤ TSB < 20      → 95
-5 ≤ TSB < 5      → 100  (optimal window)
-15 ≤ TSB < -5    → 82
-25 ≤ TSB < -15   → 62
-35 ≤ TSB < -25   → 42
TSB < -35         → 22
```

**Total readiness score:**
```
total = HRVscore × 0.35 + sleepScore × 0.35 + loadScore × 0.30
```

**Status thresholds:**
```
85–100 → Peak
70–84  → High
55–69  → Moderate
35–54  → Low
0–34   → Rest Day
```

---

## Appendix B — Plan Generation Algorithm

Reference: iOS `PlanEngine.swift`. Replicate exactly.

**Rest day positions** (index 0 = Monday):
```
7 rest days → all
6 rest days → [1,2,3,4,5,6]
5 rest days → [1,2,4,5,6]
4 rest days → [1,3,5,6]
3 rest days → [1,4,6]
2 rest days → [3,6]
1 rest day  → [6]
0 rest days → []
```

**Session queue (greedy interleaving):**
Build a remaining-count table from `domainFrequencies`. At each step, pick the domain with the highest remaining count that differs from the previously scheduled domain. If all remaining domains are the same as the last, pick any. This prevents back-to-back same-sport days.

**Session variants per domain per slot (`slot = weekday index 0–6`):**

| Domain | slot % n | Title | Duration | Intensity |
|---|---|---|---|---|
| Cycling | 0 | Zone 3 Intervals | 75 | Threshold |
| Cycling | 1 | Aerobic Endurance | 90 | Moderate |
| Cycling | 2 | Easy Recovery Ride | 60 | Easy |
| Running | 0 | Easy Run | 45 | Easy |
| Running | 1 | Tempo Run | 40 | Hard |
| Running | 2 | Long Run | 70 | Easy |
| Swimming | 0 | Interval Set | 55 | Hard |
| Swimming | 1 | Technique Session | 45 | Moderate |
| Strength | any | Per muscle split | 60 | Moderate |
| Triathlon | any | Brick Session | 90 | Moderate |
| Mobility | any | Mobility Flow | 40 | Easy |
| Recovery | any | Active Recovery | 25 | Very Easy |

---

*Last updated: 2026-06-29. Maintained alongside `NorthAx/NorthAx/` iOS source.*
