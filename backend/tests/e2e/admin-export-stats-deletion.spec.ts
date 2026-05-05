/**
 * E2E tests — Admin pages: /admin/stats, /admin/export, /admin/deletion
 * and the /api/admin/export CSV endpoint.
 *
 * T-4608: Cover the three admin pages and the CSV export API route.
 *
 * Auth strategy
 * ─────────────
 * These pages sit behind Azure Static Web Apps GitHub OAuth. Full browser-based
 * OAuth automation is not practical in Playwright, so tests take the following
 * approach:
 *
 *   • When running against a deployed SWA URL (baseURL contains
 *     "azurestaticapps.net") and GITHUB_E2E_TOKEN is absent, any test that
 *     requires admin access is skipped with a clear message.
 *
 *   • When running locally against http://localhost:3000, SWA auth middleware
 *     is not active, so admin pages are reachable directly.
 *
 *   • Each page test inspects page.url() after navigation and skips if it was
 *     redirected to the SWA login page (/.auth/login/github).
 *
 * Run with: pnpm playwright test tests/e2e/admin-export-stats-deletion.spec.ts
 */

import { test, expect } from '@playwright/test'

// ─── helpers ────────────────────────────────────────────────────────────────

const AUTH_REDIRECT_PATH = '/.auth/login/github'

/** Returns true when the current page URL is the SWA auth redirect. */
function isAuthRedirect(url: string): boolean {
  return url.includes(AUTH_REDIRECT_PATH)
}

/**
 * Returns true when the baseURL points at a deployed SWA instance and no
 * CI admin token has been supplied, meaning auth-gated pages cannot be reached.
 */
function isSwaWithoutToken(): boolean {
  const base = process.env.PLAYWRIGHT_BASE_URL ?? ''
  const hasToken = !!process.env.GITHUB_E2E_TOKEN
  return base.includes('azurestaticapps.net') && !hasToken
}

// ─── belt-and-braces health check ───────────────────────────────────────────

test('API: health is reachable regardless of auth state', async ({ request }) => {
  const response = await request.get('/api/health')
  expect(response.status()).toBe(200)
  const body = await response.json() as Record<string, unknown>
  expect(body.status).toBe('ok')
})

// ─── Stats page ──────────────────────────────────────────────────────────────

test.describe('/admin/stats', () => {
  test('renders Stats heading and date range picker when accessible', async ({ page }) => {
    if (isSwaWithoutToken()) {
      test.skip(true, 'Deployed SWA admin pages require browser OAuth — skipping without GITHUB_E2E_TOKEN')
    }

    await page.goto('/admin/stats')

    if (isAuthRedirect(page.url())) {
      test.skip(true, 'Redirected to SWA login — admin auth not available in this environment')
    }

    // Heading must contain "Stats"
    const heading = page.locator('h1')
    await expect(heading).toContainText('Stats')

    // Two date inputs must be present for the date-range filter form
    const dateInputs = page.locator('input[type="date"]')
    await expect(dateInputs).toHaveCount(2)
  })
})

// ─── Export page ─────────────────────────────────────────────────────────────

test.describe('/admin/export', () => {
  test('renders Download CSV form pointing at /api/admin/export when accessible', async ({ page }) => {
    if (isSwaWithoutToken()) {
      test.skip(true, 'Deployed SWA admin pages require browser OAuth — skipping without GITHUB_E2E_TOKEN')
    }

    await page.goto('/admin/export')

    if (isAuthRedirect(page.url())) {
      test.skip(true, 'Redirected to SWA login — admin auth not available in this environment')
    }

    // The download form must have action="/api/admin/export"
    const downloadForm = page.locator('form[action="/api/admin/export"]')
    await expect(downloadForm).toBeVisible()

    // The submit button must say "Download CSV"
    const downloadButton = downloadForm.locator('button[type="submit"]')
    await expect(downloadButton).toContainText('Download CSV')
  })
})

// ─── Deletion page ───────────────────────────────────────────────────────────

test.describe('/admin/deletion', () => {
  test('renders device ID input and DELETE confirmation input when accessible', async ({ page }) => {
    if (isSwaWithoutToken()) {
      test.skip(true, 'Deployed SWA admin pages require browser OAuth — skipping without GITHUB_E2E_TOKEN')
    }

    await page.goto('/admin/deletion')

    if (isAuthRedirect(page.url())) {
      test.skip(true, 'Redirected to SWA login — admin auth not available in this environment')
    }

    // Device ID input (id="deviceId")
    const deviceIdInput = page.locator('#deviceId')
    await expect(deviceIdInput).toBeVisible()

    // Confirmation input (id="confirmation") with placeholder="DELETE"
    const confirmationInput = page.locator('#confirmation')
    await expect(confirmationInput).toBeVisible()
    await expect(confirmationInput).toHaveAttribute('placeholder', 'DELETE')

    // Label must mention DELETE to make the confirmation requirement clear
    const confirmationLabel = page.locator('label[for="confirmation"]')
    await expect(confirmationLabel).toContainText('DELETE')
  })
})

// ─── CSV export API ───────────────────────────────────────────────────────────

test.describe('API: /api/admin/export', () => {
  test('returns CSV with BOM and header row, or skips on auth redirect', async ({ request }) => {
    const response = await request.get('/api/admin/export')
    const status = response.status()

    // 401 Unauthorized or a 3xx redirect (Playwright follows redirects to a
    // non-2xx destination that surfaces as the redirect status) means auth is
    // required and not available — skip gracefully.
    if (status === 401 || status === 302 || status === 307 || status === 308) {
      test.skip(true, `Auth required (HTTP ${status}) — skipping CSV content assertions`)
    }

    expect(status).toBe(200)

    // Content-Type must be text/csv
    const contentType = response.headers()['content-type'] ?? ''
    expect(contentType).toContain('text/csv')

    const body = await response.text()

    // The body must start with the UTF-8 BOM (U+FEFF, char code 65279) followed
    // by the CSV header row. The BOM is written as the literal character
    // in the route handler (const BOM = '﻿').
    const hasBom = body.charCodeAt(0) === 0xfeff
    expect(hasBom).toBe(true)

    // After stripping the BOM, the first line must be the header row
    const firstLine = body.replace(/^﻿/, '').split('\n')[0]
    expect(firstLine).toBe(
      'event_id,timestamp,locale,transcription_anonymised,original_intent,' +
      'parser_path,outcome,flags,label_action,corrected_intent,labelled_by,labelled_at',
    )
  })
})
