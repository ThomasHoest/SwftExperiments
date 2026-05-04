# ADR-E46 — Admin Export, Stats, and Deletion

**Status:** Accepted
**Date:** 2026-05-04
**Parent ADRs:** ADR-E41, ADR-E42, ADR-E43, ADR-E44, ADR-E45

---

## 1. Decision

Implement the admin export, stats, and deletion feature set as seven source files across three layers. The export endpoint buffers all matching rows in memory and returns a single `Response` with a UTF-8 BOM CSV body; no streaming `ReadableStream`. The stats endpoint uses `Promise.all` over parallel `query()` calls rather than a single CTE-heavy aggregation. The admin deletion endpoint executes SQL directly (SELECT-then-DELETE) rather than making an HTTP self-call to the public DELETE endpoint. All three Route Handlers use `getClientPrincipal` for a secondary guard and return 401 on null. The `DeletionForm` client island follows the same `'use client'` pattern as `LabelForm` from E-45.

---

## 2. Context

**From ADR-E42 (binding):**
- Tables: `devices(device_id UUID PK)`, `events(id BIGSERIAL PK, device_id FK ON DELETE CASCADE, received_at TIMESTAMPTZ, ...)`, `labels(id BIGSERIAL PK, event_id FK ON DELETE CASCADE, action CHECK('correct','incorrect','discard'), corrected_intent TEXT, labelled_by TEXT, labelled_at TIMESTAMPTZ, previous_action TEXT, previous_corrected_intent TEXT)`.
- `DELETE FROM devices WHERE device_id = $1` cascades to events and then to labels via `ON DELETE CASCADE`. No application-level multi-DELETE required.
- Column names are a frozen contract; any deviation is a breaking change.

**From ADR-E43 (binding):**
- Split-root layout: `src/lib/` for shared code, root `app/api/` for route handlers. `src/app/` must NOT be created.
- `@/` resolves to `./src/*`. The database singleton exports both `sql` (tagged-template) and `query` (function form).
- `query(text, params[])` returns `{ rows: T[] }`. Destructure `.rows` at every call site.
- The SELECT-then-DELETE pattern for counts is established at `app/api/telemetry/[deviceId]/route.ts`; counts may drift from cascade result; this is accepted.

**From ADR-E44 (binding):**
- SWA route rules in `staticwebapp.config.json` gate `/api/admin/*` to `allowedRoles: ["admin"]`. Null principal means misconfiguration, not an anonymous user.
- `getClientPrincipal(headers: Headers): ClientPrincipal | null` is at `src/lib/auth/clientPrincipal.ts`. Accept `request.headers` from Route Handlers.
- Admin pages under root `app/admin/`. Do NOT create `src/app/admin/`.
- `src/lib/auth.ts` (API key) and `src/lib/auth/clientPrincipal.ts` (SWA principal) coexist; never rename either.

**From ADR-E45 (binding):**
- `EventFilters` and `filtersFromSearchParams`/`filtersToSearchParams` exist at `src/lib/filters/events.ts`. Reuse directly; do not redeclare.
- `listEvents(filters)` at `src/lib/queries/events.ts`. Uses `addParam` pattern for dynamic WHERE clauses.
- LEFT JOIN LATERAL pattern for latest label per event is established; the export query extends it using `INNER JOIN LATERAL` (not LEFT) to restrict to labelled events only.
- The `'use client'` island pattern (as in `LabelForm`) is the established answer for interactive admin form components.

---

## 3. Options Considered

### 3A. Deletion: direct SQL vs HTTP self-call

**Direct SQL SELECT-then-DELETE (chosen):** The admin deletion handler executes `SELECT COUNT(*)` subqueries then `DELETE FROM devices WHERE device_id = $1` directly, using the same `query()` singleton. This is identical to the pattern in `app/api/telemetry/[deviceId]/route.ts` established by ADR-E43. No HTTP involved, no DNS round-trip to localhost, no SWA auth header forwarding complexity.

**HTTP self-call to `DELETE /api/telemetry/{deviceId}` (rejected):** Serverless functions on Azure SWA cannot reliably call themselves — the function instance may not be routable by its own hostname during cold start, and doing so would require forwarding or re-generating the `X-Api-Key` header from an env var inside the handler. This introduces a timing-dependent failure mode and a secret-handling anti-pattern.

### 3B. CSV response strategy: buffered vs streaming ReadableStream

**Buffer all rows in memory, return single `Response` (chosen):** Next.js Route Handlers return `Response` objects. The spec bounds the export set to 100k rows maximum. At an estimated 300 bytes per CSV row, 100k rows is approximately 30 MB — within serverless memory limits (Azure SWA uses 1.5 GB for Node functions) and safe to buffer. Buffering also allows setting accurate `Content-Length`, which benefits browser download progress indicators.

**Streaming ReadableStream (rejected):** Adds generator complexity with no observable benefit within the 100k-row constraint. If the constraint is revisited in a future epic, the implementation can be switched then.

### 3C. Stats query strategy: single CTE vs parallel queries

**`Promise.all` over parallel `query()` calls (chosen):** Each aggregation is a simple `SELECT` with a `GROUP BY` or a single `COUNT`. Running them as independent `query()` calls in `Promise.all` is readable, individually debuggable, and independently error-isolatable.

**Single CTE with multiple aggregations (rejected):** A single query with multiple CTEs and `UNION ALL` or `CROSS JOIN` of aggregations is less readable, harder to modify, and makes individual aggregation errors unattributable. There is no throughput benefit for an admin-only page.

### 3D. Null principal handling on admin Route Handlers

**Return 401 (chosen):** SWA's route rules guarantee a valid principal is present on all `/api/admin/*` requests. A null result from `getClientPrincipal` means the `x-ms-client-principal` header is absent — misconfiguration or direct invocation bypassing SWA. Returning 401 and logging at WARN preserves audit trail integrity and surfaces misconfigurations promptly. Matches the pattern established in ADR-E45 for the label route.

---

## 4. Rationale

Direct SQL for deletion removes all serverless self-call risks at the cost of duplicating the SELECT-then-DELETE pattern, which is already an established convention. Buffered CSV is simpler and correct within the stated row-count bound; if the bound grows, replacing the buffer with a `ReadableStream` is a one-file change. `Promise.all` for stats queries is more maintainable than a monolithic CTE and fits the no-ORM constraint cleanly. The 401-on-null-principal guard is the only defensible choice when the SWA gate is the primary enforcer.

The `DeletionForm` client island matches the architecture of `LabelForm` from E-45: the Server Component page owns layout; only the interactive submit/response cycle requires client state.

---

## 5. Consequences

- `src/lib/queries/stats.ts` introduces a new file in the established `queries/` layer. Must import `query as dbQuery` from `@/lib/db` — not the `sql` tagged-template — because all WHERE clauses are conditionally assembled.
- The export query is NOT the same function as `listEvents`. It uses `INNER JOIN LATERAL` (not LEFT) to restrict to labelled events, and has no pagination — it returns all matching rows. Write a dedicated `exportLabelledEvents(filters)` function at `src/lib/queries/export.ts`.
- `getStats` accepts `dateFrom`/`dateTo` only — not the full `EventFilters` shape. The stats page's date-range form sends only those two query params.
- `DeletionForm.tsx` must carry `'use client'` at line 1. The page is a Server Component that imports it but passes no props — the form manages all state internally.
- The CSV UTF-8 BOM (`﻿`) must be the first three bytes of the response body. Required for Excel on macOS and Windows to auto-detect UTF-8 encoding.
- RFC 4180 quoting: any field value containing a comma, double-quote, or newline must be wrapped in double quotes; interior double-quotes are doubled (`""`).
- The `corrected_intent` CSV column must be an empty string (not `null`, not `"null"`) when `label_action` is not `'incorrect'`. Enforced in the CSV serialization layer, not in SQL.
- `flags` stored as `TEXT[]` arrives as `string[]` at the query layer. Join with semicolons: `flags.join(';')`. Empty array produces empty string.
- `Content-Disposition` filename uses UTC date: `new Date().toISOString().slice(0, 10)`.
- The deletion endpoint returns 200 with all-zero counts when device is not found (idempotent). Matches the public DELETE endpoint pattern.
- `getStats` must finalize WHERE clause and params array before `Promise.all`. The `addParam` closure must not be called from within any concurrent `query()` call — all param additions happen synchronously before `Promise.all([...])`.
- `labelledCount` must use `COUNT(DISTINCT e.id)` when joining events to labels to avoid double-counting events with multiple label rows.

---

## 6. File-Level Plan

| File | Task | Description |
|---|---|---|
| `src/lib/queries/stats.ts` | T-4603 | `StatsResult` interface + `getStats(dateFrom, dateTo)` using `Promise.all` over independent `query()` calls |
| `src/lib/queries/export.ts` | T-4601 (query) | `ExportRow` type + `exportLabelledEvents(filters: EventFilters): Promise<ExportRow[]>` using `INNER JOIN LATERAL` |
| `app/api/admin/export/route.ts` | T-4601 | GET: principal guard → `filtersFromSearchParams` → `exportLabelledEvents` → CSV string with BOM → `Response` |
| `app/api/admin/deletion/route.ts` | T-4605 | POST: principal guard → parse + validate JSON body → SELECT counts → DELETE → 200 with counts |
| `app/admin/export/page.tsx` | T-4602 | Server Component: filter form + `<form action="/api/admin/export" method="GET">` download trigger |
| `app/admin/stats/page.tsx` | T-4604 | Server Component: date range form → `getStats` call → tile grid + tables |
| `app/admin/deletion/page.tsx` | T-4606 | Server Component: explanation + imports `DeletionForm` island |
| `app/admin/deletion/DeletionForm.tsx` | T-4606 | `'use client'` island: device ID input, confirmation input, POST, success/failure message |

---

## 7. Public Interface Contract

### `StatsResult` and `getStats`

```ts
// src/lib/queries/stats.ts

export interface StatsResult {
  totalEvents: number
  distinctDevices: number
  byIntent: Record<string, number>
  byOutcome: Record<string, number>
  byParserPath: Record<string, number>
  byLocale: Record<string, number>
  likelyMisparseCount: number
  labelledCount: number
  labelsByAction: { correct: number; incorrect: number; discard: number }
}

export async function getStats(
  dateFrom: string | null,
  dateTo: string | null
): Promise<StatsResult>
```

WHERE clause pattern for `getStats` — build once, share across all `Promise.all` queries:

```ts
const params: unknown[] = []
let pIdx = 1
function addParam(val: unknown): string { params.push(val); return `$${pIdx++}` }
const conds: string[] = []
if (dateFrom) conds.push(`e.received_at >= ${addParam(dateFrom)}::timestamptz`)
if (dateTo)   conds.push(`e.received_at <  ${addParam(dateTo)}::timestamptz`)
const whereClause = conds.length > 0 ? `WHERE ${conds.join(' AND ')}` : ''
// Then: Promise.all([query(sql1, params), query(sql2, params), ...])
// params array is read-only from this point; query() does not mutate inputs.
```

Nine parallel queries (all receive same `whereClause` and `params`):
1. `SELECT COUNT(*) AS n FROM events e ${whereClause}` → `totalEvents`
2. `SELECT COUNT(DISTINCT device_id) AS n FROM events e ${whereClause}` → `distinctDevices`
3. `SELECT intent, COUNT(*) AS n FROM events e ${whereClause} GROUP BY intent ORDER BY n DESC` → `byIntent`
4. `SELECT outcome, COUNT(*) AS n FROM events e ${whereClause} GROUP BY outcome` → `byOutcome`
5. `SELECT parser_path, COUNT(*) AS n FROM events e ${whereClause} GROUP BY parser_path` → `byParserPath`
6. `SELECT locale, COUNT(*) AS n FROM events e ${whereClause} GROUP BY locale` → `byLocale`
7. `SELECT COUNT(*) AS n FROM events e ${whereClause} ${whereClause ? 'AND' : 'WHERE'} 'likelyMisparse' = ANY(e.flags)` → `likelyMisparseCount`
8. `SELECT COUNT(DISTINCT e.id) AS n FROM events e INNER JOIN labels l ON l.event_id = e.id ${whereClause}` → `labelledCount`
9. `SELECT l.action, COUNT(*) AS n FROM labels l INNER JOIN events e ON e.id = l.event_id ${whereClause} GROUP BY l.action` → `labelsByAction`

### `ExportRow` and `exportLabelledEvents`

```ts
// src/lib/queries/export.ts

export interface ExportRow {
  event_id: string                // e.id::text
  timestamp: string               // e.received_at
  locale: string
  transcription_anonymised: string
  original_intent: string         // e.intent aliased
  parser_path: string
  outcome: string
  flags: string[]
  label_action: string            // l.action (guaranteed non-null by INNER JOIN)
  corrected_intent: string | null // l.corrected_intent
  labelled_by: string
  labelled_at: string
}

export async function exportLabelledEvents(
  filters: EventFilters
): Promise<ExportRow[]>
```

SQL:

```sql
SELECT
  e.id::text AS event_id,
  e.received_at AS timestamp,
  e.locale,
  e.transcription_anonymised,
  e.intent AS original_intent,
  e.parser_path,
  e.outcome,
  e.flags,
  l.action AS label_action,
  l.corrected_intent,
  l.labelled_by,
  l.labelled_at
FROM events e
INNER JOIN LATERAL (
  SELECT action, corrected_intent, labelled_by, labelled_at
  FROM labels
  WHERE event_id = e.id
    AND action IS NOT NULL
  ORDER BY labelled_at DESC
  LIMIT 1
) l ON true
[WHERE clause from filters]
ORDER BY e.received_at DESC, e.id DESC
```

Use `INNER JOIN LATERAL` — not LEFT — so unlabelled events are excluded. `addParam` and WHERE clause assembly follow the same pattern as `listEvents`. No `LIMIT` clause.

### Route response shapes

```
GET  /api/admin/export
  200  text/csv; charset=utf-8
       Content-Disposition: attachment; filename="voxio-labelled-events-<YYYY-MM-DD>.csv"
       Body: <UTF-8 BOM> + header row + [data rows]  (header row only when zero matches)
  401  { "error": "Unauthorized" }
  500  { "error": "Server error" }

POST /api/admin/deletion
  body: { "deviceId": "<UUID>", "confirmation": "DELETE" }
  200  { "deleted": { "devices": <int>, "events": <int>, "labels": <int> } }
  400  { "error": "Invalid deviceId" }            — bad UUID format
  400  { "error": "Type DELETE to confirm" }       — confirmation mismatch
  401  { "error": "Unauthorized" }
  500  { "error": "Server error" }
```

### Deletion SELECT-then-DELETE SQL pattern

```ts
// Run in Promise.all:
const [labelRes, eventRes, deviceRes] = await Promise.all([
  dbQuery<{ n: string }>('SELECT COUNT(*) AS n FROM labels WHERE event_id IN (SELECT id FROM events WHERE device_id = $1)', [deviceId]),
  dbQuery<{ n: string }>('SELECT COUNT(*) AS n FROM events WHERE device_id = $1', [deviceId]),
  dbQuery<{ n: string }>('SELECT COUNT(*) AS n FROM devices WHERE device_id = $1', [deviceId]),
])
const devices = Number(deviceRes.rows[0].n)
const events  = Number(eventRes.rows[0].n)
const labels  = Number(labelRes.rows[0].n)
if (devices === 0) return Response.json({ deleted: { devices: 0, events: 0, labels: 0 } })
await dbQuery('DELETE FROM devices WHERE device_id = $1', [deviceId])
return Response.json({ deleted: { devices, events, labels } })
```

### CSV serialization helper contract

```ts
// Inline in app/api/admin/export/route.ts (no separate file needed)
function csvField(val: string): string {
  if (/[,"\n]/.test(val)) return '"' + val.replace(/"/g, '""') + '"'
  return val
}
const BOM = '﻿'
const HEADERS = [
  'event_id','timestamp','locale','transcription_anonymised','original_intent',
  'parser_path','outcome','flags','label_action','corrected_intent','labelled_by','labelled_at',
]
const lines = [
  BOM + HEADERS.join(','),
  ...rows.map(r => [
    r.event_id,
    r.timestamp,
    r.locale,
    r.transcription_anonymised,
    r.original_intent,
    r.parser_path,
    r.outcome,
    r.flags.join(';'),
    r.label_action,
    r.label_action === 'incorrect' ? (r.corrected_intent ?? '') : '',
    r.labelled_by,
    r.labelled_at,
  ].map(csvField).join(',')),
]
const body = lines.join('\n') + '\n'
```

### `DeletionForm` client island state contract

```ts
// app/admin/deletion/DeletionForm.tsx — 'use client'
// Props: none
// Internal state:
//   deviceId: string       — controlled text input
//   confirmation: string   — controlled text input, must equal 'DELETE' to submit
//   status: 'idle' | 'pending' | 'success' | 'error'
//   result: { events: number; labels: number; devices: number } | null
//   clientError: string | null
//
// On submit:
//   if (confirmation !== 'DELETE'): set clientError, return
//   fetch POST /api/admin/deletion
//
// Success messages:
//   devices === 0 (and events === 0 and labels === 0):
//     "No data found for device {deviceId}. Nothing to delete."
//   otherwise:
//     "Deleted {events} events and {labels} labels for device {deviceId}."
//
// Error message: "Deletion failed. Please try again or contact engineering."
```

---

## 8. Conflicts Flagged

**C-1 (BLOCKING — platform constraint):** Route handlers at `app/api/admin/export/route.ts` and `app/api/admin/deletion/route.ts` are correct. Pages at `app/admin/export/page.tsx`, `app/admin/stats/page.tsx`, `app/admin/deletion/page.tsx` are correct. Do NOT create `src/app/` — confirmed platform constraint from ADR-E44.

**C-2 (BLOCKING — SQL join type):** The spec says "LEFT JOIN LATERAL with WHERE l.action IS NOT NULL." This is wrong: a LEFT JOIN allows the outer row through even when the lateral returns no rows, producing `l.action = null`. Implementer must use `INNER JOIN LATERAL` for the export query so only events with at least one label are included.

**C-3 (BLOCKING — addParam must not be called concurrently):** The `getStats` implementation must finalize the WHERE clause string and params array before `Promise.all`. The `addParam` closure must not be called from within any of the concurrent `query()` calls.

**C-4 (BLOCKING — labelledCount must be DISTINCT):** `labelledCount` requires `COUNT(DISTINCT e.id)` when joining events to labels. Using `COUNT(*)` on the join would count label rows and double-count events with multiple labels.

**C-5 (non-blocking — CSV column named `original_intent`):** The CSV header must be `original_intent` (not `intent`). The SQL `SELECT` must alias `e.intent AS original_intent`.

**C-6 (non-blocking — stats page date defaults):** When `dateFrom`/`dateTo` are absent from the query string, default to last 7 days: `dateTo = new Date().toISOString().slice(0, 10)`, `dateFrom = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10)`. These are UTC dates; the `::timestamptz` cast interprets them as midnight UTC.

**C-7 (non-blocking — corrected_intent CSV semantics):** The CSV must emit an empty string for `corrected_intent` when `label_action !== 'incorrect'`, regardless of the DB value. Enforce in the CSV serialization layer, not in SQL.

**C-8 (non-blocking — export page filter fields):** The export page form exposes `dateFrom`, `dateTo`, `intent`, `locale`, `outcome` only (per spec US-A3). The `exportLabelledEvents` function accepts the full `EventFilters` shape for internal consistency, but the page form does not expose all filter fields.

---

**VERDICT: PROCEED**
