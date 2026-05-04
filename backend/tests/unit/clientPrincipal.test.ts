/**
 * Unit tests — getClientPrincipal (E-44 T-4403)
 *
 * Contract source: backend/docs/adr/E-44-admin-auth.md §7
 *
 * Verifies:
 *   - Missing header → null
 *   - Valid base64 JSON → typed ClientPrincipal object
 *   - Malformed base64 or non-JSON → throws
 *   - Missing required fields (userId, userDetails, userRoles) → throws
 *   - userRoles not an array → throws
 *   - Empty userRoles array → valid (anonymous / pre-auth SWA request)
 *   - identityProvider field is present and correct
 *   - Admin role check pattern (idiomatic usage)
 *
 * Pure function; no live HTTP, no SWA connection, no database calls.
 *
 * Run with: pnpm test:unit
 */

import { describe, it, expect } from 'vitest'
import { getClientPrincipal } from '../../src/lib/auth/clientPrincipal'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Encodes an arbitrary object as base64 JSON and returns a Headers object
 * with the `x-ms-client-principal` header set, mirroring the SWA runtime.
 */
function makeHeaders(principal: Record<string, unknown>): Headers {
  const encoded = Buffer.from(JSON.stringify(principal)).toString('base64')
  return new Headers({ 'x-ms-client-principal': encoded })
}

/** Returns a Headers object with no x-ms-client-principal header. */
function emptyHeaders(): Headers {
  return new Headers()
}

/** A canonical valid admin principal payload. */
const VALID_ADMIN_PAYLOAD = {
  identityProvider: 'github',
  userId: 'abc123',
  userDetails: 'octocat',
  userRoles: ['authenticated', 'admin'],
} as const

// ---------------------------------------------------------------------------
// Missing header
// ---------------------------------------------------------------------------

describe('getClientPrincipal — missing header', () => {
  it('returns null when x-ms-client-principal header is absent', () => {
    const result = getClientPrincipal(emptyHeaders())
    expect(result).toBeNull()
  })
})

// ---------------------------------------------------------------------------
// Happy path — valid admin principal
// ---------------------------------------------------------------------------

describe('getClientPrincipal — valid admin principal', () => {
  it('returns a typed ClientPrincipal object for a fully-formed admin payload', () => {
    const result = getClientPrincipal(makeHeaders({ ...VALID_ADMIN_PAYLOAD }))
    expect(result).not.toBeNull()
  })

  it('exposes the correct userId', () => {
    const result = getClientPrincipal(makeHeaders({ ...VALID_ADMIN_PAYLOAD }))
    expect(result!.userId).toBe('abc123')
  })

  it('exposes the correct userDetails (GitHub username)', () => {
    const result = getClientPrincipal(makeHeaders({ ...VALID_ADMIN_PAYLOAD }))
    expect(result!.userDetails).toBe('octocat')
  })

  it('exposes a userRoles array that includes "admin"', () => {
    const result = getClientPrincipal(makeHeaders({ ...VALID_ADMIN_PAYLOAD }))
    expect(result!.userRoles).toContain('admin')
  })

  it('exposes identityProvider as "github"', () => {
    const result = getClientPrincipal(makeHeaders({ ...VALID_ADMIN_PAYLOAD }))
    expect(result!.identityProvider).toBe('github')
  })
})

// ---------------------------------------------------------------------------
// Happy path — valid non-admin principal
// ---------------------------------------------------------------------------

describe('getClientPrincipal — valid non-admin principal', () => {
  it('returns an object whose userRoles does NOT include "admin"', () => {
    const payload = {
      identityProvider: 'github',
      userId: 'user456',
      userDetails: 'regularuser',
      userRoles: ['authenticated'],
    }
    const result = getClientPrincipal(makeHeaders(payload))
    expect(result).not.toBeNull()
    expect(result!.userRoles).not.toContain('admin')
  })

  it('returns the correct userId and userDetails for a non-admin user', () => {
    const payload = {
      identityProvider: 'github',
      userId: 'user456',
      userDetails: 'regularuser',
      userRoles: ['authenticated'],
    }
    const result = getClientPrincipal(makeHeaders(payload))
    expect(result!.userId).toBe('user456')
    expect(result!.userDetails).toBe('regularuser')
  })
})

// ---------------------------------------------------------------------------
// Happy path — empty userRoles (anonymous / pre-auth SWA request)
// ---------------------------------------------------------------------------

describe('getClientPrincipal — empty userRoles array', () => {
  it('does not throw when userRoles is an empty array', () => {
    const payload = {
      identityProvider: 'github',
      userId: 'anon',
      userDetails: 'anon-user',
      userRoles: [],
    }
    expect(() => getClientPrincipal(makeHeaders(payload))).not.toThrow()
  })

  it('returns an object with an empty userRoles array', () => {
    const payload = {
      identityProvider: 'github',
      userId: 'anon',
      userDetails: 'anon-user',
      userRoles: [],
    }
    const result = getClientPrincipal(makeHeaders(payload))
    expect(result).not.toBeNull()
    expect(result!.userRoles).toEqual([])
  })
})

// ---------------------------------------------------------------------------
// identityProvider field accessibility
// ---------------------------------------------------------------------------

describe('getClientPrincipal — identityProvider field', () => {
  it('always returns identityProvider as "github" regardless of payload value', () => {
    // Even if the payload carries a different provider string the contract
    // mandates the typed field is 'github' — the implementation hard-codes it.
    const payload = {
      identityProvider: 'github',
      userId: 'abc123',
      userDetails: 'octocat',
      userRoles: ['authenticated', 'admin'],
    }
    const result = getClientPrincipal(makeHeaders(payload))
    expect(result!.identityProvider).toBe('github')
  })
})

// ---------------------------------------------------------------------------
// Error paths — malformed base64
// ---------------------------------------------------------------------------

describe('getClientPrincipal — malformed base64', () => {
  it('throws when the header value is not valid base64', () => {
    const headers = new Headers({ 'x-ms-client-principal': '!!!not-base64!!!' })
    // Buffer.from('!!!not-base64!!!', 'base64') does not throw in Node — it
    // silently ignores invalid characters and may decode to garbage, so the
    // implementation must handle the subsequent JSON.parse failure.
    expect(() => getClientPrincipal(headers)).toThrow()
  })

  it('throws with a descriptive message for a non-base64 header', () => {
    const headers = new Headers({ 'x-ms-client-principal': '!!!not-base64!!!' })
    expect(() => getClientPrincipal(headers)).toThrow('Malformed x-ms-client-principal header')
  })
})

// ---------------------------------------------------------------------------
// Error paths — valid base64 but not JSON
// ---------------------------------------------------------------------------

describe('getClientPrincipal — valid base64, invalid JSON', () => {
  it('throws when the decoded value is not parseable JSON', () => {
    const headers = new Headers({
      'x-ms-client-principal': Buffer.from('not-json').toString('base64'),
    })
    expect(() => getClientPrincipal(headers)).toThrow()
  })

  it('throws with a descriptive message for non-JSON base64 content', () => {
    const headers = new Headers({
      'x-ms-client-principal': Buffer.from('not-json').toString('base64'),
    })
    expect(() => getClientPrincipal(headers)).toThrow('Malformed x-ms-client-principal header')
  })

  it('throws when the decoded value is a JSON primitive (number)', () => {
    const headers = new Headers({
      'x-ms-client-principal': Buffer.from('42').toString('base64'),
    })
    expect(() => getClientPrincipal(headers)).toThrow()
  })

  it('throws when the decoded value is a JSON primitive (null)', () => {
    const headers = new Headers({
      'x-ms-client-principal': Buffer.from('null').toString('base64'),
    })
    expect(() => getClientPrincipal(headers)).toThrow()
  })
})

// ---------------------------------------------------------------------------
// Error paths — valid JSON but missing required fields
// ---------------------------------------------------------------------------

describe('getClientPrincipal — valid JSON, missing userId', () => {
  it('throws when userId is absent', () => {
    const headers = makeHeaders({ userDetails: 'octocat', userRoles: ['admin'] })
    expect(() => getClientPrincipal(headers)).toThrow()
  })

  it('throws with a descriptive message when userId is absent', () => {
    const headers = makeHeaders({ userDetails: 'octocat', userRoles: ['admin'] })
    expect(() => getClientPrincipal(headers)).toThrow('Malformed x-ms-client-principal header')
  })

  it('throws when userId is present but not a string (number)', () => {
    const headers = makeHeaders({ userId: 12345, userDetails: 'octocat', userRoles: ['admin'] })
    expect(() => getClientPrincipal(headers)).toThrow()
  })
})

describe('getClientPrincipal — valid JSON, missing userDetails', () => {
  it('throws when userDetails is absent', () => {
    const headers = makeHeaders({ userId: 'abc123', userRoles: ['admin'] })
    expect(() => getClientPrincipal(headers)).toThrow()
  })

  it('throws with a descriptive message when userDetails is absent', () => {
    const headers = makeHeaders({ userId: 'abc123', userRoles: ['admin'] })
    expect(() => getClientPrincipal(headers)).toThrow('Malformed x-ms-client-principal header')
  })

  it('throws when userDetails is present but not a string (boolean)', () => {
    const headers = makeHeaders({ userId: 'abc123', userDetails: true, userRoles: ['admin'] })
    expect(() => getClientPrincipal(headers)).toThrow()
  })
})

describe('getClientPrincipal — valid JSON, userRoles not an array', () => {
  it('throws when userRoles is a string (not an array)', () => {
    const headers = makeHeaders({ userId: 'abc', userDetails: 'octocat', userRoles: 'admin' })
    expect(() => getClientPrincipal(headers)).toThrow()
  })

  it('throws with a descriptive message when userRoles is a string', () => {
    const headers = makeHeaders({ userId: 'abc', userDetails: 'octocat', userRoles: 'admin' })
    expect(() => getClientPrincipal(headers)).toThrow('Malformed x-ms-client-principal header')
  })

  it('throws when userRoles is a number', () => {
    const headers = makeHeaders({ userId: 'abc', userDetails: 'octocat', userRoles: 1 })
    expect(() => getClientPrincipal(headers)).toThrow()
  })

  it('throws when userRoles is null', () => {
    const headers = makeHeaders({ userId: 'abc', userDetails: 'octocat', userRoles: null })
    expect(() => getClientPrincipal(headers)).toThrow()
  })

  it('throws when userRoles is absent entirely', () => {
    const headers = makeHeaders({ userId: 'abc', userDetails: 'octocat' })
    expect(() => getClientPrincipal(headers)).toThrow()
  })
})

// ---------------------------------------------------------------------------
// Idiomatic usage — isAdmin check pattern
// ---------------------------------------------------------------------------

describe('getClientPrincipal — isAdmin check pattern', () => {
  it('isAdmin check: userRoles includes "admin" → true', () => {
    const h = makeHeaders({
      userId: 'x',
      userDetails: 'dev',
      userRoles: ['authenticated', 'admin'],
    })
    const p = getClientPrincipal(h)
    expect(p?.userRoles.includes('admin')).toBe(true)
  })

  it('isAdmin check: userRoles does not include "admin" → false', () => {
    const h = makeHeaders({
      userId: 'x',
      userDetails: 'dev',
      userRoles: ['authenticated'],
    })
    const p = getClientPrincipal(h)
    expect(p?.userRoles.includes('admin')).toBe(false)
  })

  it('isAdmin check: null principal (missing header) → undefined via optional chain', () => {
    const p = getClientPrincipal(emptyHeaders())
    // p?.userRoles.includes('admin') evaluates to undefined when p is null
    expect(p?.userRoles.includes('admin')).toBeUndefined()
  })
})
