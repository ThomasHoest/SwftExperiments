# Runbook — Monitoring and Cold-Start Mitigation

## UptimeRobot keep-alive monitor

UptimeRobot (free tier) pings `/api/health` every 5 minutes. This prevents Neon from scaling to zero, keeping query latency low for the first telemetry batch after an idle period.

**Monitor URL:** `https://<swa-hostname>/api/health`  
*(Update this line after T-4103: record the actual SWA hostname here)*

**Owner:** Engineering lead's UptimeRobot account.

**Alert contact:** Engineering lead's email (configured in UptimeRobot free tier).

### Setup steps (one-time, after T-4103 ships the SWA hostname)

1. Sign in to [uptimerobot.com](https://uptimerobot.com) (free account).
2. **Add New Monitor** → type: HTTP(s).
3. **Friendly Name:** `Voxio Telemetry Health`
4. **URL:** `https://<swa-hostname>/api/health`
5. **Monitoring Interval:** 5 minutes.
6. **Alert Contacts:** add the engineering lead's email.
7. Save.

Confirm the first check shows status **UP** within 5 minutes.

### Why NOT a GitHub Actions cron

A 5-minute GitHub Actions cron on a private repository runs ~8,640 times/month ≈ 4,320 billed minutes. The GitHub free tier includes 2,000 minutes/month. Overage is ~$18/month — more expensive than the Neon scale-to-zero problem it solves. UptimeRobot is the correct tool.

---

## Application Insights (optional — enable when ready)

SWA integrates with Azure Application Insights to capture structured `console.log` output as queryable telemetry.

### Enable (one-time, requires Azure portal access)

1. Azure portal → Static Web Apps → `voxio-telemetry` → **Configuration** → **Application Insights** → **On**.
2. Select or create an Application Insights resource in the same subscription.
3. Copy the **Connection String** — store it as SWA Application Setting `APPLICATIONINSIGHTS_CONNECTION_STRING` if the Next.js SDK is added later. For SWA's native integration, no code change is needed — `console.log` is forwarded automatically.
4. Deploy any change to trigger the first log flush.

### Verify

Post a few telemetry batches (via the iOS app or `curl`) then query:
```kusto
traces
| where customDimensions.msg == "batch accepted"
| take 10
```

If structured fields appear as `customDimensions`, the integration is working.

See `docs/runbook-incident.md` for the full set of operational Kusto queries.
