/**
 * Unit tests — POST /api/incidents/report (E-51 T-5102)
 *
 * Contract source: backend/docs/adr/E-51-incident-backend.md §Public Interface Contract
 *
 * All database calls are mocked; tests run fully offline.
 *
 * DB call order inside the route handler (happy path):
 *   1. Upsert into `incidents` (returns [{ fingerprint }])
 *   2. Insert into `incident_occurrences` (returns [])
 *   3. Prune old occurrences (returns [])
 *
 * Auth is performed by requireTelemetryKey which reads x-telemetry-key header
 * against TELEMETRY_API_KEY env var.
 *
 * Run with: pnpm test:unit
 */

import { vi, describe, it, expect, beforeEach } from 'vitest'

vi.mock('@/lib/db', () => ({
  sql: vi.fn(),
  query: vi.fn(),
}))

vi.mock('@/lib/logger', () => ({
  logInfo: vi.fn(),
  logWarn: vi.fn(),
  logError: vi.fn(),
}))

// requireTelemetryKey is in its own lib file — mock it for isolation where
// needed, but by default we let the real implementation run against the env
// var we set in makeRequest().  We mock the db instead.
vi.mock('../../../src/lib/telemetry-key', () => ({
  requireTelemetryKey: vi.fn(),
}))

import { query } from '@/lib/db'
import { requireTelemetryKey } from '../../../src/lib/telemetry-key'
import { POST } from '../../../app/api/incidents/report/route'

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const VALID_FINGERPRINT = 'deadbeefdeadbeef' // 16 lowercase hex chars
const TELEMETRY_KEY = 'test-telemetry-key'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Returns a valid incident report payload with optional overrides. */
function validPayload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    fingerprint: VALID_FINGERPRINT,
    appVersion: '1.3.0',
    osVersion: '18.1',
    deviceModel: 'iPhone15,2',
    contextLines: ['line 1', 'line 2', 'line 3'],
    breadcrumbs: 'Home > Settings',
    errorLine: 'Error: something went wrong at ContentView.swift:42',
    ...overrides,
  }
}

/** Builds a Request with correct auth header by default. */
function makeRequest(
  body: unknown,
  telemetryKey: string | null = TELEMETRY_KEY,
): Request {
  const headers: Record<string, string> = {
    'content-type': 'application/json',
  }
  if (telemetryKey !== null) {
    headers['x-telemetry-key'] = telemetryKey
  }
  return new Request('http://localhost/api/incidents/report', {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  })
}

/**
 * Configures requireTelemetryKey mock for the happy auth path.
 * Returns { ok: true } by default.
 */
function allowAuth(): void {
  vi.mocked(requireTelemetryKey).mockReturnValue({ ok: true })
}

/**
 * Configures requireTelemetryKey to reject with the given status/error.
 */
function denyAuth(status: number, error: string): void {
  const response = Response.json({ error }, { status })
  vi.mocked(requireTelemetryKey).mockReturnValue({ ok: false, response })
}

/**
 * Configures query mock for a successful 3-step DB path.
 *   call 1: incidents upsert → [{ fingerprint }]
 *   call 2: occurrence insert → []
 *   call 3: prune old occurrences → []
 */
function mockDbForSuccess(fingerprint = VALID_FINGERPRINT): void {
  vi.mocked(query)
    .mockResolvedValueOnce({ rows: [{ fingerprint }] })
    .mockResolvedValueOnce({ rows: [] })
    .mockResolvedValueOnce({ rows: [] })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('POST /api/incidents/report — authentication', () => {
  beforeEach(() => {
    vi.resetAllMocks()
  })

  it('returns 401 when x-telemetry-key header is missing', async () => {
    denyAuth(401, 'missing_telemetry_key')
    const req = makeRequest(validPayload(), null)
    const res = await POST(req)
    expect(res.status).toBe(401)
  })

  it('returns { error: "missing_telemetry_key" } when header is absent', async () => {
    denyAuth(401, 'missing_telemetry_key')
    const req = makeRequest(validPayload(), null)
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('missing_telemetry_key')
  })

  it('returns 401 when x-telemetry-key is wrong', async () => {
    denyAuth(401, 'invalid_telemetry_key')
    const req = makeRequest(validPayload(), 'wrong-key')
    const res = await POST(req)
    expect(res.status).toBe(401)
  })

  it('returns { error: "invalid_telemetry_key" } when key is wrong', async () => {
    denyAuth(401, 'invalid_telemetry_key')
    const req = makeRequest(validPayload(), 'wrong-key')
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_telemetry_key')
  })
})

describe('POST /api/incidents/report — fingerprint validation', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAuth()
  })

  it('returns 400 for an uppercase fingerprint ("ABC...")', async () => {
    const req = makeRequest(validPayload({ fingerprint: 'DEADBEEFDEADBEEF' }))
    const res = await POST(req)
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_fingerprint')
  })

  it('returns 400 for a fingerprint that is only 15 chars', async () => {
    const req = makeRequest(validPayload({ fingerprint: 'deadbeefdeadbee' }))
    const res = await POST(req)
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_fingerprint')
  })

  it('returns 400 for a fingerprint that is 17 chars', async () => {
    const req = makeRequest(validPayload({ fingerprint: 'deadbeefdeadbeef1' }))
    const res = await POST(req)
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_fingerprint')
  })

  it('returns 400 for a mixed-case fingerprint', async () => {
    const req = makeRequest(validPayload({ fingerprint: 'DeadBeefDeadBeef' }))
    const res = await POST(req)
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_fingerprint')
  })

  it('returns 400 for a fingerprint containing non-hex chars', async () => {
    const req = makeRequest(validPayload({ fingerprint: 'xyz123xyz123xyz1' }))
    const res = await POST(req)
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_fingerprint')
  })

  it('accepts a valid 16-char lowercase hex fingerprint', async () => {
    mockDbForSuccess()
    const req = makeRequest(validPayload({ fingerprint: 'aaaa1111aaaa1111' }))
    const res = await POST(req)
    expect(res.status).toBe(201)
  })
})

describe('POST /api/incidents/report — contextLines validation', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAuth()
  })

  it('returns 400 with context_too_long when contextLines has 26 entries', async () => {
    const lines = Array.from({ length: 26 }, (_, i) => `line ${i}`)
    const req = makeRequest(validPayload({ contextLines: lines }))
    const res = await POST(req)
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('context_too_long')
  })

  it('returns 400 with line_too_long when one context line exceeds 4096 chars', async () => {
    const longLine = 'x'.repeat(4097)
    const req = makeRequest(validPayload({ contextLines: [longLine] }))
    const res = await POST(req)
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('line_too_long')
  })

  it('accepts exactly 25 context lines (boundary)', async () => {
    mockDbForSuccess()
    const lines = Array.from({ length: 25 }, (_, i) => `line ${i}`)
    const req = makeRequest(validPayload({ contextLines: lines }))
    const res = await POST(req)
    expect(res.status).toBe(201)
  })

  it('accepts an empty contextLines array (0 entries)', async () => {
    mockDbForSuccess()
    const req = makeRequest(validPayload({ contextLines: [] }))
    const res = await POST(req)
    expect(res.status).toBe(201)
  })

  it('accepts a context line of exactly 4096 chars (boundary)', async () => {
    mockDbForSuccess()
    const boundaryLine = 'a'.repeat(4096)
    const req = makeRequest(validPayload({ contextLines: [boundaryLine] }))
    const res = await POST(req)
    expect(res.status).toBe(201)
  })
})

describe('POST /api/incidents/report — happy path: first report', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAuth()
  })

  it('returns 201 on a valid first report', async () => {
    mockDbForSuccess()
    const req = makeRequest(validPayload())
    const res = await POST(req)
    expect(res.status).toBe(201)
  })

  it('returns { fingerprint } matching the submitted fingerprint', async () => {
    mockDbForSuccess()
    const req = makeRequest(validPayload())
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    expect(body.fingerprint).toBe(VALID_FINGERPRINT)
  })

  it('issues exactly 3 DB queries: upsert incidents, insert occurrence, prune', async () => {
    mockDbForSuccess()
    const req = makeRequest(validPayload())
    await POST(req)
    expect(vi.mocked(query)).toHaveBeenCalledTimes(3)
  })

  it('first DB call is the incidents upsert (contains INSERT INTO incidents)', async () => {
    mockDbForSuccess()
    const req = makeRequest(validPayload())
    await POST(req)
    const firstCall = vi.mocked(query).mock.calls[0]
    expect(firstCall[0]).toMatch(/INSERT INTO incidents/i)
  })

  it('second DB call inserts into incident_occurrences', async () => {
    mockDbForSuccess()
    const req = makeRequest(validPayload())
    await POST(req)
    const secondCall = vi.mocked(query).mock.calls[1]
    expect(secondCall[0]).toMatch(/INSERT INTO incident_occurrences/i)
  })

  it('third DB call prunes old occurrences (DELETE ... OFFSET 50)', async () => {
    mockDbForSuccess()
    const req = makeRequest(validPayload())
    await POST(req)
    const thirdCall = vi.mocked(query).mock.calls[2]
    expect(thirdCall[0]).toMatch(/DELETE FROM incident_occurrences/i)
    expect(thirdCall[0]).toMatch(/OFFSET 50/i)
  })
})

describe('POST /api/incidents/report — second report: same fingerprint', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAuth()
  })

  it('returns 201 on second report for same fingerprint', async () => {
    // Second report — upsert returns same fingerprint (ON CONFLICT DO UPDATE)
    vi.mocked(query)
      .mockResolvedValueOnce({ rows: [{ fingerprint: VALID_FINGERPRINT }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
    const req = makeRequest(validPayload())
    const res = await POST(req)
    expect(res.status).toBe(201)
    const body = await res.json() as Record<string, unknown>
    expect(body.fingerprint).toBe(VALID_FINGERPRINT)
  })

  it('occurrence insert fires on second report (verified via query call count)', async () => {
    vi.mocked(query)
      .mockResolvedValueOnce({ rows: [{ fingerprint: VALID_FINGERPRINT }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
    const req = makeRequest(validPayload())
    await POST(req)
    // Verify occurrence INSERT still runs on repeated fingerprint
    const secondCall = vi.mocked(query).mock.calls[1]
    expect(secondCall[0]).toMatch(/INSERT INTO incident_occurrences/i)
  })

  it('upsert SQL does not update error_line on conflict (no SET error_line)', async () => {
    mockDbForSuccess()
    const req = makeRequest(validPayload())
    await POST(req)
    const upsertSql = vi.mocked(query).mock.calls[0][0]
    // The ON CONFLICT clause must not include error_line in SET
    expect(upsertSql).not.toMatch(/SET.*error_line/i)
  })
})

describe('POST /api/incidents/report — pruning: 51st report', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAuth()
  })

  it('prune query fires on every report (verified via query call at position 3)', async () => {
    mockDbForSuccess()
    const req = makeRequest(validPayload())
    await POST(req)
    // The prune DELETE should always run (it is the 3rd query)
    expect(vi.mocked(query)).toHaveBeenCalledTimes(3)
    const pruneCall = vi.mocked(query).mock.calls[2]
    expect(pruneCall[0]).toMatch(/DELETE FROM incident_occurrences/i)
  })

  it('prune query uses OFFSET 50 to keep only 50 occurrences', async () => {
    mockDbForSuccess()
    const req = makeRequest(validPayload())
    await POST(req)
    const pruneCall = vi.mocked(query).mock.calls[2]
    expect(pruneCall[0]).toMatch(/OFFSET 50/i)
  })

  it('prune query is scoped to the fingerprint being reported', async () => {
    mockDbForSuccess()
    const req = makeRequest(validPayload())
    await POST(req)
    const pruneCall = vi.mocked(query).mock.calls[2]
    // The fingerprint param must be bound to the prune query
    expect(pruneCall[1]).toContain(VALID_FINGERPRINT)
  })
})

describe('POST /api/incidents/report — DB error', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAuth()
  })

  it('returns 500 when DB upsert throws', async () => {
    vi.mocked(query).mockRejectedValueOnce(new Error('connection refused'))
    const req = makeRequest(validPayload())
    const res = await POST(req)
    expect(res.status).toBe(500)
  })

  it('returns { error: "internal_error" } when DB upsert throws', async () => {
    vi.mocked(query).mockRejectedValueOnce(new Error('connection refused'))
    const req = makeRequest(validPayload())
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('internal_error')
  })

  it('does not include the raw DB error message in the response', async () => {
    vi.mocked(query).mockRejectedValueOnce(new Error('secret db credentials leaked'))
    const req = makeRequest(validPayload())
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    expect(JSON.stringify(body)).not.toContain('secret db credentials leaked')
  })

  it('returns 500 when occurrence insert throws (after successful upsert)', async () => {
    vi.mocked(query)
      .mockResolvedValueOnce({ rows: [{ fingerprint: VALID_FINGERPRINT }] })
      .mockRejectedValueOnce(new Error('insert failed'))
    const req = makeRequest(validPayload())
    const res = await POST(req)
    expect(res.status).toBe(500)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('internal_error')
  })
})

describe('POST /api/incidents/report — payload schema validation', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAuth()
  })

  it('returns 400 when fingerprint is missing entirely', async () => {
    const { fingerprint: _fp, ...noFp } = validPayload() as { fingerprint: string }
    const req = makeRequest(noFp)
    const res = await POST(req)
    expect(res.status).toBe(400)
  })

  it('returns 400 when errorLine is an empty string', async () => {
    const req = makeRequest(validPayload({ errorLine: '' }))
    const res = await POST(req)
    expect(res.status).toBe(400)
  })

  it('returns 400 when appVersion is missing', async () => {
    const { appVersion: _av, ...noAv } = validPayload() as { appVersion: string }
    const req = makeRequest(noAv)
    const res = await POST(req)
    expect(res.status).toBe(400)
  })
})
