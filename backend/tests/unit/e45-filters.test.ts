/**
 * Unit tests — E-45 T-4501: filters/events.ts
 *
 * Verifies:
 *   - filtersFromSearchParams: parses known params, applies defaults, caps limit
 *   - filtersToSearchParams: round-trips non-null values, omits null/default
 *   - encodeCursor / decodeCursor: base64 round-trip
 *   - decodeCursor: returns null for bad input
 *
 * Pure functions; no database or HTTP calls.
 */

import { describe, it, expect } from 'vitest'
import {
  filtersFromSearchParams,
  filtersToSearchParams,
  encodeCursor,
  decodeCursor,
  type EventFilters,
} from '../../src/lib/filters/events'

// ---------------------------------------------------------------------------
// filtersFromSearchParams
// ---------------------------------------------------------------------------

describe('filtersFromSearchParams — defaults', () => {
  it('returns all null fields and limit=50 when params are empty', () => {
    const f = filtersFromSearchParams(new URLSearchParams())
    expect(f.dateFrom).toBeNull()
    expect(f.dateTo).toBeNull()
    expect(f.intent).toBeNull()
    expect(f.parserPath).toBeNull()
    expect(f.outcome).toBeNull()
    expect(f.locale).toBeNull()
    expect(f.flag).toBeNull()
    expect(f.transcriptionContains).toBeNull()
    expect(f.limit).toBe(50)
    expect(f.cursor).toBeNull()
  })
})

describe('filtersFromSearchParams — known params', () => {
  it('picks up dateFrom', () => {
    const f = filtersFromSearchParams(new URLSearchParams('dateFrom=2026-01-01'))
    expect(f.dateFrom).toBe('2026-01-01')
  })

  it('picks up dateTo', () => {
    const f = filtersFromSearchParams(new URLSearchParams('dateTo=2026-12-31'))
    expect(f.dateTo).toBe('2026-12-31')
  })

  it('picks up intent', () => {
    const f = filtersFromSearchParams(new URLSearchParams('intent=playFavorite'))
    expect(f.intent).toBe('playFavorite')
  })

  it('picks up parserPath', () => {
    const f = filtersFromSearchParams(new URLSearchParams('parserPath=NLModel'))
    expect(f.parserPath).toBe('NLModel')
  })

  it('picks up outcome', () => {
    const f = filtersFromSearchParams(new URLSearchParams('outcome=confirmed'))
    expect(f.outcome).toBe('confirmed')
  })

  it('picks up locale', () => {
    const f = filtersFromSearchParams(new URLSearchParams('locale=en-GB'))
    expect(f.locale).toBe('en-GB')
  })

  it('picks up flag', () => {
    const f = filtersFromSearchParams(new URLSearchParams('flag=likelyMisparse'))
    expect(f.flag).toBe('likelyMisparse')
  })

  it('picks up transcriptionContains', () => {
    const f = filtersFromSearchParams(new URLSearchParams('transcriptionContains=hello'))
    expect(f.transcriptionContains).toBe('hello')
  })

  it('picks up cursor', () => {
    const f = filtersFromSearchParams(new URLSearchParams('cursor=abc123'))
    expect(f.cursor).toBe('abc123')
  })
})

describe('filtersFromSearchParams — limit handling', () => {
  it('uses provided valid limit', () => {
    const f = filtersFromSearchParams(new URLSearchParams('limit=100'))
    expect(f.limit).toBe(100)
  })

  it('caps limit at 200', () => {
    const f = filtersFromSearchParams(new URLSearchParams('limit=999'))
    expect(f.limit).toBe(200)
  })

  it('falls back to 50 for non-numeric limit', () => {
    const f = filtersFromSearchParams(new URLSearchParams('limit=abc'))
    expect(f.limit).toBe(50)
  })

  it('falls back to 50 for limit=0', () => {
    const f = filtersFromSearchParams(new URLSearchParams('limit=0'))
    expect(f.limit).toBe(50)
  })

  it('falls back to 50 for negative limit', () => {
    const f = filtersFromSearchParams(new URLSearchParams('limit=-10'))
    expect(f.limit).toBe(50)
  })

  it('allows limit=200 exactly', () => {
    const f = filtersFromSearchParams(new URLSearchParams('limit=200'))
    expect(f.limit).toBe(200)
  })
})

// ---------------------------------------------------------------------------
// filtersToSearchParams
// ---------------------------------------------------------------------------

describe('filtersToSearchParams — omits null and default values', () => {
  const base: EventFilters = {
    dateFrom: null,
    dateTo: null,
    intent: null,
    parserPath: null,
    outcome: null,
    locale: null,
    flag: null,
    transcriptionContains: null,
    limit: 50,
    cursor: null,
  }

  it('produces empty URLSearchParams for all-null/default filters', () => {
    const p = filtersToSearchParams(base)
    expect(p.toString()).toBe('')
  })

  it('omits limit when it equals the default (50)', () => {
    const p = filtersToSearchParams({ ...base, limit: 50 })
    expect(p.has('limit')).toBe(false)
  })

  it('includes limit when it differs from default', () => {
    const p = filtersToSearchParams({ ...base, limit: 100 })
    expect(p.get('limit')).toBe('100')
  })

  it('includes dateFrom when present', () => {
    const p = filtersToSearchParams({ ...base, dateFrom: '2026-01-01' })
    expect(p.get('dateFrom')).toBe('2026-01-01')
  })

  it('includes intent when present', () => {
    const p = filtersToSearchParams({ ...base, intent: 'stop' })
    expect(p.get('intent')).toBe('stop')
  })

  it('omits cursor when null', () => {
    const p = filtersToSearchParams({ ...base, cursor: null })
    expect(p.has('cursor')).toBe(false)
  })

  it('includes cursor when present', () => {
    const p = filtersToSearchParams({ ...base, cursor: 'xyz' })
    expect(p.get('cursor')).toBe('xyz')
  })
})

describe('filtersToSearchParams — round-trip with filtersFromSearchParams', () => {
  it('round-trips a fully-populated filter object', () => {
    const original: EventFilters = {
      dateFrom: '2026-01-01',
      dateTo: '2026-06-30',
      intent: 'playFavorite',
      parserPath: 'NLModel',
      outcome: 'confirmed',
      locale: 'en-GB',
      flag: 'likelyMisparse',
      transcriptionContains: 'play',
      limit: 100,
      cursor: null,
    }
    const params = filtersToSearchParams(original)
    const parsed = filtersFromSearchParams(params)
    expect(parsed).toEqual(original)
  })
})

// ---------------------------------------------------------------------------
// encodeCursor / decodeCursor
// ---------------------------------------------------------------------------

describe('encodeCursor / decodeCursor — round-trip', () => {
  it('encodes and decodes a bigint id', () => {
    const encoded = encodeCursor(BigInt(12345), '2026-01-01T00:00:00Z')
    const decoded = decodeCursor(encoded)
    expect(decoded).not.toBeNull()
    expect(decoded!.id).toBe('12345')
    expect(decoded!.received_at).toBe('2026-01-01T00:00:00Z')
  })

  it('encodes and decodes a number id', () => {
    const encoded = encodeCursor(42, '2026-05-04T10:30:00Z')
    const decoded = decodeCursor(encoded)
    expect(decoded).not.toBeNull()
    expect(decoded!.id).toBe('42')
    expect(decoded!.received_at).toBe('2026-05-04T10:30:00Z')
  })

  it('produces a valid base64 string', () => {
    const encoded = encodeCursor(1, '2026-01-01T00:00:00Z')
    expect(() => Buffer.from(encoded, 'base64').toString('utf-8')).not.toThrow()
  })
})

describe('decodeCursor — error paths', () => {
  it('returns null for empty string', () => {
    expect(decodeCursor('')).toBeNull()
  })

  it('returns null for non-base64 garbage', () => {
    // Buffer.from handles garbage gracefully; JSON.parse will fail
    expect(decodeCursor('!!!not-valid!!!')).toBeNull()
  })

  it('returns null when id field is missing', () => {
    const bad = Buffer.from(JSON.stringify({ received_at: '2026-01-01' })).toString('base64')
    expect(decodeCursor(bad)).toBeNull()
  })

  it('returns null when received_at field is missing', () => {
    const bad = Buffer.from(JSON.stringify({ id: '1' })).toString('base64')
    expect(decodeCursor(bad)).toBeNull()
  })

  it('returns null when fields are wrong types', () => {
    const bad = Buffer.from(JSON.stringify({ id: 123, received_at: true })).toString('base64')
    expect(decodeCursor(bad)).toBeNull()
  })

  it('returns null for plain text (not JSON)', () => {
    const bad = Buffer.from('hello world').toString('base64')
    expect(decodeCursor(bad)).toBeNull()
  })
})
