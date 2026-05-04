/**
 * Unit tests — E-45 T-4509: constants/intents.ts
 *
 * Verifies:
 *   - CANONICAL_INTENTS contains all 15 expected values
 *   - No duplicates
 *   - All values are non-empty strings
 *   - CanonicalIntent type is correctly derived (structural check via assignment)
 *
 * Pure constants; no database or HTTP calls.
 */

import { describe, it, expect } from 'vitest'
import { CANONICAL_INTENTS, type CanonicalIntent } from '../../src/lib/constants/intents'

const EXPECTED_INTENTS = [
  'playFavorite', 'playDefault', 'listFavorites',
  'stop', 'pause', 'resume',
  'setVolume', 'adjustVolume', 'mute', 'unmute',
  'joinSpeaker', 'leaveSpeaker',
  'confirm', 'cancel', 'unknown',
] as const

describe('CANONICAL_INTENTS — completeness', () => {
  it('contains exactly 15 entries', () => {
    expect(CANONICAL_INTENTS.length).toBe(15)
  })

  it('contains all expected intent strings', () => {
    for (const intent of EXPECTED_INTENTS) {
      expect(CANONICAL_INTENTS as readonly string[]).toContain(intent)
    }
  })

  it('has no duplicate entries', () => {
    const unique = new Set(CANONICAL_INTENTS)
    expect(unique.size).toBe(CANONICAL_INTENTS.length)
  })

  it('all entries are non-empty strings', () => {
    for (const intent of CANONICAL_INTENTS) {
      expect(typeof intent).toBe('string')
      expect(intent.length).toBeGreaterThan(0)
    }
  })
})

describe('CANONICAL_INTENTS — specific values present', () => {
  const checks: string[] = [
    'playFavorite', 'stop', 'setVolume', 'mute', 'unmute',
    'joinSpeaker', 'leaveSpeaker', 'unknown',
  ]
  for (const intent of checks) {
    it(`includes "${intent}"`, () => {
      expect(CANONICAL_INTENTS as readonly string[]).toContain(intent)
    })
  }
})

describe('CanonicalIntent type', () => {
  it('can be assigned from a valid CANONICAL_INTENTS member', () => {
    // TypeScript compile-time check via assignment; runtime just validates the value
    const intent: CanonicalIntent = 'stop'
    expect(intent).toBe('stop')
  })
})
