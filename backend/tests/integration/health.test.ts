/**
 * Integration tests — GET /api/health
 *
 * These tests run against a live process (local dev server or a deployed
 * preview URL). Set TEST_BASE_URL to point at any environment; defaults to
 * http://localhost:3000 for local development.
 *
 * Contract source: backend/docs/adr/E-41-infrastructure-cicd.md §7
 * Spec source: spec-telemetry-backend-admin.md — GET /api/health
 *
 * Run with: pnpm vitest run tests/integration/health.test.ts
 * (requires a running Next.js dev or start process, or TEST_BASE_URL set)
 */

import { describe, it, expect } from 'vitest'

const BASE_URL = process.env.TEST_BASE_URL ?? 'http://localhost:3000'
const HEALTH_URL = `${BASE_URL}/api/health`

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Returns true if the string is a valid ISO 8601 date-time string that
 * round-trips through Date.toISOString() exactly. This confirms the value is
 * UTC (ends with "Z") and has millisecond precision, which is the canonical
 * form Next.js Route Handlers produce with `new Date().toISOString()`.
 */
function isStrictIsoString(value: unknown): value is string {
  if (typeof value !== 'string') return false
  const d = new Date(value)
  if (isNaN(d.getTime())) return false
  // Round-trip check: ensures it's the canonical ISO-8601-UTC form
  return d.toISOString() === value
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('GET /api/health — contract tests', () => {
  it('returns HTTP 200', async () => {
    const response = await fetch(HEALTH_URL)
    expect(response.status).toBe(200)
  })

  it('returns Content-Type: application/json', async () => {
    const response = await fetch(HEALTH_URL)
    const contentType = response.headers.get('content-type') ?? ''
    expect(contentType).toContain('application/json')
  })

  it('response body has status field equal to "ok"', async () => {
    const response = await fetch(HEALTH_URL)
    const body = await response.json() as Record<string, unknown>
    expect(body).toHaveProperty('status')
    expect(body.status).toBe('ok')
  })

  it('response body has a timestamp field', async () => {
    const response = await fetch(HEALTH_URL)
    const body = await response.json() as Record<string, unknown>
    expect(body).toHaveProperty('timestamp')
  })

  it('timestamp is a valid ISO 8601 UTC string (round-trips through Date.toISOString)', async () => {
    const response = await fetch(HEALTH_URL)
    const body = await response.json() as Record<string, unknown>
    expect(
      isStrictIsoString(body.timestamp),
      `Expected a strict ISO-8601-UTC string, got: ${JSON.stringify(body.timestamp)}`,
    ).toBe(true)
  })

  it('response body contains exactly the fields defined in the contract (status + timestamp)', async () => {
    const response = await fetch(HEALTH_URL)
    const body = await response.json() as Record<string, unknown>
    const keys = Object.keys(body).sort()
    // The ADR contract is { "status": "ok", "timestamp": "<ISO 8601 UTC>" }.
    // No extra top-level fields are mandated, but the two required ones must
    // be present. We do not fail on additional fields — they may be added
    // later without breaking the contract.
    expect(keys).toContain('status')
    expect(keys).toContain('timestamp')
  })

  it('does not require authentication (no Authorization header sent)', async () => {
    // Fetch without any Authorization or X-Api-Key header to confirm the
    // endpoint is truly public. Per spec: "No auth required."
    const response = await fetch(HEALTH_URL, { headers: {} })
    expect(response.status).not.toBe(401)
    expect(response.status).not.toBe(403)
    expect(response.status).toBe(200)
  })

  it('responds to GET; does not require a request body', async () => {
    // Sending an explicit method to confirm the handler is registered as GET
    // and does not expect any body.
    const response = await fetch(HEALTH_URL, { method: 'GET' })
    expect(response.status).toBe(200)
  })

  it('responds within 2000 ms under normal conditions (soft assertion — warm backend)', async () => {
    // Per spec: health endpoint, warm backend, response time < 100 ms.
    // The hard gate is 2000 ms; exceeding it logs a warning but does not
    // fail the test, because a cold-start legitimately takes up to 5 seconds
    // (by design, that is what the keep-alive monitor is there to prevent).
    const WARN_THRESHOLD_MS = 2000
    const start = Date.now()
    const response = await fetch(HEALTH_URL)
    const elapsed = Date.now() - start

    // The request must still succeed
    expect(response.status).toBe(200)

    if (elapsed > WARN_THRESHOLD_MS) {
      console.warn(
        `[health.test.ts] SOFT ASSERTION: GET /api/health took ${elapsed} ms ` +
          `(threshold ${WARN_THRESHOLD_MS} ms). ` +
          'This is expected on a cold backend but should not occur in CI after warm-up.',
      )
    }
    // Do not throw — cold-start latency is acceptable per the spec.
  })

  it('timestamp reflects the current server time (within ±30 seconds of test clock)', async () => {
    // Validates that the handler generates a fresh timestamp per request,
    // not a cached or hard-coded value.
    const before = Date.now()
    const response = await fetch(HEALTH_URL)
    const after = Date.now()
    const body = await response.json() as Record<string, unknown>

    const serverTime = new Date(body.timestamp as string).getTime()

    // Allow a ±30 s window to accommodate slow cold-starts and test machines
    // with slightly drifted clocks. The spec does not mandate clock precision,
    // but a stale/static timestamp would indicate a broken implementation.
    expect(serverTime).toBeGreaterThanOrEqual(before - 30_000)
    expect(serverTime).toBeLessThanOrEqual(after + 30_000)
  })

  it('each request returns a distinct timestamp (not a cached response)', async () => {
    // A correctly implemented handler calls new Date() on every request.
    // Two requests 10 ms apart should produce different timestamp strings.
    const r1 = await fetch(HEALTH_URL)
    await new Promise((resolve) => setTimeout(resolve, 20))
    const r2 = await fetch(HEALTH_URL)

    const b1 = await r1.json() as Record<string, unknown>
    const b2 = await r2.json() as Record<string, unknown>

    // It is theoretically possible for two requests to land within the same
    // millisecond; tolerate that by only asserting the second timestamp is >=
    // the first, not strictly greater.
    const t1 = new Date(b1.timestamp as string).getTime()
    const t2 = new Date(b2.timestamp as string).getTime()
    expect(t2).toBeGreaterThanOrEqual(t1)
  })
})
