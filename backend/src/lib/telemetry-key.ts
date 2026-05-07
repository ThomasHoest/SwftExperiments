import { createHash, timingSafeEqual } from 'node:crypto'

function safeEqual(a: string, b: string): boolean {
  const ha = createHash('sha256').update(a).digest()
  const hb = createHash('sha256').update(b).digest()
  return timingSafeEqual(ha, hb)
}

export function requireTelemetryKey(
  request: Request
): { ok: true } | { ok: false; response: Response } {
  const configured = process.env.TELEMETRY_API_KEY ?? ''

  if (!configured) {
    return {
      ok: false,
      response: Response.json({ error: 'telemetry_key_not_configured' }, { status: 503 }),
    }
  }

  const supplied = request.headers.get('x-telemetry-key') ?? ''

  if (!supplied) {
    return {
      ok: false,
      response: Response.json({ error: 'missing_telemetry_key' }, { status: 401 }),
    }
  }

  if (!safeEqual(supplied, configured)) {
    return {
      ok: false,
      response: Response.json({ error: 'invalid_telemetry_key' }, { status: 401 }),
    }
  }

  return { ok: true }
}
