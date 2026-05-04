import { createHash, timingSafeEqual } from 'node:crypto'
import { NextResponse } from 'next/server'

function safeEqual(a: string, b: string): boolean {
  const ha = createHash('sha256').update(a).digest()
  const hb = createHash('sha256').update(b).digest()
  return timingSafeEqual(ha, hb)
}

export function requireApiKey(request: Request): NextResponse | null {
  const supplied = request.headers.get('x-api-key') ?? ''
  const expected = process.env.TELEMETRY_API_KEY ?? ''
  const prev = process.env.TELEMETRY_API_KEY_PREVIOUS

  if (!supplied) {
    return NextResponse.json({ error: 'Invalid API key' }, { status: 401 })
  }

  const valid =
    safeEqual(supplied, expected) || (prev !== undefined && safeEqual(supplied, prev))

  if (!valid) {
    return NextResponse.json({ error: 'Invalid API key' }, { status: 401 })
  }

  return null
}
