# ADR-E45 — Admin Events UI

**Status:** Accepted
**Date:** 2026-05-04
**Parent ADRs:** ADR-E41, ADR-E42, ADR-E43, ADR-E44

---

## 1. Decision

Implement the admin events UI as seven source files across three layers: filter/query helpers in `src/lib/`, four Route Handlers under root `app/api/admin/`, and two admin pages under root `app/admin/events/`. Dynamic SQL in `listEvents` uses `sql.query(text, params[])` rather than template-tag conditionals. Cursor pagination uses a two-condition tie-break. Label POST auth relies on the SWA gate; null principal returns 401. Filter parsing silently ignores malformed values. The label form is a `'use client'` island component imported by an otherwise-Server-Component detail page.

---

## 2. Context

**From ADR-E42 (binding):**
- Exact column names on `events` and `labels` are frozen.
- `labels` has no `UNIQUE(event_id, labelled_by)` — API must SELECT-then-INSERT-or-UPDATE per `(event_id, labelled_by)`.
- `labels.previous_action` and `labels.previous_corrected_intent` columns exist; an UPDATE must copy current values there before overwriting.
- `labels.action` has a `CHECK ('correct', 'incorrect', 'discard')` DB constraint.

**From ADR-E43 (binding):**
- Split-root layout: `src/lib/` for shared code, root `app/api/` for route handlers.
- `@/` → `./src/*`. `sql` singleton from `@/lib/db`.
- `sql.query(text, params[])` returns `{ rows: T[] }`; the tagged-template form returns `T[]` directly. Do not mix without awareness.

**From ADR-E44 (binding):**
- Admin pages under root `app/admin/`. `getClientPrincipal(headers: Headers)`.
- SWA gate covers `/api/admin/*` — no `requireApiKey` on admin routes.
- `src/app/` must not be created.

---

## 3. Options Considered

### 3A. Dynamic WHERE clause strategy

**`sql.query(text, params[])` (chosen):** Build the WHERE clause as a string with `$1`…`$N` placeholders and a parallel params array. The only safe path for dynamic conditions without a query builder.

**Conditional template fragments (rejected):** `@neondatabase/serverless` has no first-class fragment API. `sql.unsafe()` bypasses parameterisation — insecure.

**Query builder library (rejected):** Effectively ORM-adjacent; prohibited by ADR-001 §7 constraint 6.

### 3B. Cursor pagination tie-break

**Two-condition predicate (chosen):**
```sql
AND (
  e.received_at < $cursor_ts
  OR (e.received_at = $cursor_ts AND e.id < $cursor_id)
)
```
Uses `events_received_at_idx`, readable, mirrors the DESC sort on `(received_at, id)`.

**Row-value comparison `(e.received_at, e.id) < ($1, $2)` (rejected):** Valid SQL but mixes TIMESTAMPTZ and BIGINT in a row constructor — less readable; planner behaviour varies.

### 3C. Label null-principal handling

**Return 401 (chosen):** The SWA gate guarantees a principal is present. Null means misconfiguration — returning 401 protects audit trail integrity rather than masking errors with `'unknown'`.

### 3D. Malformed filter value handling

**Silent ignore / default (chosen):** Admin users manipulate URLs directly. A `limit=abc` should fall back to the default page size without a confusing 400 error page.

---

## 4. Rationale

`sql.query()` is the only safe path for dynamic WHERE clauses given the no-ORM constraint. The two-condition cursor predicate is explicit and index-friendly. Returning 401 on null principal protects audit trail integrity. Silent filter fallback matches admin UX conventions. The `'use client'` island pattern for the label form is the idiomatic Next.js 15 answer — only the interactive label buttons need client state.

---

## 5. Consequences

- `listEvents` uses a mutable params array alongside the WHERE string; implementer must track placeholder index carefully (suggest a helper like `addParam(value) → string` that pushes to params and returns `$N`).
- `sql.query()` returns `{ rows: T[] }` — implementer must destructure `.rows`.
- The label route must SELECT before INSERT/UPDATE (no DB UNIQUE constraint). Race condition between two simultaneous label POSTs for the same `(event_id, labelled_by)` can produce two rows — acceptable for v1 single-admin usage.
- `filtersToSearchParams` must omit null values — no empty-string params in the URL.
- Server Component detail page passes current label state as props to the `LabelForm` client island for pre-selection.
- `CANONICAL_INTENTS` is advisory for the UI picker only; `correctedIntent` in the DB is unconstrained TEXT — schema must not validate against this array.

---

## 6. File-Level Plan

| File | Task | Description |
|---|---|---|
| `src/lib/filters/events.ts` | T-4501 | `EventFilters` type; `filtersFromSearchParams`; `filtersToSearchParams`; cursor encode/decode helpers |
| `src/lib/queries/events.ts` | T-4502 | `EventRow` type; `listEvents(filters)` using `sql.query()` + LEFT JOIN LATERAL |
| `src/lib/schemas/label.ts` | T-4505 | Zod `labelSchema`: action enum, correctedIntent optional, `.refine()` |
| `src/lib/constants/intents.ts` | T-4509 | `CANONICAL_INTENTS` array derived from VoiceCommand.swift |
| `app/api/admin/events/route.ts` | T-4503 | GET: filters → listEvents → `{ rows, nextCursor, total: null }` |
| `app/api/admin/events/[id]/route.ts` | T-4504 | GET: validate id → single SELECT → 404 if missing |
| `app/api/admin/events/[id]/label/route.ts` | T-4506 | POST: validate → labelSchema → getClientPrincipal → SELECT exists → SELECT existing label → INSERT or UPDATE |
| `app/admin/events/page.tsx` | T-4507 | Server Component: filter controls, events table, cursor pagination, export link |
| `app/admin/events/[id]/page.tsx` | T-4508 | Server Component + `LabelForm` `'use client'` island |

---

## 7. Public Interface Contract

### `EventFilters`

```ts
export interface EventFilters {
  dateFrom:              string | null
  dateTo:                string | null
  intent:                string | null
  parserPath:            string | null
  outcome:               string | null
  locale:                string | null
  flag:                  string | null
  transcriptionContains: string | null
  limit:                 number          // default 50, max 200
  cursor:                string | null   // base64 JSON { id: number, received_at: string }
}
```

### `EventRow`

```ts
export interface EventRow {
  id:                       bigint
  device_id:                string
  received_at:              string
  client_timestamp:         string
  app_version:              string
  model_version:            string
  locale:                   string
  transcription_anonymised: string
  intent:                   string
  slots_anonymised:         unknown
  parser_path:              string
  outcome:                  string
  flags:                    string[]
  label_action:             string | null
  label_corrected_intent:   string | null
  label_labelled_by:        string | null
  label_labelled_at:        string | null
}
```

### `listEvents` signature

```ts
export function listEvents(filters: EventFilters): Promise<{ rows: EventRow[]; nextCursor: string | null }>
```

Fetches `limit + 1` rows; if `rows.length > limit`, pops the last row and encodes the cursor from the new last row.

### `labelSchema` (Zod)

```ts
export const labelSchema = z.object({
  action: z.enum(['correct', 'incorrect', 'discard']),
  correctedIntent: z.string().min(1).max(64).optional(),
}).refine(
  (d) => !(d.action === 'incorrect' && !d.correctedIntent),
  { message: 'correctedIntent required when action is incorrect', path: ['correctedIntent'] }
)
```

### `CANONICAL_INTENTS` (from VoiceCommand.swift)

```ts
export const CANONICAL_INTENTS = [
  'playFavorite', 'playDefault', 'listFavorites',
  'stop', 'pause', 'resume',
  'setVolume', 'adjustVolume', 'mute', 'unmute',
  'joinSpeaker', 'leaveSpeaker',
  'confirm', 'cancel', 'unknown',
] as const
```

### Route response shapes

```
GET  /api/admin/events
  200  { rows: EventRow[], nextCursor: string | null, total: null }
  500  { error: "Server error" }

GET  /api/admin/events/[id]
  200  EventRow
  400  { error: "Invalid id" }
  404  { error: "Not found" }
  500  { error: "Server error" }

POST /api/admin/events/[id]/label
  body: { action, correctedIntent? }
  200  { ok: true }
  400  { error: string, detail?: string }
  401  { error: "Unauthorized" }
  404  { error: "Event not found" }
  500  { error: "Server error" }
```

### LEFT JOIN LATERAL for latest label

```sql
LEFT JOIN LATERAL (
  SELECT action, corrected_intent, labelled_by, labelled_at
  FROM labels
  WHERE event_id = e.id
  ORDER BY labelled_at DESC
  LIMIT 1
) l ON true
```

---

## 8. Conflicts Flagged

**C-1 (BLOCKING — spec correction):** T-4503/T-4504/T-4506 reference `src/app/api/admin/`. Correct path: root `app/api/admin/`. Do not create `src/app/`.

**C-2 (BLOCKING — spec correction):** T-4507/T-4508 reference `src/app/admin/events/`. Correct path: root `app/admin/events/`. Do not create `src/app/admin/`.

**C-3 (BLOCKING — implementer must know):** `sql.query(text, params)` returns `{ rows: T[] }`. The tagged-template form `sql\`...\`` returns `T[]`. Mixing them without awareness causes a runtime type error. All dynamic queries must use `sql.query()` and destructure `.rows`.

**C-4 (BLOCKING — implementer must follow):** No `UNIQUE(event_id, labelled_by)` on `labels`. T-4506 must SELECT existing label before deciding INSERT or UPDATE. An unconditional INSERT accumulates duplicate rows.

**C-5 (BLOCKING — implementer must follow):** T-4506 UPDATE must copy current `action` → `previous_action` and `corrected_intent` → `previous_corrected_intent` before overwriting. The spec task description omits this; ADR-E42 §8 is authoritative.

**C-6 (non-blocking):** `correctedIntent` stored in DB is unconstrained TEXT. `CANONICAL_INTENTS` is for the UI picker dropdown only — Zod schema must not validate against it.

---

**VERDICT: PROCEED**
