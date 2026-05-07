/**
 * Unit tests — GET /api/agent/incidents/:fingerprint (E-51 T-5104)
 *
 * Contract source: backend/docs/adr/E-51-incident-backend.md §Public Interface Contract
 *
 * All database calls are mocked; tests run fully offline.
 *
 * DB call order inside the route handler:
 *   1. SELECT incident row by fingerprint (returns [] = 404, [row] = proceed)
 *   2. SELECT recent_occurrences (up to 10, ordered DESC)
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
import { GET } from '../../../../app/api/agent/incidents/[fingerprint]/route'

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const VALID_FINGERPRINT = 'deadbeefdeadbeef'
const AGENT_KEY = 'test-agent-key'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Next.js dynamic route context */
interface RouteContext {
  params: { fingerprint: string }
}

function makeRequest(fingerprint = VALID_FINGERPRINT): Request {
  return new Request(`http://localhost/api/agent/incidents/${fingerprint}`, {
    method: 'GET',
    headers: { 'x-agent-key': AGENT_KEY },
  })
}

function makeContext(fingerprint = VALID_FINGERPRINT): RouteContext {
  return { params: { fingerprint } }
}

function allowAgentAuth(): void {
  vi.mocked(requireAgentKey).mockReturnValue({ ok: true })
}

function denyAgentAuth(status: number, error: string): void {
  const response = Response.json({ error }, { status })
  vi.mocked(requireAgentKey).mockReturnValue({ ok: false, response })
}

/** Builds a mock incident row as returned from DB. */
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
    fingerprint: VALID_FINGERPRINT,
    first_seen_at: '2026-05-01T10:00:00Z',
    last_seen_at: '2026-05-06T12:00:00Z',
    occurrence_count: 3,
    error_line: 'Error: something failed at ContentView.swift:42',
    status: 'open',
    pr_url: null,
    pr_number: null,
    ...overrides,
  }
}

/** Builds a mock occurrence row as returned from DB. */
function makeOccurrenceRow(overrides: Partial<{
  id: string
  reported_at: string
  app_version: string
  os_version: string
  device_model: string
  context_lines: string[]
  breadcrumbs: string
}> = {}) {
  return {
    id: '42',
    reported_at: '2026-05-06T11:00:00Z',
    app_version: '1.3.0',
    os_version: '18.1',
    device_model: 'iPhone15,2',
    context_lines: ['log line 1', 'log line 2'],
    breadcrumbs: 'Home > Settings',
    ...overrides,
  }
}

/** Configures DB mocks for a full successful detail fetch. */
function mockDbForSuccess(occurrences: ReturnType<typeof makeOccurrenceRow>[] = [makeOccurrenceRow()]): void {
  vi.mocked(query)
    .mockResolvedValueOnce({ rows: [makeIncidentRow()] })
    .mockResolvedValueOnce({ rows: occurrences })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('GET /api/agent/incidents/:fingerprint — authentication', () => {
  beforeEach(() => {
    vi.resetAllMocks()
  })

  it('returns 401 when agent key is wrong', async () => {
    denyAgentAuth(401, 'invalid_agent_key')
    const res = await GET(makeRequest(), makeContext())
    expect(res.status).toBe(401)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_agent_key')
  })

  it('returns 503 when AGENT_API_KEY is unset', async () => {
    denyAgentAuth(503, 'agent_api_disabled')
    const res = await GET(makeRequest(), makeContext())
    expect(res.status).toBe(503)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('agent_api_disabled')
  })
})

describe('GET /api/agent/incidents/:fingerprint — fingerprint validation', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 400 for an uppercase fingerprint', async () => {
    const res = await GET(makeRequest('DEADBEEFDEADBEEF'), makeContext('DEADBEEFDEADBEEF'))
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_fingerprint')
  })

  it('returns 400 for a fingerprint that is only 3 chars', async () => {
    const res = await GET(makeRequest('ABC'), makeContext('ABC'))
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_fingerprint')
  })

  it('returns 400 for a 15-char fingerprint (too short)', async () => {
    const fp = 'deadbeefdeadbee'
    const res = await GET(makeRequest(fp), makeContext(fp))
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_fingerprint')
  })

  it('returns 400 for a 17-char fingerprint (too long)', async () => {
    const fp = 'deadbeefdeadbeef1'
    const res = await GET(makeRequest(fp), makeContext(fp))
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_fingerprint')
  })
})

describe('GET /api/agent/incidents/:fingerprint — not found', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 404 when fingerprint is unknown (no DB row)', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    const res = await GET(makeRequest(), makeContext())
    expect(res.status).toBe(404)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('incident_not_found')
  })

  it('returns 404 for a well-formed but unknown fingerprint', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    const res = await GET(makeRequest('aaaaaaaaaaaaaaaa'), makeContext('aaaaaaaaaaaaaaaa'))
    expect(res.status).toBe(404)
  })
})

describe('GET /api/agent/incidents/:fingerprint — happy path: 3 occurrences', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 200 with the incident and 3 occurrences', async () => {
    const occurrences = [
      makeOccurrenceRow({ id: '3', reported_at: '2026-05-06T11:00:00Z' }),
      makeOccurrenceRow({ id: '2', reported_at: '2026-05-05T11:00:00Z' }),
      makeOccurrenceRow({ id: '1', reported_at: '2026-05-04T11:00:00Z' }),
    ]
    mockDbForSuccess(occurrences)
    const res = await GET(makeRequest(), makeContext())
    expect(res.status).toBe(200)
    const body = await res.json() as Record<string, unknown>
    expect((body.recent_occurrences as unknown[]).length).toBe(3)
  })

  it('occurrences are ordered DESC (most recent first)', async () => {
    const occurrences = [
      makeOccurrenceRow({ id: '3', reported_at: '2026-05-06T11:00:00Z' }),
      makeOccurrenceRow({ id: '2', reported_at: '2026-05-05T11:00:00Z' }),
      makeOccurrenceRow({ id: '1', reported_at: '2026-05-04T11:00:00Z' }),
    ]
    mockDbForSuccess(occurrences)
    const res = await GET(makeRequest(), makeContext())
    const body = await res.json() as Record<string, unknown>
    const occs = body.recent_occurrences as Array<{ id: string; reported_at: string }>
    // Most recent first
    expect(occs[0].id).toBe('3')
    expect(occs[1].id).toBe('2')
    expect(occs[2].id).toBe('1')
  })

  it('occurrences SQL uses ORDER BY reported_at DESC LIMIT 10', async () => {
    mockDbForSuccess()
    await GET(makeRequest(), makeContext())
    const occurrenceSql = vi.mocked(query).mock.calls[1][0]
    expect(occurrenceSql).toMatch(/ORDER BY reported_at DESC/i)
    expect(occurrenceSql).toMatch(/LIMIT 10/i)
  })
})

describe('GET /api/agent/incidents/:fingerprint — capped at 10 for large occurrence count', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns exactly 10 occurrences when DB has 25 rows (LIMIT 10 enforced)', async () => {
    // Mock returns only 10 (DB enforces LIMIT 10)
    const occurrences = Array.from({ length: 10 }, (_, i) =>
      makeOccurrenceRow({ id: String(25 - i), reported_at: `2026-05-0${(9 - i) + 1}T10:00:00Z` })
    )
    vi.mocked(query)
      .mockResolvedValueOnce({ rows: [makeIncidentRow({ occurrence_count: 25 })] })
      .mockResolvedValueOnce({ rows: occurrences })

    const res = await GET(makeRequest(), makeContext())
    expect(res.status).toBe(200)
    const body = await res.json() as Record<string, unknown>
    expect((body.recent_occurrences as unknown[]).length).toBe(10)
  })

  it('incident occurrence_count field reflects the true total, not just 10', async () => {
    const occurrences = Array.from({ length: 10 }, (_, i) =>
      makeOccurrenceRow({ id: String(25 - i) })
    )
    vi.mocked(query)
      .mockResolvedValueOnce({ rows: [makeIncidentRow({ occurrence_count: 25 })] })
      .mockResolvedValueOnce({ rows: occurrences })

    const res = await GET(makeRequest(), makeContext())
    const body = await res.json() as Record<string, unknown>
    expect(body.occurrence_count).toBe(25)
  })
})

describe('GET /api/agent/incidents/:fingerprint — context_lines type', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('context_lines is returned as an array of strings (not serialised JSON)', async () => {
    const contextLines = ['line one', 'line two', 'line three']
    // Simulate DB returning context_lines already parsed as an array (JSONB auto-parses)
    mockDbForSuccess([makeOccurrenceRow({ context_lines: contextLines })])
    const res = await GET(makeRequest(), makeContext())
    const body = await res.json() as Record<string, unknown>
    const occ = (body.recent_occurrences as Array<{ context_lines: unknown }>)[0]
    expect(Array.isArray(occ.context_lines)).toBe(true)
    expect(occ.context_lines).toEqual(contextLines)
  })

  it('context_lines entries are strings', async () => {
    const contextLines = ['error: timeout', 'retrying...']
    mockDbForSuccess([makeOccurrenceRow({ context_lines: contextLines })])
    const res = await GET(makeRequest(), makeContext())
    const body = await res.json() as Record<string, unknown>
    const occ = (body.recent_occurrences as Array<{ context_lines: string[] }>)[0]
    for (const line of occ.context_lines) {
      expect(typeof line).toBe('string')
    }
  })
})

describe('GET /api/agent/incidents/:fingerprint — id as decimal string', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('occurrence id is returned as a string, not a number', async () => {
    mockDbForSuccess([makeOccurrenceRow({ id: '42' })])
    const res = await GET(makeRequest(), makeContext())
    const body = await res.json() as Record<string, unknown>
    const occ = (body.recent_occurrences as Array<{ id: unknown }>)[0]
    expect(typeof occ.id).toBe('string')
    expect(occ.id).toBe('42')
  })

  it('occurrence id preserves large BIGINT values as decimal string', async () => {
    const bigId = '9007199254740993' // > Number.MAX_SAFE_INTEGER
    mockDbForSuccess([makeOccurrenceRow({ id: bigId })])
    const res = await GET(makeRequest(), makeContext())
    const body = await res.json() as Record<string, unknown>
    const occ = (body.recent_occurrences as Array<{ id: string }>)[0]
    expect(occ.id).toBe(bigId)
  })
})

describe('GET /api/agent/incidents/:fingerprint — response shape', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('response includes all incident summary fields', async () => {
    mockDbForSuccess()
    const res = await GET(makeRequest(), makeContext())
    const body = await res.json() as Record<string, unknown>
    expect(body).toHaveProperty('fingerprint')
    expect(body).toHaveProperty('first_seen_at')
    expect(body).toHaveProperty('last_seen_at')
    expect(body).toHaveProperty('occurrence_count')
    expect(body).toHaveProperty('error_line')
    expect(body).toHaveProperty('status')
    expect(body).toHaveProperty('pr_url')
    expect(body).toHaveProperty('pr_number')
    expect(body).toHaveProperty('recent_occurrences')
  })

  it('occurrence shape includes all required fields', async () => {
    mockDbForSuccess()
    const res = await GET(makeRequest(), makeContext())
    const body = await res.json() as Record<string, unknown>
    const occ = (body.recent_occurrences as Record<string, unknown>[])[0]
    expect(occ).toHaveProperty('id')
    expect(occ).toHaveProperty('reported_at')
    expect(occ).toHaveProperty('app_version')
    expect(occ).toHaveProperty('os_version')
    expect(occ).toHaveProperty('device_model')
    expect(occ).toHaveProperty('context_lines')
    expect(occ).toHaveProperty('breadcrumbs')
  })
})

describe('GET /api/agent/incidents/:fingerprint — DB error', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 500 when incident SELECT throws', async () => {
    vi.mocked(query).mockRejectedValueOnce(new Error('neon timeout'))
    const res = await GET(makeRequest(), makeContext())
    expect(res.status).toBe(500)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('internal_error')
  })

  it('returns 500 when occurrences SELECT throws', async () => {
    vi.mocked(query)
      .mockResolvedValueOnce({ rows: [makeIncidentRow()] })
      .mockRejectedValueOnce(new Error('occurrences query failed'))
    const res = await GET(makeRequest(), makeContext())
    expect(res.status).toBe(500)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('internal_error')
  })
})
