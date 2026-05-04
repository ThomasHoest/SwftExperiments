# ADR-E41 — Infrastructure and CI/CD Bootstrap for Voxio Telemetry Backend

**Status:** Accepted
**Date:** 2026-05-04
**Deciders:** Engineering Lead
**Parent ADR:** ADR-001 (Telemetry Backend and Admin Site Architecture, Accepted)

---

## 1. Decision

Bootstrap the Voxio telemetry backend as a Next.js 15 hybrid application in a `backend/` subdirectory of the existing `SwftExperiments` monorepo, following the TheCheapPowerCompany GitHub Actions pattern: lint → vitest → build → `Azure/static-web-apps-deploy@v1` → Playwright E2E. The Azure SWA instance deploys to West Europe; the Neon Postgres project is created in `aws-eu-central-1`. All secrets live in SWA Application Settings only — never in source, never logged.

---

## 2. Context

**From ADR-001 (binding constraints):**
- Single Next.js 15 hybrid app on Azure SWA Standard plan (~$9/month); `output: 'standalone'` required.
- Admin auth via SWA built-in GitHub OAuth with `allowedRoles: ["admin"]` in `staticwebapp.config.json`; zero application auth code.
- Database: Neon serverless Postgres free tier; `@neondatabase/serverless` driver; no ORM.
- CI/CD follows the TheCheapPowerCompany pattern exactly.
- Region locked: SWA = West Europe, Neon = `aws-eu-central-1` (T-4102 decided).
- `navigationFallback` must not appear in `staticwebapp.config.json`.

---

## 3. Options Considered

**Option A — `backend/` subdirectory in this monorepo (chosen)**
One repository, shared GitHub Actions secrets context, iOS and backend PRs visible together. `SWA_APP_LOCATION` points to `backend/`; the pipeline scopes all `npm` commands to that subdirectory via `working-directory`. Mirrors TheCheapPowerCompany's `apps/marketing-site/` pattern exactly.

**Option B — Standalone `voxio-telemetry` repository**
Cleaner separation; its own issue tracker and branch protection. Requires a second GitHub repository, duplicated secrets setup, and a second CLAUDE.md context. Adds no technical benefit at this team size.

---

## 4. Rationale

Monorepo subdirectory chosen because: (1) the team is 1–5 people — the overhead of a second repo outweighs the isolation benefit; (2) `working-directory` directives scope all CI commands cleanly to `backend/`; (3) this mirrors the established TheCheapPowerCompany pattern the engineering lead cited as the reference; (4) `backend/` is self-contained and can be extracted with `git subtree` later if needed.

---

## 5. Consequences

- All subsequent epics (E-42–E-47) write files exclusively under `backend/`.
- A single GitHub Actions workflow `.github/workflows/backend-ci-cd.yml` handles the pipeline.
- Ephemeral preview SWA environments are created per PR (Standard plan).
- Neon project region `aws-eu-central-1` is permanent — any SWA region change requires recreating the Neon project and migrating all data.
- The SWA Standard plan must never be downgraded to Free — Free lacks custom auth roles.

---

## 6. File-Level Plan (binding contract for the Implementer)

```
backend/
├── .env.local.example                    — env var names only, no values
├── .gitignore                            — node_modules, .next, .env.local
├── next.config.ts                        — output: 'standalone'
├── staticwebapp.config.json              — placeholder; auth rules added in E-44
├── package.json                          — scripts: dev, build, lint, test:unit, test:e2e
├── pnpm-lock.yaml
├── tsconfig.json                         — strict mode, path alias @/*
├── tailwind.config.ts
├── postcss.config.mjs
├── app/
│   ├── layout.tsx                        — root layout (minimal shell)
│   ├── page.tsx                          — redirect to /admin/events
│   └── api/
│       └── health/
│           └── route.ts                 — GET /api/health → {status:"ok",timestamp:ISO}
├── migrations/                           — node-pg-migrate files (E-42)
├── docs/
│   ├── adr/
│   │   └── E-41-infrastructure-cicd.md  — this file
│   └── decisions/
│       ├── region.md                     — SWA=West Europe, Neon=aws-eu-central-1 (immutable)
│       ├── runbook-secrets.md            — API key rotation procedure
│       ├── runbook-local-dev.md          — Neon dev branch setup, .env.local
│       ├── runbook-migrations.md         — migration run/rollback procedure
│       └── runbook-monitoring.md         — UptimeRobot monitor URL and owner

.github/
└── workflows/
    └── backend-ci-cd.yml                 — lint → unit → build → deploy → e2e
```

---

## 7. Public Interface Contract

**Health endpoint** (only Route Handler in E-41; all other Route Handlers added in E-42+):

```
GET /api/health
→ 200 OK
   Content-Type: application/json
   { "status": "ok", "timestamp": "<ISO 8601 UTC>" }
```

No auth required. Does not touch the database. UptimeRobot pings this URL every 5 minutes.

**Canonical environment variable names** (must not change after E-41 ships):

| Name | Consumer |
|---|---|
| `DATABASE_URL` | All Route Handlers touching Neon (E-42+) |
| `TELEMETRY_API_KEY` | Ingest and deletion handlers (E-43) |
| `TELEMETRY_API_KEY_PREVIOUS` | Key rotation window only (optional) |

**GitHub Actions job names** (Test Writer's E2E tests must reference these exact names):

| Job | Trigger |
|---|---|
| `lint` | push / PR — ESLint |
| `unit` | push / PR — vitest |
| `build` | push / PR — `next build`; runs after lint + unit both pass |
| `deploy` | push / PR — `Azure/static-web-apps-deploy@v1`; outputs `static_web_app_url` |
| `e2e` | push / PR — Playwright against `static_web_app_url` |
| `cleanup_pr` | PR close — closes SWA ephemeral preview environment |

Node version: 20.

---

## 8. Manual Steps — Engineering Lead Actions Required

| Task | Status | Action |
|---|---|---|
| T-4102 — SWA region | **DONE** | West Europe confirmed. Recorded in `docs/decisions/region.md`. |
| T-4103 — Azure SWA provisioning | **PENDING** | Create SWA resource (Standard plan, West Europe). Retrieve deployment token → GitHub secret `AZURE_STATIC_WEB_APPS_API_TOKEN`. Record SWA hostname in `docs/decisions/region.md`. |
| T-4104 — Neon provisioning | **PENDING** | Create Neon project `voxio-telemetry` in `aws-eu-central-1`. Capture connection string → SWA Application Setting `DATABASE_URL`. |
| T-4105 — API key | **PENDING** | `openssl rand -hex 32`. Store as SWA Application Setting `TELEMETRY_API_KEY`. Hand off to iOS team for `TELEMETRY_BASE_URL` xcconfig. |
| T-4108 — UptimeRobot | **PENDING** | After E-43 ships `GET /api/health`, configure free-tier HTTP monitor at 5-min interval. Do NOT add a GitHub Actions cron. |

---

## 9. Conflicts

**Conflict (non-blocking, spec cleanup only):** The spec v1.1 Resolved Decisions table still reads "Cold-start mitigation: GitHub Actions cron". ADR-001 Section 8 Item 1 supersedes this — UptimeRobot is the binding decision. The stale table entry is corrected in `spec-telemetry-backend-admin.md` separately; no code impact.

---

**VERDICT: PROCEED**
