import { query as dbQuery } from '@/lib/db'
import { getClientPrincipal } from '@/lib/auth/clientPrincipal'
import { logInfo, logError } from '@/lib/logger'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export async function POST(request: Request) {
  try {
    const principal = getClientPrincipal(request.headers)
    if (!principal) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 })
    }

    let body: unknown
    try {
      body = await request.json()
    } catch {
      return Response.json({ error: 'Invalid request body' }, { status: 400 })
    }

    const { deviceId, confirmation } = body as Record<string, unknown>

    if (typeof deviceId !== 'string' || !UUID_RE.test(deviceId)) {
      return Response.json({ error: 'Invalid deviceId' }, { status: 400 })
    }

    if (confirmation !== 'DELETE') {
      return Response.json({ error: 'Type DELETE to confirm' }, { status: 400 })
    }

    // SELECT-then-DELETE: run 3 COUNT queries in parallel
    const [labelRes, eventRes, deviceRes] = await Promise.all([
      dbQuery<{ n: string }>(
        'SELECT COUNT(*) AS n FROM labels WHERE event_id IN (SELECT id FROM events WHERE device_id = $1)',
        [deviceId]
      ),
      dbQuery<{ n: string }>(
        'SELECT COUNT(*) AS n FROM events WHERE device_id = $1',
        [deviceId]
      ),
      dbQuery<{ n: string }>(
        'SELECT COUNT(*) AS n FROM devices WHERE device_id = $1',
        [deviceId]
      ),
    ])

    const devices = Number(deviceRes.rows[0]?.n ?? 0)
    const events  = Number(eventRes.rows[0]?.n ?? 0)
    const labels  = Number(labelRes.rows[0]?.n ?? 0)

    // If device not found, return all-zero counts (idempotent)
    if (devices === 0) {
      return Response.json({ deleted: { devices: 0, events: 0, labels: 0 } })
    }

    await dbQuery('DELETE FROM devices WHERE device_id = $1', [deviceId])

    logInfo('admin deletion completed', {
      deviceId,
      deletedBy: principal.userDetails,
      devices,
      events,
      labels,
    })

    return Response.json({ deleted: { devices, events, labels } })
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    logError('admin deletion error', { error: message })
    return Response.json({ error: 'Server error' }, { status: 500 })
  }
}
