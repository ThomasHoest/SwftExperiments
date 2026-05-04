/**
 * E2E tests — GET /api/health
 *
 * Runs against the deployed SWA preview URL in CI (PLAYWRIGHT_BASE_URL is set
 * by the e2e job which receives the SWA preview URL from the deploy step).
 * Falls back to http://localhost:3000 for local development.
 *
 * Contract source: backend/docs/adr/E-41-infrastructure-cicd.md §7
 * Spec source: spec-telemetry-backend-admin.md — GET /api/health
 *
 * Run with: pnpm playwright test tests/e2e/health.spec.ts
 */

import { test, expect } from '@playwright/test'

test.describe('GET /api/health', () => {
  test('returns 200 with status ok', async ({ request }) => {
    const response = await request.get('/api/health')
    expect(response.status()).toBe(200)
    const body = await response.json() as Record<string, unknown>
    expect(body.status).toBe('ok')
    expect(typeof body.timestamp).toBe('string')
    // Strict ISO-8601-UTC round-trip: confirms the handler uses new Date().toISOString()
    expect(new Date(body.timestamp as string).toISOString()).toBe(body.timestamp)
  })

  test('does not require authentication', async ({ request }) => {
    // Sending with no auth headers whatsoever — spec says "None" for auth.
    const response = await request.get('/api/health')
    expect(response.status()).not.toBe(401)
    expect(response.status()).not.toBe(403)
  })

  test('Content-Type is application/json', async ({ request }) => {
    const response = await request.get('/api/health')
    const contentType = response.headers()['content-type'] ?? ''
    expect(contentType).toContain('application/json')
  })

  test('timestamp is in ISO 8601 UTC format (ends with Z)', async ({ request }) => {
    const response = await request.get('/api/health')
    const body = await response.json() as Record<string, unknown>
    // ISO 8601 UTC strings produced by toISOString() always end with 'Z'
    expect(typeof body.timestamp).toBe('string')
    expect((body.timestamp as string).endsWith('Z')).toBe(true)
  })

  test('response body does not reveal database availability (health is DB-agnostic)', async ({ request }) => {
    // Per spec: "Does not touch the database."
    // The response must not contain any db-related fields. This is a
    // contract boundary — the health endpoint must never proxy DB status.
    // If a future implementer adds a "db" field they must update this test
    // intentionally after spec approval.
    const response = await request.get('/api/health')
    const body = await response.json() as Record<string, unknown>
    expect(body).not.toHaveProperty('db')
    expect(body).not.toHaveProperty('database')
    expect(body).not.toHaveProperty('neon')
  })
})
