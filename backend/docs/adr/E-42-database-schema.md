# ADR-E42 — Database Schema and Migrations for Voxio Telemetry Backend

**Status:** Accepted
**Date:** 2026-05-04
**Deciders:** Engineering Lead, Data Lead
**Parent ADRs:** ADR-001 (Accepted), ADR-E41 (Accepted)

---

## 1. Decision

Use `node-pg-migrate` in TypeScript mode to manage all Postgres schema changes. Three tables — `devices`, `events`, and `labels` — are created in three sequential migration files under `backend/migrations/`. No ORM is used at any layer. Foreign keys carry `ON DELETE CASCADE` so a single `DELETE FROM devices WHERE device_id = $1` removes all data for a device, satisfying the GDPR hard-delete requirement without any application-level multi-DELETE logic.

---

## 2. Context

**Binding constraints from ADR-001:**
- No ORM. All SQL written by hand; `@neondatabase/serverless` is the sole driver.
- `ON DELETE CASCADE` is mandatory on `events.device_id → devices` and `labels.event_id → events`. Application-level multi-DELETE is explicitly prohibited (ADR-001 §7 constraint 4).
- Secrets (`DATABASE_URL`) live in SWA Application Settings only.

**From ADR-E41:**
- All new files go under `backend/`. Neon project is in `aws-eu-central-1`; `DATABASE_URL` is canonical.
- A `db:migrate` step must be inserted after `deploy` and before `e2e` in CI (T-4202).

**From spec Open Question 9:** `node-pg-migrate` is the documented default. This ADR closes it.

**Forward-compatibility rule (spec NFR "Availability"):** migrations must be additive only — nullable new columns, new tables; no destructive `ALTER`, no column renames, no non-nullable columns without defaults.

---

## 3. Options Considered

**node-pg-migrate in TypeScript mode (chosen):** native TypeScript files, up/down lifecycle, internal migration tracking table, `LOCK TABLE` concurrency protection, closes spec OQ-9 directly.

**Plain SQL files + custom tsx runner:** zero npm dependency; maximum transparency. Requires hand-rolling locking, ordering, and tracking — reinventing what node-pg-migrate provides.

**Prisma Migrate:** excellent DX but ships an ORM client; prohibited by ADR-001 §7 constraint 6.

**Flyway / Liquibase:** JVM tooling; incompatible with the Node 20 CI environment.

---

## 4. Rationale

`node-pg-migrate` fits because: (1) TypeScript migration files match the repo's strict-TS posture; (2) internal `pgmigrations` table tracks applied migrations without bespoke code; (3) integrates cleanly with `DATABASE_URL`; (4) no ORM surface — ADR-001 §7 constraint 6 satisfied; (5) `migrate:up` / `migrate:down` are conventional enough for E-47 test automation.

---

## 5. Consequences

- **E-43** inherits exact column names from the contract below. Any deviation is a breaking change.
- **E-45 / E-46** rely on all indexes listed; removing an index requires a migration.
- **E-47** must call `migrate:up` against a fresh Neon dev branch before schema sanity tests.
- **CI pipeline** gains a `db:migrate` job between `deploy` and `e2e` (T-4202). Migration failures block merge.
- `node-pg-migrate` is a `devDependency` only — the running Next.js app never imports it.

---

## 6. File-Level Plan

```
backend/
├── package.json                              — add node-pg-migrate devDep; migrate:up/down/create/db:seed scripts
├── migrations/
│   ├── <timestamp>_create_devices.ts         — T-4203: devices table + index
│   ├── <timestamp>_create_events.ts          — T-4204: events table + 8 indexes
│   └── <timestamp>_create_labels.ts          — T-4205: labels table + 3 indexes + CHECK constraint
├── scripts/
│   └── seed-dev.ts                           — T-4206: 5 devices, ~500 events, ~10% labelled; prod guard
├── tests/
│   └── unit/
│       └── schema.test.ts                    — T-4207: cascade delete, CHECK constraint, column existence
└── docs/
    ├── adr/
    │   └── E-42-database-schema.md           — this file
    └── decisions/
        └── runbook-migrations.md             — create → review → run locally → commit → CI applies
```

---

## 7. Public Interface Contract

### npm script names

| Script | Purpose |
|---|---|
| `migrate:up` | Apply all pending migrations |
| `migrate:down` | Roll back the last applied migration |
| `migrate:create` | Scaffold a new timestamped migration file |
| `db:seed` | Populate local dev branch with synthetic data |

> **Implementer note:** Verify the exact `node-pg-migrate` CLI flags for migrations directory (`-m` or `--migrations-dir`) against the installed version. The task spec uses `-d` but that flag controls the database URL in some versions. Contract names do not change.

### Table schemas (verbatim — binding contract for E-43, E-45, E-46)

**`devices`**
```sql
CREATE TABLE devices (
  device_id      UUID         PRIMARY KEY,
  first_seen_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  last_seen_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  last_upload_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  app_version    TEXT,
  model_version  TEXT,
  locale         TEXT
);
CREATE INDEX devices_last_seen_at_idx ON devices (last_seen_at DESC);
```
`app_version`, `model_version`, `locale` are nullable — updated on upsert in E-43.

**`events`**
```sql
CREATE TABLE events (
  id                       BIGSERIAL    PRIMARY KEY,
  device_id                UUID         NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  received_at              TIMESTAMPTZ  NOT NULL DEFAULT now(),
  client_timestamp         TIMESTAMPTZ  NOT NULL,
  app_version              TEXT         NOT NULL,
  model_version            TEXT         NOT NULL,
  locale                   TEXT         NOT NULL,
  transcription_anonymised TEXT         NOT NULL,
  intent                   TEXT         NOT NULL,
  slots_anonymised         JSONB        NOT NULL DEFAULT '{}'::jsonb,
  parser_path              TEXT         NOT NULL,
  outcome                  TEXT         NOT NULL,
  flags                    TEXT[]       NOT NULL DEFAULT '{}'::text[]
);
CREATE INDEX events_received_at_idx      ON events (received_at DESC);
CREATE INDEX events_client_timestamp_idx ON events (client_timestamp DESC);
CREATE INDEX events_device_id_idx        ON events (device_id);
CREATE INDEX events_intent_idx           ON events (intent);
CREATE INDEX events_parser_path_idx      ON events (parser_path);
CREATE INDEX events_outcome_idx          ON events (outcome);
CREATE INDEX events_locale_idx           ON events (locale);
CREATE INDEX events_flags_gin_idx        ON events USING GIN (flags);
```
No `CHECK` on `parser_path` or `outcome` — validation is the ingest handler's job (Zod, E-43). Keeping these unconstrained means adding a new enum value requires only a code deploy, not a table-locking `ALTER`.

**`labels`**
```sql
CREATE TABLE labels (
  id                        BIGSERIAL    PRIMARY KEY,
  event_id                  BIGINT       NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  action                    TEXT         NOT NULL CHECK (action IN ('correct', 'incorrect', 'discard')),
  corrected_intent          TEXT,
  labelled_by               TEXT         NOT NULL,
  labelled_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
  previous_action           TEXT,
  previous_corrected_intent TEXT
);
CREATE INDEX labels_event_id_idx    ON labels (event_id);
CREATE INDEX labels_labelled_at_idx ON labels (labelled_at DESC);
CREATE INDEX labels_labelled_by_idx ON labels (labelled_by);
```
`labels.action` has a `CHECK` constraint — the label action set is closed by spec and a DB guard prevents silent corruption.

### Cascade delete chain

`DELETE FROM devices WHERE device_id = $1`
→ cascades to all `events` rows (via `events.device_id FK ON DELETE CASCADE`)
→ cascades to all `labels` rows (via `labels.event_id FK ON DELETE CASCADE`)

One SQL statement, one round-trip. Row-count reporting uses a CTE per ADR-001 §6.5.

---

## 8. Conflicts Flagged

**Non-blocking — Open Question 5 (label conflict):** `previous_action` / `previous_corrected_intent` implement "most-recent label wins, prior value preserved." The one-label-per-(event, admin) constraint is enforced at the API layer (E-45 T-4503), **not** by a `UNIQUE(event_id, labelled_by)` DB constraint. If E-45 issues an `INSERT` instead of an `UPDATE`, duplicate rows will silently accumulate. The E-45 Implementer must read this before T-4503.

---

**VERDICT: PROCEED**
