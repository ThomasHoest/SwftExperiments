/**
 * E2E tests — Admin Events UI  (T-4511)
 *
 * Auth strategy
 * -------------
 * Azure Static Web Apps enforces GitHub OAuth for /admin/* on deployed
 * instances. Fully automating that OAuth dance in Playwright requires a
 * real browser flow with user interaction, which is not feasible in CI.
 *
 * Guard logic:
 *   - If GITHUB_E2E_TOKEN is NOT set → skip auth-gated tests with a clear
 *     message so the CI run is green rather than broken.
 *   - If GITHUB_E2E_TOKEN IS set AND baseURL is localhost → SWA auth
 *     middleware is not active, so we exercise the page directly.
 *   - If GITHUB_E2E_TOKEN IS set AND baseURL is NOT localhost → skip with a
 *     note that manual admin-role provisioning is required; we cannot drive
 *     SWA's GitHub OAuth callback from Playwright.
 *
 * In all page-level tests we also guard against an unexpected SWA redirect to
 * /.auth/login/github (302/401/403) and skip gracefully rather than failing.
 *
 * Run with: pnpm playwright test tests/e2e/admin-events.spec.ts
 */

import { test, expect } from '@playwright/test'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Returns true when the test is running against a local dev server. */
function isLocalhost(baseURL: string | undefined): boolean {
  return !!baseURL && (baseURL.includes('localhost') || baseURL.includes('127.0.0.1'))
}

/**
 * Returns true when the current URL looks like an SWA auth redirect (the
 * unauthenticated user has been sent to the login page).
 */
function isAuthRedirect(url: string): boolean {
  return url.includes('/.auth/login') || url.includes('/.auth/logout')
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

test.describe('Admin Events UI', () => {

  // Shared before-each: skip the whole suite when auth cannot be satisfied.
  test.beforeEach(async ({}, testInfo) => {
    const token = process.env.GITHUB_E2E_TOKEN
    const baseURL = testInfo.project.use.baseURL

    if (!token) {
      test.skip(true, 'GITHUB_E2E_TOKEN not set — skipping admin E2E tests')
      return
    }

    if (!isLocalhost(baseURL)) {
      test.skip(
        true,
        'Admin E2E tests require localhost — deployed SWA GitHub OAuth cannot be automated from Playwright without a browser-based OAuth flow',
      )
    }
  })

  // -------------------------------------------------------------------------
  // 1. Basic navigation: /admin/events loads or redirects gracefully
  // -------------------------------------------------------------------------
  test('navigates to /admin/events and page loads or redirects to auth', async ({ page }) => {
    const response = await page.goto('/admin/events')
    const status = response?.status() ?? 0

    // On localhost the page should render. On a deployed SWA without a valid
    // session it redirects (302 → auth page). Both are acceptable here; what
    // is NOT acceptable is a 5xx server error.
    expect(status).not.toBeGreaterThanOrEqual(500)

    if (isAuthRedirect(page.url())) {
      // Redirected to auth — that is the correct SWA behaviour for an
      // unauthenticated request on a deployed instance. Accept and move on.
      return
    }

    // On localhost (no auth gate) the admin shell and the filter form must be
    // present. These are the stable landmarks rendered by the layout and the
    // events page regardless of whether there is seeded data.
    await expect(page.locator('nav')).toBeVisible()
    await expect(page.getByText('Voxio Admin')).toBeVisible()
    // The filter form is rendered unconditionally by EventsPage.
    await expect(page.locator('form[method="GET"]')).toBeVisible()
  })

  // -------------------------------------------------------------------------
  // 2. Filter form: intent input is rendered and accepts input
  // -------------------------------------------------------------------------
  test('filter form renders with an intent input field', async ({ page }) => {
    await page.goto('/admin/events')

    if (isAuthRedirect(page.url())) {
      test.skip(true, 'Redirected to auth — cannot verify filter form without admin access')
      return
    }

    // The intent text input must be present with name="intent".
    const intentInput = page.locator('input[name="intent"]')
    await expect(intentInput).toBeVisible()
  })

  // -------------------------------------------------------------------------
  // 3. URL param pre-fills the intent filter field
  // -------------------------------------------------------------------------
  test('?intent=playFavorite pre-fills the intent input', async ({ page }) => {
    await page.goto('/admin/events?intent=playFavorite')

    if (isAuthRedirect(page.url())) {
      test.skip(true, 'Redirected to auth — cannot verify filter pre-fill without admin access')
      return
    }

    const intentInput = page.locator('input[name="intent"]')
    await expect(intentInput).toBeVisible()
    // Next.js Server Component reads the searchParam and sets defaultValue,
    // which is reflected in the DOM value attribute.
    await expect(intentInput).toHaveValue('playFavorite')
  })

  // -------------------------------------------------------------------------
  // 4. Detail page: /admin/events/1 renders detail or Next.js 404
  // -------------------------------------------------------------------------
  test('detail page /admin/events/1 renders or shows not-found', async ({ page }) => {
    const response = await page.goto('/admin/events/1')
    const status = response?.status() ?? 0

    if (isAuthRedirect(page.url())) {
      test.skip(true, 'Redirected to auth — cannot verify detail page without admin access')
      return
    }

    // No seeded data in E2E, so the page will either:
    //   a) Return 404 (Next.js notFound() is called by EventDetailPage when
    //      getEventById returns null — Next.js renders its 404 page).
    //   b) Return 200 with event data if there happens to be a row with id=1.
    // In both cases a 5xx is unacceptable.
    expect(status).not.toBeGreaterThanOrEqual(500)

    if (status === 404) {
      // Next.js default not-found page always contains "404" in the body.
      // Accept this — it is the expected outcome with no seeded data.
      const body = await page.content()
      expect(body).toMatch(/404|not.?found/i)
      return
    }

    // If somehow a row with id=1 exists (e.g. from a prior test run that left
    // data), the detail page must render the admin shell.
    await expect(page.locator('nav')).toBeVisible()
  })

})
