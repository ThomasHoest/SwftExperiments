# agent/scripts

Scripts for the Voxio AI agent runtime. Run with `tsx` from the repo root.

---

## open-incident-pr.ts

Fetches the highest-occurrence open incident from the Voxio telemetry backend,
identifies referenced Swift source files, reads them via the GitHub API, and
opens a draft PR with a candidate fix. On success, the incident is patched to
`investigating` status with the PR URL and number.

### Usage

```sh
cd <repo-root>
AGENT_API_KEY=... \
AGENT_API_BASE=https://voxio-prod.azurestaticapps.net \
GITHUB_TOKEN=... \
GITHUB_REPO=owner/repo \
npx tsx agent/scripts/open-incident-pr.ts
```

Or from the `backend/` directory using the local `tsx` devDependency:

```sh
AGENT_API_KEY=... \
AGENT_API_BASE=https://voxio-prod.azurestaticapps.net \
GITHUB_TOKEN=... \
GITHUB_REPO=owner/repo \
pnpm tsx ../agent/scripts/open-incident-pr.ts
```

### Required environment variables

| Variable        | Description |
|-----------------|-------------|
| `AGENT_API_KEY` | API key for the `/api/agent/*` routes (`x-agent-key` header). Must match `AGENT_API_KEY` in SWA Application Settings. |
| `AGENT_API_BASE` | Base URL of the SWA deployment, e.g. `https://voxio-prod.azurestaticapps.net`. No trailing slash. |
| `GITHUB_TOKEN`  | GitHub personal access token (or fine-grained app token) with `contents:write` and `pull_requests:write` scopes on the target repo. **Never logged.** |
| `GITHUB_REPO`   | GitHub repository in `owner/repo` format, e.g. `voxio-team/voxio`. |

### Exit codes

| Code | Meaning |
|------|---------|
| `0`  | Success, or no open incidents found, or no source files referenced in the top incident. |
| `1`  | Agent API error, GitHub API error, or missing required environment variable. |

### Notes

- The script is idempotent in the sense that re-running it on the same incident
  will fail at the branch-creation step (branch already exists). This is
  acceptable for v1.
- `GITHUB_TOKEN` is never written to any log output.
- The agent routes require the `AGENT_API_KEY` SWA Application Setting to be
  configured. If it is unset, the backend returns 503.
- `GITHUB_TOKEN` and `GITHUB_REPO` are agent-side secrets only and are not
  stored in SWA Application Settings.
