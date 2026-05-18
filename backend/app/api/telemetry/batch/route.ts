import { sql } from '@/lib/db'
import { requireApiKey } from '@/lib/auth'
import { logInfo, logWarn, logError } from '@/lib/logger'
import { batchSchema, eventSchema } from '@/lib/schemas/batch'

export async function POST(request: Request): Promise<Response> {
  // Step 1: Auth
  const authResult = requireApiKey(request)
  if (authResult !== null) {
    const suppliedKey = request.headers.get('x-api-key')
    if (suppliedKey) {
      // Wrong key (present but invalid) — log WARN with source IP
      const ip = request.headers.get('x-forwarded-for') ?? 'unknown'
      logWarn('invalid api key', { ip })
    }
    return authResult
  }

  // Step 2: Body size check
  const body = await request.text()
  if (body.length > 1_048_576) {
    return Response.json({ error: 'Batch too large' }, { status: 413 })
  }

  // Step 3: JSON parse
  let parsed: unknown
  try {
    parsed = JSON.parse(body)
  } catch {
    return Response.json(
      { error: 'Invalid request body', detail: 'Malformed JSON' },
      { status: 400 }
    )
  }

  // Step 4: Batch-level Zod validation
  const batchResult = batchSchema.safeParse(parsed)
  if (!batchResult.success) {
    const firstError = batchResult.error.errors[0]
    const detail = firstError ? `${firstError.path.join('.')}: ${firstError.message}` : 'Invalid batch'
    return Response.json({ error: 'Invalid request body', detail }, { status: 400 })
  }

  const batch = batchResult.data
  const { deviceId, appVersion, modelVersion, events } = batch

  try {
    // Step 5: Rate limit check
    const rateLimitRows = await sql`
      UPDATE devices SET last_upload_at = now()
      WHERE device_id = ${deviceId} AND last_upload_at < now() - interval '60 seconds'
      RETURNING device_id
    `

    if (rateLimitRows.length === 0) {
      // Either rate-limited or new device — check which
      const existsRows = await sql`
        SELECT 1 FROM devices WHERE device_id = ${deviceId}
      `
      if (existsRows.length > 0) {
        // Device exists but is rate-limited
        return new Response(
          JSON.stringify({ error: 'Rate limit exceeded', retryAfterSeconds: 60 }),
          {
            status: 429,
            headers: {
              'Content-Type': 'application/json',
              'Retry-After': '60',
            },
          }
        )
      }
      // New device — continue
    }

    // Step 6: Per-event Zod validation
    const errors: Array<{ index: number; reason: string }> = []
    const validEvents: typeof events = []

    for (let i = 0; i < events.length; i++) {
      const eventResult = eventSchema.safeParse(events[i])
      if (eventResult.success) {
        validEvents.push(eventResult.data)
      } else {
        const firstErr = eventResult.error.errors[0]
        const reason = firstErr
          ? `${firstErr.path.join('.')}: ${firstErr.message}`
          : 'Invalid event'
        errors.push({ index: i, reason })
      }
    }

    if (validEvents.length === 0) {
      return Response.json(
        { error: 'Invalid request body', detail: 'No valid events' },
        { status: 400 }
      )
    }

    // Step 7: Device UPSERT — must happen before event inserts (FK constraint)
    const localeForDevice = validEvents[0].locale
    await sql`
      INSERT INTO devices (device_id, first_seen_at, last_seen_at, last_upload_at, app_version, model_version, locale)
      VALUES (${deviceId}, now(), now(), now(), ${appVersion}, ${modelVersion}, ${localeForDevice})
      ON CONFLICT (device_id) DO UPDATE SET
        last_seen_at   = now(),
        last_upload_at = now(),
        app_version    = EXCLUDED.app_version,
        model_version  = EXCLUDED.model_version,
        locale         = EXCLUDED.locale
    `

    // Step 8: Single multi-row INSERT for all valid events.
    //
    // Previously this was a per-event INSERT in a `for` loop. With the Neon
    // serverless driver, each `await sql\`...\`` is a separate HTTP round-
    // trip to the proxy — 100 events ≈ 100 round-trips + the device UPSERT,
    // which exceeded the Azure Functions consumption-tier execution timeout
    // (~30 s) once cold-start latency on the first SQL call was added in.
    // The Azure SWA frontend then returned a generic
    // "Backend call failure" 500 to the client. One INSERT × N rows scales
    // far better and stays well inside the timeout for typical batch sizes
    // (iOS caps batches at 25 events).
    const cols = 11
    const placeholders = validEvents
      .map((_, i) => {
        const base = i * cols
        return `($${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5}, $${base + 6}, $${base + 7}, $${base + 8}::jsonb, $${base + 9}, $${base + 10}, $${base + 11})`
      })
      .join(', ')

    const params: unknown[] = []
    for (const event of validEvents) {
      params.push(
        deviceId,
        event.timestamp,
        appVersion,
        modelVersion,
        event.locale,
        event.transcriptionAnonymised,
        event.intent,
        JSON.stringify(event.slotsAnonymised),
        event.parserPath,
        event.outcome,
        event.flags
      )
    }

    // Note: `sql` from @neondatabase/serverless accepts both tagged-template
    // and `(text, params)` call forms. The plain-function form is what the
    // bulk INSERT needs (a variable-length VALUES clause is awkward to
    // express via tagged template). Both forms are mocked by the same
    // `vi.fn()` in unit tests, so test compatibility is preserved.
    await sql(
      `INSERT INTO events (
        device_id, client_timestamp, app_version, model_version, locale,
        transcription_anonymised, intent, slots_anonymised, parser_path, outcome, flags
      ) VALUES ${placeholders}`,
      params
    )

    const accepted = validEvents.length
    const rejected = errors.length

    // Step 9: Log and respond
    logInfo('batch accepted', {
      deviceId,
      batchSize: events.length,
      accepted,
      rejected,
      status: 202,
    })

    // Step 10: Return 202
    return Response.json({ accepted, rejected, errors }, { status: 202 })
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    logError('database error', { handler: 'POST /api/telemetry/batch', error: message })

    if (message.includes('timeout')) {
      return Response.json({ error: 'Database unavailable' }, { status: 503 })
    }
    return Response.json({ error: 'Server error' }, { status: 500 })
  }
}
