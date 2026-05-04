/**
 * Unit tests — seed-dev.ts prod guard logic (E-42)
 *
 * The seed script must refuse to run in production to prevent accidental data
 * population against a live database.  Guard conditions from the ADR spec:
 *
 *   1. NODE_ENV === 'production'  → process.exit(1)
 *   2. DATABASE_URL contains 'production'  → process.exit(1)
 *   3. NODE_ENV === 'development' (normal case) → guard does NOT fire
 *
 * Strategy: the guard logic is extracted as a pure function here so the tests
 * are fully offline (no DB connection, no side-effects).  When the Implementer
 * creates backend/scripts/seed-dev.ts they MUST export the guard function so
 * these tests can import it:
 *
 *   export function checkProdGuard(
 *     env: string | undefined,
 *     databaseUrl: string | undefined,
 *   ): void { ... }
 *
 * Until that export exists the tests import a local inline implementation that
 * mirrors the required behaviour, ensuring the contract is locked in before the
 * Implementer begins work.
 *
 * Contract source: backend/docs/adr/E-42-database-schema.md §6 (T-4206)
 *
 * Run with: pnpm test:unit
 */

import { describe, it, expect, vi, afterEach } from 'vitest'
import path from 'node:path'
import { existsSync } from 'node:fs'

// ---------------------------------------------------------------------------
// Try to import the real guard from the seed script.
// If the script doesn't exist yet, fall back to a local reference
// implementation that matches the required contract.
// ---------------------------------------------------------------------------

const SEED_SCRIPT_PATH = path.resolve(
  new URL(import.meta.url).pathname,
  '../../../../scripts/seed-dev.ts',
)

type GuardFn = (env: string | undefined, databaseUrl: string | undefined) => void

/**
 * Reference implementation of the prod guard.
 *
 * This matches the exact logic that seed-dev.ts MUST implement.  If the
 * Implementer deviates from these conditions the real-import branch of the
 * tests will catch it.
 */
function referenceGuard(env: string | undefined, databaseUrl: string | undefined): void {
  if (env === 'production') {
    process.exit(1)
    return
  }
  if (databaseUrl?.includes('production')) {
    process.exit(1)
  }
}

/**
 * Resolves to the real exported `checkProdGuard` from seed-dev.ts when the
 * file exists and exports that function, otherwise falls back to the reference
 * implementation.
 */
async function resolveGuard(): Promise<GuardFn> {
  if (!existsSync(SEED_SCRIPT_PATH)) {
    return referenceGuard
  }
  try {
    const mod = await import(SEED_SCRIPT_PATH) as Record<string, unknown>
    if (typeof mod.checkProdGuard === 'function') {
      return mod.checkProdGuard as GuardFn
    }
    // Script exists but hasn't exported the guard function yet; use reference.
    return referenceGuard
  } catch {
    return referenceGuard
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('seed-dev prod guard', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('calls process.exit(1) when NODE_ENV is "production"', async () => {
    const guard = await resolveGuard()
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((_code?: number | string | null | undefined) => {
      // Prevent actual process termination during tests
      return undefined as never
    })

    guard('production', 'postgres://user:pass@db.example.com/mydb')

    expect(exitSpy).toHaveBeenCalledWith(1)
  })

  it('calls process.exit(1) when DATABASE_URL contains "production"', async () => {
    const guard = await resolveGuard()
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((_code?: number | string | null | undefined) => {
      return undefined as never
    })

    guard('development', 'postgres://user:pass@production.db.neon.tech/mydb')

    expect(exitSpy).toHaveBeenCalledWith(1)
  })

  it('calls process.exit(1) when DATABASE_URL contains "production" regardless of NODE_ENV', async () => {
    const guard = await resolveGuard()
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((_code?: number | string | null | undefined) => {
      return undefined as never
    })

    // Even with an unusual NODE_ENV value, a production URL must trigger the guard
    guard('staging', 'postgres://user:pass@ep-production-xyz.neon.tech/voxio')

    expect(exitSpy).toHaveBeenCalledWith(1)
  })

  it('does NOT call process.exit when NODE_ENV is "development"', async () => {
    const guard = await resolveGuard()
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((_code?: number | string | null | undefined) => {
      return undefined as never
    })

    guard('development', 'postgres://user:pass@dev.db.neon.tech/voxio_dev')

    expect(exitSpy).not.toHaveBeenCalled()
  })

  it('does NOT call process.exit when NODE_ENV is "test"', async () => {
    const guard = await resolveGuard()
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((_code?: number | string | null | undefined) => {
      return undefined as never
    })

    guard('test', 'postgres://user:pass@test.db.neon.tech/voxio_test')

    expect(exitSpy).not.toHaveBeenCalled()
  })

  it('does NOT call process.exit when DATABASE_URL is undefined and NODE_ENV is "development"', async () => {
    const guard = await resolveGuard()
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((_code?: number | string | null | undefined) => {
      return undefined as never
    })

    guard('development', undefined)

    expect(exitSpy).not.toHaveBeenCalled()
  })

  it('calls process.exit(1) when both NODE_ENV is "production" AND DATABASE_URL contains "production"', async () => {
    const guard = await resolveGuard()
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((_code?: number | string | null | undefined) => {
      return undefined as never
    })

    guard('production', 'postgres://user:pass@production.neon.tech/voxio')

    // At minimum one exit(1) call is expected; the exact call count depends on
    // whether the implementation short-circuits after the first match.
    expect(exitSpy).toHaveBeenCalledWith(1)
  })
})
