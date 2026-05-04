# Launch Checklist — Voxio Telemetry Backend

Run through every item before declaring the backend production-ready.

---

## Cloud infrastructure

- [ ] **T-4103** — Azure SWA resource created (Standard plan, West Europe).
  - SWA hostname recorded in `docs/decisions/region.md`.
  - GitHub Actions secret `AZURE_STATIC_WEB_APPS_API_TOKEN` set.

- [ ] **T-4104** — Neon project `voxio-telemetry` created (`aws-eu-central-1`, free tier).
  - Production branch (`main`) connection string → SWA Application Setting `DATABASE_URL` + GitHub secret `DATABASE_URL`.
  - Create a Neon branch named `staging` (branched from `main`) → GitHub secret `STAGING_DATABASE_URL`.
  - Neon project name and connection string location recorded in `docs/decisions/region.md`.

- [ ] **T-4105** — Telemetry API key generated and distributed.
  - `TELEMETRY_API_KEY` set as SWA Application Setting.
  - Key handed to iOS team via secure channel (1Password vault or equivalent).
  - iOS `Debug.xcconfig` and `Release.xcconfig` updated with new key.

---

## Database

- [ ] **Migrations applied to production.**
  Run `pnpm migrate:up` with the production `DATABASE_URL`, or confirm the `migrate` CI job succeeded on the last `main` deploy.

  Verify tables exist:
  ```sql
  \dt
  -- Expected: devices, events, labels, pgmigrations
  ```

- [ ] **Indexes present.**
  ```sql
  \di
  -- Expected: events_received_at_idx, events_device_id_idx, events_intent_idx, etc.
  ```

---

## CI/CD pipeline

- [ ] **CI pipeline green on `main`.**
  All jobs pass: `lint` → `unit` → `build` → `deploy` → `migrate` → `e2e`.

- [ ] **Preview environment created for a test PR.**
  Open a trivial PR, confirm the SWA preview URL is reachable.

- [ ] **`cleanup_pr` job runs on PR close.**
  Merge or close the test PR, confirm the preview environment is destroyed.

---

## Application health

- [ ] **`GET /api/health` returns 200 on the production hostname.**
  ```sh
  curl https://<swa-hostname>/api/health
  # {"status":"ok","timestamp":"..."}
  ```

- [ ] **UptimeRobot monitor configured** (`docs/decisions/runbook-monitoring.md`).
  - Monitor URL: `https://<swa-hostname>/api/health`
  - Interval: 5 minutes.
  - Alert contact: engineering lead's email.

---

## Admin access

- [ ] **Admin role assigned** to all engineering team members.
  Azure portal → SWA → Role Management → Invite → role: `admin`.
  Full procedure: `docs/runbook-admin-roles.md`.

- [ ] **Sign-in flow verified.**
  Navigate to `https://<swa-hostname>/admin`, confirm GitHub OAuth redirect, confirm role-gated access.

---

## iOS integration

- [ ] **Ingest endpoint reachable from iOS.**
  Post a test batch from the iOS app (or `curl`):
  ```sh
  curl -X POST https://<swa-hostname>/api/telemetry/batch \
    -H "x-api-key: <TELEMETRY_API_KEY>" \
    -H "content-type: application/json" \
    -d '{"deviceId":"00000000-0000-0000-0000-000000000001","events":[...]}'
  # → 202
  ```

- [ ] **GDPR deletion endpoint reachable from iOS.**
  ```sh
  curl -X DELETE https://<swa-hostname>/api/telemetry/00000000-0000-0000-0000-000000000001 \
    -H "x-api-key: <TELEMETRY_API_KEY>"
  # → 200 {"deleted":{"events":0,"labels":0,"devices":0}}
  ```

---

## Observability (optional — enable when ready)

- [ ] **Application Insights enabled** on the SWA resource.
  Verify structured logs appear in the Kusto query interface.
  See `docs/decisions/runbook-monitoring.md`.

- [ ] **GDPR safety audit passed.**
  Run `traces | order by timestamp desc | take 50 | project message, customDimensions` and confirm no transcription text appears in any log field.

---

## Sign-off

Record the completion date and the engineer who ran the checklist here before the first iOS build with telemetry enabled ships to App Store.

| Item | Completed by | Date |
|---|---|---|
| Cloud infrastructure | | |
| Database | | |
| CI/CD | | |
| Application health | | |
| Admin access | | |
| iOS integration | | |
