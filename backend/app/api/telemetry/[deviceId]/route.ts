import { z } from 'zod'
import { sql } from '@/lib/db'
import { requireApiKey } from '@/lib/auth'
import { logInfo, logWarn, logError } from '@/lib/logger'

export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ deviceId: string }> }
): Promise<Response> {
  // Step 1: Auth
  const authResult = requireApiKey(request)
  if (authResult !== null) {
    const suppliedKey = request.headers.get('x-api-key')
    if (suppliedKey) {
      const ip = request.headers.get('x-forwarded-for') ?? 'unknown'
      logWarn('invalid api key', { ip })
    }
    return authResult
  }

  // Step 2: Validate deviceId is a UUID
  const { deviceId } = await params
  const uuidResult = z.string().uuid().safeParse(deviceId)
  if (!uuidResult.success) {
    return Response.json({ error: 'Invalid deviceId' }, { status: 400 })
  }

  try {
    // Step 3: SELECT counts
    const countRows = await sql`
      SELECT
        (SELECT count(*)::int FROM events WHERE device_id = ${deviceId})       AS events,
        (SELECT count(*)::int FROM labels l JOIN events e ON l.event_id = e.id WHERE e.device_id = ${deviceId}) AS labels,
        (SELECT count(*)::int FROM devices WHERE device_id = ${deviceId})      AS devices
    `

    const counts = countRows[0] as { events: number; labels: number; devices: number }
    const eventsDeleted = counts?.events ?? 0
    const labelsDeleted = counts?.labels ?? 0
    const devicesDeleted = counts?.devices ?? 0

    // Step 4: DELETE (cascades to events and labels via ON DELETE CASCADE)
    await sql`DELETE FROM devices WHERE device_id = ${deviceId}`

    // Step 5: Log INFO
    logInfo('device deleted', {
      deviceId,
      eventsDeleted,
      labelsDeleted,
      status: 200,
    })

    // Step 6: Return 200
    return Response.json(
      { deleted: { devices: devicesDeleted, events: eventsDeleted, labels: labelsDeleted } },
      { status: 200 }
    )
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    logError('database error', { handler: `DELETE /api/telemetry/${deviceId}`, error: message })
    return Response.json({ error: 'Server error' }, { status: 500 })
  }
}
