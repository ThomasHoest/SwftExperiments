/**
 * Unit tests — POST /api/admin/deletion (E-46 T-4605)
 *
 * Contract source: backend/docs/adr/E-46-admin-export-stats.md §7
 *
 * All database calls and auth are mocked; tests run fully offline.
 *
 * SQL call order inside the route handler:
 *   1. SELECT counts: labels, events, devices for the given device_id (Promise.all)
 *   2. Early return (200 all-zero) if devices count === 0
 *   3. DELETE FROM devices WHERE device_id = $1 (CASCADE removes events + labels)
 *
 * Run with: pnpm test:unit
 */

import { vi, describe, it, expect, beforeEach } from 'vitest'

vi.mock('@/lib/db', () => ({
  sql: vi.fn(),
  query: vi.fn(),
}))

vi.mock('@/lib/auth/clientPrincipal', () => ({
  getClientPrincipal: vi.fn(),
}))

import { query } from '@/lib/db'
import { getClientPrincipal } from '@/lib/auth/clientPrincipal'
import { POST } from '../../app/api/admin/deletion/route'

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const VALID_UUID = '123e4567-e89b-12d3-a456-426614174000'

const VALID_PRINCIPAL = {
  identityProvider: 'github' as const,
  userId: 'user123',
  userDetails: 'admin-user',
  userRoles: ['authenticated', 'admin'],
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Builds a POST request with a JSON body for the deletion endpoint. */
function makePostRequest(body: unknown): Request {
  return new Request('http://localhost/api/admin/deletion', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })
}

/**
 * Mocks the 3-query SELECT-then-DELETE pattern.
 * Queries fire in this order:
 *   1. SELECT COUNT(*) labels
 *   2. SELECT COUNT(*) events
 *   3. SELECT COUNT(*) devices
 *   4. DELETE FROM devices (only when devices > 0)
 */
function mockSelectCounts({
  labels = '0',
  events = '0',
  devices = '1',
  deleteRejects = false,
  selectRejects = false,
}: {
  labels?: string
  events?: string
  devices?: string
  deleteRejects?: boolean
  selectRejects?: boolean
} = {}) {
  const mockedQuery = vi.mocked(query)

  if (selectRejects) {
    mockedQuery.mockRejectedValueOnce(new Error('DB connection refused'))
    return
  }

  // The ADR specifies Promise.all with three SELECT queries then one DELETE.
  // Match the exact order from the ADR SQL pattern:
  //   [labelRes, eventRes, deviceRes] = await Promise.all([...])
  mockedQuery
    .mockResolvedValueOnce({ rows: [{ n: labels }] })   // labels count
    .mockResolvedValueOnce({ rows: [{ n: events }] })   // events count
    .mockResolvedValueOnce({ rows: [{ n: devices }] })  // devices count

  if (Number(devices) > 0) {
    if (deleteRejects) {
      mockedQuery.mockRejectedValueOnce(new Error('deadlock detected'))
    } else {
      mockedQuery.mockResolvedValueOnce({ rows: [] })   // DELETE result
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('POST /api/admin/deletion — 401 when principal is null', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns 401 when getClientPrincipal returns null', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(null)
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    const res = await POST(req)
    expect(res.status).toBe(401)
  })

  it('returns { error: "Unauthorized" } when principal is null', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(null)
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Unauthorized')
  })
})

describe('POST /api/admin/deletion — 400 invalid deviceId', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
  })

  it('returns 400 for a non-UUID deviceId', async () => {
    const req = makePostRequest({ deviceId: 'not-a-uuid', confirmation: 'DELETE' })
    const res = await POST(req)
    expect(res.status).toBe(400)
  })

  it('returns { error: "Invalid deviceId" } for a non-UUID deviceId', async () => {
    const req = makePostRequest({ deviceId: 'not-a-uuid', confirmation: 'DELETE' })
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Invalid deviceId')
  })

  it('returns 400 for an empty string deviceId', async () => {
    const req = makePostRequest({ deviceId: '', confirmation: 'DELETE' })
    const res = await POST(req)
    expect(res.status).toBe(400)
  })

  it('returns { error: "Invalid deviceId" } for an empty string deviceId', async () => {
    const req = makePostRequest({ deviceId: '', confirmation: 'DELETE' })
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Invalid deviceId')
  })

  it('returns 400 when deviceId is absent from the body', async () => {
    const req = makePostRequest({ confirmation: 'DELETE' })
    const res = await POST(req)
    expect(res.status).toBe(400)
  })

  it('returns 400 for a deviceId that is a plain integer string', async () => {
    const req = makePostRequest({ deviceId: '12345', confirmation: 'DELETE' })
    const res = await POST(req)
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Invalid deviceId')
  })
})

describe('POST /api/admin/deletion — 400 confirmation mismatch', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
  })

  it('returns 400 when confirmation is not "DELETE"', async () => {
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'delete' })
    const res = await POST(req)
    expect(res.status).toBe(400)
  })

  it('returns { error: "Type DELETE to confirm" } when confirmation is lowercase "delete"', async () => {
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'delete' })
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Type DELETE to confirm')
  })

  it('returns 400 when confirmation is an empty string', async () => {
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: '' })
    const res = await POST(req)
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Type DELETE to confirm')
  })

  it('returns 400 when confirmation is absent from the body', async () => {
    const req = makePostRequest({ deviceId: VALID_UUID })
    const res = await POST(req)
    expect(res.status).toBe(400)
  })

  it('returns 400 when confirmation is "YES" instead of "DELETE"', async () => {
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'YES' })
    const res = await POST(req)
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Type DELETE to confirm')
  })
})

describe('POST /api/admin/deletion — device not found (idempotent)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
  })

  it('returns 200 when devices count is 0', async () => {
    mockSelectCounts({ labels: '0', events: '0', devices: '0' })
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    const res = await POST(req)
    expect(res.status).toBe(200)
  })

  it('returns all-zero counts when device is not found', async () => {
    mockSelectCounts({ labels: '0', events: '0', devices: '0' })
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    const deleted = body.deleted as Record<string, number>
    expect(deleted).toEqual({ devices: 0, events: 0, labels: 0 })
  })

  it('does not issue a DELETE query when devices count is 0', async () => {
    mockSelectCounts({ labels: '0', events: '0', devices: '0' })
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    await POST(req)
    // Only 3 SELECT queries should have been called (no DELETE)
    expect(vi.mocked(query)).toHaveBeenCalledTimes(3)
  })
})

describe('POST /api/admin/deletion — device found with data', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
  })

  it('returns 200 when device exists and has data', async () => {
    mockSelectCounts({ labels: '5', events: '20', devices: '1' })
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    const res = await POST(req)
    expect(res.status).toBe(200)
  })

  it('returns correct non-zero counts matching SELECT results', async () => {
    mockSelectCounts({ labels: '5', events: '20', devices: '1' })
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    const deleted = body.deleted as Record<string, number>
    expect(deleted.devices).toBe(1)
    expect(deleted.events).toBe(20)
    expect(deleted.labels).toBe(5)
  })

  it('issues exactly 4 DB calls: 3 SELECTs + 1 DELETE', async () => {
    mockSelectCounts({ labels: '3', events: '10', devices: '1' })
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    await POST(req)
    expect(vi.mocked(query)).toHaveBeenCalledTimes(4)
  })

  it('returns deleted.devices=1 when one device is found and deleted', async () => {
    mockSelectCounts({ labels: '0', events: '1', devices: '1' })
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    const deleted = body.deleted as Record<string, number>
    expect(deleted.devices).toBe(1)
  })
})

describe('POST /api/admin/deletion — DB error during SELECT counts', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
  })

  it('returns 500 when DB throws during the SELECT counts query', async () => {
    mockSelectCounts({ selectRejects: true })
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    const res = await POST(req)
    expect(res.status).toBe(500)
  })

  it('returns { error: "Server error" } when DB throws during SELECT counts', async () => {
    mockSelectCounts({ selectRejects: true })
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Server error')
  })
})

describe('POST /api/admin/deletion — DB error during DELETE', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
  })

  it('returns 500 when DB throws during DELETE', async () => {
    mockSelectCounts({ labels: '2', events: '5', devices: '1', deleteRejects: true })
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    const res = await POST(req)
    expect(res.status).toBe(500)
  })

  it('returns { error: "Server error" } when DB throws during DELETE', async () => {
    mockSelectCounts({ labels: '2', events: '5', devices: '1', deleteRejects: true })
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Server error')
  })
})

describe('POST /api/admin/deletion — response shape', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
  })

  it('response body has a "deleted" key wrapping the counts', async () => {
    mockSelectCounts({ labels: '3', events: '7', devices: '1' })
    const req = makePostRequest({ deviceId: VALID_UUID, confirmation: 'DELETE' })
    const res = await POST(req)
    const body = await res.json() as Record<string, unknown>
    expect(body).toHaveProperty('deleted')
    const deleted = body.deleted as Record<string, number>
    expect(deleted).toHaveProperty('devices')
    expect(deleted).toHaveProperty('events')
    expect(deleted).toHaveProperty('labels')
  })
})
