/**
 * Unit tests — getStats (E-46 T-4603)
 *
 * Contract source: backend/docs/adr/E-46-admin-export-stats.md §7
 *
 * All database calls are mocked; tests run fully offline.
 *
 * getStats fires 9 parallel query() calls via Promise.all:
 *   1. Total events count
 *   2. Distinct devices count
 *   3. By intent (GROUP BY)
 *   4. By outcome (GROUP BY)
 *   5. By parser_path (GROUP BY)
 *   6. By locale (GROUP BY)
 *   7. likelyMisparse count
 *   8. Labelled count (COUNT DISTINCT)
 *   9. Labels by action (GROUP BY)
 *
 * Run with: pnpm test:unit
 */

import { vi, describe, it, expect, beforeEach } from 'vitest'

vi.mock('@/lib/db', () => ({
  sql: vi.fn(),
  query: vi.fn(),
}))

import { query } from '@/lib/db'
import { getStats } from '../../src/lib/queries/stats'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Builds a full set of 9 mock resolved values for Promise.all in the order
 * they are fired inside getStats.
 */
function mockAllQueries({
  totalEvents = '0',
  distinctDevices = '0',
  byIntent = [] as { intent: string; n: string }[],
  byOutcome = [] as { outcome: string; n: string }[],
  byParserPath = [] as { parser_path: string; n: string }[],
  byLocale = [] as { locale: string; n: string }[],
  likelyMisparse = '0',
  labelledCount = '0',
  labelsByAction = [] as { action: string; n: string }[],
} = {}) {
  const mockedQuery = vi.mocked(query)
  mockedQuery
    .mockResolvedValueOnce({ rows: [{ n: totalEvents }] })
    .mockResolvedValueOnce({ rows: [{ n: distinctDevices }] })
    .mockResolvedValueOnce({ rows: byIntent })
    .mockResolvedValueOnce({ rows: byOutcome })
    .mockResolvedValueOnce({ rows: byParserPath })
    .mockResolvedValueOnce({ rows: byLocale })
    .mockResolvedValueOnce({ rows: [{ n: likelyMisparse }] })
    .mockResolvedValueOnce({ rows: [{ n: labelledCount }] })
    .mockResolvedValueOnce({ rows: labelsByAction })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('getStats — null dateFrom and dateTo', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('runs all 9 queries and returns a StatsResult when both dates are null', async () => {
    mockAllQueries({ totalEvents: '42', distinctDevices: '7' })
    const result = await getStats(null, null)
    expect(result).toBeDefined()
    expect(vi.mocked(query)).toHaveBeenCalledTimes(9)
  })

  it('returns correct totalEvents when dates are null', async () => {
    mockAllQueries({ totalEvents: '42' })
    const result = await getStats(null, null)
    expect(result.totalEvents).toBe(42)
  })

  it('returns correct distinctDevices when dates are null', async () => {
    mockAllQueries({ distinctDevices: '5' })
    const result = await getStats(null, null)
    expect(result.distinctDevices).toBe(5)
  })

  it('omits WHERE clause from queries when both dates are null', async () => {
    mockAllQueries()
    await getStats(null, null)
    const calls = vi.mocked(query).mock.calls
    // When no date filters, params array should be empty for all 9 queries
    for (const [, params] of calls) {
      expect(params).toEqual([])
    }
  })
})

describe('getStats — dateFrom and dateTo provided', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('passes dateFrom and dateTo as params to all 9 queries', async () => {
    mockAllQueries({ totalEvents: '100', distinctDevices: '10' })
    await getStats('2026-01-01', '2026-06-01')
    const calls = vi.mocked(query).mock.calls
    expect(calls).toHaveLength(9)
    // All queries share the same params array with the two date values
    for (const [, params] of calls) {
      expect(params).toContain('2026-01-01')
      expect(params).toContain('2026-06-01')
    }
  })

  it('returns correct totalEvents when dates are provided', async () => {
    mockAllQueries({ totalEvents: '88' })
    const result = await getStats('2026-01-01', '2026-06-01')
    expect(result.totalEvents).toBe(88)
  })
})

describe('getStats — dateFrom only (dateTo null)', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('passes only dateFrom as a param when dateTo is null', async () => {
    mockAllQueries({ totalEvents: '20' })
    await getStats('2026-01-01', null)
    const calls = vi.mocked(query).mock.calls
    for (const [, params] of calls) {
      expect(params).toContain('2026-01-01')
      expect(params).not.toContain(null)
    }
  })
})

describe('getStats — dateTo only (dateFrom null)', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('passes only dateTo as a param when dateFrom is null', async () => {
    mockAllQueries({ totalEvents: '15' })
    await getStats(null, '2026-06-01')
    const calls = vi.mocked(query).mock.calls
    for (const [, params] of calls) {
      expect(params).toContain('2026-06-01')
    }
  })
})

describe('getStats — zero-row DB responses', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns all-zero counts when DB returns zero rows', async () => {
    mockAllQueries({
      totalEvents: '0',
      distinctDevices: '0',
      likelyMisparse: '0',
      labelledCount: '0',
    })
    const result = await getStats(null, null)
    expect(result.totalEvents).toBe(0)
    expect(result.distinctDevices).toBe(0)
    expect(result.likelyMisparseCount).toBe(0)
    expect(result.labelledCount).toBe(0)
  })

  it('returns empty Record objects for group-by fields when DB returns no rows', async () => {
    mockAllQueries()
    const result = await getStats(null, null)
    expect(result.byIntent).toEqual({})
    expect(result.byOutcome).toEqual({})
    expect(result.byParserPath).toEqual({})
    expect(result.byLocale).toEqual({})
  })

  it('returns all-zero labelsByAction when DB returns no label rows', async () => {
    mockAllQueries()
    const result = await getStats(null, null)
    expect(result.labelsByAction).toEqual({ correct: 0, incorrect: 0, discard: 0 })
  })
})

describe('getStats — byIntent grouping', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('builds byIntent Record from multiple intent rows', async () => {
    mockAllQueries({
      byIntent: [
        { intent: 'playFavorite', n: '30' },
        { intent: 'stop', n: '15' },
        { intent: 'volumeUp', n: '5' },
      ],
    })
    const result = await getStats(null, null)
    expect(result.byIntent).toEqual({ playFavorite: 30, stop: 15, volumeUp: 5 })
  })

  it('returns a single-entry Record when only one intent row is returned', async () => {
    mockAllQueries({
      byIntent: [{ intent: 'stop', n: '99' }],
    })
    const result = await getStats(null, null)
    expect(result.byIntent).toEqual({ stop: 99 })
  })

  it('returns empty byIntent when no intent rows', async () => {
    mockAllQueries()
    const result = await getStats(null, null)
    expect(result.byIntent).toEqual({})
  })
})

describe('getStats — labelsByAction breakdown', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('correctly maps correct/incorrect/discard from DB rows', async () => {
    mockAllQueries({
      labelsByAction: [
        { action: 'correct', n: '10' },
        { action: 'incorrect', n: '4' },
        { action: 'discard', n: '2' },
      ],
    })
    const result = await getStats(null, null)
    expect(result.labelsByAction).toEqual({ correct: 10, incorrect: 4, discard: 2 })
  })

  it('leaves missing action keys at 0 when only one action is returned', async () => {
    mockAllQueries({
      labelsByAction: [{ action: 'correct', n: '7' }],
    })
    const result = await getStats(null, null)
    expect(result.labelsByAction.correct).toBe(7)
    expect(result.labelsByAction.incorrect).toBe(0)
    expect(result.labelsByAction.discard).toBe(0)
  })

  it('ignores unknown action values from DB', async () => {
    mockAllQueries({
      labelsByAction: [
        { action: 'correct', n: '3' },
        { action: 'unknown_action', n: '99' },
      ],
    })
    const result = await getStats(null, null)
    expect(result.labelsByAction.correct).toBe(3)
    // unknown_action must not appear in the typed result
    expect((result.labelsByAction as Record<string, number>)['unknown_action']).toBeUndefined()
  })
})

describe('getStats — DB error propagation', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('propagates error when the first query (totalEvents) rejects', async () => {
    vi.mocked(query).mockRejectedValueOnce(new Error('connection timeout'))
    // Fill remaining calls so Promise.all doesn't stall
    for (let i = 0; i < 8; i++) {
      vi.mocked(query).mockResolvedValueOnce({ rows: [{ n: '0' }] })
    }
    await expect(getStats(null, null)).rejects.toThrow('connection timeout')
  })

  it('propagates error when any query in Promise.all rejects', async () => {
    // First 7 succeed, 8th (labelledCount) fails
    for (let i = 0; i < 7; i++) {
      vi.mocked(query).mockResolvedValueOnce({ rows: [{ n: '0' }] })
    }
    vi.mocked(query).mockRejectedValueOnce(new Error('deadlock detected'))
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    await expect(getStats(null, null)).rejects.toThrow('deadlock detected')
  })
})

describe('getStats — return shape completeness', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns all 9 StatsResult fields', async () => {
    mockAllQueries({
      totalEvents: '100',
      distinctDevices: '12',
      byIntent: [{ intent: 'stop', n: '5' }],
      byOutcome: [{ outcome: 'confirmed', n: '50' }],
      byParserPath: [{ parser_path: 'NLModel', n: '80' }],
      byLocale: [{ locale: 'en-GB', n: '60' }],
      likelyMisparse: '3',
      labelledCount: '20',
      labelsByAction: [{ action: 'correct', n: '15' }, { action: 'incorrect', n: '5' }],
    })
    const result = await getStats('2026-01-01', '2026-06-01')
    expect(result.totalEvents).toBe(100)
    expect(result.distinctDevices).toBe(12)
    expect(result.byIntent).toEqual({ stop: 5 })
    expect(result.byOutcome).toEqual({ confirmed: 50 })
    expect(result.byParserPath).toEqual({ NLModel: 80 })
    expect(result.byLocale).toEqual({ 'en-GB': 60 })
    expect(result.likelyMisparseCount).toBe(3)
    expect(result.labelledCount).toBe(20)
    expect(result.labelsByAction).toEqual({ correct: 15, incorrect: 5, discard: 0 })
  })
})
