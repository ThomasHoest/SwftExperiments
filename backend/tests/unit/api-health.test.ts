/**
 * Unit tests — GET /api/health (E-43 T-4304)
 *
 * Contract source: backend/docs/adr/E-43-ingest-api.md §7
 *
 * Verifies:
 *   - Response status is 200
 *   - Body contains { status: 'ok' }
 *   - Body contains a parseable ISO 8601 timestamp
 *   - The database (`sql` from @/lib/db) is never called
 *
 * Run with: pnpm test:unit
 */

import { vi, describe, it, expect, beforeEach } from 'vitest'

// Mock the database module BEFORE importing the route handler.
// The health endpoint must NOT touch the database at all.
vi.mock('@/lib/db', () => ({
  sql: vi.fn(),
}))

import { sql } from '@/lib/db'
import { GET } from '../../app/api/health/route'

describe('GET /api/health', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('returns HTTP 200', async () => {
    const response = await GET()
    expect(response.status).toBe(200)
  })

  it('returns { status: "ok" } in the body', async () => {
    const response = await GET()
    const body = await response.json() as Record<string, unknown>
    expect(body.status).toBe('ok')
  })

  it('returns a parseable ISO 8601 timestamp', async () => {
    const response = await GET()
    const body = await response.json() as Record<string, unknown>

    expect(typeof body.timestamp).toBe('string')

    // Must parse without NaN
    const parsed = new Date(body.timestamp as string)
    expect(parsed.toString()).not.toBe('Invalid Date')

    // Must be a valid ISO 8601 UTC string (ends with 'Z' or has offset)
    expect(body.timestamp as string).toMatch(
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/,
    )
  })

  it('does not call sql (database must be unreachable from health handler)', async () => {
    await GET()
    expect(vi.mocked(sql)).not.toHaveBeenCalled()
  })
})
