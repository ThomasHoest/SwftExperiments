/**
 * Unit tests — GET /api/agent/incidents (E-51 T-5103)
 *
 * Contract source: backend/docs/adr/E-51-incident-backend.md §Public Interface Contract
 *
 * All database calls are mocked; tests run fully offline.
 *
 * Cursor encoding: Buffer.from(JSON.stringify({ last_seen_at, fingerprint })).toString("base64")
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

vi.mock('../../../../src/lib/agent-auth', () => ({
  requireAgentKey: vi.fn(),
}))

import { query } from '@/lib/db'
import { requireAgentKey } from '../../../../src/lib/agent-auth'
import { GET } from '../../../../app/api/agent/incidents/route'

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const AGENT_KEY = 'test-agent-key'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeRequest(searchParams: Record<string, string> = {}): Request {
  const url = new URL('http://localhost/api/agent/incidents')
  for (const [k, v] of Object.entries(searchParams)) {
    url.searchParams.set(k, v)
  }
  return new Request(url.toString(), {
    method: 'GET',
    headers: { 'x-agent-key': AGENT_KEY },
  })
}

function allowAgentAuth(): void {
  vi.mocked(requireAgentKey).mockReturnValue({ ok: true })
}

function denyAgentAuth(status: number, error: string): void {
  const response = Response.json({ error }, { status })
  vi.mocked(requireAgentKey).mockReturnValue({ ok: false, response })
}

/** Builds a mock incident summary row. */
function makeIncidentRow(overrides: Partial<{
  fingerprint: string
  first_seen_at: string
  last_seen_at: string
  occurrence_count: number
  error_line: string
  status: string
  pr_url: string | null
  pr_number: number | null
}> = {}) {
  return {
    fingerprint: 'deadbeefdeadbeef',
    first_seen_at: '2026-05-01T10:00:00Z',
    last_seen_at: '2026-05-06T12:00:00Z',
    occurrence_count: 3,
    error_line: 'Error: something failed',
    status: 'open',
    pr_url: null,
    pr_number: null,
    ...overrides,
  }
}

/** Encodes a cursor the way the route handler produces one. */
function encodeCursor(last_seen_at: string, fingerprint: string): string {
  return Buffer.from(JSON.stringify({ last_seen_at, fingerprint })).toString('base64')
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('GET /api/agent/incidents — authentication', () => {
  beforeEach(() => {
    vi.resetAllMocks()
  })

  it('returns 401 when agent key is wrong', async () => {
    denyAgentAuth(401, 'invalid_agent_key')
    const res = await GET(makeRequest())
    expect(res.status).toBe(401)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_agent_key')
  })

  it('returns 503 when AGENT_API_KEY is unset', async () => {
    denyAgentAuth(503, 'agent_api_disabled')
    const res = await GET(makeRequest())
    expect(res.status).toBe(503)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('agent_api_disabled')
  })
})

describe('GET /api/agent/incidents — no params (default page)', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 200 with an incidents array', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [makeIncidentRow()] })
    const res = await GET(makeRequest())
    expect(res.status).toBe(200)
    const body = await res.json() as Record<string, unknown>
    expect(Array.isArray(body.incidents)).toBe(true)
  })

  it('returns up to 20 incidents (fetches 21 to detect has-more)', async () => {
    // Return 21 rows → should give us 20 in response + nextCursor set
    const rows = Array.from({ length: 21 }, (_, i) =>
      makeIncidentRow({ fingerprint: `deadbeef0000000${i.toString(16).padStart(1, '0')}` })
    )
    vi.mocked(query).mockResolvedValueOnce({ rows })
    const res = await GET(makeRequest())
    expect(res.status).toBe(200)
    const body = await res.json() as Record<string, unknown>
    expect((body.incidents as unknown[]).length).toBe(20)
  })

  it('returns nextCursor as non-null when 21 rows are returned from DB', async () => {
    const rows = Array.from({ length: 21 }, (_, i) =>
      makeIncidentRow({
        fingerprint: `aaaa111100000${i.toString(16).padStart(3, '0')}`,
        last_seen_at: `2026-05-0${(i % 9) + 1}T10:00:00Z`,
      })
    )
    vi.mocked(query).mockResolvedValueOnce({ rows })
    const res = await GET(makeRequest())
    const body = await res.json() as Record<string, unknown>
    expect(body.nextCursor).not.toBeNull()
    expect(typeof body.nextCursor).toBe('string')
  })

  it('returns nextCursor: null when fewer than 21 rows returned', async () => {
    const rows = Array.from({ length: 5 }, (_, i) =>
      makeIncidentRow({ fingerprint: `bbbb222200000${i.toString(16).padStart(3, '0')}` })
    )
    vi.mocked(query).mockResolvedValueOnce({ rows })
    const res = await GET(makeRequest())
    const body = await res.json() as Record<string, unknown>
    expect(body.nextCursor).toBeNull()
  })

  it('returns nextCursor: null when exactly 20 rows returned (no more data)', async () => {
    const rows = Array.from({ length: 20 }, (_, i) =>
      makeIncidentRow({ fingerprint: `cccc333300000${i.toString(16).padStart(3, '0')}` })
    )
    vi.mocked(query).mockResolvedValueOnce({ rows })
    const res = await GET(makeRequest())
    const body = await res.json() as Record<string, unknown>
    expect(body.nextCursor).toBeNull()
  })

  it('DB query is called with ORDER BY last_seen_at DESC, fingerprint DESC', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    await GET(makeRequest())
    const sql = vi.mocked(query).mock.calls[0][0]
    expect(sql).toMatch(/ORDER BY last_seen_at DESC, fingerprint DESC/i)
  })

  it('DB query fetches 21 rows (LIMIT 21)', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    await GET(makeRequest())
    const sql = vi.mocked(query).mock.calls[0][0]
    const params = vi.mocked(query).mock.calls[0][1]
    expect(sql).toMatch(/LIMIT \$4/i)
    expect(params?.[3]).toBe(21)
  })

  it('incident summary shape includes all required fields', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [makeIncidentRow()] })
    const res = await GET(makeRequest())
    const body = await res.json() as Record<string, unknown>
    const incident = (body.incidents as Record<string, unknown>[])[0]
    expect(incident).toHaveProperty('fingerprint')
    expect(incident).toHaveProperty('first_seen_at')
    expect(incident).toHaveProperty('last_seen_at')
    expect(incident).toHaveProperty('occurrence_count')
    expect(incident).toHaveProperty('error_line')
    expect(incident).toHaveProperty('status')
    expect(incident).toHaveProperty('pr_url')
    expect(incident).toHaveProperty('pr_number')
  })
})

describe('GET /api/agent/incidents — status filter', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 400 with invalid_status for ?status=bogus', async () => {
    const res = await GET(makeRequest({ status: 'bogus' }))
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_status')
  })

  it('returns 400 for ?status=OPEN (wrong case)', async () => {
    const res = await GET(makeRequest({ status: 'OPEN' }))
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_status')
  })

  it('accepts ?status=open and passes it to DB query', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    const res = await GET(makeRequest({ status: 'open' }))
    expect(res.status).toBe(200)
    const params = vi.mocked(query).mock.calls[0][1] as unknown[]
    expect(params).toContain('open')
  })

  it('accepts ?status=investigating', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    const res = await GET(makeRequest({ status: 'investigating' }))
    expect(res.status).toBe(200)
  })

  it('accepts ?status=resolved', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    const res = await GET(makeRequest({ status: 'resolved' }))
    expect(res.status).toBe(200)
  })

  it('accepts ?status=ignored', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    const res = await GET(makeRequest({ status: 'ignored' }))
    expect(res.status).toBe(200)
  })
})

describe('GET /api/agent/incidents — cursor pagination', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 400 with invalid_cursor for ?cursor=not-base64', async () => {
    const res = await GET(makeRequest({ cursor: 'not-base64!!!' }))
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_cursor')
  })

  it('returns 400 for a base64 string that decodes to non-JSON', async () => {
    const badCursor = Buffer.from('this is not json').toString('base64')
    const res = await GET(makeRequest({ cursor: badCursor }))
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_cursor')
  })

  it('returns 400 for a base64 cursor missing the last_seen_at field', async () => {
    const badCursor = Buffer.from(JSON.stringify({ fingerprint: 'deadbeefdeadbeef' })).toString('base64')
    const res = await GET(makeRequest({ cursor: badCursor }))
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_cursor')
  })

  it('accepts a well-formed cursor and passes last_seen_at to DB query', async () => {
    const last_seen_at = '2026-05-06T12:00:00Z'
    const fingerprint = 'deadbeefdeadbeef'
    const cursor = encodeCursor(last_seen_at, fingerprint)
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    const res = await GET(makeRequest({ cursor }))
    expect(res.status).toBe(200)
    const params = vi.mocked(query).mock.calls[0][1] as unknown[]
    // last_seen_at should be passed to the WHERE clause
    expect(params).toContain(last_seen_at)
  })

  it('second page results do not overlap with first page (cursor encodes 20th row)', async () => {
    // Simulate: first page returns 21 rows (so nextCursor is set to row 20)
    const firstPageRows = Array.from({ length: 21 }, (_, i) => makeIncidentRow({
      fingerprint: `aaaa111100000${i.toString(16).padStart(3, '0')}`,
      last_seen_at: `2026-05-${(10 - i).toString().padStart(2, '0')}T10:00:00Z`,
    }))
    vi.mocked(query).mockResolvedValueOnce({ rows: firstPageRows })

    const firstRes = await GET(makeRequest())
    const firstBody = await firstRes.json() as Record<string, unknown>
    const nextCursor = firstBody.nextCursor as string
    expect(nextCursor).toBeTruthy()

    // Decode cursor and verify it points to the 20th row (index 19)
    const decoded = JSON.parse(Buffer.from(nextCursor, 'base64').toString('utf-8')) as {
      last_seen_at: string
      fingerprint: string
    }
    expect(decoded.fingerprint).toBe(firstPageRows[19].fingerprint)
    expect(decoded.last_seen_at).toBe(firstPageRows[19].last_seen_at)

    // Simulate second page using that cursor
    const secondPageRows = [makeIncidentRow({ fingerprint: 'bbbb222200000001' })]
    vi.mocked(query).mockResolvedValueOnce({ rows: secondPageRows })

    const secondRes = await GET(makeRequest({ cursor: nextCursor }))
    expect(secondRes.status).toBe(200)
    const secondBody = await secondRes.json() as Record<string, unknown>
    const firstFps = (firstBody.incidents as Array<{ fingerprint: string }>).map(i => i.fingerprint)
    const secondFps = (secondBody.incidents as Array<{ fingerprint: string }>).map(i => i.fingerprint)
    // No overlap between pages
    const overlap = firstFps.filter(fp => secondFps.includes(fp))
    expect(overlap).toHaveLength(0)
  })

  it('nextCursor is null when second page has fewer than 21 results', async () => {
    const last_seen_at = '2026-05-06T12:00:00Z'
    const cursor = encodeCursor(last_seen_at, 'deadbeefdeadbeef')
    vi.mocked(query).mockResolvedValueOnce({ rows: [makeIncidentRow()] })

    const res = await GET(makeRequest({ cursor }))
    const body = await res.json() as Record<string, unknown>
    expect(body.nextCursor).toBeNull()
  })
})

describe('GET /api/agent/incidents — DB error', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 500 when DB query throws', async () => {
    vi.mocked(query).mockRejectedValueOnce(new Error('neon connection refused'))
    const res = await GET(makeRequest())
    expect(res.status).toBe(500)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('internal_error')
  })
})
