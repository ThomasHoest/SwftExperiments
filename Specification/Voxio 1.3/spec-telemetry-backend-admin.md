# Telemetry Backend & Admin Site Specification — Voxio 1.3
**Version:** 1.1
**Status:** Draft
**Date:** 2026-05-04
**Platform:** Web — Next.js 15 hybrid app on Azure Static Web Apps (Standard plan)
**References:** VoxioSpecification-1.3.md (Feature 1, Flow A — E-35, US-53–55, A-1–A-6), research-telemetry-backend.md, VoxioSpecification-1.1.md (format reference), CLAUDE.md

**Amendment history**

| Version | Date | Summary |
|---|---|---|
| 1.0 | 2026-05-04 | Initial draft. Defines the telemetry ingest backend, admin labelling site, and database schema that consume the iOS Flow A uploads specified in VoxioSpecification-1.3.md. |
| 1.1 | 2026-05-04 | Architect review (ADR-telemetry-backend.md). Two items revised: (1) keep-alive ping changed from GitHub Actions cron to UptimeRobot free tier to stay within cost ceiling; (2) Neon region selection promoted from open question to blocking pre-provisioning prerequisite. |

---

## Introduction

The Voxio iOS app's Flow A (Feature 1, Voice Model Improvement) uploads anonymised parse-outcome events in batches to a backend so the team can review, label, and use them to retrain the `NLModel` shipped in future app releases. The iOS-side behaviour is fully specified in `VoxioSpecification-1.3.md`. **This document specifies the backend and admin site that receive those uploads.** Neither component exists yet.

The system has three concerns:

1. **Telemetry ingest API** — accepts authenticated batch uploads from the iOS app, writes events to a Postgres database, and supports per-`deviceId` GDPR deletion.
2. **Admin web UI** — gives the Voxio team an authenticated browser interface to filter, view, and label events, export labelled events as CSV for retraining, and trigger GDPR deletion.
3. **Operations** — keep-alive ping, CI/CD pipeline, and environment configuration that keep the system running reliably at near-zero cost.

The whole system is one Next.js 15 hybrid app deployed to a single Azure Static Web Apps instance. There is no separate backend service. Admin authentication is handled entirely by SWA's built-in GitHub OAuth; the application has zero auth code. Database access is via the `@neondatabase/serverless` driver against a free-tier Neon Postgres project. The iOS app authenticates ingest requests with a static `X-Api-Key` header stored in its Keychain.

This spec does not change any iOS behaviour. The iOS data model, anonymisation rules, consent flow, upload schedule, and deletion request flow are specified in VoxioSpecification-1.3.md and are referenced — not redefined — here.

### What is in scope

- HTTP API contract for telemetry ingest, GDPR deletion, and health check
- Database schema (Postgres tables, indexes, cascade behaviour)
- Admin site screens: events list, event detail, labelling, export, stats, deletion
- Admin authentication and role configuration via Azure SWA built-in GitHub OAuth
- Keep-alive ping configuration
- CI/CD pipeline expectations (lint → unit tests → build → deploy → E2E)
- Non-functional requirements (latency, cost ceiling, GDPR compliance)

### What is NOT in scope

- iOS-side telemetry collection, anonymisation, buffering, upload scheduling, or consent UI — all in VoxioSpecification-1.3.md
- The `NLModel` retraining pipeline that consumes the exported CSV — handled offline by the team after export
- Multi-tenant or per-customer data partitioning — single-tenant only
- Rich analytics, A/B testing dashboards, or BI tooling
- Public-facing site, marketing pages, or non-admin users
- Any over-the-air model distribution — model updates ship in App Store releases per VoxioSpecification-1.3.md
- Audio storage or replay — telemetry is text only by privacy guarantee

---

## Technical Context

| Decision | Choice | Rationale |
|---|---|---|
| Hosting | Azure Static Web Apps Standard plan (~$9/month) running a single Next.js 15 hybrid app | Standard plan is required for custom auth roles (`admin`); the same SWA instance also serves the API Route Handlers via the managed App Service backend. One service, one deployment, one bill. |
| Framework | Next.js 15 in hybrid mode (`output: 'standalone'`), Route Handlers under `app/api/*/route.ts` for the API surface | Confirmed in Microsoft's official SWA + Next.js tutorial. Avoids a separate Azure Functions project. |
| Admin authentication | SWA built-in GitHub OAuth, Standard-plan custom `admin` role assigned to specific GitHub usernames via the portal Role Management blade | Zero application auth code. Sign-in via `/.auth/login/github`. Route restriction via `staticwebapp.config.json` rule `"allowedRoles": ["admin"]`. NextAuth.js v5 is known broken on SWA (issues #1524, #12547) — eliminated. |
| Admin route protection | Single rule in `staticwebapp.config.json`: `{ "route": "/admin/*", "allowedRoles": ["admin"] }` and a parallel rule for admin-only API routes (e.g. `/api/admin/*`) | Declarative; cannot be bypassed by application bugs. Anonymous and `authenticated` (signed-in non-admin) users receive 401/403 from the SWA runtime before any handler runs. |
| Database | Neon serverless Postgres, free tier (0.5 GB storage, 100 CU-hours/month, scale-to-zero) | Only option with a genuine free tier at indie volumes. SQL makes filtering, labelling, and CSV export trivial. ~5 million events fit in 0.5 GB at ~100 bytes/event. |
| Database driver | `@neondatabase/serverless` (HTTP-based, edge-compatible) accessed from Next.js Route Handlers | No connection pooler needed; works in the SWA-managed App Service runtime. Connection string in `DATABASE_URL` env var. |
| Database region | Must match SWA deployment region: `aws-eu-central-1` if SWA in West Europe; `aws-us-east-1` if SWA in East US | **Blocking pre-provisioning prerequisite.** The Neon project region cannot be changed after creation without deleting the database and losing all data. The SWA region must be confirmed by the engineering lead before any infrastructure is provisioned. |
| iOS → backend authentication | Static `X-Api-Key` HTTP header, validated in the Route Handler against the `TELEMETRY_API_KEY` environment variable | Anonymised non-PII telemetry — App Attest is overkill. Key is generated via `openssl rand -hex 32`. iOS stores it in Keychain. Rotation = update env var + ship app release. |
| Per-device rate limiting | At ingest time, reject more than 1 batch per `deviceId` per 60 seconds with HTTP 429 | Mitigates worst-case key extraction from the iOS binary. Tracked in-memory or via a `last_upload_at` column on a `devices` table. |
| GDPR deletion | `DELETE /api/telemetry/{deviceId}` cascades to all `events` and `labels` rows for that device. Schema enforces this via `ON DELETE CASCADE`. | Required by the iOS-side US-53 / T-3508 deletion request. Backend deletion must be terminal — not soft-delete. |
| CI/CD | GitHub Actions, following the TheCheapPowerCompany repo pattern: lint → vitest unit tests → `next build` → deploy via `Azure/static-web-apps-deploy@v1` → Playwright E2E against the deployed preview | Established team pattern. Pull requests deploy to ephemeral preview environments (Standard plan feature). |
| Cold-start mitigation | UptimeRobot free tier monitor hitting `GET /api/health` every 5 minutes | UptimeRobot supports up to 50 monitors at 5-minute intervals on the free plan — no GitHub Actions minutes consumed. A GitHub Actions cron at 5-minute intervals would run ~8,640 times/month (~4,320 billed minutes on a private repo), exceeding the 2,000-minute free tier and producing ~$18/month overage. UptimeRobot is the correct tool. |
| Logging | Application-level structured `console.log` (collected by SWA App Insights integration if enabled) | Sufficient for an internal tool. No external log aggregator required at this scale. |
| Secrets | All secrets (DB URL, telemetry API key, future signing keys) live in SWA Application Settings (env vars). Never in source. | SWA env vars are encrypted at rest and only injected into the managed runtime. |

---

## Goals

- The iOS app can upload a batch of up to 100 events with a single authenticated POST and receive a 2xx response within 5 seconds on a warm backend.
- An authenticated admin can filter, view, label, and export events through a browser without any local tooling.
- A user-initiated GDPR deletion request from the iOS app permanently removes all of that device's events and labels from the database.
- The backend stores no PII: it accepts only the anonymised event schema specified in VoxioSpecification-1.3.md A-1.
- Total monthly hosting cost stays at or below $10 USD at projected indie volumes (≤ 100k events/month, ≤ 5 admins).
- A failed deployment never takes the API down — Azure SWA preview environments and atomic blue/green deploys handle this automatically.
- Admin route protection is enforced by configuration, not by application code, so a code bug cannot leak admin functionality.
- The labelling workflow produces a CSV file in a shape the team's existing `NLModel` retraining script can consume directly.

---

## Out of Scope (this version)

- **Any iOS-side change** — covered in VoxioSpecification-1.3.md
- **Multi-environment promotion beyond preview/production** — no separate staging environment
- **Multi-tenancy or per-customer isolation** — single dataset, single admin team
- **Rich analytics dashboards or BI integration** — basic counts only; export to CSV for any deeper analysis
- **A model registry or automated retraining trigger** — retraining is a manual offline step
- **Public API documentation or third-party API access** — internal tool, no public surface
- **Audit log of admin actions** — deferred; admin team is small enough that GitHub identity in SWA logs is sufficient
- **Bulk re-label or undo of label changes** — labels are individually editable; no bulk operations
- **Webhook notifications** (e.g. "new batch arrived") — not required for the labelling workflow
- **Scheduled CSV export to cloud storage** — manual download only
- **Custom email-based admin invitations** — admins are invited via GitHub username through the SWA portal
- **Soft-delete or deletion grace period** — `DELETE /api/telemetry/{deviceId}` is immediate and final by GDPR design

---

## API Specification

All endpoints are served by Next.js Route Handlers. All paths are absolute relative to the SWA hostname (e.g. `https://voxio-telemetry.azurestaticapps.net/api/...`).

Request and response bodies are JSON with `Content-Type: application/json` unless noted. All timestamps are ISO 8601 strings in UTC.

### `POST /api/telemetry/batch`

Ingest a batch of telemetry events from the iOS app.

**Authentication**

- Required header: `X-Api-Key: <TELEMETRY_API_KEY>`
- Missing header → 401 Unauthorized
- Mismatched header → 401 Unauthorized
- Endpoint is **not** behind SWA role-based auth; it is a public URL gated only by the API key.

**Request body**

```json
{
  "deviceId": "550e8400-e29b-41d4-a716-446655440000",
  "appVersion": "1.3.0",
  "modelVersion": "voxio-en-v3",
  "events": [
    {
      "transcriptionAnonymised": "play favorite [HASH:a1b2c3d4]",
      "intent": "playFavorite",
      "slotsAnonymised": { "favorite": "[HASH:a1b2c3d4]" },
      "parserPath": "FoundationModels",
      "outcome": "confirmed",
      "locale": "en-US",
      "timestamp": "2026-05-04T14:32:11.123Z",
      "flags": ["likelyMisparse"]
    }
  ]
}
```

**Field constraints**

| Field | Type | Required | Notes |
|---|---|---|---|
| `deviceId` | string (UUID v4) | yes | Anonymous device ID per iOS T-3507 |
| `appVersion` | string | yes | Semver, e.g. `1.3.0` |
| `modelVersion` | string | yes | Identifier of the bundled `.mlmodel` |
| `events` | array | yes | 1 to 100 entries |
| `events[].transcriptionAnonymised` | string | yes | Already anonymised on device |
| `events[].intent` | string | yes | One of the documented intents (see VoxioSpecification-1.3.md) |
| `events[].slotsAnonymised` | object (JSON) | yes | May be empty `{}`; never null |
| `events[].parserPath` | string | yes | One of `PersonalisationAlias`, `PersonalisationMemory`, `FoundationModels`, `NLModel`, `KeywordRegex`, `Unknown` |
| `events[].outcome` | string | yes | One of `confirmed`, `cancelled`, `timedOut`, `unknown` |
| `events[].locale` | string | yes | BCP-47, e.g. `en-US`, `da-DK` |
| `events[].timestamp` | string (ISO 8601) | yes | UTC; client clock |
| `events[].flags` | string array | no | Subset of `likelyMisparse`, `recoverableUnknown`, `broadcast` |

**Responses**

| Status | Body | Meaning |
|---|---|---|
| 202 Accepted | `{ "accepted": <int>, "rejected": <int>, "errors": [] }` | All events queued for write. `rejected` is non-zero only when individual events failed validation but the batch as a whole was processed. |
| 400 Bad Request | `{ "error": "Invalid request body", "detail": "<message>" }` | Schema validation failure (missing required field, wrong type, batch > 100 events) |
| 401 Unauthorized | `{ "error": "Invalid API key" }` | Missing or wrong `X-Api-Key` |
| 413 Payload Too Large | `{ "error": "Batch too large" }` | Body exceeds 1 MB |
| 429 Too Many Requests | `{ "error": "Rate limit exceeded", "retryAfterSeconds": 60 }` | More than 1 batch from this `deviceId` within 60 seconds |
| 500 Internal Server Error | `{ "error": "Server error" }` | Database write failure or unhandled exception |
| 503 Service Unavailable | `{ "error": "Database unavailable" }` | Neon connection failure (cold-start exceeded internal timeout) |

**Behaviour**

- The handler validates the API key first; auth failures never touch the database.
- Schema validation is per-batch and per-event. A malformed event in an otherwise valid batch is recorded in the response `errors` array; the batch as a whole returns 202 if at least one event was written. If all events fail validation, the batch returns 400.
- Successful writes insert one row per event into `events`, with the batch-level fields (`device_id`, `app_version`, `model_version`) denormalised onto each row.
- The handler upserts a row in `devices` keyed by `device_id`, updating `last_seen_at` and `last_upload_at`.
- Rate limit tracking: `devices.last_upload_at` compared against `now() - interval '60 seconds'`. Atomic compare-and-set inside a single transaction.

### `DELETE /api/telemetry/{deviceId}`

Permanently delete all telemetry data associated with a specific anonymous device ID. Initiated by the iOS app per US-53 / T-3508.

**Authentication**

- Required header: `X-Api-Key: <TELEMETRY_API_KEY>` (same key as ingest)
- Missing or wrong key → 401
- The endpoint is **not** behind SWA role-based auth; it is callable by anyone holding the iOS API key, which is correct because the iOS app initiates deletion on behalf of the device.

**Path parameter**

| Name | Type | Notes |
|---|---|---|
| `deviceId` | string (UUID v4) | Must match the `deviceId` originally uploaded by this device |

**Request body**

None.

**Responses**

| Status | Body | Meaning |
|---|---|---|
| 200 OK | `{ "deleted": { "events": <int>, "labels": <int>, "devices": 1 } }` | All rows for this `deviceId` deleted |
| 200 OK | `{ "deleted": { "events": 0, "labels": 0, "devices": 0 } }` | No data found for this `deviceId` (still 200; deletion is idempotent) |
| 400 Bad Request | `{ "error": "Invalid deviceId" }` | `deviceId` is not a valid UUID |
| 401 Unauthorized | `{ "error": "Invalid API key" }` | Missing or wrong `X-Api-Key` |
| 500 Internal Server Error | `{ "error": "Server error" }` | DB failure |

**Behaviour**

- Single SQL statement: `DELETE FROM devices WHERE device_id = $1`.
- `events.device_id` and `labels.event_id` foreign keys are declared `ON DELETE CASCADE`, so a single delete on `devices` removes everything.
- Operation is final — there is no soft-delete or recovery path.
- Endpoint is idempotent: deleting a non-existent `deviceId` returns 200 with zero counts.

### `GET /api/health`

Unauthenticated keep-alive ping. Used by the GitHub Actions cron job (every 5 minutes) to prevent the SWA-managed App Service from going idle.

**Authentication**

None.

**Responses**

| Status | Body | Meaning |
|---|---|---|
| 200 OK | `{ "status": "ok", "timestamp": "<ISO 8601>" }` | Process is alive |
| 500 Internal Server Error | `{ "status": "error" }` | Unhandled exception |

**Behaviour**

- Does **not** touch the database. The goal is to keep the App Service warm; involving Neon would also keep Neon awake unnecessarily.
- Response time on a warm backend < 100 ms.
- Response time on a cold backend may exceed 5 seconds — that is the keep-alive working as designed.

### `GET /api/admin/events`, `POST /api/admin/events/{id}/label`, `GET /api/admin/export`, `GET /api/admin/stats`

Admin-only endpoints. All require `allowedRoles: ["admin"]` enforced by `staticwebapp.config.json`. Anonymous or non-admin requests receive 401/403 from SWA before the handler runs.

These endpoints are referenced by the admin site screens (next section) and follow conventional REST patterns: list with query parameters for filtering and pagination, POST to create a label, GET with `Content-Type: text/csv` for export, GET returning a JSON aggregation for stats. Detailed payload shapes are implementation-level and tracked in the epics/tasks document, not this spec.

---

## User Stories

The user stories below describe **admin** users only. iOS user stories US-53–55 covering the iOS-side telemetry consent, upload, and deletion request flow are specified in VoxioSpecification-1.3.md and are not duplicated here.

---

**US-A1 — View and filter the events list**
> As an admin, I want to browse incoming telemetry events with filters so that I can find the events most relevant to model improvement.

**Acceptance criteria:**
- Visiting `/admin/events` while signed in as an admin shows a paginated table of events ordered by `timestamp` descending.
- Each row shows: timestamp, anonymised transcription, intent, parser path, outcome, locale, and any flags.
- The page supports filters (combinable, applied via URL query parameters): date range, intent, parser path, outcome, locale, flag presence (`likelyMisparse`, `recoverableUnknown`, `broadcast`), and a free-text substring filter on the anonymised transcription.
- Pagination is server-driven via cursor or offset; default page size is 50, max 200.
- An unauthenticated user accessing `/admin/events` is redirected to GitHub sign-in by SWA.
- A signed-in non-admin user accessing `/admin/events` receives 403 from SWA without the application running.

---

**US-A2 — Label an event**
> As an admin, I want to mark whether the parser got an event right or wrong, and what the correct intent should have been, so that the labelled data can be used for retraining.

**Acceptance criteria:**
- From the events list, opening an event reveals a detail view at `/admin/events/{id}`.
- The detail view shows all event fields plus a labelling control with three actions: **Correct** (parser intent was right), **Incorrect** (lets the admin pick the correct intent from a dropdown of valid intents), and **Discard** (mark this event as not useful for training; e.g. background noise transcription).
- Submitting a label writes a row to the `labels` table linked to this event, including the admin's GitHub username (read from the SWA `clientPrincipal`) and a timestamp.
- An event already labelled shows the existing label and allows the admin to change it (update in place; one label per event per admin — most recent label wins for export purposes).
- Labelling does not modify the original event row.

---

**US-A3 — Export labelled events as CSV**
> As an admin, I want to export labelled events as a CSV file so that I can feed them into the offline retraining script.

**Acceptance criteria:**
- A button on `/admin/events` and on a dedicated `/admin/export` page initiates a download of `voxio-labelled-events-<ISO date>.csv`.
- The export includes only events that have at least one label, and uses the most recent label per event.
- CSV columns (in order): `event_id`, `timestamp`, `locale`, `transcription_anonymised`, `original_intent`, `parser_path`, `outcome`, `flags`, `label_action` (`correct` / `incorrect` / `discard`), `corrected_intent` (empty unless action is `incorrect`), `labelled_by`, `labelled_at`.
- Filters applied to the events list (date range, locale, intent) carry over to the export by URL query parameters.
- For a typical export of up to 100,000 rows the response streams as `text/csv` and completes within 30 seconds.
- The CSV is UTF-8 encoded with a BOM, RFC 4180 quoting, and `\n` (LF) line endings.

---

**US-A4 — Trigger GDPR deletion for a deviceId**
> As an admin, I want to manually delete all telemetry for a specific device ID so that I can satisfy a user request that arrived through a channel other than the iOS app's in-app deletion button.

**Acceptance criteria:**
- A page at `/admin/deletion` accepts a `deviceId` (UUID) via a form input.
- Submitting the form calls the same `DELETE /api/telemetry/{deviceId}` endpoint used by the iOS app, authenticated by the admin's session (via an internal admin-only handler that holds the API key server-side, never exposed to the browser).
- Successful deletion shows a confirmation message with the row counts: *"Deleted 1,243 events and 87 labels for device 550e8400-…"*.
- A deletion of a non-existent `deviceId` shows: *"No data found for that device ID. Nothing to delete."* (still treated as success — idempotent).
- A failed deletion (DB error) shows: *"Deletion failed. Please try again or contact engineering."* and logs the underlying error.
- The form requires a typed confirmation step ("Type DELETE to confirm") before the destructive call is dispatched, to prevent accidents.

---

**US-A5 — View stats dashboard**
> As an admin, I want a high-level view of telemetry counts so that I can see at a glance how the parser is performing.

**Acceptance criteria:**
- A page at `/admin/stats` shows the following aggregations over a selectable date range (default: last 7 days):
  - Total events received
  - Counts by `intent` (table or bar chart)
  - Counts by `outcome` (`confirmed`, `cancelled`, `timedOut`, `unknown`)
  - Counts by `parserPath`
  - Counts by `locale` (`en-US`, `da-DK`)
  - Count of events flagged `likelyMisparse`
  - Count of distinct active devices
- All aggregations are computed via SQL `GROUP BY` on the `events` table; no precomputed materialised views in v1.
- The stats page renders within 3 seconds for a 7-day window over up to 1 million events.
- The page is read-only — no data mutations.

---

## Admin Site Screens

The admin UI is rendered by the Next.js app pages under `/admin/*`. All pages are server-rendered; auth is enforced by SWA before the page renders. The visual style is a plain functional admin theme — no marketing polish required. Tailwind CSS or shadcn/ui is acceptable.

| Screen | Path | Purpose |
|---|---|---|
| Events list | `/admin/events` | Paginated, filterable table of all telemetry events. Primary triage surface. Links to detail view per row. |
| Event detail | `/admin/events/{id}` | Full event data plus labelling control (Correct / Incorrect / Discard). Shows existing label if present. |
| Export | `/admin/export` | Download labelled events as CSV. Filter inputs duplicated from the events list for convenience. |
| Stats | `/admin/stats` | Aggregations: counts by intent, outcome, parser path, locale, plus distinct device count and `likelyMisparse` count. Date-range selector. |
| Deletion | `/admin/deletion` | Manual GDPR deletion form. Requires typed confirmation. |
| Sign-in landing | `/admin` (unauthenticated) | If not signed in, prompts the user to sign in with GitHub via `/.auth/login/github`. If signed in but not in the `admin` role, shows "Access denied" message. |

The admin layout includes a top navigation bar with links to Events, Stats, Export, and Deletion, plus a sign-out link (`/.auth/logout`) and the current admin's GitHub username on the right.

---

## Error States

| Scenario | Expected Behaviour |
|---|---|
| Ingest request missing `X-Api-Key` | 401 with body `{"error": "Invalid API key"}`. Not logged as an error (expected adversarial traffic). |
| Ingest request with wrong `X-Api-Key` | 401 with body `{"error": "Invalid API key"}`. Logged at WARN with source IP. |
| Ingest body fails JSON parsing | 400 with body `{"error": "Invalid request body", "detail": "Malformed JSON"}` |
| Ingest body schema validation fails | 400 with body `{"error": "Invalid request body", "detail": "<first failing field>"}` |
| Ingest body > 1 MB | 413 with body `{"error": "Batch too large"}` |
| Ingest events array > 100 entries | 400 with body `{"error": "Invalid request body", "detail": "Batch may contain at most 100 events"}` |
| Ingest rate limit hit (same deviceId within 60 s) | 429 with body `{"error": "Rate limit exceeded", "retryAfterSeconds": 60}` and header `Retry-After: 60` |
| Ingest succeeds for some events, fails for others | 202 with body `{"accepted": N, "rejected": M, "errors": [{"index": i, "reason": "<message>"}]}` |
| Database write fails during ingest | 500 with body `{"error": "Server error"}`. iOS app per US-54 retries with exponential backoff. |
| Neon database is cold and exceeds 10-second connection timeout | 503 with body `{"error": "Database unavailable"}`. iOS app retries. |
| Deletion called with malformed UUID | 400 with body `{"error": "Invalid deviceId"}` |
| Deletion succeeds for unknown deviceId | 200 with body `{"deleted": {"events": 0, "labels": 0, "devices": 0}}` (idempotent) |
| Deletion DB call fails | 500 with body `{"error": "Server error"}` |
| Admin opens `/admin/events` while not signed in | SWA redirects to `/.auth/login/github` |
| Admin opens `/admin/events` signed in but not in `admin` role | SWA returns 403 page; the application is not invoked |
| Admin labels an event that was deleted between page load and submit | 404 with admin-facing toast: *"Event no longer exists. It may have been deleted."* |
| Admin export query yields zero labelled events | Download still occurs; CSV contains the header row only |
| Admin export query times out (> 60 s) | Stream is closed; admin sees a partial CSV. Logged at ERROR. Mitigation: narrower date range filter. |
| Admin deletion form submitted without typed `DELETE` confirmation | Inline validation error: *"Type DELETE to confirm before submitting."* No request sent. |
| Health endpoint hit while DB is down | Still returns 200 — health does not check the DB by design |

---

## Non-Functional Requirements

**Latency**

- Ingest endpoint, warm backend: 99th percentile response time ≤ 1.5 seconds for a 100-event batch.
- Ingest endpoint, cold backend: response time may reach 5 seconds (acknowledged SWA cold-start). The iOS app per US-54 tolerates this with exponential backoff.
- Health endpoint, warm: ≤ 100 ms.
- Admin page render, warm: ≤ 1 second up to 50 events visible.
- Stats page render, warm: ≤ 3 seconds over 7-day window across up to 1 million events.
- CSV export, warm: streams within 30 seconds for up to 100,000 rows.

**Cold-start mitigation**

- A UptimeRobot free-tier monitor hits `GET /api/health` every 5 minutes. This keeps the SWA-managed App Service warm at zero cost.
- UptimeRobot is used instead of a GitHub Actions cron: a 5-minute cron on a private repository runs ~8,640 times/month (~4,320 billed minutes), exceeding the free tier and adding ~$18/month in overage. UptimeRobot's free plan supports up to 50 monitors at 5-minute intervals with no GitHub Actions minutes consumed.
- The monitor is configured on UptimeRobot pointing at `https://<swa-hostname>/api/health`. If observation shows the App Service stays warm naturally under typical traffic patterns, the monitor can be paused.

**Storage**

- Database storage stays within the Neon free tier (0.5 GB) at projected indie volumes (≤ 100k events/month). At ~100 bytes per event row, this allows ~5 million events before archiving is needed.
- When approaching the free-tier limit, the team will manually export and prune old (> 12 months) data. No automated archiving in v1.

**Cost**

- Total monthly hosting cost ≤ $10 USD: $9 SWA Standard + $0 Neon free tier + $0 GitHub Actions free tier.
- If volume grows past free-tier limits, the next step is Neon Launch tier (~$19/month) or a self-hosted Postgres on Azure. Out of scope for v1.

**GDPR compliance**

- The system stores no PII: only an anonymous device UUID, anonymised transcription text, and parse metadata.
- Deletion is end-to-end: a `DELETE /api/telemetry/{deviceId}` call removes all events and labels for that device with no soft-delete tombstone.
- Database backups, if any, must respect deletion within 30 days (Neon's default backup retention is well within this).
- A privacy notice at `/admin` describes the dataset for any new admin onboarded.

**Availability**

- Target uptime: best-effort. There is no SLA. Azure SWA's own SLA covers the hosting layer; the application has no high-availability requirements because the iOS client buffers events for 24 hours and retries.
- Maintenance windows: deployments via CI/CD are zero-downtime (SWA atomic blue/green). Database schema migrations are forward-compatible (additive columns/tables only) so deploys never require downtime.

**Security**

- All traffic is HTTPS-only (SWA default; HTTP redirects to HTTPS).
- The `TELEMETRY_API_KEY` is generated with `openssl rand -hex 32` (256 bits of entropy) and stored only in SWA Application Settings.
- Admin authentication is delegated to GitHub OAuth via SWA. No application password storage.
- No secret is logged. The ingest handler must not log request bodies (which contain anonymised transcriptions).
- Database connections use TLS (Neon default).

**Accessibility**

- Admin site is keyboard-navigable for all primary actions (filter, paginate, label, export, deletion).
- Form inputs have associated `<label>` elements.
- Colour is not the only signal for label state (icons or text labels accompany any colour cue).
- WCAG 2.1 AA contrast ratios on all text. Not formally audited in v1.

**Observability**

- All requests are logged with `console.log` in structured JSON; SWA captures them automatically and routes to Application Insights if configured.
- The ingest handler logs at INFO: deviceId, batch size, accepted/rejected counts, response status. It logs at ERROR for 5xx responses with the exception message but never the request body.
- Admin actions (label create/update, deletion) are logged at INFO with the GitHub username from `clientPrincipal`.

---

## Open Questions

1. **GitHub OAuth provider — pre-configured or custom?** — Owner: engineering lead. Default assumption: use the SWA pre-configured GitHub provider (no email exposed). If admins need their email surfaced (e.g. for audit log per-row attribution), we register a custom GitHub OAuth app on the Standard plan.
2. **SWA region and Neon region** — **Blocking pre-provisioning prerequisite, not an open question.** The engineering lead must confirm the SWA deployment region before infrastructure is provisioned. The Neon project must be created in the matching region (`aws-eu-central-1` for West Europe SWA, `aws-us-east-1` for East US SWA). This cannot be changed after the Neon project is created without deleting all data and recreating the project.
3. **UptimeRobot monitor strictness** — Owner: engineering lead. Default assumption: configure the UptimeRobot monitor from day one. If observation shows the App Service stays warm naturally under typical traffic, the monitor can be paused.
4. **Stats granularity** — Owner: data lead. Default assumption: ship the stats page with the aggregations listed in US-A5. Time-series charts (events per hour/day) are deferred. Revisit if the team finds the static counts insufficient.
5. **Label conflict resolution across multiple admins** — Owner: data lead. Default assumption: most-recent label wins for export. An audit-log column on `labels` records the previous label whenever it is overwritten, so historical labels are preserved server-side but only the latest exports.
6. **CSV column for `useCount` or first-seen timestamp** — Owner: data lead. Default assumption: not included; the export contains exactly the columns listed in US-A3. Adjust if the retraining script needs additional fields.
7. **Rate limit storage** — Owner: engineering lead. Default assumption: track `last_upload_at` on the `devices` table; rate-limit decision is a SQL `UPDATE … WHERE last_upload_at < now() - interval '60 seconds' RETURNING` race-free check. If the SQL approach has measurable latency cost, switch to an in-process LRU map (acceptable because the SWA App Service runs as a single instance under indie load).
8. **Admin deletion endpoint authentication** — Owner: engineering lead. Default assumption: the `/admin/deletion` form posts to an admin-only Next.js API route, which then calls the public `DELETE /api/telemetry/{deviceId}` server-side using the `TELEMETRY_API_KEY` injected from env. The API key never reaches the browser. Confirm this is acceptable or switch to a dedicated admin-only DB call.
9. **Schema migration tooling** — Owner: engineering lead. Default assumption: use a lightweight tool such as `node-pg-migrate` or a hand-rolled SQL migration directory invoked from CI. No ORM. Confirm before first migration is written.
10. **Monitoring and alerting** — Owner: engineering lead. Default assumption: rely on Application Insights surfacing of 5xx responses; no PagerDuty or external alerting in v1. If a 5xx incident occurs without notice, revisit.

---

## Resolved Decisions

| Question | Decision |
|---|---|
| Hosting platform | Azure Static Web Apps Standard plan, single Next.js 15 hybrid app |
| Should admin auth be NextAuth.js? | No — SWA built-in GitHub OAuth, NextAuth.js v5 is broken on SWA per upstream issues |
| Database | Neon serverless Postgres, free tier |
| iOS → backend auth | Static `X-Api-Key` header validated against `TELEMETRY_API_KEY` env var |
| Should ingest store raw audio? | No — text only, by privacy guarantee in VoxioSpecification-1.3.md |
| Should ingest store any PII? | No — only the anonymised event schema from A-1 |
| GDPR deletion semantics | Hard delete with cascade; no soft delete or grace period |
| Are admin endpoints behind SWA role auth or app code? | SWA role auth (`allowedRoles: ["admin"]` in `staticwebapp.config.json`); zero application auth code |
| Should the iOS deletion endpoint require admin auth? | No — it is gated by the same `X-Api-Key` as ingest, because the iOS app initiates deletion on the user's behalf |
| Cold-start mitigation | Scheduled `GET /api/health` ping every 5 minutes via GitHub Actions cron |
| CSV format | UTF-8 with BOM, RFC 4180 quoting, LF line endings, columns as specified in US-A3 |
| Label model | One `labels` row per (event, admin); most-recent overwrite wins; previous label retained in audit column |
| Rate limit | 1 batch per `deviceId` per 60 seconds at ingest |
| Batch size limit | Up to 100 events per batch; up to 1 MB body size |
| CI/CD pattern | GitHub Actions following TheCheapPowerCompany repo: lint → vitest → build → SWA deploy → Playwright E2E |
| Ingest endpoint authentication separation | Ingest is **not** behind SWA role auth — it must be reachable by the iOS app, which has no SWA session. API key is the sole auth. |
| Should the system include a model registry? | No — model versioning is tracked only via `modelVersion` string on each event; OTA model distribution is out of scope |
| Should there be staging in addition to preview/prod? | No — preview environments per PR cover the staging role |
