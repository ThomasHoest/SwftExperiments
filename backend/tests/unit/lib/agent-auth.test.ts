/**
 * Unit tests — src/lib/agent-auth.ts (E-51 T-5101-pre, absorbed from E-48 T-4801)
 *
 * Contract source: backend/docs/adr/E-51-incident-backend.md §Public Interface Contract
 *
 * Tests verify the full requireAgentKey contract:
 *   - AGENT_API_KEY unset/empty → 503 { error: "agent_api_disabled" }
 *   - x-agent-key missing/empty → 401 { error: "missing_agent_key" }
 *   - wrong key → 401 { error: "invalid_agent_key" }
 *   - correct key → { ok: true }
 *   - key value never logged (spy on logWarn)
 *
 * Run with: pnpm test:unit
 */

import { vi, describe, it, expect, beforeEach, afterEach } from 'vitest'

vi.mock('@/lib/logger', () => ({
  logInfo: vi.fn(),
  logWarn: vi.fn(),
  logError: vi.fn(),
}))

import { logWarn } from '@/lib/logger'
import { requireAgentKey } from '../../../src/lib/agent-auth'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const VALID_AGENT_KEY = 'super-secret-agent-key-for-tests'

function makeRequest(agentKey?: string): Request {
  const headers: Record<string, string> = {}
  if (agentKey !== undefined) {
    headers['x-agent-key'] = agentKey
  }
  return new Request('http://localhost/api/agent/incidents', {
    method: 'GET',
    headers,
  })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('requireAgentKey — AGENT_API_KEY env var unset', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    delete process.env.AGENT_API_KEY
  })

  afterEach(() => {
    delete process.env.AGENT_API_KEY
  })

  it('returns { ok: false } when AGENT_API_KEY is unset', () => {
    const req = makeRequest(VALID_AGENT_KEY)
    const result = requireAgentKey(req)
    expect(result.ok).toBe(false)
  })

  it('returns a 503 response when AGENT_API_KEY is unset', async () => {
    const req = makeRequest(VALID_AGENT_KEY)
    const result = requireAgentKey(req)
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.response.status).toBe(503)
    }
  })

  it('returns { error: "agent_api_disabled" } body when AGENT_API_KEY is unset', async () => {
    const req = makeRequest(VALID_AGENT_KEY)
    const result = requireAgentKey(req)
    expect(result.ok).toBe(false)
    if (!result.ok) {
      const body = await result.response.json() as Record<string, unknown>
      expect(body.error).toBe('agent_api_disabled')
    }
  })

  it('returns 503 when AGENT_API_KEY is set to empty string', async () => {
    process.env.AGENT_API_KEY = ''
    const req = makeRequest(VALID_AGENT_KEY)
    const result = requireAgentKey(req)
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.response.status).toBe(503)
      const body = await result.response.json() as Record<string, unknown>
      expect(body.error).toBe('agent_api_disabled')
    }
  })
})

describe('requireAgentKey — x-agent-key header missing or empty', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    process.env.AGENT_API_KEY = VALID_AGENT_KEY
  })

  afterEach(() => {
    delete process.env.AGENT_API_KEY
  })

  it('returns { ok: false } when x-agent-key header is absent', () => {
    const req = makeRequest(undefined)
    const result = requireAgentKey(req)
    expect(result.ok).toBe(false)
  })

  it('returns a 401 response when x-agent-key header is absent', async () => {
    const req = makeRequest(undefined)
    const result = requireAgentKey(req)
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.response.status).toBe(401)
    }
  })

  it('returns { error: "missing_agent_key" } when x-agent-key header is absent', async () => {
    const req = makeRequest(undefined)
    const result = requireAgentKey(req)
    expect(result.ok).toBe(false)
    if (!result.ok) {
      const body = await result.response.json() as Record<string, unknown>
      expect(body.error).toBe('missing_agent_key')
    }
  })

  it('returns 401 with missing_agent_key when x-agent-key is an empty string', async () => {
    const req = makeRequest('')
    const result = requireAgentKey(req)
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.response.status).toBe(401)
      const body = await result.response.json() as Record<string, unknown>
      expect(body.error).toBe('missing_agent_key')
    }
  })
})

describe('requireAgentKey — wrong key', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    process.env.AGENT_API_KEY = VALID_AGENT_KEY
  })

  afterEach(() => {
    delete process.env.AGENT_API_KEY
  })

  it('returns { ok: false } when x-agent-key is incorrect', () => {
    const req = makeRequest('wrong-key-value')
    const result = requireAgentKey(req)
    expect(result.ok).toBe(false)
  })

  it('returns a 401 response when x-agent-key is incorrect', async () => {
    const req = makeRequest('wrong-key-value')
    const result = requireAgentKey(req)
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.response.status).toBe(401)
    }
  })

  it('returns { error: "invalid_agent_key" } when x-agent-key is incorrect', async () => {
    const req = makeRequest('wrong-key-value')
    const result = requireAgentKey(req)
    expect(result.ok).toBe(false)
    if (!result.ok) {
      const body = await result.response.json() as Record<string, unknown>
      expect(body.error).toBe('invalid_agent_key')
    }
  })

  it('returns 401 for a key that is almost correct (off by one char)', async () => {
    const almostCorrect = VALID_AGENT_KEY.slice(0, -1) + 'X'
    const req = makeRequest(almostCorrect)
    const result = requireAgentKey(req)
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.response.status).toBe(401)
      const body = await result.response.json() as Record<string, unknown>
      expect(body.error).toBe('invalid_agent_key')
    }
  })
})

describe('requireAgentKey — correct key', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    process.env.AGENT_API_KEY = VALID_AGENT_KEY
  })

  afterEach(() => {
    delete process.env.AGENT_API_KEY
  })

  it('returns { ok: true } when x-agent-key matches AGENT_API_KEY', () => {
    const req = makeRequest(VALID_AGENT_KEY)
    const result = requireAgentKey(req)
    expect(result.ok).toBe(true)
  })

  it('does not return a response property when key is correct', () => {
    const req = makeRequest(VALID_AGENT_KEY)
    const result = requireAgentKey(req)
    expect(result.ok).toBe(true)
    // TypeScript narrowing — no response field when ok: true
    expect('response' in result).toBe(false)
  })
})

describe('requireAgentKey — key never appears in log output', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    process.env.AGENT_API_KEY = VALID_AGENT_KEY
  })

  afterEach(() => {
    delete process.env.AGENT_API_KEY
  })

  it('does not log the key value on a successful auth', () => {
    const req = makeRequest(VALID_AGENT_KEY)
    requireAgentKey(req)
    const warnCalls = vi.mocked(logWarn).mock.calls
    const allLogText = JSON.stringify(warnCalls)
    expect(allLogText).not.toContain(VALID_AGENT_KEY)
  })

  it('does not log the supplied key value on an invalid_agent_key failure', () => {
    const wrongKey = 'my-very-secret-wrong-key'
    const req = makeRequest(wrongKey)
    requireAgentKey(req)
    const warnCalls = vi.mocked(logWarn).mock.calls
    const allLogText = JSON.stringify(warnCalls)
    expect(allLogText).not.toContain(wrongKey)
  })

  it('does not log AGENT_API_KEY value in any warn call', () => {
    const req = makeRequest('some-key')
    requireAgentKey(req)
    const warnCalls = vi.mocked(logWarn).mock.calls
    const allLogText = JSON.stringify(warnCalls)
    expect(allLogText).not.toContain(VALID_AGENT_KEY)
  })
})
