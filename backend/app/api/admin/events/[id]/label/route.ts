import { type NextRequest } from 'next/server'
import { query as dbQuery } from '@/lib/db'
import { labelSchema } from '@/lib/schemas/label'
import { getClientPrincipal } from '@/lib/auth/clientPrincipal'
import { logInfo, logError } from '@/lib/logger'

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    // Step 1: Validate id
    const { id: idStr } = await params
    const id = parseInt(idStr, 10)
    if (!Number.isFinite(id) || id <= 0) {
      return Response.json({ error: 'Invalid id' }, { status: 400 })
    }

    // Step 2: Parse body with labelSchema
    let body: unknown
    try {
      body = await request.json()
    } catch {
      return Response.json({ error: 'Invalid request body', detail: 'Malformed JSON' }, { status: 400 })
    }

    const parseResult = labelSchema.safeParse(body)
    if (!parseResult.success) {
      const firstError = parseResult.error.errors[0]
      const detail = firstError ? `${firstError.path.join('.')}: ${firstError.message}` : 'Invalid body'
      return Response.json({ error: 'Invalid request body', detail }, { status: 400 })
    }

    const { action, correctedIntent } = parseResult.data

    // Step 3: Get principal; return 401 if null
    const principal = getClientPrincipal(request.headers)
    if (!principal) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const labelledBy = principal.userDetails

    // Step 4: SELECT event exists
    const { rows: eventRows } = await dbQuery<{ id: number }>(
      'SELECT id FROM events WHERE id = $1',
      [id]
    )
    if (eventRows.length === 0) {
      return Response.json({ error: 'Event not found' }, { status: 404 })
    }

    // Step 5: SELECT existing label for this (event_id, labelled_by)
    const { rows: existingRows } = await dbQuery<{
      id: number
      action: string
      corrected_intent: string | null
    }>(
      'SELECT id, action, corrected_intent FROM labels WHERE event_id = $1 AND labelled_by = $2',
      [id, labelledBy]
    )

    const correctedIntentValue = correctedIntent ?? null

    if (existingRows.length > 0) {
      // Step 6: UPDATE — copy current → previous, then set new values
      const existing = existingRows[0]
      await dbQuery(
        `UPDATE labels
         SET previous_action           = action,
             previous_corrected_intent = corrected_intent,
             action                    = $1,
             corrected_intent          = $2,
             labelled_at               = now()
         WHERE id = $3`,
        [action, correctedIntentValue, existing.id]
      )
    } else {
      // Step 7: INSERT new label
      await dbQuery(
        'INSERT INTO labels (event_id, action, corrected_intent, labelled_by) VALUES ($1, $2, $3, $4)',
        [id, action, correctedIntentValue, labelledBy]
      )
    }

    // Step 9: Log INFO
    logInfo('admin label saved', {
      eventId: id,
      action,
      correctedIntent: correctedIntentValue,
      labelledBy,
      isUpdate: existingRows.length > 0,
    })

    // Step 8: Return 200
    return Response.json({ ok: true })
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    logError('admin label error', { error: message })
    return Response.json({ error: 'Server error' }, { status: 500 })
  }
}
