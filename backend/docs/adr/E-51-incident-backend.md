# ADR: E-51 — Incident Backend & Agent Interface

**Status:** Approved — gates Implementer and Test Writer start
**Date:** 2026-05-07
**Epic:** E-51 (T-5101 – T-5108)
**Absorbs:** E-48 primitives (requireAgentKey, AGENT_API_KEY, agent SWA route rule)

---

## Decision

Implement E-51 in a single PR that absorbs the unimplemented E-48 primitives (`requireAgentKey` middleware, `/api/agent/*` SWA route rule) as a prerequisite block. The two new tables (`incidents`, `incident_occurrences`) are introduced via a `node-pg-migrate` TypeScript migration at timestamp `1746350003000`. The ingest route (`POST /api/incidents/report`) uses a new `requireTelemetryKey` helper reading the `x-telemetry-key` header — distinct from the existing `requireApiKey` which reads `x-api-key`. Agent routes use `requireAgentKey` from `src/lib/agent-auth.ts`. The agent PR script lives outside the SWA process at `agent/scripts/open-incident-pr.ts`.

---

## Context

**What exists:**
- `src/lib/auth.ts` — exports `requireApiKey(request)`. Reads `x-api-key` header against `TELEMETRY_API_KEY` using `timingSafeEqual`. Returns `null` on success, `NextResponse` 401 on failure.
- `src/lib/db.ts` — `query<T>(text, params)` helper over `@neondatabase/serverless`.
- `src/lib/logger.ts` — `logInfo`, `logWarn`, `logError` emitting JSON lines.
- Migrations `1746350000000`–`1746350002000` — `devices`, `events`, `labels`.
- `staticwebapp.config.json` — has `/admin` rules only. **Missing `/api/telemetry/*` and `/api/agent/*` anonymous rules.**
- No `app/api/agent/` directory, no `src/lib/agent-auth.ts`, no `app/api/incidents/` directory.

**What is missing (E-48 not implemented):**
- `src/lib/agent-auth.ts` — does not exist.
- `app/api/agent/` — no agent routes exist.
- SWA anonymous rules for telemetry, incidents, and agent paths.

---

## Options Considered

**Option A — Absorb E-48 into E-51 (chosen).** `requireAgentKey` and the missing SWA route rules are implemented as the first block of E-51's PR (~30 lines + 3 JSON entries). E-51 cannot ship without them; a blocking separate PR adds friction with no architectural benefit.

**Option B — Return REVISE SPEC.** Clean dependency separation but delays E-51 and E-49 by at least one additional cycle. Rejected.

---

## Rationale

`requireAgentKey` is self-contained and its full contract is specified in the E-48 spec. E-49 (not yet implemented) will import it from the same location after E-51 lands. The SWA route rules are mandatory for any API route to be reachable; their absence is a gap from E-43/E-48, not a design choice.

---

## Consequences

1. The E-51 Implementer also owns `src/lib/agent-auth.ts`, `src/lib/telemetry-key.ts`, and the three SWA route rule additions.
2. After E-51 lands, E-49 has no remaining E-48 blockers.
3. The existing `requireApiKey` in `src/lib/auth.ts` reads `x-api-key` — do not modify it. The ingest route uses `requireTelemetryKey` instead.
4. Migration timestamp `1746350003000` is the next valid value.
5. `agent/scripts/` is a new top-level directory. Run with `tsx agent/scripts/open-incident-pr.ts` from repo root using `tsx` from `backend/package.json` devDependencies.

---

## File-Level Plan

**New files:**

| Path | Task |
|---|---|
| `backend/migrations/1746350003000_incident_tables.ts` | T-5101 |
| `backend/src/lib/agent-auth.ts` | T-5101-pre (absorbed E-48/T-4801) |
| `backend/src/lib/telemetry-key.ts` | T-5102 (new helper for x-telemetry-key) |
| `backend/app/api/incidents/report/route.ts` | T-5102 |
| `backend/app/api/agent/incidents/route.ts` | T-5103 |
| `backend/app/api/agent/incidents/[fingerprint]/route.ts` | T-5104 + T-5105 (GET + PATCH named exports) |
| `agent/scripts/open-incident-pr.ts` | T-5106 |
| `agent/scripts/README.md` | T-5106 |
| `backend/test/unit/lib/agent-auth.test.ts` | T-5101-pre |
| `backend/test/unit/api/incidents/report.test.ts` | T-5102 |
| `backend/test/unit/api/agent/incidents-list.test.ts` | T-5103 |
| `backend/test/unit/api/agent/incidents-detail.test.ts` | T-5104 |
| `backend/test/unit/api/agent/incidents-patch.test.ts` | T-5105 |
| `backend/test/integration/incident-flow.test.ts` | T-5107 |

**Modified files:**

| Path | Task | Change |
|---|---|---|
| `staticwebapp.config.json` (repo root) | T-5101-pre + T-5108 | Add `/api/telemetry/*`, `/api/incidents/*`, `/api/agent/*` anonymous rules |

---

## Public Interface Contract

### `src/lib/agent-auth.ts`
```typescript
export function requireAgentKey(
  request: Request
): { ok: true } | { ok: false; response: Response }
// AGENT_API_KEY unset/empty → 503 { error: "agent_api_disabled" }
// x-agent-key missing/empty → 401 { error: "missing_agent_key" }
// wrong key → 401 { error: "invalid_agent_key" }
// match → { ok: true }
// never logs key value
```

### `src/lib/telemetry-key.ts`
```typescript
export function requireTelemetryKey(
  request: Request
): { ok: true } | { ok: false; response: Response }
// TELEMETRY_API_KEY unset → 503 { error: "telemetry_key_not_configured" }
// x-telemetry-key missing → 401 { error: "missing_telemetry_key" }
// wrong key → 401 { error: "invalid_telemetry_key" }
```

### `POST /api/incidents/report` — Zod-validated body
```typescript
{ fingerprint: string        // /^[0-9a-f]{16}$/
  appVersion: string         // 1..32 chars
  osVersion: string          // 1..32 chars
  deviceModel: string        // 1..64 chars
  contextLines: string[]     // 0..25 entries, each <=4096 chars
  breadcrumbs: string        // 0..1024 chars
  errorLine: string }        // 1..4096 chars
// Success: 201 { fingerprint: string }
// Auth: x-telemetry-key header
```

### `GET /api/agent/incidents`
```typescript
// Query: status?: "open"|"investigating"|"resolved"|"ignored", cursor?: string
// Cursor encoding: Buffer.from(JSON.stringify({ last_seen_at, fingerprint })).toString("base64")
// Response: { incidents: AgentIncidentSummary[], nextCursor: string|null }
// Page size: 20 fixed. Auth: x-agent-key.
interface AgentIncidentSummary {
  fingerprint: string; first_seen_at: string; last_seen_at: string
  occurrence_count: number; error_line: string
  status: "open"|"investigating"|"resolved"|"ignored"
  pr_url: string|null; pr_number: number|null
}
```

### `GET /api/agent/incidents/:fingerprint`
```typescript
// Response: AgentIncidentSummary fields + recent_occurrences (up to 10, DESC)
interface AgentIncidentOccurrence {
  id: string              // BIGINT as decimal string
  reported_at: string; app_version: string; os_version: string
  device_model: string; context_lines: string[]; breadcrumbs: string
}
```

### `PATCH /api/agent/incidents/:fingerprint`
```typescript
// Body (at least one field): { status?, pr_url?, pr_number? }
// pr_url must start "https://", 1..512 chars; pr_number positive int
// Success 200: { fingerprint, status, pr_url, pr_number }
```

### `staticwebapp.config.json` route order
```json
[
  { "route": "/admin",           "allowedRoles": ["admin"] },
  { "route": "/admin/*",         "allowedRoles": ["admin"] },
  { "route": "/api/admin/*",     "allowedRoles": ["admin"] },
  { "route": "/api/telemetry/*", "allowedRoles": ["anonymous"] },
  { "route": "/api/incidents/*", "allowedRoles": ["anonymous"] },
  { "route": "/api/agent/*",     "allowedRoles": ["anonymous"] }
]
```

---

## Conflicts Flagged

**C-1 (BLOCKING — header name):** `requireApiKey` reads `x-api-key`; spec and iOS client use `x-telemetry-key`. Ingest route must use `requireTelemetryKey`. Do not touch `requireApiKey`.

**C-2 (BLOCKING — missing SWA rules):** No `/api/telemetry/*` or `/api/agent/*` anonymous rules in committed config. Both added in this PR. Confirm existing telemetry ingest is reachable in production before merging.

**C-3 (non-blocking — cursor shape):** Incidents cursor uses `{ last_seen_at, fingerprint }`, not the events cursor shape `{ received_at, id }`. Write a dedicated encoder inline in the incidents list route; do not reuse `src/lib/filters/events.ts`.

**C-4 (non-blocking — agent/ directory):** `agent/scripts/` is a new top-level directory. No separate `package.json` needed; use `tsx` from `backend/devDependencies`.

**C-5 (non-blocking — SWA 401 redirect):** Existing `responseOverrides` redirects all 401s to `/.auth/login/github`. Machine callers receive 302 on wrong key — known and accepted per ADR-E44.

---

**Verdict: PROCEED**
