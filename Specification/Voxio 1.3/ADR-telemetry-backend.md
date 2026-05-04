# ADR-001 — Telemetry Backend and Admin Site Architecture for Voxio 1.3

**Status:** Accepted (two spec items revised per REVISE verdict — see Section 8)
**Date:** 2026-05-04
**Deciders:** Engineering Lead, Data Lead
**Refs:** spec-telemetry-backend-admin.md v1.0, research-telemetry-backend.md, VoxioSpecification-1.3.md v1.3.3, CLAUDE.md

---

## 1. Decision

Deploy the Voxio 1.3 telemetry ingest API and admin labelling site as a single Next.js 15 hybrid application on Azure Static Web Apps (Standard plan), backed by a Neon serverless Postgres database, with SWA built-in GitHub OAuth for admin authentication and a static `X-Api-Key` header for iOS-to-backend authentication.

---

## 2. Context

### Problem being solved

VoxioSpecification-1.3.md Feature 1 / Flow A (E-35, US-53–55, T-3501–T-3508) requires a backend that can:

1. Accept batched, anonymised parse-outcome events uploaded by the iOS app (up to 100 events per batch, at most once per 24 hours per device, Wi-Fi only).
2. Support per-`deviceId` GDPR hard-deletion initiated by the iOS app (T-3508, US-53).
3. Provide an authenticated admin interface where a small team (1–5 people) can filter, label, and export telemetry events as CSV for offline NLModel retraining.

Neither the backend nor the admin site exist yet. The iOS data model, anonymisation rules, consent flow, and deletion request mechanism are fully specified in VoxioSpecification-1.3.md and are consumed — not redefined — by this backend.

### Constraints

- **Indie project budget:** total monthly hosting cost must remain at or below $10 USD.
- **Existing Azure SWA pattern:** the team's established CI/CD pattern (TheCheapPowerCompany repo) already uses Azure Static Web Apps + GitHub Actions (lint → vitest → build → SWA deploy → Playwright E2E). Any new backend must fit this pattern without introducing a second class of infrastructure to maintain.
- **Privacy requirements (VoxioSpecification-1.3.md):** no PII is stored. The backend receives only an anonymous device UUID, anonymised transcription text (favorite names SHA-256-hashed, speaker names stripped), and parse-outcome metadata. Audio is never transmitted.
- **GDPR deletion (US-53 / T-3508):** a `DELETE /api/telemetry/{deviceId}` call must permanently and immediately remove all events and labels for that device, with no soft-delete tombstone.
- **Admin access:** 1–5 named individuals identified by GitHub username. No end-user-facing registration, no email-based invitations, no custom auth code.

---

## 3. Options Considered

### Option A — Single Next.js 15 hybrid app on Azure SWA *(chosen)*

One repository, one deployment unit. Static admin pages served from SWA's global CDN. API Route Handlers (`app/api/*/route.ts`) proxied to a managed App Service instance. Admin authentication handled by SWA's built-in GitHub OAuth and Standard-plan custom-role system — zero application auth code. Database access via `@neondatabase/serverless` against Neon free-tier Postgres.

Cost: $9/month (SWA Standard) + $0 (Neon free tier) = $9/month.

Risks: Next.js hybrid on SWA is marked "preview" as of May 2026; cold-start latency of 5+ seconds after idle; Neon region must match SWA region at provisioning time (cannot be changed later).

### Option B — Static Next.js frontend + separate Azure Functions v4 API

The admin UI is fully statically exported (`output: 'export'`). A separate Azure Functions v4 project hosts the API endpoints as a linked SWA backend. This eliminates the "preview" hybrid risk but is mutually exclusive with Option A (SWA does not support linked custom backends alongside hybrid Next.js). Requires a second project structure (Azure Functions). Admin pages must be fully client-rendered.

Cost: same as Option A.

### Option C — Third-party BaaS (Supabase, Firebase)

Supabase: genuine Postgres, built-in GitHub Auth, auto-generated API. Supabase free tier **pauses projects after 7 days of inactivity** — the telemetry endpoint would be unavailable to real iOS devices during idle periods. Paid plan ($25/month) exceeds the $10 ceiling.

Firebase Firestore: NoSQL makes the filtering, GROUP BY, and CSV export queries awkward.

Option C in any flavour either exceeds the cost ceiling, introduces prod-quality risk, or requires application auth code the SWA approach eliminates.

---

## 4. Decision Rationale

**Option A is chosen** over B and C:

1. **Consistency with the established team pattern.** The TheCheapPowerCompany CI/CD pipeline maps directly onto Option A with no new infrastructure concepts. Option B requires Azure Functions v4 project structure. Option C breaks out of the Azure SWA ecosystem.
2. **Zero application auth code.** SWA built-in GitHub OAuth with `allowedRoles: ["admin"]` in `staticwebapp.config.json` enforces admin routes at the runtime level — a code bug cannot accidentally expose admin functionality.
3. **SQL for the labelling and export workflow.** Neon Postgres makes filtering, aggregation, and streaming CSV export trivial. Firestore would require materialised views or client-side joins.
4. **Cost ceiling.** Option A: $9/month. Option C (Supabase paid): $25/month.
5. **Single deployment unit.** One SWA instance, one CI/CD pipeline, one bill.
6. **No ORM.** `@neondatabase/serverless` directly is consistent with the team pattern and keeps the dependency surface minimal.

Option B is documented as the concrete fallback if the hybrid preview status causes production issues — it requires no database or auth changes.

---

## 5. Consequences and Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Next.js 15 hybrid on Azure SWA is "preview" | Medium | Microsoft's tutorial covers this path; community use in production confirmed. Fallback: Option B (static export + Azure Functions v4), no database or auth changes needed. |
| Cold-start latency (5+ seconds after idle) | Low | iOS app tolerates with exponential backoff (US-54). Admin UI acceptable for internal tool. UptimeRobot free tier pings `GET /api/health` every 5 minutes to prevent idle. |
| Neon region must match SWA region at provisioning | Medium | **Blocking prerequisite** — cannot be changed post-provisioning without recreating the database and losing all data. Must be resolved before any infrastructure is provisioned. |
| SWA Standard plan required for custom roles | Low | $9/month; within the $10 ceiling. |
| Neon free tier storage ceiling (0.5 GB) | Low | ~5 million events fit in 0.5 GB at ~100 bytes/event. At ≤100k events/month: ~50 months headroom. Manual export-and-prune is the v1 archiving strategy. |

---

## 6. Spec Validation Results

### 6.1 POST /api/telemetry/batch — X-Api-Key on a public URL
**Accepted.** Data is anonymised non-PII. Worst case: spam writes. Mitigations: 256-bit key, iOS Keychain storage, per-device rate limit. Consistent with research Finding 4.

### 6.2 DELETE /api/telemetry/{deviceId} — same iOS X-Api-Key
**Accepted.** A malicious caller needs both the API key AND a victim's deviceId UUID. The deviceId is stored only in the victim's Keychain. For anonymised non-PII data this trade-off is appropriate at indie scale.

### 6.3 Admin deletion form — server-side API key pattern
**Safe.** The admin Route Handler (behind `allowedRoles: ["admin"]`) calls the public DELETE endpoint server-side. The API key never reaches the browser. Standard server-side secrets pattern.

### 6.4 Rate limiting — SQL last_upload_at under concurrency
**Safe.** `UPDATE devices SET last_upload_at = now() WHERE device_id = $1 AND (last_upload_at IS NULL OR last_upload_at < now() - interval '60 seconds') RETURNING device_id` is race-free at the Postgres row level. The second concurrent `UPDATE` sees the first one's committed value and returns 0 rows → 429. SQL approach preferred over in-process LRU because it survives restarts.

### 6.5 Neon cascade delete — ON DELETE CASCADE correctness
**Correct.** `DELETE FROM devices WHERE device_id = $1` cascades via FK to `events`, which cascades to `labels`. Atomic. **Implementation note:** returning row counts requires a CTE (`WITH deleted_events AS (DELETE FROM events WHERE device_id = $1 RETURNING id) …`) rather than a preceding SELECT COUNT — one round-trip, not two.

### 6.6 No ORM — @neondatabase/serverless driver
**Consistent** with TheCheapPowerCompany pattern. Correct choice.

### 6.7 Conflicts with CLAUDE.md
**None.** CLAUDE.md describes an iOS-only project. The backend is a new web project and must live in a new top-level directory (e.g. `backend/`) or a separate repository — not inside `iOS/`.

### 6.8 Conflicts with VoxioSpecification-1.3.md
**None.** The API contract matches the iOS-side task descriptions (T-3501, T-3505, T-3508). The `broadcast` flag in the backend spec's field table is consistent with the Resolved Decisions table in VoxioSpecification-1.3.md v1.3.3.

---

## 7. Implementation Constraints (binding on implementer)

1. All secrets (`DATABASE_URL`, `TELEMETRY_API_KEY`) live in SWA Application Settings only. Never in source, never logged.
2. The ingest Route Handler must never log the request body. Log at INFO: deviceId, batch size, accepted count, rejected count, status.
3. Admin Route Handlers must be declared under `app/api/admin/` and listed in `staticwebapp.config.json` with `"allowedRoles": ["admin"]`. Handlers must not implement their own auth check — the SWA runtime enforces it.
4. Cascade delete must be implemented with `ON DELETE CASCADE` foreign key constraints, not application-level multi-DELETE statements.
5. The rate-limit check must be inside the same database transaction as the ingest write, using `UPDATE devices … RETURNING`.
6. The Next.js app must use `output: 'standalone'` in `next.config.js`. `navigationFallback` must not be used in `staticwebapp.config.json`.
7. CI/CD follows the TheCheapPowerCompany pattern: lint → vitest → `next build` → `Azure/static-web-apps-deploy@v1` → Playwright E2E against the deployed preview URL.
8. The Neon project region must match the SWA region. **This must be confirmed before any infrastructure is provisioned.**

---

## 8. Items Revised in Spec Following REVISE Verdict

Two items were flagged by the architect and addressed in `spec-telemetry-backend-admin.md` v1.1:

**Item 1 — Keep-alive ping: GitHub Actions cron replaced with UptimeRobot.**
The original spec stated "Free tier of GitHub Actions covers the cron cost." This is false for a private repository: a 5-minute cron runs ~8,640 times/month. At ~30 seconds/run that is ~4,320 billed minutes, exceeding the 2,000-minute free tier and producing ~$18/month in overage — blowing through the $10 hosting ceiling. Resolution: use **UptimeRobot free tier** (up to 50 monitors, 5-minute interval, no GitHub Actions minutes consumed) rather than a GitHub Actions cron. The spec technical context table and keep-alive NFR section have been updated accordingly.

**Item 2 — Neon region promoted from Open Question to blocking prerequisite.**
The original spec listed SWA region selection as Open Question 2. The Neon project region must match the SWA region at creation time — it cannot be changed afterwards without recreating the project and losing all data. This cannot be deferred to mid-implementation. Resolution: promoted to a named blocking prerequisite in the spec's Non-Functional Requirements section and removed from Open Questions.

---

**Verdict: PROCEED** *(following the two spec revisions above)*
