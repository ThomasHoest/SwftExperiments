# Agent Scripts

Standalone scripts that run on the agent runtime (developer machine or CI).
These are **not** part of the Next.js app and do not run inside SWA Functions.

## open-incident-pr.ts

Fetches the open incident with the highest occurrence count, asks Claude to
propose a fix, opens a GitHub draft PR with the changes, and marks the
incident as `investigating`.

### Required environment variables

| Variable | Description |
|---|---|
| `AGENT_API_KEY` | `x-agent-key` for `/api/agent/*` backend routes |
| `AGENT_API_BASE` | SWA hostname, e.g. `https://voxio-prod.azurestaticapps.net` |
| `GITHUB_TOKEN` | GitHub PAT with `contents:write` and `pull_requests:write` scopes |
| `GITHUB_REPO` | `owner/repo`, e.g. `T-Creative/SwftExperiments` |
| `ANTHROPIC_API_KEY` | Anthropic API key (used by `@anthropic-ai/sdk`) |

### Usage

```bash
cd backend
AGENT_API_KEY=... \
AGENT_API_BASE=https://voxio-prod.azurestaticapps.net \
GITHUB_TOKEN=... \
GITHUB_REPO=T-Creative/SwftExperiments \
ANTHROPIC_API_KEY=... \
pnpm tsx agent/scripts/open-incident-pr.ts
```

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success, or no actionable incidents (no open incidents / no source file references / no fix generated) |
| `1` | Fatal error (network failure, GitHub API error, bad env vars) |

### Idempotency note

Re-running the script on the same incident will fail at the branch-creation step
because `incident/<fingerprint>` already exists. This is intentional in v1 —
check GitHub for the existing draft PR.
