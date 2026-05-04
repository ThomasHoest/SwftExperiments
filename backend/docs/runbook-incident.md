# Runbook — Incident Response

## 5xx surge

**Detect:** App Insights → Kusto: `traces | where severityLevel >= 3 | order by timestamp desc | take 100`

**Likely causes:**
- Neon cold start (first request after scale-to-zero): retries on the iOS client will self-heal within 1–2 seconds. UptimeRobot should have kept Neon warm; check the monitor status.
- Neon unavailable: check [status.neon.tech](https://neon.tech/docs/introduction/status). If the region is degraded, there is no mitigation — wait for Neon recovery.
- Bad deploy: roll back immediately (see below).

**Mitigation:**
1. Check UptimeRobot for alert history — did the `/api/health` monitor trip before the surge?
2. Check Neon dashboard for compute activity.
3. If a recent deploy is suspected, roll back via Azure portal (see "Deployment broken main" below).

---

## Deployment broken main

Azure SWA uses atomic blue/green deployment. Rolling back is a single click.

1. Azure portal → Static Web Apps → `voxio-telemetry` → **Deployments**.
2. Find the last known-good deployment.
3. Click **Redeploy** on that entry. The previous build is immediately swapped in — no rebuild required.
4. Confirm `/api/health` returns 200 on the production hostname.

To prevent recurrence: require the `build` and `unit` jobs to pass before the `deploy` job can run (already enforced in the workflow).

---

## API key compromised

1. Generate a new key: `openssl rand -hex 32`
2. Set `TELEMETRY_API_KEY_PREVIOUS` in SWA Application Settings to the **current** key value (this opens a one-release rotation window where both keys are accepted).
3. Set `TELEMETRY_API_KEY` in SWA Application Settings to the **new** key value.
4. Redeploy (or wait for next CI run — the settings take effect immediately without a code deploy).
5. Coordinate with the iOS team: ship a new iOS release with the new key in the Keychain seed (per `runbook-secrets.md`).
6. After the old iOS version is sunset (sufficient adoption of new release), clear `TELEMETRY_API_KEY_PREVIOUS` from SWA Application Settings.

**Note:** The iOS app will receive 401s for telemetry uploads during the window between steps 3 and 5 if the device has not updated. The `TELEMETRY_API_KEY_PREVIOUS` setting prevents this for devices still on the old version.

---

## Admin lost access

1. Azure portal → Static Web Apps → `voxio-telemetry` → **Role Management**.
2. Click **Invite** — enter the GitHub username.
3. Set role: `admin`.
4. Send the invitation link to the user. They must accept via GitHub OAuth login.

Full procedure: `docs/runbook-admin-roles.md`.

---

## Approaching free-tier ceiling (Neon storage)

Check current usage:

```sql
SELECT pg_size_pretty(pg_database_size(current_database()));
```

Run this via the Neon SQL editor or via `psql` with the production `DATABASE_URL`.

Free tier limit: **0.5 GB**. At ~100 bytes per event row, this is ~5 million events.

**If approaching the limit:**

Option A — Prune old data (preferred):
```sql
DELETE FROM events
WHERE received_at < NOW() - INTERVAL '12 months';
```
This cascades to labels via `ON DELETE CASCADE`. Run from Neon SQL editor; do not run from the application. Take a CSV export first (`/admin/export?dateFrom=...&dateTo=...`) to preserve the labelled training data.

Option B — Upgrade to Neon Launch tier ($19/month) for 10 GB storage.

---

## GDPR deletion request via email

When a user emails a deletion request (rather than using the in-app button):

1. Sign in to `/admin` with your GitHub account.
2. Navigate to `/admin/deletion`.
3. Enter the device ID from the user's email (they can find it in the iOS app: Settings → Privacy → Telemetry → Device ID).
4. Type `DELETE` in the confirmation field.
5. Submit and confirm the deletion counts shown match what you expect.
6. Record the request in the team's GDPR log (out-of-system document): date, device ID, requester email, deletion count.

The deletion is immediate and permanent. The cascade removes all `events` and `labels` rows for the device in a single transaction.

---

## Structured log queries (App Insights Kusto)

**Recent errors:**
```kusto
traces
| where severityLevel >= 3
| order by timestamp desc
| take 100
```

**Ingest rate by hour:**
```kusto
traces
| where customDimensions.msg == "batch accepted"
| summarize count() by bin(timestamp, 1h)
| order by timestamp desc
```

**401 rate (brute-force detection):**
```kusto
traces
| where customDimensions.msg == "invalid api key"
| summarize count() by bin(timestamp, 1h)
| order by timestamp desc
```

**Verify no transcription text in logs (GDPR safety check — run periodically):**
```kusto
traces
| order by timestamp desc
| take 50
| project message, customDimensions
```
Scan for any recognizable speech text. If found, identify the log call site and remove it immediately — then audit prior log entries.
