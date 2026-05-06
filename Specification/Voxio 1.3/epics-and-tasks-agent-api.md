# Epics & Tasks: Agent API for Telemetry Labelling and Corpus Export (Voxio 1.3)
**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-05
**References:** ADR-005 (`docs/decisions/ADR-005-agent-api.md`), `epics-and-tasks-telemetry-backend.md` (E-41 – E-47, format reference), spec-telemetry-backend-admin.md (v1.1), VoxioSpecification-1.3.md, CLAUDE.md
**Stack:** TypeScript, Next.js 15 App Router (hybrid mode), Postgres (Neon serverless), deployed to Azure Static Web Apps Standard plan

---

## Overview

This document covers two epics — **E-48: Agent API Infrastructure & Auth** and
**E-49: Agent API Routes & Corpus Export** — that extend the existing Voxio
telemetry backend (delivered in E-41 – E-47) with a programmatic API surface
for an AI labelling agent. The agent fetches anonymised telemetry events,
labels them as `correct`, `incorrect`, or `discard`, and exports a deduplicated
training corpus (CSV or JSONL) used to retrain the on-device NL model that
ships with the iOS app.

No new infrastructure is introduced: the Agent API ships as additional Route
Handlers under `app/api/agent/*` in the same Next.js app, deployed to the same
Azure Static Web Apps instance, backed by the same Neon Postgres database.
Authentication is a static API key (separate from the iOS telemetry key),
distributed out-of-band to the agent operator.

This document is **additive** to `epics-and-tasks-telemetry-backend.md` —
the tables `events`, `labels`, and `devices` already exist (E-42), the SWA
+ Neon stack is already provisioned (E-41), and the labelling control flow
is already implemented for human admins (E-45). The Agent API reuses every
one of those primitives.

Epic numbering begins at **E-48**, continuing from E-47 in the telemetry
backend document. Task numbering begins at **T-4801**.

---

## Epic Index

| # | Epic | Tasks | Feature Area |
|---|---|---|---|
| E-48 | Agent API Infrastructure & Auth | T-4801 – T-4806 | Auth middleware, env vars, SWA config, schema migration, shared label service |
| E-49 | Agent API Routes & Corpus Export | T-4901 – T-4910 | Event fetch, single + batch labelling, corpus export, tests |

---

## E-48 — Agent API Infrastructure & Auth

Establish the cross-cutting primitives every Agent API route needs: a static
API-key auth middleware, a new SWA Application Setting `AGENT_API_KEY`, the
SWA route configuration that declares `/api/agent/*` as anonymous-but-key-gated
(matching the existing telemetry ingest pattern), a database migration that
adds the composite index used by the agent fetch query, a verification /
fix-up of the `labels.event_id` foreign key for GDPR `ON DELETE CASCADE`
compliance, and the shared `src/lib/label.ts` service function that both
the existing admin label endpoint and the new agent label endpoints call into.

This epic produces no user-visible functionality on its own. It produces
the auth surface, the schema changes, and the shared service layer that
E-49 builds on.

**Depends on:** E-41 (SWA + Neon provisioned), E-42 (`events`, `labels`,
`devices` tables exist), E-45 (admin label endpoint exists and will be
refactored to call the shared service).
**Unlocks:** E-49 (every route handler in E-49 imports from `src/lib/label.ts`,
relies on the auth middleware from T-4801, and queries against the index
added in T-4804).

---

### Authentication and configuration

- [ ] **T-4801** Create the agent auth middleware at `src/lib/agent-auth.ts`.
  Export a single function `requireAgentKey(request: Request): { ok: true } | { ok: false; response: Response }`.
  The function:
  1. Reads `process.env.AGENT_API_KEY`. If undefined or empty string, returns
     `{ ok: false, response: Response.json({ error: "agent_api_disabled" }, { status: 503 }) }`.
     Log at warn level: `"AGENT_API_KEY not configured — agent endpoints disabled"` — this must
     not leak the key value (which is undefined here anyway, but the pattern matters).
  2. Reads the `x-agent-key` header (case-insensitive — Next.js normalises).
     If missing or empty, returns
     `{ ok: false, response: Response.json({ error: "missing_agent_key" }, { status: 401 }) }`.
  3. Compares the header value to `AGENT_API_KEY` using a constant-time
     comparison. Use `crypto.timingSafeEqual` after wrapping both strings in
     `Buffer.from(s, "utf8")` and verifying lengths match (mismatched lengths
     return false without calling `timingSafeEqual`, since that function
     throws on length mismatch).
     If unequal, return `{ ok: false, response: Response.json({ error: "invalid_agent_key" }, { status: 401 }) }`.
  4. On success, return `{ ok: true }`.

  Do not log the header value, the env var value, or any prefix/suffix of
  either, ever — even on error paths. Do not include the agent_id in this
  middleware (agent_id is a request-body field, not part of authentication).

  **Files added:** `src/lib/agent-auth.ts`.
  **Files changed:** none.
  **Acceptance criteria:**
  - With `AGENT_API_KEY` unset: any request returns 503 with body `{ "error": "agent_api_disabled" }`.
  - With `AGENT_API_KEY=abc123`, no header: returns 401 with body `{ "error": "missing_agent_key" }`.
  - With `AGENT_API_KEY=abc123`, header `x-agent-key: wrong`: returns 401 with body `{ "error": "invalid_agent_key" }`.
  - With `AGENT_API_KEY=abc123`, header `x-agent-key: abc123`: returns `{ ok: true }`.
  - Comparing two equal-length but unequal keys does not short-circuit on first byte (verified by unit test that times multiple comparisons; tolerance is loose, the goal is correctness of the API not nanosecond timing).

  *No dependencies within this document. Prerequisite for every E-49 route.*

- [ ] **T-4802** Add the `AGENT_API_KEY` SWA Application Setting and document
  rotation. Generate the key locally with `openssl rand -hex 32` (64-character
  256-bit random string). Add it to the SWA Configuration blade as
  `AGENT_API_KEY`. Update `.env.local.example` at the repo root by appending:
  ```
  # API key for the labelling agent to authenticate against /api/agent/*
  # (separate from TELEMETRY_API_KEY — never reuse the iOS app's key)
  AGENT_API_KEY=
  ```
  Update `docs/runbook-secrets.md` with a new section "Agent API key rotation":
  rotation = generate new key with `openssl rand -hex 32`, update SWA env var,
  communicate new key to the agent operator via the same secure channel as
  `TELEMETRY_API_KEY` (1Password vault or equivalent). Unlike the iOS key,
  rotation does not require shipping a release — the agent operator just
  updates their stored secret. There is **no** parallel-acceptance window
  (`AGENT_API_KEY_PREVIOUS` is not implemented in v1).

  **Files changed:**
  - `.env.local.example`
  - `docs/runbook-secrets.md`
  **Acceptance criteria:**
  - `AGENT_API_KEY` is set in the SWA production environment (verified by
    a smoke `curl` against any `/api/agent/*` endpoint returning 401, not 503,
    when the wrong header is sent).
  - The key is stored in the team's 1Password vault under the entry "Voxio
    Agent API key — production".
  - `.env.local.example` contains the variable with a blank value and the
    inline comment.
  - `docs/runbook-secrets.md` contains a "Agent API key rotation" subsection.

  *Depends on: T-4801 (the middleware that reads this env var must exist
  before the value is meaningful).*

- [ ] **T-4803** Update `staticwebapp.config.json` at the repo root to
  declare the `/api/agent/*` route surface as anonymous-but-handler-gated.
  This matches the pattern already used for `/api/telemetry/*` from E-43.
  Add to the `routes` array:
  ```json
  {
    "route": "/api/agent/*",
    "allowedRoles": ["anonymous"]
  }
  ```
  Place this entry **before** any `/api/admin/*` rule (which requires the
  `admin` role) and **after** the existing `/api/telemetry/*` rule, so the
  matching is in source order. Do not change any other routes.

  Confirm the resulting file is valid JSON (run `cat staticwebapp.config.json | jq .`
  in CI or locally before commit).

  **Files changed:**
  - `staticwebapp.config.json`
  **Acceptance criteria:**
  - The file remains valid JSON and SWA accepts it on deploy (no
    `Validation failed` in the deploy logs).
  - A `GET /api/agent/events` request without any SWA auth cookie reaches
    the Route Handler (verified by observing a 401 from `requireAgentKey`,
    not a 401 from SWA's auth layer with `WWW-Authenticate` header).
  - The `/api/admin/*` routes still require the `admin` role (no
    regression — verified by the existing E-44 / E-47 admin auth tests).

  *Depends on: T-4801. Soft-blocks: every route in E-49 — without this
  entry, SWA's default deny rule may intercept the request before the
  Route Handler runs.*

### Database schema

- [ ] **T-4804** Create the migration `migrations/NNNN_agent_api_index.ts`
  (NNNN is the next sequential migration number — check the
  `migrations/` directory for the highest existing number and add 1).
  The migration adds a composite partial index on `events` tuned for the
  agent fetch query pattern (filter by `outcome`, `parser_path`, `locale`,
  `app_version`, optional `labelled` join, paginate by `received_at, id`).

  Up SQL:
  ```sql
  CREATE INDEX IF NOT EXISTS events_agent_fetch_idx
    ON events (received_at DESC, id DESC)
    INCLUDE (outcome, parser_path, locale, app_version);
  ```
  Down SQL:
  ```sql
  DROP INDEX IF EXISTS events_agent_fetch_idx;
  ```

  Notes:
  - `INCLUDE` columns are stored in the index leaf without being part of
    the key, allowing index-only scans for the common filter case.
  - The "labelled" filter is implemented as a `LEFT JOIN labels ON labels.event_id = events.id`
    in the query, with `WHERE labels.id IS NULL` for `labelled=false`. The
    `labels.event_id` index already exists (created in E-42 T-4204).
  - Do not add a UNIQUE constraint here — the existing primary keys are
    sufficient.

  Run the migration locally against the dev branch with `npm run migrate:up`,
  confirm the index appears via `\d events` in `psql`. Commit the migration.
  CI applies it to production on merge to `main`.

  **Files added:** `migrations/NNNN_agent_api_index.ts`.
  **Files changed:** none.
  **Acceptance criteria:**
  - `npm run migrate:up` applies cleanly against an existing database.
  - `npm run migrate:down` reverses the index without error.
  - `EXPLAIN ANALYZE` on the agent fetch query (T-4901) shows the index
    being used (look for `Index Scan using events_agent_fetch_idx`).
  - The migration file follows the existing `node-pg-migrate` TypeScript
    pattern used in `migrations/0001_initial_schema.ts` (or whichever the
    first migration is named).

  *Depends on: E-42 (the `events` table exists). No dependencies inside
  this document.*

- [ ] **T-4805** Verify and (if missing) fix the `labels.event_id` foreign
  key to declare `ON DELETE CASCADE`. This is required for GDPR compliance:
  when a device is deleted via `DELETE /api/telemetry/{deviceId}` (E-43
  T-4303), all associated events are removed via the existing cascade
  from `devices` → `events`; the cascade from `events` → `labels` must
  also fire so no orphan label rows remain referencing removed events.

  Run against the production database (or a clean snapshot of it):
  ```sql
  SELECT conname, confdeltype
    FROM pg_constraint
   WHERE conrelid = 'labels'::regclass
     AND contype = 'f';
  ```
  `confdeltype` should be `c` (CASCADE). If it is `a` (NO ACTION) or
  `r` (RESTRICT), create a corrective migration
  `migrations/NNNN_labels_fk_cascade.ts`:

  Up SQL:
  ```sql
  ALTER TABLE labels DROP CONSTRAINT labels_event_id_fkey;
  ALTER TABLE labels
    ADD CONSTRAINT labels_event_id_fkey
    FOREIGN KEY (event_id)
    REFERENCES events(id)
    ON DELETE CASCADE;
  ```
  Down SQL:
  ```sql
  ALTER TABLE labels DROP CONSTRAINT labels_event_id_fkey;
  ALTER TABLE labels
    ADD CONSTRAINT labels_event_id_fkey
    FOREIGN KEY (event_id)
    REFERENCES events(id);
  ```

  If the existing constraint is already `CASCADE`, document the verification
  in the task PR description and skip the migration. Either way, add an
  integration test under `test/integration/gdpr-cascade.test.ts` that:
  1. Inserts a device, an event, and a label.
  2. Calls `DELETE /api/telemetry/{deviceId}`.
  3. Asserts that all three rows are gone from `devices`, `events`, `labels`.

  **Files added (conditional):** `migrations/NNNN_labels_fk_cascade.ts`.
  **Files added (always):** `test/integration/gdpr-cascade.test.ts`.
  **Files changed:** none.
  **Acceptance criteria:**
  - `pg_constraint.confdeltype` for `labels_event_id_fkey` is `c` after
    this task ships.
  - The integration test passes against a clean local database.
  - The verification result (was the corrective migration needed or not?)
    is recorded in `docs/runbook-migrations.md`.

  *Depends on: E-42 (the `labels` table exists with its existing FK).
  Independent of T-4804.*

### Shared service layer

- [ ] **T-4806** Create the shared label service at `src/lib/label.ts`.
  This module is the single authority for writing to the `labels` table —
  both the existing admin endpoint from E-45 (`POST /api/admin/events/:id/label`)
  and the new agent endpoints (T-4902, T-4903) call into it. Refactor the
  admin endpoint to use this service in the same task (it currently inlines
  its own SQL).

  Define and export the following:

  ```typescript
  export const VALID_INTENTS = [
    "stop", "pause", "resume", "play", "playFavorite",
    "setVolume", "volumeUp", "volumeDown", "mute", "unmute",
    "listFavorites", "joinSpeaker", "leaveSpeaker",
    "confirm", "cancel", "unknown",
  ] as const;
  export type Intent = (typeof VALID_INTENTS)[number];

  export type LabelAction = "correct" | "incorrect" | "discard";

  export interface ApplyLabelInput {
    eventId: string;          // events.id (UUID)
    action: LabelAction;
    correctedIntent?: string; // required iff action === "incorrect"
    labelledBy: string;       // free-form, "agent:<agent_id>" or "admin:<github_login>"
  }

  export interface AppliedLabel {
    id: string;
    eventId: string;
    action: LabelAction;
    correctedIntent: string | null;
    labelledBy: string;
    labelledAt: string;       // ISO 8601 UTC
  }

  export class LabelValidationError extends Error {
    constructor(public code:
      | "event_not_found"
      | "invalid_action"
      | "missing_corrected_intent"
      | "invalid_corrected_intent"
      | "corrected_intent_not_allowed",
      message: string) {
      super(message);
      this.name = "LabelValidationError";
    }
  }

  export async function applyLabel(
    input: ApplyLabelInput,
    db: DatabaseClient,
  ): Promise<AppliedLabel>;
  ```

  The `applyLabel` function:
  1. Validates `action` is one of `correct`, `incorrect`, `discard` — else
     throws `LabelValidationError("invalid_action")`.
  2. If `action === "incorrect"`:
     - `correctedIntent` must be present and non-empty — else throws
       `LabelValidationError("missing_corrected_intent")`.
     - `correctedIntent` must be in `VALID_INTENTS` — else throws
       `LabelValidationError("invalid_corrected_intent")`.
  3. If `action !== "incorrect"` and `correctedIntent` is provided, throws
     `LabelValidationError("corrected_intent_not_allowed")` — defensive
     against malformed agent requests.
  4. Verifies the event exists (`SELECT 1 FROM events WHERE id = $1`).
     If not, throws `LabelValidationError("event_not_found")`.
  5. Performs the upsert against `labels`:
     ```sql
     INSERT INTO labels (event_id, action, corrected_intent, labelled_by, labelled_at)
     VALUES ($1, $2, $3, $4, NOW())
     ON CONFLICT (event_id) DO UPDATE
       SET previous_action = labels.action,
           previous_corrected_intent = labels.corrected_intent,
           action = EXCLUDED.action,
           corrected_intent = EXCLUDED.corrected_intent,
           labelled_by = EXCLUDED.labelled_by,
           labelled_at = EXCLUDED.labelled_at
     RETURNING id, event_id, action, corrected_intent, labelled_by, labelled_at;
     ```
  6. Returns the resulting row mapped to `AppliedLabel`.

  The `previous_action` and `previous_corrected_intent` columns already
  exist in the schema (per ADR-005, "schema already has audit columns").
  The function does not write to these columns directly — the `ON CONFLICT`
  clause copies the prior values into them.

  Refactor `app/api/admin/events/[id]/label/route.ts` (from E-45) to import
  `applyLabel` and replace its inline SQL block. The admin endpoint
  constructs `labelledBy` as `"admin:" + clientPrincipal.userDetails`
  (the GitHub login from SWA auth). All existing admin tests must continue
  to pass.

  **Files added:** `src/lib/label.ts`, `test/unit/lib/label.test.ts`.
  **Files changed:** `app/api/admin/events/[id]/label/route.ts` — replace
  inline SQL with a call to `applyLabel`.
  **Acceptance criteria:**
  - All five validation branches throw `LabelValidationError` with the
    correct `code` (verified by unit tests, one per branch).
  - A first-time label inserts a row with `previous_action = null`.
  - A second label on the same event copies the prior values into
    `previous_action` and `previous_corrected_intent`.
  - The admin endpoint behaviour is unchanged from before the refactor
    (existing E-45 / E-47 tests pass).
  - `VALID_INTENTS` matches exactly the 16-element list in this task.

  *Depends on: T-4805 (the FK behaviour is part of the contract this
  service relies on).*

---

## E-49 — Agent API Routes & Corpus Export

Implement the four Route Handlers under `app/api/agent/*`: list events,
label one event, label a batch, and export the training corpus. Each
route imports `requireAgentKey` from T-4801 and (where applicable)
`applyLabel` from T-4806. Add unit tests for each route's input validation
branches and an integration test that exercises the full agent workflow
end-to-end against a test database.

**Depends on:** E-48 (auth middleware, env var, SWA config, index, and
shared service all in place).
**Unlocks:** AI labelling agent operator can begin labelling once this
epic ships. The exported corpus from `GET /api/agent/corpus` becomes the
input to the next training run of the on-device NL model.

### Route: list events

- [ ] **T-4901** Create `app/api/agent/events/route.ts` implementing
  `GET /api/agent/events`. Cursor-paginated, returns unlabelled events
  by default.

  Query parameters (parsed via `zod`):
  - `after` — optional, opaque cursor string. Format: base64-encoded JSON
    `{ "received_at": "ISO8601", "id": "uuid" }`. Decoded server-side.
  - `limit` — optional integer, 1 ≤ limit ≤ 200, default 100. Reject with
    400 `{ "error": "invalid_limit", "detail": "must be 1..200" }` if out
    of range.
  - `outcome` — optional, one of `"success"`, `"failure"`, `"unknown"`.
    Other values → 400 `{ "error": "invalid_outcome" }`.
  - `parser_path` — optional, free-form string, max length 64. SQL exact
    match.
  - `locale` — optional, BCP-47 string like `"en-US"` or `"da-DK"`, max
    length 16. SQL exact match.
  - `app_version` — optional, max length 32. SQL exact match.
  - `labelled` — optional boolean, default `false`. Accepted forms:
    `"true"`, `"false"`, `"1"`, `"0"`. Other values → 400.

  Response body shape (TypeScript interface, also documented in
  `docs/agent-api.md` per T-4910):
  ```typescript
  interface AgentEventsResponse {
    events: AgentEvent[];
    cursor: string | null;   // null when has_more === false
    has_more: boolean;
  }
  interface AgentEvent {
    id: string;                          // UUID
    received_at: string;                 // ISO 8601 UTC
    transcription_anonymised: string;
    intent: string;
    parser_path: string;
    outcome: "success" | "failure" | "unknown";
    slots_anonymised: Record<string, unknown>;  // JSON object, may be {}
    flags: string[];                     // tag list, may be []
    locale: string;
    app_version: string;
    model_version: string;
    existing_label: {
      action: "correct" | "incorrect" | "discard";
      corrected_intent: string | null;
      labelled_by: string;
      labelled_at: string;
    } | null;
  }
  ```

  **`device_id` MUST NOT appear in the response under any circumstance** —
  do not select it from the database, do not include it in any debug log,
  do not surface it via error messages. This is a privacy contract from
  ADR-005.

  SQL (with `labelled = false` — the default and most-common path):
  ```sql
  SELECT e.id, e.received_at, e.transcription_anonymised, e.intent,
         e.parser_path, e.outcome, e.slots_anonymised, e.flags,
         e.locale, e.app_version, e.model_version
    FROM events e
    LEFT JOIN labels l ON l.event_id = e.id
   WHERE l.id IS NULL
     AND ($1::text IS NULL OR e.outcome = $1)
     AND ($2::text IS NULL OR e.parser_path = $2)
     AND ($3::text IS NULL OR e.locale = $3)
     AND ($4::text IS NULL OR e.app_version = $4)
     AND ($5::timestamptz IS NULL OR (e.received_at, e.id) < ($5, $6))
   ORDER BY e.received_at DESC, e.id DESC
   LIMIT $7;
  ```
  Parameter binding: `$1=outcome`, `$2=parser_path`, `$3=locale`,
  `$4=app_version`, `$5=cursor.received_at`, `$6=cursor.id`, `$7=limit + 1`.
  Fetch one extra row to determine `has_more`: if the result has `limit + 1`
  rows, drop the last and set `has_more = true`; otherwise `has_more = false`.

  When `labelled = true`, change the join to `INNER JOIN` and select
  `l.action`, `l.corrected_intent`, `l.labelled_by`, `l.labelled_at` into
  `existing_label`. When `labelled = false`, `existing_label` is always `null`.

  Cursor encoding: after the result set is materialised, take the last
  row and produce
  `cursor = base64(JSON.stringify({ received_at: row.received_at, id: row.id }))`.
  When `has_more === false`, return `cursor: null`.

  Error responses:
  - Invalid cursor (malformed base64 or JSON) → 400 `{ "error": "invalid_cursor" }`.
  - Database error → 500 `{ "error": "internal_error" }`. Log the underlying
    error at error level with the request ID; do not include it in the
    response body.

  **Files added:** `app/api/agent/events/route.ts`,
  `test/unit/api/agent/events.test.ts`.
  **Acceptance criteria:**
  - With no query params and `labelled` defaulted to `false`, returns the
    100 most recent unlabelled events ordered by `received_at DESC, id DESC`.
  - `?limit=5` returns 5 events and a non-null cursor when more exist.
  - Following the cursor with `?after=<cursor>` returns the next 5 events,
    none overlapping the first page.
  - `?outcome=failure` filters to failures only.
  - `?labelled=true` returns events that have a label, with `existing_label`
    populated.
  - `?limit=0` returns 400 `invalid_limit`.
  - `?limit=201` returns 400 `invalid_limit`.
  - `?after=not-base64` returns 400 `invalid_cursor`.
  - No `device_id` field appears in any response payload (verified by a
    snapshot test that fails if any response key matches `/device.?id/i`).
  - Wrong agent key → 401 (auth middleware test).
  - `EXPLAIN ANALYZE` of the default query uses `events_agent_fetch_idx`
    (T-4804).

  *Depends on: T-4801, T-4803, T-4804.*

### Route: label single event

- [ ] **T-4902** Create `app/api/agent/events/[id]/label/route.ts`
  implementing `POST /api/agent/events/:id/label`.

  Request body (validated with `zod`):
  ```typescript
  interface LabelRequestBody {
    action: "correct" | "incorrect" | "discard";
    corrected_intent?: string;
    agent_id: string;            // free-form identifier, 1..64 chars
  }
  ```

  Path parameter `id` must be a valid UUID (zod `.uuid()`); else 400
  `{ "error": "invalid_event_id" }`.

  Body validation rules (delegated to `applyLabel` from T-4806 once the
  request is parsed):
  - `action === "incorrect"` requires `corrected_intent` ∈ `VALID_INTENTS`.
  - `action !== "incorrect"` forbids `corrected_intent`.
  - `agent_id` length 1..64, regex `/^[A-Za-z0-9_.-]+$/` (no whitespace,
    no special chars, no colon — colons are reserved for the `labelled_by`
    prefix).

  Construct `labelledBy = "agent:" + body.agent_id` and call
  `applyLabel({ eventId: id, action, correctedIntent, labelledBy }, db)`.

  Map `LabelValidationError` to HTTP responses:
  - `event_not_found` → 404 `{ "error": "event_not_found" }`
  - `invalid_action` → 400 `{ "error": "invalid_action" }`
  - `missing_corrected_intent` → 400 `{ "error": "missing_corrected_intent" }`
  - `invalid_corrected_intent` → 400 `{ "error": "invalid_corrected_intent", "valid_intents": [...] }`
  - `corrected_intent_not_allowed` → 400 `{ "error": "corrected_intent_not_allowed" }`

  Success response (200):
  ```json
  {
    "id": "<event-uuid>",
    "action": "correct",
    "corrected_intent": null,
    "labelled_by": "agent:nl-trainer-v3",
    "labelled_at": "2026-05-05T12:34:56.000Z"
  }
  ```
  The `id` field is the **event id** (not the label row id), matching the
  shape specified in ADR-005.

  **Files added:** `app/api/agent/events/[id]/label/route.ts`,
  `test/unit/api/agent/events-label.test.ts`.
  **Acceptance criteria:**
  - `POST /api/agent/events/{valid-id}/label` with body
    `{ "action": "correct", "agent_id": "test-agent" }` returns 200 with
    `labelled_by: "agent:test-agent"`.
  - With `{ "action": "incorrect", "corrected_intent": "stop", "agent_id": "test" }`
    on a `setVolume` event: returns 200 and the row is stored.
  - With `{ "action": "incorrect", "agent_id": "test" }` (no
    `corrected_intent`): returns 400 `missing_corrected_intent`.
  - With `{ "action": "incorrect", "corrected_intent": "fly", "agent_id": "test" }`:
    returns 400 `invalid_corrected_intent` and the response body contains the
    full valid intents list.
  - With `{ "action": "correct", "corrected_intent": "stop", "agent_id": "test" }`:
    returns 400 `corrected_intent_not_allowed`.
  - With `agent_id: "has spaces"`: returns 400 `invalid_agent_id`.
  - With `agent_id: ""` or missing: returns 400 from zod schema validation.
  - On a non-existent event id: returns 404 `event_not_found`.
  - Re-labelling a previously-labelled event: returns 200, and the
    `previous_action` column on the `labels` row is now populated with the
    prior `action`.
  - Wrong agent key → 401.

  *Depends on: T-4801, T-4806.*

### Route: label batch

- [ ] **T-4903** Create `app/api/agent/events/label-batch/route.ts`
  implementing `POST /api/agent/events/label-batch`. Allows the agent to
  label up to 200 events in a single HTTP round-trip.

  Request body:
  ```typescript
  interface LabelBatchRequest {
    agent_id: string;            // same constraints as T-4902
    labels: Array<{
      event_id: string;          // UUID
      action: "correct" | "incorrect" | "discard";
      corrected_intent?: string;
    }>;
  }
  ```

  Validation:
  - `labels.length` must be 1..200; else 400
    `{ "error": "invalid_batch_size", "detail": "labels must contain 1..200 entries" }`.
  - `agent_id` validated as in T-4902.
  - Each `labels[i].event_id` is a UUID (zod). Per-entry validation
    failures are collected — they do NOT abort the batch.

  Execution: open a single Postgres transaction (`BEGIN ... COMMIT`).
  For each label entry:
  1. Validate the entry's shape with zod. On failure, push
     `{ event_id: <as-given-or-null>, error: "invalid_<field>" }` into
     `rejected` and continue.
  2. Call `applyLabel` (T-4806) with `labelledBy = "agent:" + body.agent_id`.
  3. On `LabelValidationError`, push
     `{ event_id, error: <error.code> }` into `rejected` and continue.
  4. On success, increment `accepted`.

  Commit the transaction at the end. Partial success means the transaction
  commits with whatever rows succeeded. **Rationale:** ADR-005 specifies
  partial success — individual errors don't abort the batch.

  If the transaction itself fails (Postgres connection error, deadlock,
  etc.), rollback and return 500
  `{ "error": "transaction_failed" }`. Log the underlying error at error
  level.

  Response (200, even when `rejected` is non-empty):
  ```typescript
  interface LabelBatchResponse {
    accepted: number;
    rejected: Array<{
      event_id: string | null;
      error: string;             // one of the LabelValidationError codes,
                                 // or "invalid_event_id", "invalid_action", etc.
    }>;
  }
  ```

  **Files added:** `app/api/agent/events/label-batch/route.ts`,
  `test/unit/api/agent/events-label-batch.test.ts`.
  **Acceptance criteria:**
  - Batch of 3 valid labels: `accepted=3, rejected=[]`, all three rows in
    `labels` table.
  - Batch of 3 where one has a non-existent event id: `accepted=2,
    rejected=[{event_id, error:"event_not_found"}]`, two rows committed.
  - Batch of 200: succeeds within 5 seconds against the dev database.
  - Batch of 201: returns 400 `invalid_batch_size`.
  - Batch of 0: returns 400 `invalid_batch_size`.
  - Batch with one entry missing `event_id`: that entry rejected, others
    proceed.
  - Batch where all entries fail: returns 200 with `accepted=0` and
    `rejected.length=N` (NOT a 4xx — partial-success contract still holds
    when partial = zero).
  - Forcing a transaction-level failure (e.g. by mocking `commit` to
    throw): returns 500 `transaction_failed` and no rows are persisted.
  - Wrong agent key → 401.

  *Depends on: T-4801, T-4806.*

### Route: corpus export

- [ ] **T-4904** Create `app/api/agent/corpus/route.ts` implementing
  `GET /api/agent/corpus`. Exports a deduplicated training corpus suitable
  for retraining the on-device NL model.

  Query parameters:
  - `locale` — optional, BCP-47 string. Filters to events with that locale.
    No default; absent = all locales.
  - `since` — optional, label id (UUID). When provided, returns only rows
    where `labels.id > since` (lexicographic UUID compare is fine since
    new UUIDs are timestamped via UUIDv7 if used; otherwise treat as an
    opaque cursor and use `labels.labelled_at >= (SELECT labelled_at FROM labels WHERE id = $since)`).
    **Decision: use `labels.id` comparison directly with v7 UUIDs.** If
    the schema uses v4 UUIDs, switch to `labelled_at` cursor and document
    the choice in the route file's leading comment.
  - `format` — optional, `"csv"` (default) or `"jsonl"`. Other values →
    400 `{ "error": "invalid_format" }`.

  Selection logic:
  - Include rows where `labels.action = 'correct'` — text label is
    `events.intent`.
  - Include rows where `labels.action = 'incorrect' AND labels.corrected_intent IS NOT NULL` —
    text label is `labels.corrected_intent`.
  - Exclude rows where `labels.action = 'discard'`.
  - Exclude rows with no label.

  SQL:
  ```sql
  SELECT DISTINCT
         e.transcription_anonymised AS text,
         CASE l.action
           WHEN 'correct' THEN e.intent
           WHEN 'incorrect' THEN l.corrected_intent
         END AS label
    FROM events e
    JOIN labels l ON l.event_id = e.id
   WHERE l.action IN ('correct', 'incorrect')
     AND (l.action <> 'incorrect' OR l.corrected_intent IS NOT NULL)
     AND ($1::text IS NULL OR e.locale = $1)
     AND ($2::uuid IS NULL OR l.id > $2)
   ORDER BY text, label;
  ```
  `SELECT DISTINCT` deduplicates same `(text, label)` pairs. Ordering
  produces a stable export.

  Output formats:

  **CSV** (`Content-Type: text/csv; charset=utf-8`):
  - First three bytes: UTF-8 BOM `﻿` (matches the existing corpus
    format used by the iOS NL model build pipeline).
  - Header line: `text,label\n`.
  - Each subsequent line: `<text>,<label>\n` where each field is
    CSV-escaped per RFC 4180:
    - If the field contains `,`, `"`, `\r`, or `\n`, wrap it in double
      quotes and double any internal `"`.
    - Else write it literally.
  - Line endings: `\n` (LF only — matches iOS pipeline convention).

  **JSONL** (`Content-Type: application/x-ndjson; charset=utf-8`):
  - One JSON object per line: `{"text":"...","label":"..."}`.
  - Lines separated by `\n`. No trailing newline after the last line is
    required, but include one for tooling friendliness.
  - Strings are encoded per JSON spec — `JSON.stringify` handles all
    escaping.

  Streaming: stream rows via `ReadableStream` to avoid buffering large
  exports in memory. Use `pg`'s cursor-based reads (or Neon's HTTP-fetch
  API in chunks of 1000) so a 100k-row export does not exceed the SWA
  memory limit.

  Add `Content-Disposition: attachment; filename="voxio-corpus-<locale>-<isodate>.<ext>"`
  for direct download support — `<locale>` defaults to `"all"` if no
  locale param, `<ext>` is `csv` or `jsonl`.

  **Files added:** `app/api/agent/corpus/route.ts`,
  `test/unit/api/agent/corpus.test.ts`.
  **Acceptance criteria:**
  - With no params, default CSV export contains: BOM, `text,label\n`
    header, then deduplicated rows.
  - `?format=jsonl` returns valid NDJSON parseable line-by-line with
    `JSON.parse`.
  - A discarded label does not appear in either format.
  - An incorrect label without `corrected_intent` does not appear (defensive
    — the schema constraint should already prevent this row existing).
  - Two events with identical `transcription_anonymised` and identical
    final label produce only one row in the export.
  - Two events with identical text but different labels produce two rows.
  - `?locale=da-DK` excludes English rows.
  - `?since=<uuid>` excludes labels with id ≤ that uuid.
  - `?format=xml` → 400 `invalid_format`.
  - A row containing a comma in `transcription_anonymised` is correctly
    quoted in CSV and unmodified in JSONL.
  - A row containing a literal `"` is correctly escaped in both formats.
  - The CSV starts with bytes `0xEF 0xBB 0xBF` (UTF-8 BOM).
  - `Content-Disposition` header is present and well-formed.
  - Wrong agent key → 401.

  *Depends on: T-4801, T-4805 (cascade behaviour ensures no orphan label
  rows pollute the export). Independent of T-4806.*

### Tests and observability

- [ ] **T-4905** Add unit tests for the auth middleware at
  `test/unit/lib/agent-auth.test.ts`. Cover all four branches from T-4801
  (missing env, missing header, wrong key, correct key) plus an extra case
  for length-mismatch keys (which must not throw from `timingSafeEqual`).

  Use vitest's `vi.stubEnv` to set and unset `AGENT_API_KEY` per test.
  Construct `Request` objects with the `Headers` API to set / omit
  `x-agent-key`.

  **Acceptance criteria:**
  - All five test cases pass (4 branches + length mismatch).
  - Coverage for `src/lib/agent-auth.ts` is 100% lines + 100% branches.

  *Depends on: T-4801.*

- [ ] **T-4906** Add an integration test at
  `test/integration/agent-flow.test.ts` exercising the full agent workflow
  end-to-end against a clean test database:
  1. Seed 50 events across two locales (`en-US`, `da-DK`), three
     parser paths, and varying outcomes.
  2. `GET /api/agent/events?limit=20` — assert 20 rows, valid cursor.
  3. `GET /api/agent/events?after=<cursor>&limit=20` — assert next 20.
  4. `POST /api/agent/events/{id}/label` with action=correct on 5 events.
  5. `POST /api/agent/events/label-batch` with a 30-entry mix
     (20 correct, 5 incorrect-with-corrected-intent, 3 discard,
     2 invalid event ids) — assert `accepted=28, rejected.length=2`.
  6. `GET /api/agent/events?labelled=false` — assert count decreased
     by 33 (5 + 20 + 5 + 3, the discards still count as labelled).
  7. `GET /api/agent/corpus?format=jsonl` — assert each line is valid
     JSON, the row count matches `correct + incorrect-with-intent`, and no
     `discard` rows appear.
  8. `GET /api/agent/corpus?format=csv&locale=da-DK` — assert BOM, header,
     no `en-US` rows, and stable ordering.
  9. `DELETE /api/telemetry/{deviceId}` (one of the seeded device ids) —
     assert the events for that device disappear from `/api/agent/events`
     AND from `/api/agent/corpus` (cascade verification — ties to T-4805).

  Run against a Neon dev branch dedicated to integration tests; teardown
  truncates `devices`, `events`, `labels` between runs.

  **Acceptance criteria:**
  - The full nine-step flow passes in CI in under 60 seconds.
  - No `device_id` appears anywhere in any agent response (regex assertion
    on every response body).

  *Depends on: T-4901, T-4902, T-4903, T-4904, T-4805.*

- [ ] **T-4907** Add structured logging to every agent route. Each
  successful request logs at info level a single JSON line:
  ```json
  {
    "level": "info",
    "route": "/api/agent/events",
    "method": "GET",
    "agent_authenticated": true,
    "duration_ms": 47,
    "result_count": 100,
    "request_id": "<uuid>"
  }
  ```
  For label routes, include `agent_id` (the validated body field, never
  the API key) and `accepted` / `rejected_count`. For the corpus route,
  include `format`, `row_count`, and `bytes_written`.

  Errors log at error level with the same shape plus `error_code` and
  `error_message`. **Never log the request body for label routes if
  it contains a `corrected_intent`** — the field is anonymised but logging
  it doubles the storage; it is sufficient to log the shape (counts, types)
  not the values. The transcription_anonymised text is never logged at
  any level.

  Use the existing logger from `src/lib/logger.ts` (created in E-47). If
  that file does not exist yet, create a minimal `console.log(JSON.stringify(...))`
  shim and note the dependency on E-47.

  **Acceptance criteria:**
  - A successful `GET /api/agent/events` produces exactly one info log
    line.
  - A 401 produces one warn log line including `agent_authenticated: false`
    but not the rejected key value.
  - A 500 produces one error log line including `error_code` and a stable
    `error_message`.
  - No log line contains the string `AGENT_API_KEY`'s value.
  - No log line contains a `transcription_anonymised` field's value.

  *Depends on: T-4901, T-4902, T-4903, T-4904.*

### Documentation

- [ ] **T-4908** Add the OpenAPI 3.1 spec at `docs/agent-api.openapi.yaml`
  describing all four routes from T-4901 – T-4904. Include:
  - Security scheme: `apiKeyAuth` with `in: header, name: x-agent-key`.
  - Schemas: `AgentEvent`, `AgentEventsResponse`, `LabelRequestBody`,
    `LabelResponse`, `LabelBatchRequest`, `LabelBatchResponse`.
  - Responses for 200, 400, 401, 404, 500, 503 on every route.
  - Example request/response pairs for each route.

  Validate the file with `npx @redocly/cli lint docs/agent-api.openapi.yaml`
  in CI (add to the lint job in `.github/workflows/ci-cd.yml`).

  **Acceptance criteria:**
  - File parses and lints clean with zero errors and zero warnings.
  - The shapes match the TypeScript interfaces in T-4901 – T-4903 exactly
    (no drift).

  *Depends on: T-4901, T-4902, T-4903, T-4904.*

- [ ] **T-4909** Write `docs/agent-api.md` — the prose runbook for the
  agent operator. Sections:
  1. **Overview** — what the API does, who it's for.
  2. **Authentication** — how to obtain `AGENT_API_KEY`, how to send the
     `x-agent-key` header, rotation policy (cross-references
     `docs/runbook-secrets.md`).
  3. **Endpoints** — one subsection per route with a `curl` example.
  4. **Cursor pagination** — explain the opaque cursor and a complete
     end-to-end example fetching all unlabelled events.
  5. **Labelling workflow** — recommended pattern: fetch a page → predict
     labels → submit batch → fetch next page. Include rate-limit
     guidance (target ≤ 10 req/sec; the API does not enforce a hard limit
     in v1, but exceeding 50 req/sec may trip Neon's connection pool).
  6. **Corpus export** — example pipeline ending in feeding the CSV into
     the iOS NL model build script.
  7. **Privacy contract** — explicit statement that responses never
     contain `device_id`, that `labelled_by` is `agent:<agent_id>`, and
     that GDPR deletion of a device (via `/api/telemetry/{deviceId}`)
     also removes the corresponding events from the agent's view.

  **Acceptance criteria:**
  - Document exists at `docs/agent-api.md`.
  - Each `curl` example is copy-pasteable and assumes only `AGENT_API_KEY`
    and the SWA hostname as inputs.
  - Privacy contract section is present and matches ADR-005 exactly.

  *Depends on: T-4901, T-4902, T-4903, T-4904.*

- [ ] **T-4910** End-to-end smoke test against the production deploy.
  After E-49 ships to `main`, the engineering lead runs the following
  against the production SWA hostname using the production `AGENT_API_KEY`:
  ```bash
  H="x-agent-key: $AGENT_API_KEY"
  curl -fsS -H "$H" "$BASE/api/agent/events?limit=1" | jq .
  curl -fsS -H "$H" -X POST -d '{"action":"discard","agent_id":"smoke-test"}' \
    -H "Content-Type: application/json" \
    "$BASE/api/agent/events/$EVENT_ID/label" | jq .
  curl -fsS -H "$H" "$BASE/api/agent/corpus?format=jsonl" | head -5
  ```
  Document the results (status codes, response shapes, elapsed time) in
  `docs/runbook-cicd.md` under a new "Agent API smoke test" section.

  **Acceptance criteria:**
  - All three curls return 200.
  - The labelling curl writes a row to `labels` with
    `labelled_by = "agent:smoke-test"`.
  - The smoke-test row is then deleted manually (or by re-labelling) so
    it does not pollute the corpus.

  *Depends on: T-4901, T-4902, T-4904, T-4802 (production env var set).*
