import { describe, it, expect } from 'vitest'
import { GET } from './route'

describe('GET /api/health', () => {
  it('returns status ok with a timestamp', async () => {
    const response = await GET()
    const body = await response.json()
    expect(response.status).toBe(200)
    expect(body.status).toBe('ok')
    expect(typeof body.timestamp).toBe('string')
    expect(() => new Date(body.timestamp)).not.toThrow()
  })
})
