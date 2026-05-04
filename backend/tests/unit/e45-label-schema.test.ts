/**
 * Unit tests — E-45 T-4505: schemas/label.ts
 *
 * Verifies the labelSchema Zod contract:
 *   - action enum accepts 'correct', 'incorrect', 'discard' only
 *   - correctedIntent is optional for 'correct' and 'discard'
 *   - correctedIntent is required when action is 'incorrect' (via .refine())
 *   - correctedIntent is NOT validated against CANONICAL_INTENTS (DB is unconstrained TEXT)
 *   - correctedIntent length constraints: min(1), max(64)
 *   - Invalid action values are rejected
 *
 * Pure Zod validation; no database or HTTP calls.
 */

import { describe, it, expect } from 'vitest'
import { labelSchema, type LabelInput } from '../../src/lib/schemas/label'

// ---------------------------------------------------------------------------
// action enum — happy paths
// ---------------------------------------------------------------------------

describe('labelSchema — action "correct"', () => {
  it('accepts action=correct without correctedIntent', () => {
    const result = labelSchema.safeParse({ action: 'correct' })
    expect(result.success).toBe(true)
  })

  it('accepts action=correct with a correctedIntent (ignored by DB but schema allows it)', () => {
    const result = labelSchema.safeParse({ action: 'correct', correctedIntent: 'stop' })
    expect(result.success).toBe(true)
  })
})

describe('labelSchema — action "discard"', () => {
  it('accepts action=discard without correctedIntent', () => {
    const result = labelSchema.safeParse({ action: 'discard' })
    expect(result.success).toBe(true)
  })

  it('accepts action=discard with a correctedIntent', () => {
    const result = labelSchema.safeParse({ action: 'discard', correctedIntent: 'stop' })
    expect(result.success).toBe(true)
  })
})

describe('labelSchema — action "incorrect"', () => {
  it('rejects action=incorrect without correctedIntent', () => {
    const result = labelSchema.safeParse({ action: 'incorrect' })
    expect(result.success).toBe(false)
  })

  it('rejects action=incorrect with correctedIntent=undefined', () => {
    const result = labelSchema.safeParse({ action: 'incorrect', correctedIntent: undefined })
    expect(result.success).toBe(false)
  })

  it('accepts action=incorrect with a valid correctedIntent', () => {
    const result = labelSchema.safeParse({ action: 'incorrect', correctedIntent: 'stop' })
    expect(result.success).toBe(true)
  })

  it('includes path ["correctedIntent"] in the refine error', () => {
    const result = labelSchema.safeParse({ action: 'incorrect' })
    if (result.success) throw new Error('Expected failure')
    const paths = result.error.errors.map(e => e.path.join('.'))
    expect(paths).toContain('correctedIntent')
  })

  it('error message mentions correctedIntent required', () => {
    const result = labelSchema.safeParse({ action: 'incorrect' })
    if (result.success) throw new Error('Expected failure')
    const messages = result.error.errors.map(e => e.message)
    expect(messages.some(m => m.toLowerCase().includes('correctedintent'))).toBe(true)
  })
})

// ---------------------------------------------------------------------------
// action enum — invalid values
// ---------------------------------------------------------------------------

describe('labelSchema — invalid action values', () => {
  it('rejects action="approve"', () => {
    const result = labelSchema.safeParse({ action: 'approve' })
    expect(result.success).toBe(false)
  })

  it('rejects action="" (empty string)', () => {
    const result = labelSchema.safeParse({ action: '' })
    expect(result.success).toBe(false)
  })

  it('rejects missing action', () => {
    const result = labelSchema.safeParse({})
    expect(result.success).toBe(false)
  })

  it('rejects action=null', () => {
    const result = labelSchema.safeParse({ action: null })
    expect(result.success).toBe(false)
  })
})

// ---------------------------------------------------------------------------
// correctedIntent constraints
// ---------------------------------------------------------------------------

describe('labelSchema — correctedIntent length constraints', () => {
  it('rejects correctedIntent of empty string (min 1)', () => {
    const result = labelSchema.safeParse({ action: 'incorrect', correctedIntent: '' })
    expect(result.success).toBe(false)
  })

  it('accepts correctedIntent of length 1', () => {
    const result = labelSchema.safeParse({ action: 'incorrect', correctedIntent: 'a' })
    expect(result.success).toBe(true)
  })

  it('accepts correctedIntent of length 64', () => {
    const result = labelSchema.safeParse({ action: 'incorrect', correctedIntent: 'a'.repeat(64) })
    expect(result.success).toBe(true)
  })

  it('rejects correctedIntent of length 65 (max 64)', () => {
    const result = labelSchema.safeParse({ action: 'incorrect', correctedIntent: 'a'.repeat(65) })
    expect(result.success).toBe(false)
  })
})

// ---------------------------------------------------------------------------
// correctedIntent not restricted to CANONICAL_INTENTS (ADR constraint C-6)
// ---------------------------------------------------------------------------

describe('labelSchema — correctedIntent unconstrained (C-6)', () => {
  it('accepts a correctedIntent that is NOT in CANONICAL_INTENTS', () => {
    // The DB column is unconstrained TEXT; schema must not validate against the constants array
    const result = labelSchema.safeParse({ action: 'incorrect', correctedIntent: 'customIntent' })
    expect(result.success).toBe(true)
  })

  it('accepts an arbitrary string as correctedIntent', () => {
    const result = labelSchema.safeParse({ action: 'incorrect', correctedIntent: 'some-future-intent' })
    expect(result.success).toBe(true)
  })
})

// ---------------------------------------------------------------------------
// TypeScript inferred type sanity check
// ---------------------------------------------------------------------------

describe('labelSchema — inferred type LabelInput', () => {
  it('has the expected shape for a correct label', () => {
    const raw = { action: 'correct' as const }
    const result = labelSchema.safeParse(raw)
    if (!result.success) throw new Error('Expected success')
    const data: LabelInput = result.data
    expect(data.action).toBe('correct')
    expect(data.correctedIntent).toBeUndefined()
  })

  it('has the expected shape for an incorrect label', () => {
    const raw = { action: 'incorrect' as const, correctedIntent: 'stop' }
    const result = labelSchema.safeParse(raw)
    if (!result.success) throw new Error('Expected success')
    const data: LabelInput = result.data
    expect(data.action).toBe('incorrect')
    expect(data.correctedIntent).toBe('stop')
  })
})
