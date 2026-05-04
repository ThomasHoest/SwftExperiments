# Epics & Tasks: Telemetry Backend & Admin Site (Voxio 1.3)
**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-04
**References:** spec-telemetry-backend-admin.md (v1.1), VoxioSpecification-1.3.md (Feature 1, Flow A — E-35, US-53–55, A-1–A-6), epics-and-tasks-voxio-1.2.md (format reference), CLAUDE.md
**Stack:** TypeScript, Next.js 15 (hybrid mode), Postgres (Neon serverless), deployed to Azure Static Web Apps Standard plan

---

## Overview

This document breaks the approved Telemetry Backend & Admin Site specification (v1.1) into epics and constituent tasks. The deliverable is a single Next.js 15 hybrid web application deployed to Azure Static Web Apps. It hosts the telemetry ingest API used by the Voxio iOS app (Flow A in `VoxioSpecification-1.3.md`) and the authenticated admin labelling site used by the Voxio team. There is no separate backend service — Route Handlers under `app/api/*/route.ts` and admin pages under `app/admin/*/page.tsx` are shipped together.

This is a **new repository**, separate from the iOS Xcode project at `iOS/Voxio.xcodeproj`. All paths in tasks below are relative to the new repo root unless otherwise noted. The repo is owned by the Voxio team and follows the TheCheapPowerCompany GitHub Actions pattern: lint → vitest → `next build` → SWA deploy → Playwright E2E.

Epic numbering begins at **E-41**, continuing from `VoxioSpecification-1.3.md` which ends at E-40. Task numbering begins at **T-4101**, continuing from T-4006.

---

## Epic Index

| # | Epic | User Stories | Feature Area |
|---|---|---|---|
| E-41 | Infrastructure and CI/CD | (operations) | Repo bootstrap, SWA + Neon provisioning, GitHub Actions, UptimeRobot |
| E-42 | Database Schema and Migrations | (data layer for US-A1–A5, US-53) | Postgres tables, indexes, ON DELETE CASCADE, migration tooling |
| E-43 | Telemetry Ingest API | US-54, US-53 | `POST /api/telemetry/batch`, `DELETE /api/telemetry/{deviceId}`, `GET /api/health` |
| E-44 | Admin Authentication and Route Protection | US-A1 (auth gate) | SWA built-in GitHub OAuth, `staticwebapp.config.json` role rules, admin shell |
| E-45 | Admin Events UI | US-A1, US-A2 | Events list, event detail, labelling control, admin API routes |
| E-46 | Admin Export and Stats | US-A3, US-A4, US-A5 | CSV export, stats dashboard, GDPR deletion form |
| E-47 | Testing and Observability | (cross-cutting) | Vitest unit tests, Playwright E2E, structured logging, App Insights |

---

## E-41 — Infrastructure and CI/CD

Bootstrap the new repository, create the Azure Static Web Apps Standard-plan instance and the Neon Postgres project in matching regions, configure GitHub Actions to deploy preview environments per pull request and production on `main`, and configure the UptimeRobot keep-alive monitor. This epic produces no application functionality on its own — it produces the deployment pipeline and the running (empty) infrastructure that every subsequent epic builds on.

The SWA region and matching Neon region are a **blocking pre-provisioning prerequisite** per spec v1.1 (Technical Context, "Database region"). The engineering lead must confirm the SWA region before T-4102 / T-4103 are executed; the Neon project region cannot be changed after creation without deleting the database.

**Depends on:** none — this is the foundation epic.
**Unlocks:** all subsequent epics (E-42 needs the Neon project; E-43–E-46 need the SWA app and Route Handler surface; E-47 needs the CI pipeline).

---

### Repository bootstrap

- [ ] **T-4101** Create a new GitHub repository `voxio-telemetry` (or the team's preferred name) under the Voxio team's GitHub organisation. Initialise with `.gitignore` for Node + Next.js, an MIT or proprietary licence file as the team prefers, and a `README.md` that links to `spec-telemetry-backend-admin.md` and this epics document. Default branch: `main`. Configure branch protection: require PR review, require status checks (`lint`, `unit`, `build`, `e2e`) before merge.

  Initialise the project with Next.js 15 in hybrid mode:
  ```
  npx create-next-app@latest . --typescript --eslint --tailwind --app --src-dir --import-alias "@/*"
  ```
  Then edit `next.config.ts` to add `output: 'standalone'` (required for SWA + Next.js hybrid). Add the `staticwebapp.config.json` placeholder file at the repo root (rules added in E-44).

  Add the following dev dependencies: `vitest`, `@vitest/ui`, `@playwright/test`, `tsx`, `@types/node`. Runtime dependencies: `@neondatabase/serverless`, `zod` (request validation).

  Commit and push the initial scaffold. Open a draft PR to verify the repository is set up correctly before adding deployment workflows.
  *No dependencies. Prerequisite for all subsequent tasks.*

### Cloud provisioning

- [ ] **T-4102** **Pre-provisioning: confirm SWA region.** The engineering lead must record the SWA deployment region (West Europe or East US) in `docs/decisions/region.md`. This decision is irreversible without recreating the Neon project and losing all data. Once the region is confirmed in writing, T-4103 and T-4104 may proceed.
  *Depends on: T-4101.*

- [ ] **T-4103** Create the Azure Static Web Apps resource in the confirmed region (T-4102) on the **Standard plan** (~$9/month). Standard plan is required for custom auth roles (`admin`) and for preview environments per PR. Configure:
  - SKU: Standard
  - Region: as recorded in `docs/decisions/region.md`
  - Source: GitHub repository `voxio-telemetry`, branch `main`
  - Build preset: Next.js
  - App location: `/`
  - Output location: (leave empty — SWA detects Next.js standalone output)

  After creation, retrieve the SWA deployment token from the Azure portal (Manage deployment token). Store it as the GitHub Actions secret `AZURE_STATIC_WEB_APPS_API_TOKEN` on the `voxio-telemetry` repository. Note the SWA hostname (e.g. `https://voxio-telemetry-<random>.<region>.azurestaticapps.net`) and record it in `docs/decisions/region.md`.
  *Depends on: T-4102.*

- [ ] **T-4104** Create the Neon Postgres project in the **matching region** as confirmed in T-4102:
  - West Europe SWA → `aws-eu-central-1`
  - East US SWA → `aws-us-east-1`

  Project name: `voxio-telemetry`. Plan: Free tier (0.5 GB storage, 100 CU-hours/month, scale-to-zero). Default database: `voxio` (or the Neon-default `neondb` — record the choice). Capture the connection string from the Neon dashboard in the form `postgres://<user>:<password>@<host>/<database>?sslmode=require`. Store it as the SWA Application Setting `DATABASE_URL` (Standard plan SWA → Configuration blade in Azure portal). The string is encrypted at rest by SWA and only injected into the managed runtime — never log it, never commit it.
  *Depends on: T-4102, T-4103.*

- [ ] **T-4105** Generate and configure the telemetry API key. Run `openssl rand -hex 32` locally to produce a 64-character (256-bit) random key. Store it as the SWA Application Setting `TELEMETRY_API_KEY`. Communicate the key to the iOS team via a secure channel (1Password vault or equivalent) so they can ship it in the iOS app's Keychain seed (per `VoxioSpecification-1.3.md` T-3507). Document the rotation procedure in `docs/runbook-secrets.md`: rotation = generate a new key, update the SWA env var, ship a new iOS release. The old and new keys may be accepted in parallel for one release window if `TELEMETRY_API_KEY_PREVIOUS` is set (optional; out of scope for v1).
  *Depends on: T-4103.*

### CI/CD pipeline

- [ ] **T-4106** Create `.github/workflows/ci-cd.yml` following the TheCheapPowerCompany pattern. Triggers: `push` to `main`, `pull_request` to `main`. Jobs:
  1. **lint** — `npm ci` then `npm run lint` (ESLint default Next.js config).
  2. **unit** — `npm ci` then `npm run test:unit` (vitest, exit code 0 required).
  3. **build** — `npm ci` then `npm run build`. Required to confirm the Next.js standalone build succeeds.
  4. **deploy** — uses `Azure/static-web-apps-deploy@v1` with `AZURE_STATIC_WEB_APPS_API_TOKEN`. On `pull_request`, deploys to the ephemeral preview environment for that PR (Standard plan feature). On `push` to `main`, deploys to production. Sets `app_location: /`, `api_location: ""`, `output_location: ""` (Next.js detection handles the rest).
  5. **e2e** — runs after `deploy`. `npm run test:e2e` against the just-deployed preview URL (passed in via `${{ steps.deploy.outputs.static_web_app_url }}`). Playwright tests must complete within 5 minutes. Failures block the PR but do not roll back production (preview-only).

  Job dependencies: `unit` and `lint` run in parallel; `build` after both succeed; `deploy` after `build`; `e2e` after `deploy`.

  TypeScript interface for the workflow shape is documented inline. Use `actions/setup-node@v4` with Node 20 (Next.js 15 supported runtime).
  *Depends on: T-4101, T-4103.*

- [ ] **T-4107** Configure `.env.local.example` at the repo root with the development environment variable names (no values):
  ```
  # Database (Neon connection string for local dev — see runbook-local-dev.md)
  DATABASE_URL=

  # API key for the iOS app to authenticate telemetry uploads (from openssl rand -hex 32)
  TELEMETRY_API_KEY=

  # Optional: previous API key accepted in parallel during rotation
  TELEMETRY_API_KEY_PREVIOUS=
  ```
  Add `.env.local` to `.gitignore` (already present from create-next-app). Document in `docs/runbook-local-dev.md` how a developer creates their own Neon dev branch (Neon supports per-developer branches at no extra cost on the free tier) and pastes the dev branch connection string into `.env.local`.
  *Depends on: T-4101, T-4104.*

### Cold-start mitigation

- [ ] **T-4108** Configure the UptimeRobot free-tier keep-alive monitor. Sign in to UptimeRobot (free account, supports up to 50 monitors at 5-minute intervals). Add a new HTTP(s) monitor:
  - URL: `https://<swa-hostname>/api/health` (the SWA hostname from T-4103)
  - Interval: 5 minutes
  - Type: HTTP(s)
  - Alert contacts: engineering lead's email (free tier limit)

  Document the monitor URL and login owner in `docs/runbook-monitoring.md`. **Do not** add a GitHub Actions cron for the same purpose — a 5-minute cron on a private repo runs ~8,640 times/month (~4,320 billed minutes), exceeding the 2,000-minute free tier and adding ~$18/month in overage. Per spec v1.1, UptimeRobot is the correct tool.

  Note: T-4108 may be paused during initial development if `/api/health` does not yet exist; resume after T-4304 ships.
  *Depends on: T-4103. Soft-blocks on T-4304 (the `/api/health` endpoint).*

### Verification

- [ ] **T-4109** End-to-end pipeline smoke test. Push a trivial change (e.g. a typo fix in `README.md`) on a branch, open a PR, observe the CI pipeline run lint → unit → build → deploy (to preview) → e2e. Confirm the SWA preview URL is reachable and returns the Next.js default page. Merge the PR; confirm production deploy succeeds. Record the elapsed time of each step in `docs/runbook-cicd.md` for future regression detection.
  *Depends on: T-4106.*

---

## E-42 — Database Schema and Migrations

Define the Postgres schema for the three core tables (`devices`, `events`, `labels`), the indexes required for admin filtering and stats queries, and the `ON DELETE CASCADE` foreign keys that make the GDPR deletion endpoint a one-statement operation. Set up a lightweight SQL migration tool runnable from CI and locally. Seed local dev data so engineers can build admin UI without depending on iOS uploads.

**Depends on:** E-41 (T-4104 — Neon project must exist).
**Unlocks:** E-43 (Route Handlers write to these tables), E-45 / E-46 (admin pages query these tables).

---

### Migration tooling

- [ ] **T-4201** Add `node-pg-migrate` as a dev dependency. Initialise with `npx node-pg-migrate -d migrations -j ts`. Configure `package.json` scripts:
  ```
  "migrate:up":   "node-pg-migrate -d migrations -j ts up",
  "migrate:down": "node-pg-migrate -d migrations -j ts down",
  "migrate:create": "node-pg-migrate -d migrations -j ts create"
  ```
  `DATABASE_URL` is read from the environment. Migrations are written in TypeScript (`migrations/*.ts`). Document the workflow in `docs/runbook-migrations.md`: create migration → review SQL → run locally against dev branch → commit → CI applies to production on merge to `main`.

  Per spec v1.1 Open Question 9, the default assumption is `node-pg-migrate`. If the engineering lead overrules in favour of plain SQL files invoked from a custom script, replace this task before any migrations are written.
  *Depends on: T-4101, T-4104.*

- [ ] **T-4202** Add a `db:migrate` step to the CI pipeline (T-4106) that runs after the `deploy` job succeeds and before `e2e`. The step runs `npm run migrate:up` against the production `DATABASE_URL` (or the preview branch's `DATABASE_URL`, if the preview deploys to a per-PR Neon branch). Failures block the deployment from being marked successful. Migrations must be forward-compatible (additive only — new columns nullable, new tables, no destructive ALTER) so a partially deployed migration never breaks the previous app version (per spec v1.1 NFR "Availability").
  *Depends on: T-4201, T-4106.*

### Schema — `devices` table

- [ ] **T-4203** Create migration `migrations/<timestamp>_create_devices.ts` that adds the `devices` table:
  ```sql
  CREATE TABLE devices (
    device_id     UUID         PRIMARY KEY,
    first_seen_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    last_upload_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    app_version   TEXT,
    model_version TEXT,
    locale        TEXT
  );
  CREATE INDEX devices_last_seen_at_idx ON devices (last_seen_at DESC);
  ```
  `device_id` is the anonymous UUID supplied by the iOS app per A-1 / T-3507. `last_upload_at` is updated on every accepted batch and is the column consulted by the rate-limit logic in T-4302.
  *Depends on: T-4201.*

### Schema — `events` table

- [ ] **T-4204** Create migration `migrations/<timestamp>_create_events.ts` that adds the `events` table:
  ```sql
  CREATE TABLE events (
    id                        BIGSERIAL    PRIMARY KEY,
    device_id                 UUID         NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
    received_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
    client_timestamp          TIMESTAMPTZ  NOT NULL,
    app_version               TEXT         NOT NULL,
    model_version             TEXT         NOT NULL,
    locale                    TEXT         NOT NULL,
    transcription_anonymised  TEXT         NOT NULL,
    intent                    TEXT         NOT NULL,
    slots_anonymised          JSONB        NOT NULL DEFAULT '{}'::jsonb,
    parser_path               TEXT         NOT NULL,
    outcome                   TEXT         NOT NULL,
    flags                     TEXT[]       NOT NULL DEFAULT '{}'::text[]
  );
  CREATE INDEX events_received_at_idx       ON events (received_at DESC);
  CREATE INDEX events_client_timestamp_idx  ON events (client_timestamp DESC);
  CREATE INDEX events_device_id_idx         ON events (device_id);
  CREATE INDEX events_intent_idx            ON events (intent);
  CREATE INDEX events_parser_path_idx       ON events (parser_path);
  CREATE INDEX events_outcome_idx           ON events (outcome);
  CREATE INDEX events_locale_idx            ON events (locale);
  CREATE INDEX events_flags_gin_idx         ON events USING GIN (flags);
  ```
  Field constraints follow the API spec (Field constraints table in `spec-telemetry-backend-admin.md`):
  - `parser_path` ∈ {`PersonalisationAlias`, `PersonalisationMemory`, `FoundationModels`, `NLModel`, `KeywordRegex`, `Unknown`}
  - `outcome` ∈ {`confirmed`, `cancelled`, `timedOut`, `unknown`}
  - `flags` is a Postgres text array, queryable with `flags && ARRAY['likelyMisparse']` for membership checks.

  Indexes are chosen for the admin filter set defined in US-A1: date range (received_at + client_timestamp), intent, parser_path, outcome, locale, flag presence. The GIN index on `flags` makes flag presence filters O(log n) rather than full-scan. Free-text substring on `transcription_anonymised` is a `LIKE` scan in v1; revisit if perf is poor at >1M rows.
  *Depends on: T-4203.*

### Schema — `labels` table

- [ ] **T-4205** Create migration `migrations/<timestamp>_create_labels.ts` that adds the `labels` table:
  ```sql
  CREATE TABLE labels (
    id                  BIGSERIAL    PRIMARY KEY,
    event_id            BIGINT       NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    action              TEXT         NOT NULL CHECK (action IN ('correct', 'incorrect', 'discard')),
    corrected_intent    TEXT,
    labelled_by         TEXT         NOT NULL,
    labelled_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    previous_action     TEXT,
    previous_corrected_intent TEXT
  );
  CREATE INDEX labels_event_id_idx        ON labels (event_id);
  CREATE INDEX labels_labelled_at_idx     ON labels (labelled_at DESC);
  CREATE INDEX labels_labelled_by_idx     ON labels (labelled_by);
  ```
  Schema notes:
  - `corrected_intent` is non-null only when `action = 'incorrect'`. Application validates this; DB does not enforce it via CHECK to keep the constraint simple (per spec v1.1 NFR — labels are write-mostly, validation happens at the API).
  - `labelled_by` is the GitHub username from `clientPrincipal.userDetails` (per US-A2).
  - `previous_action` and `previous_corrected_intent` capture the prior label whenever an admin overwrites — fulfilling spec v1.1 Open Question 5 default ("most-recent label wins for export; previous label preserved server-side").
  - One row per (event, admin) pair is enforced at the API layer (E-45 T-4503): updating a label issues an `UPDATE` not an `INSERT`. The `previous_*` columns capture the prior values within the same row.
  - `ON DELETE CASCADE` on `event_id` ensures GDPR deletion of an event removes its labels. Combined with `ON DELETE CASCADE` on `events.device_id`, a single `DELETE FROM devices WHERE device_id = $1` cascades through both tables (per spec API "DELETE /api/telemetry/{deviceId}").
  *Depends on: T-4204.*

### Local dev seed data

- [ ] **T-4206** Add `scripts/seed-dev.ts` that populates the local Neon dev branch with synthetic test data: 5 devices, ~500 events spread over 14 days across both locales (`en-US`, `da-DK`), all five parser paths, all four outcomes, ~10% labelled with mixed `correct`/`incorrect`/`discard` actions, ~5% flagged `likelyMisparse`. Use `@faker-js/faker` for synthetic transcriptions (anonymised tokens like `play favorite [HASH:abc123]`). Add a `package.json` script `"db:seed": "tsx scripts/seed-dev.ts"`. Document in `docs/runbook-local-dev.md` that `npm run migrate:up && npm run db:seed` produces a working local environment for admin UI development.

  The seed script must refuse to run if `DATABASE_URL` points at a production-like host (heuristic: connection string contains `prod` or matches the recorded production hostname). Document the safety check inline.
  *Depends on: T-4203, T-4204, T-4205.*

### Verification

- [ ] **T-4207** Schema sanity test in `tests/unit/schema.test.ts`. Connects to a fresh Neon dev branch, runs all migrations, asserts: (a) all three tables exist with the expected columns and types; (b) all indexes exist; (c) inserting a `devices` row, then an `events` row referencing it, then a `labels` row, then `DELETE FROM devices WHERE device_id = ...` cascades both tables to empty; (d) inserting an event with an invalid `outcome` value succeeds at DB level (validation is the API's job — confirm absence of CHECK constraint on `outcome`); (e) inserting a label with `action = 'invalid'` fails with the CHECK constraint error. Tests use a per-test transaction wrapper that rolls back on completion to keep the dev branch clean.
  *Depends on: T-4206.*

---

## E-43 — Telemetry Ingest API

Implement the three public Route Handlers consumed by the iOS app: `POST /api/telemetry/batch` (ingest), `DELETE /api/telemetry/{deviceId}` (GDPR deletion), and `GET /api/health` (UptimeRobot keep-alive). All three are defined under `src/app/api/...`. None of these endpoints are behind SWA role auth — they are gated by the static `X-Api-Key` header (ingest, deletion) or are entirely public (health). Admin endpoints under `/api/admin/*` are introduced in E-45.

**Depends on:** E-41 (SWA + Neon provisioned), E-42 (tables and indexes exist).
**Unlocks:** UptimeRobot monitor (T-4108) needs `/api/health`; iOS Flow A integration testing depends on this epic.

---

### Shared infrastructure

- [ ] **T-4301** Create `src/lib/db.ts` exporting a singleton Neon serverless client. Uses `@neondatabase/serverless`:
  ```ts
  import { neon, NeonQueryFunction } from '@neondatabase/serverless';

  const sql: NeonQueryFunction<false, false> = neon(process.env.DATABASE_URL!);
  export { sql };
  ```
  All Route Handlers import `sql` from `@/lib/db`. The HTTP-based driver works in the SWA-managed App Service runtime (per spec v1.1 Technical Context — no connection pooler needed). On `DATABASE_URL` missing or malformed, the import throws synchronously — confirm this fails CI clearly rather than at first request.
  *Depends on: T-4101, T-4104.*

- [ ] **T-4302** Create `src/lib/auth.ts` exporting `requireApiKey(request: Request): NextResponse | null`. Reads the `X-Api-Key` header, compares (constant-time string compare) against `process.env.TELEMETRY_API_KEY`. Returns `null` if valid (caller proceeds), or a `NextResponse.json({ error: 'Invalid API key' }, { status: 401 })` if missing or wrong. Logs at WARN with source IP (from `request.headers.get('x-forwarded-for')`) when the key is wrong; logs nothing when the key is missing (treated as expected adversarial traffic per spec v1.1 Error States).

  Optional: also accept `process.env.TELEMETRY_API_KEY_PREVIOUS` to support rotation windows (per T-4105). If both env vars are set, accept either.
  *Depends on: T-4105.*

- [ ] **T-4303** Create `src/lib/logger.ts` exporting `logInfo(msg, fields)`, `logWarn(msg, fields)`, `logError(msg, fields)`. All emit structured JSON via `console.log` / `console.warn` / `console.error` so SWA's Application Insights integration captures them per spec v1.1 NFR "Observability":
  ```ts
  function emit(level: 'INFO' | 'WARN' | 'ERROR', msg: string, fields?: Record<string, unknown>) {
    const line = JSON.stringify({ ts: new Date().toISOString(), level, msg, ...fields });
    if (level === 'ERROR') console.error(line);
    else if (level === 'WARN') console.warn(line);
    else console.log(line);
  }
  ```
  Strict rule: the ingest handler **must not log request bodies** — they contain anonymised transcriptions and per spec v1.1 NFR "Security" no transcription text is logged. Only log batch size, device id, accepted/rejected counts, response status.
  *Depends on: T-4101.*

### `GET /api/health`

- [ ] **T-4304** Create `src/app/api/health/route.ts` exporting `GET`:
  ```ts
  export async function GET() {
    return Response.json({ status: 'ok', timestamp: new Date().toISOString() }, { status: 200 });
  }
  ```
  Does **not** touch the database — the goal is to keep the App Service warm without keeping Neon awake (per spec v1.1 API "GET /api/health"). Response time on a warm backend < 100 ms; on a cold backend may exceed 5 seconds (acknowledged behaviour).
  *Depends on: T-4101.*

### `POST /api/telemetry/batch`

- [ ] **T-4305** Create `src/lib/schemas/batch.ts` exporting Zod schemas for the ingest request body. Mirrors the API spec field constraints exactly:
  ```ts
  import { z } from 'zod';

  export const eventSchema = z.object({
    transcriptionAnonymised: z.string().min(1).max(2000),
    intent: z.string().min(1).max(64),
    slotsAnonymised: z.record(z.string(), z.unknown()).default({}),
    parserPath: z.enum([
      'PersonalisationAlias',
      'PersonalisationMemory',
      'FoundationModels',
      'NLModel',
      'KeywordRegex',
      'Unknown',
    ]),
    outcome: z.enum(['confirmed', 'cancelled', 'timedOut', 'unknown']),
    locale: z.string().regex(/^[a-z]{2}-[A-Z]{2}$/),
    timestamp: z.string().datetime({ offset: true }),
    flags: z.array(z.enum(['likelyMisparse', 'recoverableUnknown', 'broadcast'])).default([]),
  });

  export const batchSchema = z.object({
    deviceId: z.string().uuid(),
    appVersion: z.string().min(1).max(32),
    modelVersion: z.string().min(1).max(64),
    events: z.array(eventSchema).min(1).max(100),
  });

  export type Batch = z.infer<typeof batchSchema>;
  ```
  Zod `.safeParse` is used by the Route Handler to extract a list of failed-event indices when partial validation fails (per spec API "Behaviour" — events that fail validation are reported in the `errors` array but the batch still returns 202 if at least one event was written).
  *Depends on: T-4101.*

- [ ] **T-4306** Create `src/app/api/telemetry/batch/route.ts` exporting `POST`. Pipeline:
  1. Call `requireApiKey(request)`. If non-null, return immediately (401).
  2. Read raw body via `await request.text()`. If `Content-Length > 1_048_576` (1 MB) or `body.length > 1_048_576`, return 413 `{ error: 'Batch too large' }`.
  3. JSON.parse the body. On parse failure, return 400 `{ error: 'Invalid request body', detail: 'Malformed JSON' }`.
  4. Validate with `batchSchema.safeParse`. If `success === false`, return 400 with `detail` describing the first failing field.
  5. Rate limit check (T-4307).
  6. Per-event write (T-4308).
  7. Upsert `devices` row (T-4309).
  8. Return 202 with `{ accepted, rejected, errors }`.

  Wraps each step in `try/catch`. Database errors return 500 `{ error: 'Server error' }`. Neon connection timeout (>10 s) returns 503 `{ error: 'Database unavailable' }`. Logs at INFO on success: `{ deviceId, batchSize, accepted, rejected, status: 202 }`. Logs at ERROR on 5xx with the exception message but **never the request body**.
  *Depends on: T-4301, T-4302, T-4303, T-4305.*

- [ ] **T-4307** Implement per-device rate limit inside `POST /api/telemetry/batch`. Single SQL statement using `last_upload_at` on `devices` (per spec v1.1 Technical Context "Per-device rate limiting"):
  ```sql
  UPDATE devices
  SET last_upload_at = now()
  WHERE device_id = $1
    AND last_upload_at < now() - interval '60 seconds'
  RETURNING device_id;
  ```
  - If the row exists and `last_upload_at` is recent (no row returned), the request is rate-limited. Return 429 with header `Retry-After: 60` and body `{ error: 'Rate limit exceeded', retryAfterSeconds: 60 }`.
  - If the row does not exist (first batch from this device), the UPDATE returns 0 rows but is not a rate-limit hit — handle by attempting the INSERT path in T-4309. The race between concurrent first-batch requests is not a meaningful concern given the iOS upload schedule (≤ 1 per hour).
  - Distinguish "no row, never seen" from "row exists, rate-limited" by issuing a second `SELECT 1 FROM devices WHERE device_id = $1` only if the UPDATE returned 0 rows. This is acceptable given the 1-batch-per-60-s ceiling.

  Open Question 7 in spec v1.1 reserves the option to switch to an in-process LRU map if the SQL approach has measurable latency cost. Implement the SQL approach as the default and benchmark in T-4310.
  *Depends on: T-4306.*

- [ ] **T-4308** Implement per-event write inside `POST /api/telemetry/batch`. Insert all valid events in a single multi-row INSERT for performance:
  ```sql
  INSERT INTO events (
    device_id, client_timestamp, app_version, model_version, locale,
    transcription_anonymised, intent, slots_anonymised, parser_path, outcome, flags
  ) VALUES ($1, $2, ...), ($1, $3, ...), ... ;
  ```
  Use parameterised queries via the `sql` tag from `@neondatabase/serverless`. Batch-level fields (`device_id`, `app_version`, `model_version`) are denormalised onto each row per spec API "Behaviour" (paragraph after the `POST /api/telemetry/batch` Responses table).

  Validation is per-event: a malformed event in an otherwise valid batch is recorded in the response `errors: [{ index, reason }]` array and not inserted. If at least one event was inserted, return 202; if all events failed validation, return 400 `{ error: 'Invalid request body', detail: 'No valid events' }`. Events that fail Zod validation in T-4305 are surfaced through this same `errors` array.
  *Depends on: T-4307.*

- [ ] **T-4309** Implement `devices` upsert inside `POST /api/telemetry/batch`. After event INSERT succeeds, run:
  ```sql
  INSERT INTO devices (device_id, first_seen_at, last_seen_at, last_upload_at, app_version, model_version, locale)
  VALUES ($1, now(), now(), now(), $2, $3, $4)
  ON CONFLICT (device_id) DO UPDATE
  SET last_seen_at  = now(),
      last_upload_at = now(),
      app_version   = EXCLUDED.app_version,
      model_version = EXCLUDED.model_version,
      locale        = EXCLUDED.locale;
  ```
  `locale` is taken from the first event in the batch (all events in a batch share a locale per iOS-side anonymisation). The combination of T-4307 (UPDATE-and-check) and T-4309 (INSERT … ON CONFLICT … UPDATE) handles both first-time and returning devices in two SQL statements.

  Order matters: the rate-limit UPDATE in T-4307 runs first; if it succeeds (or this is a brand-new device), proceed to event INSERT (T-4308) and then this devices upsert. If the events INSERT fails, the devices upsert does not run — events and device-row writes are not in a transaction in v1 (acceptable because the iOS app retries the entire batch on 5xx).
  *Depends on: T-4308.*

- [ ] **T-4310** Add a benchmark/perf check in `tests/perf/ingest.bench.ts` that posts 100 batches of 100 events each against a local Neon dev branch and asserts the 99th-percentile end-to-end latency stays below 1.5 seconds (warm backend) per spec v1.1 NFR "Latency". Runs locally only — not in CI by default — but documented in `docs/runbook-perf.md`. If T-4307's SQL approach pushes p99 above 1.5 s, this benchmark surfaces the regression and triggers the fallback to an in-process LRU map (Open Question 7).
  *Depends on: T-4309.*

### `DELETE /api/telemetry/{deviceId}`

- [ ] **T-4311** Create `src/app/api/telemetry/[deviceId]/route.ts` exporting `DELETE`. Pipeline:
  1. Call `requireApiKey(request)`. If non-null, return 401.
  2. Validate `params.deviceId` is a valid UUID v4 via `z.string().uuid().safeParse(params.deviceId)`. On failure, return 400 `{ error: 'Invalid deviceId' }`.
  3. Run `DELETE FROM devices WHERE device_id = $1 RETURNING (SELECT count(*) FROM events WHERE device_id = $1) AS event_count, (SELECT count(*) FROM labels l JOIN events e ON l.event_id = e.id WHERE e.device_id = $1) AS label_count`. Capture `event_count` and `label_count` **before** the cascade fires by issuing two `SELECT count(*)` queries first, then the `DELETE`.

     Concretely:
     ```sql
     -- Step 1: count what is about to be deleted
     SELECT (SELECT count(*) FROM events WHERE device_id = $1) AS events,
            (SELECT count(*) FROM labels l JOIN events e ON l.event_id = e.id WHERE e.device_id = $1) AS labels,
            (SELECT count(*) FROM devices WHERE device_id = $1) AS devices;
     -- Step 2: cascade delete
     DELETE FROM devices WHERE device_id = $1;
     ```
  4. Return 200 `{ deleted: { events, labels, devices } }`. Idempotent — if the device does not exist, all counts are 0 and status is still 200 per spec API "DELETE /api/telemetry/{deviceId}".
  5. Log at INFO: `{ deviceId, eventsDeleted, labelsDeleted, status: 200 }`.

  No transaction is required: the `DELETE FROM devices` cascades atomically through Postgres. The two SELECTs and the DELETE can run as separate statements; minor count drift between SELECT and DELETE is acceptable for a final delete log entry.
  *Depends on: T-4301, T-4302, T-4303.*

### Verification

- [ ] **T-4312** Unit tests in `tests/unit/api-telemetry-batch.test.ts` and `tests/unit/api-telemetry-delete.test.ts`. Use vitest. Mock `@/lib/db` with an in-memory adapter. Tests cover:
  - Ingest: missing key → 401; wrong key → 401; valid batch → 202 with correct accepted count; batch with one malformed event → 202 with `rejected: 1` and `errors[0].index`; all-malformed batch → 400; oversized body (>1 MB) → 413; >100 events → 400; rate-limit hit on second batch within 60 s → 429 with `Retry-After: 60` header.
  - Deletion: missing key → 401; non-UUID deviceId → 400; valid deviceId with data → 200 with non-zero counts; valid deviceId with no data → 200 with zero counts; DB error during DELETE → 500.
  - Health: returns 200 with `status: ok` and a parseable ISO timestamp; does not invoke `sql` (assert mock was not called).
  *Depends on: T-4306, T-4309, T-4311, T-4304.*

- [ ] **T-4313** Manual integration test: from a developer machine, generate a sample batch JSON file matching the spec request body, POST it via `curl` against the deployed preview URL with the correct `X-Api-Key`, observe a 202 response, then query `SELECT * FROM events ORDER BY received_at DESC LIMIT 5` against the corresponding Neon branch and confirm the row landed correctly. Then call `DELETE /api/telemetry/{deviceId}` for the same `deviceId`, observe a 200 with `events: 1`, and re-query to confirm the row is gone. Document the curl invocation in `docs/runbook-manual-tests.md`.
  *Depends on: T-4306, T-4311, T-4109.*

---

## E-44 — Admin Authentication and Route Protection

Configure SWA built-in GitHub OAuth and the `staticwebapp.config.json` rules that gate `/admin/*` and `/api/admin/*` behind the custom `admin` role. Build the admin shell layout (top nav, sign-out link, current-user display). Build the sign-in landing page at `/admin` for unauthenticated visitors and the access-denied state for signed-in non-admin users. The application contains zero auth code — all enforcement is declarative in `staticwebapp.config.json`, and identity flows from the SWA-injected `clientPrincipal`.

**Depends on:** E-41 (SWA Standard plan exists; only Standard supports custom roles).
**Unlocks:** E-45, E-46 (admin pages render inside the admin shell).

---

### SWA configuration

- [ ] **T-4401** Edit `staticwebapp.config.json` at the repo root. Add the route rules and identity provider configuration:
  ```json
  {
    "routes": [
      { "route": "/admin/*",      "allowedRoles": ["admin"] },
      { "route": "/api/admin/*",  "allowedRoles": ["admin"] }
    ],
    "responseOverrides": {
      "401": { "redirect": "/.auth/login/github", "statusCode": 302 },
      "403": { "rewrite":  "/admin/access-denied" }
    },
    "auth": {
      "identityProviders": {
        "gitHub": { "registration": { "clientIdSettingName": "GITHUB_CLIENT_ID", "clientSecretSettingName": "GITHUB_CLIENT_SECRET" } }
      }
    }
  }
  ```
  Per spec v1.1 Open Question 1, the default is to use SWA's pre-configured GitHub provider (no custom OAuth app required). If the team chooses to use the pre-configured provider, omit the `registration` block — SWA uses its built-in app and admin emails are not exposed. Document the chosen mode in `docs/decisions/auth.md`.

  After this file lands, the SWA runtime enforces 401 on anonymous access to `/admin/*` and 403 on signed-in-but-not-admin access — **before** any Next.js Route Handler or page renders. A Next.js bug or accidental commit cannot leak admin functionality.
  *Depends on: T-4103.*

- [ ] **T-4402** Configure the `admin` custom role in the Azure portal. Per spec v1.1 Technical Context: navigate to the SWA resource → Role Management → Invite. For each engineering team member who needs admin access, enter their GitHub username, role `admin`, and send the invitation. They sign in via `/.auth/login/github` once and the admin role attaches to their session.

  Document the on/off-boarding procedure in `docs/runbook-admin-roles.md`: how to add a new admin (Azure portal Role Management invite), how to remove (revoke from same blade), and the maximum (no SWA hard limit; team-policy limit ~5 admins per spec NFR Cost).
  *Depends on: T-4401.*

### Admin shell layout

- [ ] **T-4403** Create `src/lib/auth/clientPrincipal.ts` exporting `getClientPrincipal(request: Request): ClientPrincipal | null`. Reads the SWA-injected `x-ms-client-principal` header (base64-encoded JSON), decodes it, and returns:
  ```ts
  type ClientPrincipal = {
    identityProvider: 'github';
    userId: string;
    userDetails: string;          // GitHub username
    userRoles: string[];          // includes 'admin' for invited admins
  };
  ```
  Returns `null` if the header is missing (anonymous request — should never happen on `/admin/*` paths because SWA gates them, but treated defensively). Throws if the header is present but malformed (logged at ERROR, surfaced as a 500 page).

  This helper is used by:
  - The admin layout (T-4404) to display the current user.
  - Admin API routes (E-45 T-4506) to write the GitHub username into `labels.labelled_by`.
  *Depends on: T-4401.*

- [ ] **T-4404** Create `src/app/admin/layout.tsx` — the shared admin shell. Renders:
  - A top nav bar with links: **Events** (`/admin/events`), **Stats** (`/admin/stats`), **Export** (`/admin/export`), **Deletion** (`/admin/deletion`).
  - On the right of the nav: the current admin's GitHub username (from `getClientPrincipal`) and a **Sign out** link to `/.auth/logout?post_logout_redirect_uri=/`.
  - `<main>` slot rendering `{children}`.

  Uses Tailwind CSS with a plain functional admin theme — per spec v1.1 Admin Site Screens: "no marketing polish required". Top nav fixed at the top, content scrolls below. Keyboard-accessible: `Tab` cycles through nav links, `Enter` activates. WCAG 2.1 AA contrast on all text per spec v1.1 NFR "Accessibility".
  *Depends on: T-4403.*

- [ ] **T-4405** Create `src/app/admin/page.tsx` — the sign-in landing / access-denied page. Behaviour driven by request state:
  - If unauthenticated, renders a brief intro: "Voxio Telemetry Admin — sign in with your invited GitHub account to continue." with a button linking to `/.auth/login/github`. Reached when a non-admin user follows a link to `/admin` directly (bypassing the route gate's redirect).
  - If signed in but not in the `admin` role, renders the access-denied state: "Your GitHub account does not have admin access. Contact the engineering lead to request access." with a sign-out link.
  - If signed in as admin, redirects to `/admin/events` (the primary triage surface per spec v1.1 Admin Site Screens).

  Path `/admin/access-denied` is a sub-route used by the `responseOverrides[403]` rewrite from T-4401. Implement as an alias to this page or a sibling page that renders the same access-denied state.

  The page also includes the privacy notice text required by spec v1.1 NFR "GDPR compliance" — a paragraph describing the dataset (anonymised UUIDs, anonymised transcriptions, no PII) for any new admin onboarded.
  *Depends on: T-4404.*

### Verification

- [ ] **T-4406** Manual integration test for auth gate. Test matrix on the deployed preview environment:
  1. Anonymous user visits `/admin/events` → SWA redirects to `/.auth/login/github`.
  2. Sign in as a GitHub user **not** invited to `admin` role → SWA returns 403 → redirected via `responseOverrides[403]` to `/admin/access-denied` showing the access-denied state.
  3. Sign in as a GitHub user invited to `admin` role → can reach `/admin/events`, top nav shows username on the right.
  4. Click **Sign out** → redirected to `/.auth/logout` then back to `/`.
  5. Anonymous user POSTs to `/api/admin/events/1/label` → SWA returns 401 from the route gate **without** invoking the Route Handler (verify by absence of any log line for the request).
  Document the test accounts and result in the PR description.
  *Depends on: T-4402, T-4404, T-4405.*

---

## E-45 — Admin Events UI

Build the events list page (`/admin/events`), the event detail page (`/admin/events/{id}`), and the labelling control. Build the supporting admin API routes: `GET /api/admin/events` (paginated filtered list), `GET /api/admin/events/{id}` (single event detail), `POST /api/admin/events/{id}/label` (create or update label). The labelling action is the core team workflow per spec v1.1.

**Depends on:** E-42 (events and labels tables), E-44 (admin shell + auth gate).
**Unlocks:** E-46 (export consumes the same filter URL params).

---

### Filter and pagination model

- [ ] **T-4501** Create `src/lib/filters/events.ts` defining the canonical filter shape:
  ```ts
  export type EventFilters = {
    dateFrom?: string;     // ISO 8601 date or datetime
    dateTo?: string;
    intent?: string;
    parserPath?: 'PersonalisationAlias' | 'PersonalisationMemory' | 'FoundationModels' | 'NLModel' | 'KeywordRegex' | 'Unknown';
    outcome?: 'confirmed' | 'cancelled' | 'timedOut' | 'unknown';
    locale?: string;
    flag?: 'likelyMisparse' | 'recoverableUnknown' | 'broadcast';
    transcriptionContains?: string;  // free-text substring filter
    cursor?: string;                 // base64-encoded { id, received_at }
    limit?: number;                  // default 50, max 200
  };
  ```
  Export `filtersFromSearchParams(params: URLSearchParams): EventFilters` (parses URL query params, validates with Zod, returns clean object) and `filtersToSearchParams(f: EventFilters): URLSearchParams` (round-trips for the export link).

  Cursor pagination is preferred over offset because event volume can grow large; the cursor encodes `{ id, received_at }` of the last row on the current page. Decode is `JSON.parse(atob(cursor))`. Document this in inline comments.
  *Depends on: T-4204.*

- [ ] **T-4502** Create `src/lib/queries/events.ts` exporting `listEvents(filters: EventFilters): Promise<{ rows: EventRow[]; nextCursor: string | null }>`. Builds a parameterised SQL query against the `events` table (LEFT JOIN `labels` to surface latest label inline):
  ```sql
  SELECT e.*,
         l.action AS label_action,
         l.corrected_intent AS label_corrected_intent,
         l.labelled_by AS label_labelled_by,
         l.labelled_at AS label_labelled_at
  FROM events e
  LEFT JOIN LATERAL (
    SELECT * FROM labels WHERE event_id = e.id ORDER BY labelled_at DESC LIMIT 1
  ) l ON true
  WHERE ($1::timestamptz IS NULL OR e.received_at >= $1)
    AND ($2::timestamptz IS NULL OR e.received_at <  $2)
    AND ($3::text IS NULL OR e.intent       = $3)
    AND ($4::text IS NULL OR e.parser_path  = $4)
    AND ($5::text IS NULL OR e.outcome      = $5)
    AND ($6::text IS NULL OR e.locale       = $6)
    AND ($7::text IS NULL OR e.flags && ARRAY[$7]::text[])
    AND ($8::text IS NULL OR e.transcription_anonymised ILIKE '%' || $8 || '%')
    AND (...cursor predicate if cursor...)
  ORDER BY e.received_at DESC, e.id DESC
  LIMIT $9 + 1;     -- fetch one extra to compute nextCursor
  ```
  If `LIMIT + 1` rows are returned, the last row becomes the next cursor and is dropped from the response. `EventRow` is the TypeScript type matching the SELECT shape:
  ```ts
  type EventRow = {
    id: number;
    deviceId: string;
    receivedAt: string;
    clientTimestamp: string;
    appVersion: string;
    modelVersion: string;
    locale: string;
    transcriptionAnonymised: string;
    intent: string;
    slotsAnonymised: Record<string, unknown>;
    parserPath: string;
    outcome: string;
    flags: string[];
    label: { action: string; correctedIntent: string | null; labelledBy: string; labelledAt: string } | null;
  };
  ```
  *Depends on: T-4501, T-4301.*

### Admin API routes

- [ ] **T-4503** Create `src/app/api/admin/events/route.ts` exporting `GET`. Pipeline:
  1. Auth is already enforced by `staticwebapp.config.json` (T-4401). Read `clientPrincipal` for logging.
  2. Parse filters via `filtersFromSearchParams(request.nextUrl.searchParams)`.
  3. Call `listEvents(filters)` from T-4502.
  4. Return `{ rows, nextCursor, total: null }`. (Total count is omitted in v1 to keep the query fast — cursor pagination doesn't need it.)

  Errors return 500 `{ error: 'Server error' }`. Log at INFO with `{ admin: clientPrincipal.userDetails, filterKeys: Object.keys(filters), rowCount }`.
  *Depends on: T-4502.*

- [ ] **T-4504** Create `src/app/api/admin/events/[id]/route.ts` exporting `GET`. Pipeline:
  1. Auth enforced by SWA route gate.
  2. Validate `params.id` is a positive integer.
  3. Run `SELECT e.*, ... FROM events e LEFT JOIN LATERAL (SELECT * FROM labels WHERE event_id = e.id ORDER BY labelled_at DESC LIMIT 1) l ON true WHERE e.id = $1`.
  4. If no row, return 404 `{ error: 'Event not found' }`.
  5. Otherwise return the single `EventRow`.
  *Depends on: T-4502.*

- [ ] **T-4505** Create `src/lib/schemas/label.ts` exporting the label submission schema:
  ```ts
  export const labelSchema = z.object({
    action: z.enum(['correct', 'incorrect', 'discard']),
    correctedIntent: z.string().min(1).max(64).optional(),
  }).refine(
    (v) => v.action !== 'incorrect' || !!v.correctedIntent,
    { message: 'correctedIntent is required when action = incorrect' }
  );
  ```
  Used by T-4506 to validate incoming label submissions.
  *Depends on: T-4205.*

- [ ] **T-4506** Create `src/app/api/admin/events/[id]/label/route.ts` exporting `POST`. Pipeline:
  1. Auth enforced by SWA route gate. Read `clientPrincipal`.
  2. Validate `params.id` is a positive integer.
  3. Parse body with `labelSchema` (T-4505). On failure, 400.
  4. Confirm the event exists: `SELECT id FROM events WHERE id = $1`. If not, return 404 `{ error: 'Event no longer exists. It may have been deleted.' }` (matches the toast string in spec v1.1 Error States).
  5. Look up the existing label for this event by this admin: `SELECT id, action, corrected_intent FROM labels WHERE event_id = $1 AND labelled_by = $2`.
  6. If no existing row: `INSERT INTO labels (event_id, action, corrected_intent, labelled_by) VALUES ($1, $2, $3, $4)`.
  7. If existing row: `UPDATE labels SET previous_action = action, previous_corrected_intent = corrected_intent, action = $1, corrected_intent = $2, labelled_at = now() WHERE id = $3`. (Preserves prior label per spec v1.1 Open Question 5 default.)
  8. Return 200 `{ ok: true, action, correctedIntent }`.
  9. Log at INFO with `{ admin: clientPrincipal.userDetails, eventId, action, correctedIntent }` per spec v1.1 NFR "Observability".
  *Depends on: T-4505, T-4403.*

### Admin pages

- [ ] **T-4507** Create `src/app/admin/events/page.tsx` — the events list. Server component reads filter params from `searchParams`, calls the admin API route via the SWA-internal hostname (or directly invokes `listEvents` since both run in the same process). Renders:
  - A filter sidebar (or top filter bar) with controls for: date range (two date inputs), intent dropdown, parser path dropdown, outcome dropdown, locale dropdown, flag dropdown ("any flag", `likelyMisparse`, `recoverableUnknown`, `broadcast`), transcription substring text input. Submit button updates the URL's query parameters and triggers a re-render.
  - A table with columns: timestamp, anonymised transcription (truncated to 80 chars with hover-to-expand), intent, parser path, outcome, locale, flags (rendered as small chips), label state (icon — green check for `correct`, red cross for `incorrect`, grey dash for `discard`, empty for unlabelled). Each row is a link to `/admin/events/{id}` (preserves filter state via URL).
  - Pagination controls below the table: "Next" button using `nextCursor` (URL-encoded into `?cursor=...`), "Previous" via browser back. Page size selector (50, 100, 200).
  - Top-right: "Export labelled events as CSV" link to `/admin/export?<current filter params>` (E-46).
  - On a non-admin SWA user (shouldn't happen due to T-4401, but defensive): show the access-denied state.

  Layout uses Tailwind. Per spec v1.1 NFR "Accessibility": all inputs have associated `<label>` elements; colour is not the only signal for label state (icon + colour + text on hover). Render time ≤ 1 second up to 50 events visible per spec v1.1 NFR "Latency".
  *Depends on: T-4503, T-4404.*

- [ ] **T-4508** Create `src/app/admin/events/[id]/page.tsx` — the event detail page. Server component fetches the event via T-4504. Renders:
  - Full event display: every field from `EventRow`, formatted. `slotsAnonymised` rendered as a `<pre>` JSON block. `flags` as chips. `transcriptionAnonymised` in a monospace block (preserves any structural anonymisation tokens like `[HASH:abc123]`).
  - Existing label (if any): action, corrected intent, `labelledBy`, `labelledAt`. If overwritten, also show `previousAction` and `previousCorrectedIntent` (per spec v1.1 Open Question 5 default).
  - Labelling control with three buttons: **Correct**, **Incorrect**, **Discard**. **Incorrect** expands an inline `<select>` of valid intents (the iOS app's documented intent set — load from `src/lib/constants/intents.ts`). Submit button posts to `/api/admin/events/{id}/label` (T-4506).
  - On submit success: the page re-renders with the new label state and a transient toast "Label saved." On submit failure (404): toast "Event no longer exists. It may have been deleted." (matching spec v1.1 Error States).
  - "Back to events" link returning to `/admin/events?<preserved filters>`.

  This is a server component with a client island for the label submission form (Next.js 15 `'use client'` directive on the form component only). Keyboard accessible: filter controls reachable via Tab, label buttons reachable via Tab + Enter.
  *Depends on: T-4504, T-4506.*

- [ ] **T-4509** Create `src/lib/constants/intents.ts` exporting the canonical list of iOS intents. This list is the dropdown source for the **Incorrect → corrected intent** picker in T-4508. Derive the list from `VoxioSpecification-1.3.md` (or the iOS app's parser code). Examples: `playFavorite`, `pause`, `play`, `next`, `previous`, `volumeUp`, `volumeDown`, `setVolume`, `mute`, `unmute`, `joinSpeaker`, `leaveSpeaker`, `addAlias`, `addMemory`, `unknown`. Document the source-of-truth alignment in `docs/runbook-intents.md`: when iOS adds a new intent, this list must be updated in lockstep before the next admin export.
  *Depends on: T-4508.*

### Verification

- [ ] **T-4510** Unit tests in `tests/unit/api-admin-events.test.ts` and `tests/unit/api-admin-label.test.ts`. Use vitest with the in-memory DB adapter. Tests cover:
  - List with no filters returns up to `limit` rows in `received_at DESC` order.
  - Filter by `intent=playFavorite` only returns matching rows.
  - Filter by `flag=likelyMisparse` uses the GIN index (assert via EXPLAIN, optional).
  - Cursor pagination: page 1 returns `nextCursor`; page 2 returns the next page; final page has `nextCursor: null`.
  - Free-text `transcriptionContains` matches case-insensitively.
  - Label POST with `action=correct` inserts a row.
  - Label POST with `action=incorrect` requires `correctedIntent` (400 without).
  - Label POST overwriting existing label preserves `previous_action` and `previous_corrected_intent` (verified by SELECT after UPDATE).
  - Label POST on non-existent event returns 404.
  *Depends on: T-4503, T-4504, T-4506.*

- [ ] **T-4511** Playwright E2E test in `tests/e2e/admin-events.spec.ts`. Authenticates via SWA's GitHub OAuth (using a CI-only service account with admin role), navigates to `/admin/events`, applies the `intent=playFavorite` filter, clicks the first row, applies an "Incorrect → playFavorite" label, asserts the label persists on page reload. Documented in spec v1.1 Technical Context "CI/CD" — Playwright runs against the deployed preview after `deploy` succeeds.
  *Depends on: T-4507, T-4508, T-4106.*

---

## E-46 — Admin Export and Stats

Build the three remaining admin pages: `/admin/export` (CSV download of labelled events), `/admin/stats` (aggregations over a date range), and `/admin/deletion` (manual GDPR deletion form for ad-hoc requests). All three are read-only or carefully gated; the deletion form posts to a server-side proxy that forwards to `DELETE /api/telemetry/{deviceId}` with the API key never reaching the browser.

**Depends on:** E-42 (tables), E-43 (deletion endpoint), E-44 (admin shell + auth), E-45 (filters URL contract reused by export).
**Unlocks:** the offline retraining pipeline (consumes the exported CSV).

---

### CSV export

- [ ] **T-4601** Create `src/app/api/admin/export/route.ts` exporting `GET`. Pipeline:
  1. Auth enforced by SWA route gate.
  2. Parse the same `EventFilters` shape as the events list (T-4501) — filter URL params carry over from `/admin/events`.
  3. Build a streaming SQL cursor (or fetch in pages of 5,000) over events that have at least one label, joining the most-recent label per event via the same LATERAL pattern as T-4502, but inverted: `INNER JOIN LATERAL (...) l ON true` (only events with labels) plus the filter predicates.
  4. Stream the response as `text/csv; charset=utf-8` with header `Content-Disposition: attachment; filename="voxio-labelled-events-<ISO date>.csv"` (date computed at request time, e.g. `2026-05-04`).
  5. First chunk: UTF-8 BOM (`﻿`) followed by the header row:
     ```
     event_id,timestamp,locale,transcription_anonymised,original_intent,parser_path,outcome,flags,label_action,corrected_intent,labelled_by,labelled_at
     ```
  6. Subsequent chunks: one CSV row per event. Apply RFC 4180 quoting: wrap any value containing `,`, `"`, or newline in double quotes; escape internal `"` as `""`. `flags` is joined with `;` inside a quoted field. `corrected_intent` is empty unless action is `incorrect`. Line endings are LF (`\n`) per spec v1.1 US-A3.

  Implement using `Response.body` as a `ReadableStream` to stream rows without buffering the whole result in memory. Per spec v1.1 NFR "Latency", up to 100,000 rows must complete in 30 seconds; per Error States, a stream timeout (>60 s) closes the stream and is logged at ERROR.

  Log at INFO on completion: `{ admin, filterKeys, rowsWritten, durationMs }`.
  *Depends on: T-4501, T-4301, T-4303.*

- [ ] **T-4602** Create `src/app/admin/export/page.tsx` — the export page. Renders:
  - Filter inputs duplicated from the events list (date range, locale, intent) — pre-filled from the query string when the user navigated here from the events list "Export" link.
  - A "Download CSV" `<form action="/api/admin/export" method="GET">` that includes the filter inputs as form fields. Submitting triggers the streaming download.
  - A short note: "Exports include only events with at least one label. Most-recent label per event wins." (Per spec v1.1 US-A3.)
  - Empty-state copy: "No labelled events match these filters." rendered if a quick `SELECT count(*)` (a server-side check before showing the form's submit) returns 0. The download still works in zero-result mode — it returns the CSV header row only per spec Error States.
  *Depends on: T-4601, T-4404.*

### Stats dashboard

- [ ] **T-4603** Create `src/lib/queries/stats.ts` exporting `getStats(dateFrom: Date, dateTo: Date): Promise<StatsResult>`. Runs the following aggregations as a single multi-statement query (or as a small set of parallel queries with `Promise.all`):
  ```sql
  -- total
  SELECT count(*) AS total FROM events WHERE received_at BETWEEN $1 AND $2;
  -- by intent
  SELECT intent, count(*) FROM events WHERE received_at BETWEEN $1 AND $2 GROUP BY intent ORDER BY count(*) DESC;
  -- by outcome
  SELECT outcome, count(*) FROM events WHERE received_at BETWEEN $1 AND $2 GROUP BY outcome;
  -- by parser path
  SELECT parser_path, count(*) FROM events WHERE received_at BETWEEN $1 AND $2 GROUP BY parser_path;
  -- by locale
  SELECT locale, count(*) FROM events WHERE received_at BETWEEN $1 AND $2 GROUP BY locale;
  -- likelyMisparse count
  SELECT count(*) FROM events WHERE received_at BETWEEN $1 AND $2 AND flags && ARRAY['likelyMisparse']::text[];
  -- distinct devices
  SELECT count(DISTINCT device_id) FROM events WHERE received_at BETWEEN $1 AND $2;
  ```
  Returns `StatsResult`:
  ```ts
  type StatsResult = {
    total: number;
    byIntent: Array<{ intent: string; count: number }>;
    byOutcome: Array<{ outcome: string; count: number }>;
    byParserPath: Array<{ parserPath: string; count: number }>;
    byLocale: Array<{ locale: string; count: number }>;
    likelyMisparseCount: number;
    distinctDevices: number;
  };
  ```
  Per spec v1.1 NFR "Latency", must complete in ≤ 3 seconds for a 7-day window over up to 1 million events. The indexes from T-4204 cover all filter and group-by columns.
  *Depends on: T-4204, T-4301.*

- [ ] **T-4604** Create `src/app/admin/stats/page.tsx` — the stats page. Server component reads `dateFrom` and `dateTo` from the query string (defaults: last 7 days), calls `getStats` (T-4603), renders:
  - Header with the selected date range and a date-range picker (two date inputs + "Apply").
  - Top-of-page big-number tiles: Total events, Distinct devices, `likelyMisparse` count.
  - Four tables (or simple bar charts using a tiny CSS-only bar visual — no chart library needed in v1): by intent, by outcome, by parser path, by locale. Tables are sorted by count descending.
  - All counts as plain integers; no formatting beyond thousands separators.

  Per spec v1.1 US-A5: read-only, no data mutations. No precomputed materialised views — all aggregations are on-demand SQL `GROUP BY`.
  *Depends on: T-4603, T-4404.*

### GDPR deletion form

- [ ] **T-4605** Create `src/app/api/admin/deletion/route.ts` exporting `POST`. This is the server-side proxy that holds the `TELEMETRY_API_KEY` and forwards to the public `DELETE /api/telemetry/{deviceId}` endpoint. Pipeline:
  1. Auth enforced by SWA route gate (admin-only).
  2. Parse body `{ deviceId: string, confirmation: string }`.
  3. Validate `deviceId` is a UUID. On failure, 400.
  4. Validate `confirmation === 'DELETE'`. On failure, 400 `{ error: 'Confirmation required' }`.
  5. Issue an internal HTTP request to `DELETE /api/telemetry/{deviceId}` on the same SWA hostname, with header `X-Api-Key: ${process.env.TELEMETRY_API_KEY}`. (Alternative: bypass HTTP and run the DELETE SQL directly here. Either is acceptable per spec v1.1 Open Question 8 default — implement the HTTP-internal-call approach so the public deletion endpoint is the single source of cascade truth.)
  6. Return the inner response's `deleted` counts to the admin page.
  7. Log at INFO: `{ admin, deviceId, eventsDeleted, labelsDeleted }`.

  The API key never reaches the browser — the form posts to this admin-only route (which is gated by SWA admin role), and this route reads the key from `process.env` and forwards.
  *Depends on: T-4311, T-4403.*

- [ ] **T-4606** Create `src/app/admin/deletion/page.tsx` — the deletion form. Renders:
  - A short explanation: "Manually delete all telemetry data for a specific device ID. This satisfies a user GDPR deletion request received outside the iOS app."
  - A form with two fields: `deviceId` (text input, expected UUID format) and `confirmation` (text input with the placeholder "Type DELETE to confirm"). Submit button is disabled until `confirmation === 'DELETE'` (client-side gate; server-side gate in T-4605).
  - On submit, POST to `/api/admin/deletion` (T-4605). On success, render a confirmation message: "Deleted {events} events and {labels} labels for device {deviceId}." (matches spec v1.1 US-A4 confirmation string).
  - On idempotent zero-result success: render "No data found for that device ID. Nothing to delete."
  - On error: render "Deletion failed. Please try again or contact engineering." (matches spec v1.1 US-A4 error string).
  - On submit without `confirmation === 'DELETE'`: inline validation error "Type DELETE to confirm before submitting." — no request sent.

  The form uses Next.js 15 server actions or a client island `'use client'` form. Either pattern is acceptable; document the choice.
  *Depends on: T-4605, T-4404.*

### Verification

- [ ] **T-4607** Unit tests in `tests/unit/csv-export.test.ts`, `tests/unit/stats.test.ts`, `tests/unit/admin-deletion.test.ts`. Cover:
  - CSV: header row with BOM; correct columns in correct order; quoting of values containing `,` `"` or newline; LF line endings; empty filtered result returns header-only CSV; `flags` joined with `;`; `corrected_intent` empty when action is not `incorrect`.
  - Stats: 7-day window returns expected counts on seeded data; empty-window returns zeros; date range outside data returns zeros.
  - Deletion: missing `confirmation: 'DELETE'` → 400; non-UUID deviceId → 400; valid deviceId → forwards to inner DELETE and returns counts; admin role enforced (covered in T-4406 not duplicated here).
  *Depends on: T-4601, T-4603, T-4605.*

- [ ] **T-4608** Playwright E2E in `tests/e2e/admin-export-stats-deletion.spec.ts`. Test flow:
  1. Sign in as admin (CI service account).
  2. Navigate `/admin/stats`, select a 7-day window, assert tiles show non-zero values from seed data.
  3. Navigate `/admin/export`, click "Download CSV", capture the response, assert `Content-Type` header is `text/csv` and the first bytes are the UTF-8 BOM + expected header row.
  4. Navigate `/admin/deletion`, submit a valid synthetic device ID with `confirmation: DELETE`, assert the confirmation message renders with non-zero deletion counts.
  *Depends on: T-4602, T-4604, T-4606, T-4106.*

---

## E-47 — Testing and Observability

Cross-cutting: stand up the vitest unit test runner and Playwright E2E runner with shared fixtures, configure the structured logger from T-4303 to flow into Application Insights (if the team enables it on the SWA resource), and document the runbook for incident response. This epic's tasks finalise the test surface that's referenced from earlier epics' verification tasks (T-4207, T-4312, T-4510, T-4511, T-4607, T-4608).

**Depends on:** E-41 (CI runs the tests), E-43–E-46 (the code under test exists).
**Unlocks:** the team's confidence that production deploys are safe.

---

### Vitest setup

- [ ] **T-4701** Configure vitest at the repo root. Add `vitest.config.ts` with:
  - `test.environment = 'node'`
  - `test.globals = true` (so tests can use `describe` / `it` / `expect` without imports)
  - `test.setupFiles = ['tests/setup.ts']`
  - `test.coverage.provider = 'v8'`, `coverage.reporter = ['text', 'lcov']`

  Add `tests/setup.ts` with:
  - Loads `.env.test` (per-test environment variables; `DATABASE_URL` points at a Neon test branch).
  - A `beforeEach` hook that begins a SAVEPOINT against the test DB and rolls back in `afterEach` so tests cannot pollute each other.
  - Global mocks for `@/lib/db` to allow either real-DB tests or in-memory adapter tests, switched by `process.env.TEST_MODE`.

  Add `package.json` scripts: `"test:unit": "vitest run"`, `"test:unit:watch": "vitest"`. Document in `docs/runbook-testing.md`.
  *Depends on: T-4101.*

### Playwright setup

- [ ] **T-4702** Configure Playwright at the repo root. Add `playwright.config.ts` with:
  - `testDir: './tests/e2e'`
  - `use.baseURL: process.env.E2E_BASE_URL` (in CI, this is the SWA preview URL passed by the `deploy` job)
  - `projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }]` (single browser in v1)
  - `retries: 2` (preview environments can be cold)
  - `timeout: 60_000`

  Create the SWA-friendly auth fixture in `tests/e2e/fixtures.ts`. Per spec v1.1 Technical Context "CI/CD", admin auth via SWA GitHub OAuth in CI requires an admin-roled GitHub service account. Document the service account setup (account creation, role invitation, GH CLI token storage as `GITHUB_E2E_TOKEN` secret) in `docs/runbook-e2e-auth.md`. The fixture programmatically obtains a SWA session cookie via the service account's GitHub PAT and the SWA `/.auth/me` endpoint.

  Add `package.json` scripts: `"test:e2e": "playwright test"`, `"test:e2e:ui": "playwright test --ui"`.
  *Depends on: T-4106, T-4402.*

### Logging and Application Insights

- [ ] **T-4703** Wire the structured logger from T-4303 to Application Insights, if the team enables the SWA → App Insights integration. Per spec v1.1 NFR "Observability", the integration is captured automatically — the application emits structured `console.log` and SWA's runtime forwards. Verify by:
  1. Enabling Application Insights on the SWA resource in the Azure portal (SWA → Configuration → Application Insights → On). Capture the connection string.
  2. Deploying a change.
  3. Posting a few telemetry batches (some valid, some 401, some 429).
  4. Querying App Insights via Kusto (`traces | where customDimensions.msg == "telemetry batch accepted" | take 50`) and confirming the structured fields are queryable.

  Document the standard queries in `docs/runbook-observability.md`:
  - Recent 5xx errors: `traces | where severityLevel >= 3 | take 100`
  - Ingest rate by hour: `traces | where customDimensions.msg == "telemetry batch accepted" | summarize count() by bin(timestamp, 1h)`
  - 401 rate (key brute-force detection): `traces | where customDimensions.msg == "telemetry batch unauthorized" | summarize count() by bin(timestamp, 1h)`

  Per spec v1.1 NFR "Security": confirm no transcription text appears anywhere in App Insights logs (sample 50 random log lines and grep). If it does, the logger has been misused — patch immediately.
  *Depends on: T-4303, T-4306.*

### Cascade-delete integration test

- [ ] **T-4704** Add `tests/integration/cascade-delete.test.ts`. Connects to a live Neon test branch. Inserts a `devices` row, 5 `events` rows referencing it, 3 `labels` rows referencing two of those events. Calls `DELETE FROM devices WHERE device_id = $1`. Asserts: `events` table for that `device_id` is empty; `labels` table for those event IDs is empty. Repeats with the public `DELETE /api/telemetry/{deviceId}` Route Handler (calling it via fetch against the local Next.js dev server) to validate the end-to-end path. Required by spec v1.1 NFR "GDPR compliance" — the cascade is the single safety net for deletion correctness.
  *Depends on: T-4205, T-4311, T-4701.*

### Runbooks

- [ ] **T-4705** Author `docs/runbook-incident.md`. Sections:
  - **5xx surge** — how to identify (App Insights query), likely causes (Neon cold start, DB unavailable), mitigation (UptimeRobot ping forces warmth; Neon dashboard for status).
  - **Deployment broken main** — how to roll back via SWA portal (atomic blue/green; previous slot one click away).
  - **API key compromised** — generate new key with `openssl rand -hex 32`, set `TELEMETRY_API_KEY_PREVIOUS` to the old key (one-release rotation window), update `TELEMETRY_API_KEY`, ship iOS release with new key, after iOS release adoption clear `TELEMETRY_API_KEY_PREVIOUS`.
  - **Admin lost access** — Azure portal Role Management → re-invite GitHub username.
  - **Approaching free tier ceiling (Neon storage)** — query `SELECT pg_size_pretty(pg_database_size(current_database()))`, manual export and prune events older than 12 months, or upgrade to Neon Launch tier ($19/month).
  - **GDPR deletion request via email** — admin signs in, navigates `/admin/deletion`, enters the device ID, types DELETE, submits. Records the request in the team's GDPR log (out-of-system).
  *Depends on: all earlier epics (this references all subsystems).*

### Final readiness

- [ ] **T-4706** Final pre-launch checklist. Walk through each item, confirm in PR description:
  - [ ] SWA Standard plan provisioned in the confirmed region (T-4103).
  - [ ] Neon project provisioned in matching region (T-4104).
  - [ ] `DATABASE_URL`, `TELEMETRY_API_KEY` in SWA Application Settings (T-4104, T-4105).
  - [ ] All migrations applied to production DB (T-4202).
  - [ ] CI pipeline green on `main` (T-4106, T-4109).
  - [ ] UptimeRobot monitor configured and pinging `/api/health` every 5 minutes (T-4108).
  - [ ] Admin role assigned to all engineering team members in Azure portal (T-4402).
  - [ ] `staticwebapp.config.json` deployed and gates `/admin/*` and `/api/admin/*` (T-4401, T-4406).
  - [ ] iOS team has the `TELEMETRY_API_KEY` for the next iOS release (T-4105).
  - [ ] `docs/decisions/region.md`, `docs/runbook-secrets.md`, `docs/runbook-incident.md`, `docs/runbook-monitoring.md`, `docs/runbook-admin-roles.md` all written (T-4102, T-4105, T-4108, T-4402, T-4705).
  - [ ] Application Insights integration verified and queries documented (T-4703).
  - [ ] Cascade delete integration test passes (T-4704).
  - [ ] Manual smoke test: post a real telemetry batch from a development iOS build against production; verify it appears in `/admin/events`; label it; export the CSV; delete the device; verify it's gone.
  *Depends on: all earlier tasks.*

---

## Recommended Implementation Order

1. **T-4101 → T-4102 → T-4103, T-4104** (repo + region + SWA + Neon). The region decision (T-4102) is the gatekeeper for everything else; do not start T-4103 or T-4104 until it is recorded in writing.

2. **T-4105 (API key) and T-4106 (CI/CD) in parallel**. T-4106 may run before T-4108 (UptimeRobot) because UptimeRobot requires `/api/health` to exist (T-4304).

3. **E-42 schema and migrations (T-4201–T-4207)** before any Route Handler work. Migrations must be in place before T-4306 (ingest) writes to the tables. T-4202 (CI migration step) lands with T-4106.

4. **E-43 ingest API (T-4301–T-4313)** can begin once schema is in place. Sub-order: T-4301, T-4302, T-4303 in parallel → T-4304 (health) → T-4305 → T-4306–T-4309 in sequence (each builds on the previous step of the pipeline) → T-4311 (deletion) in parallel with T-4308–T-4309 → T-4312 (unit tests) and T-4313 (manual integration) at the end.

5. **T-4108 (UptimeRobot) lands after T-4304** — the monitor needs the health endpoint to exist before pointing at it. Soft-blocks E-43 verification but does not block development.

6. **E-44 admin auth (T-4401–T-4406)** can begin in parallel with E-43 because it touches different files. T-4401 lands first to gate `/admin/*`; T-4402 (role assignment) can happen any time after T-4401. T-4404 (admin layout) and T-4405 (sign-in landing) follow.

7. **E-45 events UI (T-4501–T-4511)** depends on both E-43 (it reuses `@/lib/db`) and E-44 (admin shell). Sub-order: T-4501 → T-4502 → T-4503, T-4504, T-4506 in parallel → T-4505 (label schema) lands before T-4506 → T-4507, T-4508 in parallel → T-4509 (intents constants) lands before T-4508 → T-4510 (unit tests), T-4511 (E2E) at the end.

8. **E-46 export, stats, deletion (T-4601–T-4608)** depends on E-45 (filter URL contract) and E-43 (deletion endpoint). Sub-order: T-4601, T-4603, T-4605 in parallel (three independent backend routes) → T-4602, T-4604, T-4606 in parallel (three independent pages) → T-4607 (unit tests), T-4608 (E2E).

9. **E-47 cross-cutting (T-4701–T-4706)**. T-4701, T-4702 (test runners) lift early — they're consumed by every previous verification task. T-4703 (App Insights) after the first ingest deploy. T-4704 (cascade-delete integration) after T-4311. T-4705 (runbooks) is incremental — sections written as each subsystem ships. T-4706 (pre-launch checklist) is the gate before any iOS app referencing this backend ships to TestFlight.

A reasonable team sequence (one full-stack engineer + part-time iOS team coordination):

```
Week 1:   T-4101 (repo bootstrap)
          T-4102 (region decision — engineering lead, blocking)
          T-4103, T-4104, T-4105 (SWA + Neon + API key)
          T-4106, T-4107 (CI/CD + .env example)

Week 2:   T-4201, T-4202 (migration tooling + CI step)
          T-4203, T-4204, T-4205 (three table migrations)
          T-4206, T-4207 (seed data + schema sanity test)
          T-4301, T-4302, T-4303 (DB client + auth helper + logger)
          T-4304 (health endpoint)
          T-4108 (UptimeRobot monitor)

Week 3:   T-4305 (Zod schemas)
          T-4306–T-4309 (ingest pipeline — auth, rate limit, event write, devices upsert)
          T-4310 (perf benchmark)
          T-4311 (deletion endpoint)
          T-4312, T-4313 (ingest verification)
          T-4401, T-4402 (SWA config + admin role assignment)
          T-4403 (clientPrincipal helper)

Week 4:   T-4404, T-4405 (admin layout + sign-in landing)
          T-4406 (auth gate manual test)
          T-4501, T-4502 (filters + queries)
          T-4503, T-4504, T-4505, T-4506 (admin events API routes)
          T-4509 (intents constants)
          T-4507, T-4508 (events list + detail pages)
          T-4510 (admin events unit tests)

Week 5:   T-4601, T-4602 (CSV export route + page)
          T-4603, T-4604 (stats query + page)
          T-4605, T-4606 (deletion proxy + page)
          T-4607 (export/stats/deletion unit tests)
          T-4701, T-4702 (vitest + Playwright config)
          T-4511, T-4608 (E2E tests for events and export/stats/deletion)
          T-4703 (App Insights + queries doc)

Week 6:   T-4704 (cascade delete integration test)
          T-4705 (runbook authoring — finalise all sections)
          T-4706 (pre-launch checklist)
          End-to-end smoke test: real iOS development build → production → admin label → CSV export → delete
          Coordinate with iOS team for App Store release containing TELEMETRY_API_KEY
```

---

## Task Summary

| Epic | Tasks | Notes |
|---|---|---|
| E-41 Infrastructure and CI/CD | 9 | T-4101–T-4109. Repo bootstrap, region decision (blocking), SWA Standard + Neon free tier, GitHub Actions, UptimeRobot, smoke test. |
| E-42 Database Schema and Migrations | 7 | T-4201–T-4207. `node-pg-migrate` tooling + CI step, three tables (devices, events, labels) with indexes and ON DELETE CASCADE, seed data, schema sanity test. |
| E-43 Telemetry Ingest API | 13 | T-4301–T-4313. Shared DB/auth/logger libs, `/api/health`, `POST /api/telemetry/batch` (auth + Zod + rate limit + event write + devices upsert), `DELETE /api/telemetry/{deviceId}`, unit + manual verification. |
| E-44 Admin Authentication and Route Protection | 6 | T-4401–T-4406. `staticwebapp.config.json` route rules, admin role assignment, clientPrincipal helper, admin shell layout, sign-in landing, auth gate manual test. |
| E-45 Admin Events UI | 11 | T-4501–T-4511. Filters + queries libs, three admin API routes (list, detail, label POST), label schema, two pages (list + detail), intents constants, unit + Playwright E2E. |
| E-46 Admin Export and Stats | 8 | T-4601–T-4608. CSV export streaming route + page, stats aggregation query + page, GDPR deletion proxy + form, unit + Playwright E2E. |
| E-47 Testing and Observability | 6 | T-4701–T-4706. Vitest + Playwright runners, App Insights wiring, cascade-delete integration, runbooks, pre-launch checklist. |
| **Total** | **60** | First epics-and-tasks file in the new `voxio-telemetry` repository. Cumulative project total: 321 (Voxio iOS through v1.2) + 6 (Voxio iOS v1.3 through E-40, T-4006) + 60 = **387 tasks across all Voxio surfaces.** |

---

## Amendment History

| Date | Source | Change |
|---|---|---|
| 2026-05-04 | Initial draft | First version of the Telemetry Backend & Admin Site epics and tasks (E-41–E-47, T-4101–T-4706). Derived from approved spec v1.1 and architect review (ADR-telemetry-backend.md). |
