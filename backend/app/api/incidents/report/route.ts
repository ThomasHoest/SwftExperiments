import { z } from 'zod'
import { query } from '@/lib/db'
import { requireTelemetryKey } from '@/lib/telemetry-key'
import { logInfo, logError } from '@/lib/logger'

const incidentReportSchema = z.object({
  fingerprint: z.string().regex(/^[0-9a-f]{16}$/, 'invalid_fingerprint'),
  appVersion: z.string().min(1).max(32),
  osVersion: z.string().min(1).max(32),
  deviceModel: z.string().min(1).max(64),
  contextLines: z.array(z.string().max(4096)).max(25),
  breadcrumbs: z.string().max(1024),
  errorLine: z.string().min(1).max(4096),
})

export async function POST(request: Request): Promise<Response> {
  // Auth
  const auth = requireTelemetryKey(request)
  if (!auth.ok) {
    return auth.response
  }

  // Parse body
  let raw: unknown
  try {
    raw = await request.json()
  } catch {
    return Response.json({ error: 'invalid_payload', detail: 'Malformed JSON' }, { status: 400 })
  }

  // Zod validation
  const result = incidentReportSchema.safeParse(raw)
  if (!result.success) {
    const firstError = result.error.errors[0]

    // Check specific field errors for custom error codes
    if (firstError?.path[0] === 'fingerprint' || firstError?.message === 'invalid_fingerprint') {
      return Response.json({ error: 'invalid_fingerprint' }, { status: 400 })
    }

    if (firstError?.path[0] === 'contextLines') {
      // Array length violation
      if (firstError.code === 'too_big' && firstError.path.length === 1) {
        return Response.json(
          { error: 'context_too_long', detail: 'max 25 lines' },
          { status: 400 }
        )
      }
      // Individual line too long
      return Response.json({ error: 'line_too_long' }, { status: 400 })
    }

    if (firstError?.path[0] === 'errorLine') {
      return Response.json({ error: 'invalid_error_line' }, { status: 400 })
    }

    const detail = firstError
      ? `${firstError.path.join('.')}: ${firstError.message}`
      : 'Invalid payload'
    return Response.json({ error: 'invalid_payload', detail }, { status: 400 })
  }

  const body = result.data

  try {
    // Transaction: upsert incident + insert occurrence + prune
    await query('BEGIN')

    try {
      // 1. Upsert incident
      const upsertResult = await query<{ fingerprint: string }>(
        `INSERT INTO incidents (fingerprint, error_line)
         VALUES ($1, $2)
         ON CONFLICT (fingerprint) DO UPDATE
           SET last_seen_at = now(),
               occurrence_count = incidents.occurrence_count + 1
         RETURNING fingerprint`,
        [body.fingerprint, body.errorLine]
      )

      const fingerprint = upsertResult.rows[0]?.fingerprint ?? body.fingerprint

      // 2. Insert occurrence
      await query(
        `INSERT INTO incident_occurrences
           (fingerprint, app_version, os_version, device_model, context_lines, breadcrumbs)
         VALUES ($1, $2, $3, $4, $5::jsonb, $6)`,
        [
          body.fingerprint,
          body.appVersion,
          body.osVersion,
          body.deviceModel,
          JSON.stringify(body.contextLines),
          body.breadcrumbs,
        ]
      )

      // 3. Prune: keep only last 50 occurrences per fingerprint
      await query(
        `DELETE FROM incident_occurrences
          WHERE id IN (
            SELECT id FROM incident_occurrences
             WHERE fingerprint = $1
             ORDER BY reported_at DESC
             OFFSET 50
          )`,
        [body.fingerprint]
      )

      await query('COMMIT')

      logInfo('incident reported', { fingerprint })
      return Response.json({ fingerprint }, { status: 201 })
    } catch (err) {
      await query('ROLLBACK')
      throw err
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    logError('incident report db error', {
      handler: 'POST /api/incidents/report',
      error: message,
    })
    return Response.json({ error: 'internal_error' }, { status: 500 })
  }
}
