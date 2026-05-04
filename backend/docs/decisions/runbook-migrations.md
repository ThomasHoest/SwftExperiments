# Runbook — Database Migrations

Tool: `node-pg-migrate` (devDependency). Migration files live in `backend/migrations/`.  
Driver: `@neondatabase/serverless` via `DATABASE_URL`.

---

## Lifecycle: create → review → run locally → commit → CI applies

1. **Create** a new migration file with a sequential timestamp name:
   ```
   pnpm migrate:create -- my_migration_description
   ```
   This generates `migrations/<timestamp>_my_migration_description.ts` with empty `up`/`down` stubs.

2. **Edit** the new file — write SQL using `pgm.sql(...)` or `pgm.createTable(...)`. Always implement both `up` and `down`.

3. **Run locally** against your Neon dev branch (see below). Verify the schema looks right.

4. **Commit** the migration file alongside any code that depends on it, in a single PR.

5. **CI applies** the migration automatically in the `db:migrate` job after `deploy` and before `e2e`.

---

## Running migrate:up locally

Set `DATABASE_URL` to your Neon dev branch connection string, then:

```sh
export DATABASE_URL="postgresql://..."
pnpm migrate:up
```

node-pg-migrate creates a `pgmigrations` table on first run and tracks which files have been applied. Subsequent calls are idempotent — only pending migrations are run.

To roll back the last applied migration:

```sh
pnpm migrate:down
```

---

## Creating a new migration

```sh
pnpm migrate:create -- add_column_to_events
```

The double `--` passes the name argument through pnpm to node-pg-migrate.

Edit the generated file. Implement both `up` (forward) and `down` (rollback).

---

## Forward-compatibility rule — additive only

Migrations must be backwards-compatible with the running application code. Allowed:

- Adding a new nullable column (with or without a default).
- Adding a new table.
- Adding a new index.

Prohibited without a coordinated multi-deploy plan:

- Dropping or renaming a column.
- Changing a column's type.
- Adding a NOT NULL column without a default.
- Removing or tightening a CHECK constraint that live code relies on.

This rule exists because a zero-downtime deployment means the old app version is still running while the migration is applied. Destructive schema changes break the old version.

---

## Seeding a dev branch

```sh
export DATABASE_URL="postgresql://..."
export NODE_ENV=development
pnpm db:seed
```

The seed script inserts 5 devices, ~500 events, and labels ~10% of events. It refuses to run if `NODE_ENV=production` or if the `DATABASE_URL` hostname contains `prod` or `production`.
