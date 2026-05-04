# Runbook — CI/CD Pipeline

Workflow file: `.github/workflows/backend-ci-cd.yml`

## Job graph

```
lint ──┐
       ├── build ── deploy ── migrate ── e2e
unit ──┘

cleanup_pr  (fires only on PR close)
```

`lint` and `unit` run in parallel. `build` starts only when both pass. `deploy` follows `build`. `migrate` follows `deploy`. `e2e` follows `migrate`.

## Job descriptions

| Job | What it does | Blocks merge if it fails? |
|---|---|---|
| `lint` | `pnpm lint` — ESLint with Next.js rules | Yes |
| `unit` | `pnpm test:unit` — vitest unit suite (291 tests) | Yes |
| `build` | `pnpm build` — Next.js standalone build | Yes |
| `deploy` | `Azure/static-web-apps-deploy@v1` — uploads to SWA | Yes |
| `migrate` | `pnpm migrate:up` — applies pending DB migrations | Yes |
| `e2e` | `pnpm test:e2e` — Playwright against the deployed preview URL | Yes (blocks PR; failures on `main` push do not auto-rollback) |
| `cleanup_pr` | Closes the SWA ephemeral preview environment on PR close | No (informational) |

## Secrets required

| Secret name | Purpose | Where to set |
|---|---|---|
| `AZURE_STATIC_WEB_APPS_API_TOKEN` | SWA deployment token | GitHub → repo → Settings → Secrets → Actions |
| `DATABASE_URL` | Neon **production** connection string | GitHub → repo → Settings → Secrets → Actions |
| `STAGING_DATABASE_URL` | Neon **staging** connection string | GitHub → repo → Settings → Secrets → Actions |

Both `DATABASE_URL` and `STAGING_DATABASE_URL` are used only in the `migrate` job. If either is absent, migrations are skipped with a warning — the pipeline continues so the workflow runs before Neon is provisioned.

## Environments and their databases

| Branch | SWA environment | Database secret used |
|---|---|---|
| `main` | `production` | `DATABASE_URL` |
| `develop` | `staging` | `STAGING_DATABASE_URL` |
| PR targeting `main` or `develop` | ephemeral (PR number) | none — migrations skipped |

The staging SWA environment has a stable URL (not ephemeral). Create a dedicated Neon branch named `staging` (branched from `main`) and use its connection string as `STAGING_DATABASE_URL`.

## Preview environments

Each PR gets an ephemeral SWA preview URL of the form:
```
https://<random>.westeurope.2.azurestaticapps.net
```

The URL is available in the `deploy` job output `static_web_app_url` and passed to the `e2e` job via `PLAYWRIGHT_BASE_URL`. Playwright tests run against this URL, not localhost.

The preview environment is destroyed by the `cleanup_pr` job when the PR is closed or merged.

## Triggering conditions

| Event | Jobs that run |
|---|---|
| `push` to `main` with changes in `backend/**` | All jobs → production deploy |
| `push` to `voxio-1.3` with changes in `backend/**` | All jobs → preview deploy |
| `pull_request` opened/synchronised targeting `main` | All jobs → preview deploy |
| `pull_request` closed | `cleanup_pr` only |

## Typical job durations

*(Update after running the smoke test — T-4109)*

| Job | Expected duration |
|---|---|
| `lint` | ~30s |
| `unit` | ~15s |
| `build` | ~60s |
| `deploy` | ~90s |
| `migrate` | ~10s (no-op when no new migrations) |
| `e2e` | ~120s |

## Troubleshooting

**`deploy` fails with "AZURE_STATIC_WEB_APPS_API_TOKEN not set":**
Generate a new token in Azure portal → SWA → Manage deployment token → set as GitHub secret.

**`migrate` fails with "password authentication failed":**
The `DATABASE_URL` secret is stale. Regenerate credentials in the Neon dashboard and update the GitHub secret.

**`e2e` fails with "page timed out" on first run:**
Preview environment cold-start. Re-run the job; `retries: 2` in `playwright.config.ts` handles this automatically.

**`build` fails with "Module not found":**
An import path is broken. Run `pnpm build` locally to reproduce, then fix the import.
