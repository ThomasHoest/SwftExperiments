/**
 * Unit tests — filtersFromSearchParams, filtersToSearchParams, encodeCursor, decodeCursor (E-45 T-4501)
 *
 * Contract source: backend/docs/adr/E-45-admin-events.md §7
 *
 * All functions are pure — no mocking needed.
 *
 * Run with: pnpm test:unit
 */

import { describe, it, expect } from 'vitest'
import {
  filtersFromSearchParams,
  filtersToSearchParams,
  encodeCursor,
  decodeCursor,
} from '../../src/lib/filters/events'

// ---------------------------------------------------------------------------
// filtersFromSearchParams
// ---------------------------------------------------------------------------

describe('filtersFromSearchParams — empty params → all null, limit=50', () => {
  it('returns null for all string fields when params are empty', () => {
    const params = new URLSearchParams()
    const filters = filtersFromSearchParams(params)
    expect(filters.dateFrom).toBeNull()
    expect(filters.dateTo).toBeNull()
    expect(filters.intent).toBeNull()
    expect(filters.parserPath).toBeNull()
    expect(filters.outcome).toBeNull()
    expect(filters.locale).toBeNull()
    expect(filters.flag).toBeNull()
    expect(filters.transcriptionContains).toBeNull()
    expect(filters.cursor).toBeNull()
  })

  it('defaults limit to 50 when no limit param is provided', () => {
    const filters = filtersFromSearchParams(new URLSearchParams())
    expect(filters.limit).toBe(50)
  })
})

describe('filtersFromSearchParams — limit=100 → limit=100', () => {
  it('parses a valid limit within range', () => {
    const filters = filtersFromSearchParams(new URLSearchParams('limit=100'))
    expect(filters.limit).toBe(100)
  })
})

describe('filtersFromSearchParams — limit=999 → limit clamped to 200', () => {
  it('clamps limit to 200 when the value exceeds the maximum', () => {
    const filters = filtersFromSearchParams(new URLSearchParams('limit=999'))
    expect(filters.limit).toBe(200)
  })

  it('clamps exactly at the boundary: limit=201 → 200', () => {
    const filters = filtersFromSearchParams(new URLSearchParams('limit=201'))
    expect(filters.limit).toBe(200)
  })

  it('accepts exactly limit=200 without clamping', () => {
    const filters = filtersFromSearchParams(new URLSearchParams('limit=200'))
    expect(filters.limit).toBe(200)
  })
})

describe('filtersFromSearchParams — limit=abc → falls back to 50 (malformed, silent ignore)', () => {
  it('falls back to 50 for a non-numeric limit value', () => {
    const filters = filtersFromSearchParams(new URLSearchParams('limit=abc'))
    expect(filters.limit).toBe(50)
  })

  it('falls back to 50 for an empty limit value', () => {
    const filters = filtersFromSearchParams(new URLSearchParams('limit='))
    expect(filters.limit).toBe(50)
  })

  it('falls back to 50 for limit=0 (not positive)', () => {
    const filters = filtersFromSearchParams(new URLSearchParams('limit=0'))
    expect(filters.limit).toBe(50)
  })

  it('falls back to 50 for a negative limit value', () => {
    const filters = filtersFromSearchParams(new URLSearchParams('limit=-10'))
    expect(filters.limit).toBe(50)
  })
})

describe("filtersFromSearchParams — intent=playFavorite → intent='playFavorite'", () => {
  it('parses the intent filter correctly', () => {
    const filters = filtersFromSearchParams(new URLSearchParams('intent=playFavorite'))
    expect(filters.intent).toBe('playFavorite')
  })
})

describe("filtersFromSearchParams — dateFrom=2026-01-01 → dateFrom='2026-01-01'", () => {
  it('parses the dateFrom filter correctly', () => {
    const filters = filtersFromSearchParams(new URLSearchParams('dateFrom=2026-01-01'))
    expect(filters.dateFrom).toBe('2026-01-01')
  })
})

describe('filtersFromSearchParams — all filters', () => {
  it('parses all supported filter fields in one pass', () => {
    const qs = new URLSearchParams({
      dateFrom: '2026-01-01',
      dateTo: '2026-12-31',
      intent: 'playFavorite',
      parserPath: 'NLModel',
      outcome: 'confirmed',
      locale: 'en-GB',
      flag: 'likelyMisparse',
      transcriptionContains: 'play',
      limit: '25',
      cursor: 'abc123',
    })
    const filters = filtersFromSearchParams(qs)
    expect(filters.dateFrom).toBe('2026-01-01')
    expect(filters.dateTo).toBe('2026-12-31')
    expect(filters.intent).toBe('playFavorite')
    expect(filters.parserPath).toBe('NLModel')
    expect(filters.outcome).toBe('confirmed')
    expect(filters.locale).toBe('en-GB')
    expect(filters.flag).toBe('likelyMisparse')
    expect(filters.transcriptionContains).toBe('play')
    expect(filters.limit).toBe(25)
    expect(filters.cursor).toBe('abc123')
  })
})

// ---------------------------------------------------------------------------
// filtersToSearchParams
// ---------------------------------------------------------------------------

describe('filtersToSearchParams — omits null values', () => {
  it('produces an empty URLSearchParams when all optional fields are null and limit is default', () => {
    const filters = filtersFromSearchParams(new URLSearchParams())
    const params = filtersToSearchParams(filters)
    // Limit 50 is the default and should be omitted
    expect(params.toString()).toBe('')
  })

  it('does not include null fields in the output', () => {
    const filters = filtersFromSearchParams(new URLSearchParams('intent=stop'))
    // Override intent to null to confirm omission
    const params = filtersToSearchParams({ ...filters, intent: null })
    expect(params.has('intent')).toBe(false)
  })
})

describe('filtersToSearchParams — includes non-default limit', () => {
  it('includes limit in output when it differs from the default of 50', () => {
    const filters = filtersFromSearchParams(new URLSearchParams('limit=100'))
    const params = filtersToSearchParams(filters)
    expect(params.get('limit')).toBe('100')
  })

  it('omits limit when it equals the default of 50', () => {
    const filters = filtersFromSearchParams(new URLSearchParams())
    const params = filtersToSearchParams(filters)
    expect(params.has('limit')).toBe(false)
  })
})

describe('filtersToSearchParams — round-trip with non-null values', () => {
  it('preserves all non-null filter values through a round-trip', () => {
    const original = new URLSearchParams({
      dateFrom: '2026-01-01',
      dateTo: '2026-06-30',
      intent: 'setVolume',
      limit: '75',
    })
    const filters = filtersFromSearchParams(original)
    const params = filtersToSearchParams(filters)
    expect(params.get('dateFrom')).toBe('2026-01-01')
    expect(params.get('dateTo')).toBe('2026-06-30')
    expect(params.get('intent')).toBe('setVolume')
    expect(params.get('limit')).toBe('75')
  })
})

// ---------------------------------------------------------------------------
// encodeCursor / decodeCursor
// ---------------------------------------------------------------------------

describe('encodeCursor + decodeCursor — round-trip', () => {
  it('round-trips id and received_at correctly', () => {
    const encoded = encodeCursor(42n, '2026-05-04T10:00:00.000Z')
    const decoded = decodeCursor(encoded)
    expect(decoded).not.toBeNull()
    expect(decoded!.id).toBe('42')
    expect(decoded!.received_at).toBe('2026-05-04T10:00:00.000Z')
  })

  it('round-trips a numeric id (non-bigint) correctly', () => {
    const encoded = encodeCursor(99, '2026-01-01T00:00:00.000Z')
    const decoded = decodeCursor(encoded)
    expect(decoded).not.toBeNull()
    expect(decoded!.id).toBe('99')
    expect(decoded!.received_at).toBe('2026-01-01T00:00:00.000Z')
  })

  it('produces a base64 string (no spaces or newlines)', () => {
    const encoded = encodeCursor(1n, '2026-05-04T00:00:00.000Z')
    expect(typeof encoded).toBe('string')
    expect(encoded).toMatch(/^[A-Za-z0-9+/=]+$/)
  })

  it('round-trips a large bigint id without loss', () => {
    const largeId = 9007199254740993n // beyond Number.MAX_SAFE_INTEGER
    const encoded = encodeCursor(largeId, '2026-05-04T12:34:56.789Z')
    const decoded = decodeCursor(encoded)
    expect(decoded).not.toBeNull()
    expect(decoded!.id).toBe('9007199254740993')
  })
})

describe('decodeCursor — malformed base64 → returns null (no throw)', () => {
  it('returns null for a clearly invalid base64 string', () => {
    expect(() => decodeCursor('!!not-base64!!')).not.toThrow()
    expect(decodeCursor('!!not-base64!!')).toBeNull()
  })

  it('returns null for valid base64 that decodes to non-JSON', () => {
    const b64 = Buffer.from('this is not json').toString('base64')
    expect(decodeCursor(b64)).toBeNull()
  })

  it('returns null for valid base64 JSON missing required id field', () => {
    const b64 = Buffer.from(JSON.stringify({ received_at: '2026-05-04T00:00:00Z' })).toString('base64')
    expect(decodeCursor(b64)).toBeNull()
  })

  it('returns null for valid base64 JSON missing required received_at field', () => {
    const b64 = Buffer.from(JSON.stringify({ id: '42' })).toString('base64')
    expect(decodeCursor(b64)).toBeNull()
  })

  it('returns null when id field is a number (not a string)', () => {
    const b64 = Buffer.from(JSON.stringify({ id: 42, received_at: '2026-05-04T00:00:00Z' })).toString('base64')
    expect(decodeCursor(b64)).toBeNull()
  })

  it('returns null for an empty string', () => {
    expect(decodeCursor('')).toBeNull()
  })
})
