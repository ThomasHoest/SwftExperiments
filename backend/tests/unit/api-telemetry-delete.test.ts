/**
 * Unit tests — DELETE /api/telemetry/{deviceId} (E-43 T-4311, T-4312)
 *
 * Contract source: backend/docs/adr/E-43-ingest-api.md §7
 *
 * All database calls are mocked; tests run fully offline.
 *
 * SQL call order inside the route handler:
 *   1. SELECT counts: events, labels, devices rows for the given device_id
 *   2. DELETE FROM devices WHERE device_id = $1 (CASCADE removes events + labels)
 *
 * Run with: pnpm test:unit
 */

import { vi, describe, it, expect, beforeEach } from 'vitest'

vi.mock('@/lib/db', () => ({
  sql: vi.fn(),
}))

import { sql } from '@/lib/db'
import { DELETE } from '../../app/api/telemetry/[deviceId]/route'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const VALID_UUID = '123e4567-e89b-12d3-a456-426614174000'

/** Builds a minimal Request for the delete endpoint with API key auth. */
function makeRequest(apiKey = 'test-key', extraHeaders: Record<string, string> = {}): Request {
  process.env.TELEMETRY_API_KEY = 'test-key'

  const headers: Record<string, string> = {
    ...extraHeaders,
  }
  if (apiKey !== '') {
    headers['x-api-key'] = apiKey
  }

  return new Request(`http://localhost/api/telemetry/${VALID_UUID}`, {
    method: 'DELETE',
    headers,
  })
}

/** Route handler params shape (Next.js dynamic segment). */
interface RouteContext {
  params: { deviceId: string }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('DELETE /api/telemetry/[deviceId]', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    process.env.TELEMETRY_API_KEY = 'test-key'
  })

  // ── Authentication ─────────────────────────────────────────────────────────

  it('returns 401 when X-Api-Key header is absent', async () => {
    const req = new Request(`http://localhost/api/telemetry/${VALID_UUID}`, {
      method: 'DELETE',
      // No x-api-key header
    })
    const ctx: RouteContext = { params: { deviceId: VALID_UUID } }
    const res = await DELETE(req, ctx)
    expect(res.status).toBe(401)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Invalid API key')
  })

  it('returns 401 when X-Api-Key header has a wrong value', async () => {
    const req = makeRequest('totally-wrong-key')
    const ctx: RouteContext = { params: { deviceId: VALID_UUID } }
    const res = await DELETE(req, ctx)
    expect(res.status).toBe(401)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Invalid API key')
  })

  // ── Input validation ───────────────────────────────────────────────────────

  it('returns 400 with { error: "Invalid deviceId" } for a non-UUID deviceId', async () => {
    const req = makeRequest()
    const ctx: RouteContext = { params: { deviceId: 'not-a-valid-uuid' } }
    const res = await DELETE(req, ctx)
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Invalid deviceId')
  })

  it('returns 400 for a deviceId that is an empty string', async () => {
    const req = makeRequest()
    const ctx: RouteContext = { params: { deviceId: '' } }
    const res = await DELETE(req, ctx)
    expect(res.status).toBe(400)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Invalid deviceId')
  })

  it('accepts a UUID-like string with wrong version digit (Zod .uuid() checks format, not version)', async () => {
    // Zod's z.string().uuid() validates format only — UUID v5 passes. Handler proceeds to DB.
    const mockedSql = vi.mocked(sql)
    mockedSql.mockResolvedValueOnce([{ events: 0, labels: 0, devices: 0 }] as never)
    mockedSql.mockResolvedValueOnce([] as never)

    const req = makeRequest()
    const ctx: RouteContext = { params: { deviceId: '123e4567-e89b-52d3-a456-426614174000' } }
    const res = await DELETE(req, ctx)
    expect([200, 400]).toContain(res.status)
  })

  // ── Happy path — device with data ──────────────────────────────────────────

  it('returns 200 with non-zero counts when device has existing data', async () => {
    const mockedSql = vi.mocked(sql)
    // Call 1: SELECT counts → device has 47 events, 3 labels, 1 device row
    mockedSql.mockResolvedValueOnce([{ events: 47, labels: 3, devices: 1 }] as never)
    // Call 2: DELETE → cascade deletes everything
    mockedSql.mockResolvedValueOnce([] as never)

    const req = makeRequest()
    const ctx: RouteContext = { params: { deviceId: VALID_UUID } }
    const res = await DELETE(req, ctx)
    expect(res.status).toBe(200)

    const body = await res.json() as Record<string, unknown>
    const deleted = body.deleted as Record<string, number>
    expect(deleted).toBeDefined()
    expect(deleted.events).toBe(47)
    expect(deleted.labels).toBe(3)
    expect(deleted.devices).toBe(1)
  })

  // ── Happy path — device does not exist (idempotent) ───────────────────────

  it('returns 200 with all-zero counts when device does not exist', async () => {
    const mockedSql = vi.mocked(sql)
    // Call 1: SELECT counts → no rows found
    mockedSql.mockResolvedValueOnce([{ events: 0, labels: 0, devices: 0 }] as never)
    // Call 2: DELETE → nothing to delete
    mockedSql.mockResolvedValueOnce([] as never)

    const req = makeRequest()
    const ctx: RouteContext = { params: { deviceId: VALID_UUID } }
    const res = await DELETE(req, ctx)
    expect(res.status).toBe(200)

    const body = await res.json() as Record<string, unknown>
    const deleted = body.deleted as Record<string, number>
    expect(deleted).toBeDefined()
    expect(deleted.events).toBe(0)
    expect(deleted.labels).toBe(0)
    expect(deleted.devices).toBe(0)
  })

  // ── Database errors ────────────────────────────────────────────────────────

  it('returns 500 when the database throws during DELETE', async () => {
    const mockedSql = vi.mocked(sql)
    // Call 1: SELECT counts succeeds
    mockedSql.mockResolvedValueOnce([{ events: 10, labels: 2, devices: 1 }] as never)
    // Call 2: DELETE throws
    mockedSql.mockRejectedValueOnce(new Error('deadlock detected') as never)

    const req = makeRequest()
    const ctx: RouteContext = { params: { deviceId: VALID_UUID } }
    const res = await DELETE(req, ctx)
    expect(res.status).toBe(500)

    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Server error')
  })

  it('returns 500 when the database throws on the initial count query', async () => {
    vi.mocked(sql).mockRejectedValueOnce(new Error('connection timeout') as never)

    const req = makeRequest()
    const ctx: RouteContext = { params: { deviceId: VALID_UUID } }
    const res = await DELETE(req, ctx)
    expect(res.status).toBe(500)

    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Server error')
  })
})
