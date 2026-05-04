# Secrets Runbook — Voxio Telemetry Backend

## Environment variables

All secrets live in SWA Application Settings only. Never commit secrets to source.

| Name | Purpose | How to rotate |
|---|---|---|
| `DATABASE_URL` | Neon Postgres connection string | Generate new Neon credentials → update SWA Application Setting → redeploy |
| `TELEMETRY_API_KEY` | iOS app ingest authentication | `openssl rand -hex 32` → set as new key → set old key as `TELEMETRY_API_KEY_PREVIOUS` → ship new iOS release → remove previous key after old app version is sunset |
| `AZURE_STATIC_WEB_APPS_API_TOKEN` | GitHub Actions deploy token | Regenerate in Azure portal → update GitHub Actions secret |

## iOS handoff

After generating `TELEMETRY_API_KEY`, hand the value to the iOS team to set in `Debug.xcconfig` (staging) and `Release.xcconfig` (production) as the `TELEMETRY_BASE_URL` xcconfig build setting.
