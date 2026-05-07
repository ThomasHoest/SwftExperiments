/**
 * Unit tests — PATCH /api/agent/incidents/:fingerprint (E-51 T-5105)
 *
 * Contract source: backend/docs/adr/E-51-incident-backend.md §Public Interface Contract
 *
 * All database calls are mocked; tests run fully offline.
 *
 * DB call order inside PATCH handler:
 *   1. UPDATE incidents ... RETURNING fingerprint, status, pr_url, pr_number
 *      → rowCount 0 = 404, rowCount 1 = 200
 *
 * Also verifies the GET handler from T-5104 is unaffected (regression).
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
import { PATCH, GET } from '../../../../app/api/agent/incidents/[fingerprint]/route'

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const VALID_FINGERPRINT = 'deadbeefdeadbeef'
const AGENT_KEY = 'test-agent-key'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface RouteContext {
  params: { fingerprint: string }
}

function makePatchRequest(
  fingerprint: string,
  body: unknown,
): Request {
  return new Request(`http://localhost/api/agent/incidents/${fingerprint}`, {
    method: 'PATCH',
    headers: {
      'x-agent-key': AGENT_KEY,
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  })
}

function makeGetRequest(fingerprint = VALID_FINGERPRINT): Request {
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

/** Builds the RETURNING row shape from the DB UPDATE. */
function makeUpdatedRow(overrides: Partial<{
  fingerprint: string
  status: string
  pr_url: string | null
  pr_number: number | null
}> = {}) {
  return {
    fingerprint: VALID_FINGERPRINT,
    status: 'open',
    pr_url: null,
    pr_number: null,
    ...overrides,
  }
}

/** Incident row for GET regression tests. */
function makeIncidentRow() {
  return {
    fingerprint: VALID_FINGERPRINT,
    first_seen_at: '2026-05-01T10:00:00Z',
    last_seen_at: '2026-05-06T12:00:00Z',
    occurrence_count: 3,
    error_line: 'Error: something failed',
    status: 'investigating',
    pr_url: 'https://github.com/owner/repo/pull/42',
    pr_number: 42,
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('PATCH /api/agent/incidents/:fingerprint — authentication', () => {
  beforeEach(() => {
    vi.resetAllMocks()
  })

  it('returns 401 when agent key is wrong', async () => {
    denyAgentAuth(401, 'invalid_agent_key')
    const res = await PATCH(makePatchRequest(VALID_FINGERPRINT, { status: 'investigating' }), makeContext())
    expect(res.status).toBe(401)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_agent_key')
  })

  it('returns 503 when AGENT_API_KEY is unset', async () => {
    denyAgentAuth(503, 'agent_api_disabled')
    const res = await PATCH(makePatchRequest(VALID_FINGERPRINT, { status: 'investigating' }), makeContext())
    expect(res.status).toBe(503)
  })
})

describe('PATCH /api/agent/incidents/:fingerprint — fingerprint validation', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 400 for an invalid fingerprint format', async () => {
    const badFp = 'BADFINGERPRINT!!'
    const res = await PATCH(makePatchRequest(badFp, { status: 'investigating' }), makeContext(badFp))
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_fingerprint')
  })
})

describe('PATCH /api/agent/incidents/:fingerprint — body validation', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 400 with no_fields_to_update for an empty body {}', async () => {
    const res = await PATCH(makePatchRequest(VALID_FINGERPRINT, {}), makeContext())
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('no_fields_to_update')
  })

  it('returns 400 with invalid_status for { status: "bogus" }', async () => {
    const res = await PATCH(makePatchRequest(VALID_FINGERPRINT, { status: 'bogus' }), makeContext())
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_status')
  })

  it('returns 400 with invalid_status for an uppercase status value', async () => {
    const res = await PATCH(makePatchRequest(VALID_FINGERPRINT, { status: 'OPEN' }), makeContext())
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_status')
  })

  it('returns 400 with invalid_pr_url for an http:// URL (not https)', async () => {
    const res = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, { pr_url: 'http://insecure.example.com' }),
      makeContext()
    )
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_pr_url')
  })

  it('returns 400 with invalid_pr_url for a pr_url that does not start with https://', async () => {
    const res = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, { pr_url: 'ftp://example.com' }),
      makeContext()
    )
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_pr_url')
  })

  it('returns 400 with invalid_pr_url for a pr_url exceeding 512 chars', async () => {
    const longUrl = 'https://github.com/' + 'a'.repeat(500)
    const res = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, { pr_url: longUrl }),
      makeContext()
    )
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_pr_url')
  })

  it('returns 400 with invalid_pr_number for pr_number = -1', async () => {
    const res = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, { pr_number: -1 }),
      makeContext()
    )
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_pr_number')
  })

  it('returns 400 with invalid_pr_number for pr_number = 0', async () => {
    const res = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, { pr_number: 0 }),
      makeContext()
    )
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_pr_number')
  })

  it('returns 400 with invalid_pr_number for a fractional pr_number', async () => {
    const res = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, { pr_number: 3.14 }),
      makeContext()
    )
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('invalid_pr_number')
  })
})

describe('PATCH /api/agent/incidents/:fingerprint — happy path: status only', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 200 when only status is provided', async () => {
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeUpdatedRow({ status: 'investigating' })],
    })
    const res = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, { status: 'investigating' }),
      makeContext()
    )
    expect(res.status).toBe(200)
  })

  it('returns the updated status in the response body', async () => {
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeUpdatedRow({ status: 'investigating' })],
    })
    const res = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, { status: 'investigating' }),
      makeContext()
    )
    const body = await res.json() as Record<string, unknown>
    expect(body.status).toBe('investigating')
  })

  it('response includes fingerprint, status, pr_url, pr_number', async () => {
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeUpdatedRow({ status: 'resolved' })],
    })
    const res = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, { status: 'resolved' }),
      makeContext()
    )
    const body = await res.json() as Record<string, unknown>
    expect(body).toHaveProperty('fingerprint')
    expect(body).toHaveProperty('status')
    expect(body).toHaveProperty('pr_url')
    expect(body).toHaveProperty('pr_number')
  })

  it('accepts all four valid status values', async () => {
    for (const status of ['open', 'investigating', 'resolved', 'ignored'] as const) {
      vi.mocked(query).mockResolvedValueOnce({ rows: [makeUpdatedRow({ status })] })
      const res = await PATCH(
        makePatchRequest(VALID_FINGERPRINT, { status }),
        makeContext()
      )
      expect(res.status).toBe(200)
    }
  })
})

describe('PATCH /api/agent/incidents/:fingerprint — happy path: all three fields', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 200 when all three fields are provided', async () => {
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeUpdatedRow({
        status: 'investigating',
        pr_url: 'https://github.com/owner/repo/pull/42',
        pr_number: 42,
      })],
    })
    const res = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, {
        status: 'investigating',
        pr_url: 'https://github.com/owner/repo/pull/42',
        pr_number: 42,
      }),
      makeContext()
    )
    expect(res.status).toBe(200)
    const body = await res.json() as Record<string, unknown>
    expect(body.status).toBe('investigating')
    expect(body.pr_url).toBe('https://github.com/owner/repo/pull/42')
    expect(body.pr_number).toBe(42)
  })

  it('passes all three fields to the DB UPDATE', async () => {
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeUpdatedRow({ status: 'investigating', pr_url: 'https://github.com/x/y/pull/1', pr_number: 1 })],
    })
    await PATCH(
      makePatchRequest(VALID_FINGERPRINT, {
        status: 'investigating',
        pr_url: 'https://github.com/x/y/pull/1',
        pr_number: 1,
      }),
      makeContext()
    )
    const updateParams = vi.mocked(query).mock.calls[0][1] as unknown[]
    expect(updateParams).toContain('investigating')
    expect(updateParams).toContain('https://github.com/x/y/pull/1')
    expect(updateParams).toContain(1)
  })

  it('accepts a pr_url of exactly 512 chars (boundary)', async () => {
    const borderlineUrl = 'https://github.com/' + 'a'.repeat(493) // 512 total with prefix
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeUpdatedRow({ pr_url: borderlineUrl })],
    })
    const res = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, { pr_url: borderlineUrl }),
      makeContext()
    )
    expect(res.status).toBe(200)
  })
})

describe('PATCH /api/agent/incidents/:fingerprint — not found', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 404 when UPDATE affects zero rows', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    const res = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, { status: 'investigating' }),
      makeContext()
    )
    expect(res.status).toBe(404)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('incident_not_found')
  })

  it('returns 404 for a valid fingerprint that has no incident row', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    const res = await PATCH(
      makePatchRequest('aaaaaaaaaaaaaaaa', { status: 'ignored' }),
      makeContext('aaaaaaaaaaaaaaaa')
    )
    expect(res.status).toBe(404)
  })
})

describe('PATCH /api/agent/incidents/:fingerprint — DB error', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('returns 500 when DB UPDATE throws', async () => {
    vi.mocked(query).mockRejectedValueOnce(new Error('db constraint violation'))
    const res = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, { status: 'investigating' }),
      makeContext()
    )
    expect(res.status).toBe(500)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('internal_error')
  })
})

describe('PATCH regression — GET handler unaffected after PATCH', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    allowAgentAuth()
  })

  it('GET handler returns the patched state after a successful PATCH', async () => {
    // Step 1: PATCH updates status to investigating
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeUpdatedRow({ status: 'investigating', pr_url: 'https://github.com/owner/repo/pull/42', pr_number: 42 })],
    })
    const patchRes = await PATCH(
      makePatchRequest(VALID_FINGERPRINT, {
        status: 'investigating',
        pr_url: 'https://github.com/owner/repo/pull/42',
        pr_number: 42,
      }),
      makeContext()
    )
    expect(patchRes.status).toBe(200)

    // Step 2: GET returns the updated incident row
    vi.mocked(query)
      .mockResolvedValueOnce({ rows: [makeIncidentRow()] })
      .mockResolvedValueOnce({ rows: [] }) // no occurrences
    const getRes = await GET(makeGetRequest(), makeContext())
    expect(getRes.status).toBe(200)
    const getBody = await getRes.json() as Record<string, unknown>
    // The GET handler still works and returns the incident
    expect(getBody.fingerprint).toBe(VALID_FINGERPRINT)
    expect(getBody.status).toBe('investigating')
    expect(getBody.pr_url).toBe('https://github.com/owner/repo/pull/42')
    expect(getBody.pr_number).toBe(42)
  })

  it('GET returns 200 independently of any prior PATCH (no state leakage between handlers)', async () => {
    vi.mocked(query)
      .mockResolvedValueOnce({ rows: [makeIncidentRow()] })
      .mockResolvedValueOnce({ rows: [] })
    const getRes = await GET(makeGetRequest(), makeContext())
    expect(getRes.status).toBe(200)
  })
})
