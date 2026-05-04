# Runbook — Local Development Setup

## Prerequisites

- Node 20 (`nvm use 20` or `fnm use 20`)
- pnpm 9 (`npm install -g pnpm@9`)
- A Neon account (free tier at [neon.tech](https://neon.tech))

---

## Step 1 — Create a personal Neon dev branch

Neon supports per-developer branches at no extra cost on the free tier. Each branch is a full copy of the schema and data, isolated from production.

1. Sign in to the Neon console → project `voxio-telemetry`.
2. **Branches** → **Create Branch**.
3. Branch name: `dev/<your-github-username>` (e.g. `dev/mrandersen`).
4. Parent: `main` branch (production schema).
5. Click **Create Branch**.
6. Copy the **Connection String** from the branch detail page (it includes host, database, user, and password).

---

## Step 2 — Configure `.env.local`

In `backend/`:

```sh
cp .env.local.example .env.local
```

Edit `.env.local`:

```
DATABASE_URL=postgresql://<user>:<password>@<host>/<database>?sslmode=require
TELEMETRY_API_KEY=dev-key-not-secret
```

Use the connection string from your Neon dev branch for `DATABASE_URL`.

`TELEMETRY_API_KEY` can be any string in local dev — it is compared against the same env var in the API routes.

`.env.local` is in `.gitignore` — it is never committed.

---

## Step 3 — Install and migrate

```sh
pnpm install
pnpm migrate:up
```

`migrate:up` applies all pending migration files in `backend/migrations/` to your dev branch. On a fresh branch this creates the `devices`, `events`, and `labels` tables.

---

## Step 4 — Seed development data

```sh
export NODE_ENV=development
pnpm db:seed
```

This inserts 5 devices, ~500 events, and labels ~10% of events. The seed script refuses to run if `NODE_ENV=production` or if the `DATABASE_URL` hostname contains `prod` or `production`.

---

## Step 5 — Run the dev server

```sh
pnpm dev
```

The app is available at `http://localhost:3000`.

**Note:** SWA auth (`x-ms-client-principal` header injection) is not available in local dev. Admin pages (`/admin/*`) will receive a null principal from `getClientPrincipal`. Use the [SWA CLI](https://azure.github.io/static-web-apps-cli/) to emulate SWA auth locally:

```sh
npx @azure/static-web-apps-cli start http://localhost:3000 --run "pnpm dev"
```

The SWA CLI runs at `http://localhost:4280` and injects mock auth headers.

---

## Refreshing your dev branch from production

If your dev branch schema is stale relative to `main`:

1. Neon console → your dev branch → **Reset branch** → reset from `main`.
2. Re-run `pnpm db:seed` to repopulate.

Resetting a branch is instant (Neon copy-on-write) and free.
