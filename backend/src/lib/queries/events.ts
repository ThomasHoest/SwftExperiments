import { query as dbQuery } from '@/lib/db'
import { EventFilters, encodeCursor, decodeCursor } from '@/lib/filters/events'

export interface EventRow {
  id: bigint
  device_id: string
  received_at: string
  client_timestamp: string
  app_version: string
  model_version: string
  locale: string
  transcription_anonymised: string
  intent: string
  slots_anonymised: unknown
  parser_path: string
  outcome: string
  flags: string[]
  label_action: string | null
  label_corrected_intent: string | null
  label_labelled_by: string | null
  label_labelled_at: string | null
}

export async function listEvents(
  filters: EventFilters
): Promise<{ rows: EventRow[]; nextCursor: string | null }> {
  const params: unknown[] = []
  let pIdx = 1

  function addParam(val: unknown): string {
    params.push(val)
    return `$${pIdx++}`
  }

  const where: string[] = []

  if (filters.dateFrom)  where.push(`e.received_at >= ${addParam(filters.dateFrom)}::timestamptz`)
  if (filters.dateTo)    where.push(`e.received_at <  ${addParam(filters.dateTo)}::timestamptz`)
  if (filters.intent)    where.push(`e.intent = ${addParam(filters.intent)}`)
  if (filters.parserPath) where.push(`e.parser_path = ${addParam(filters.parserPath)}`)
  if (filters.outcome)   where.push(`e.outcome = ${addParam(filters.outcome)}`)
  if (filters.locale)    where.push(`e.locale = ${addParam(filters.locale)}`)
  if (filters.flag)      where.push(`e.flags && ARRAY[${addParam(filters.flag)}]::text[]`)
  if (filters.transcriptionContains)
    where.push(`e.transcription_anonymised ILIKE '%' || ${addParam(filters.transcriptionContains)} || '%'`)

  if (filters.cursor) {
    const cur = decodeCursor(filters.cursor)
    if (cur) {
      const pTs = addParam(cur.received_at)
      const pId = addParam(cur.id)
      where.push(`(e.received_at < ${pTs}::timestamptz OR (e.received_at = ${pTs}::timestamptz AND e.id < ${pId}::bigint))`)
    }
  }

  const whereClause = where.length > 0 ? `WHERE ${where.join(' AND ')}` : ''
  const limitParam = addParam(filters.limit + 1)

  const query = `
    SELECT
      e.id, e.device_id, e.received_at, e.client_timestamp,
      e.app_version, e.model_version, e.locale,
      e.transcription_anonymised, e.intent, e.slots_anonymised,
      e.parser_path, e.outcome, e.flags,
      l.action AS label_action,
      l.corrected_intent AS label_corrected_intent,
      l.labelled_by AS label_labelled_by,
      l.labelled_at AS label_labelled_at
    FROM events e
    LEFT JOIN LATERAL (
      SELECT action, corrected_intent, labelled_by, labelled_at
      FROM labels
      WHERE event_id = e.id
      ORDER BY labelled_at DESC
      LIMIT 1
    ) l ON true
    ${whereClause}
    ORDER BY e.received_at DESC, e.id DESC
    LIMIT ${limitParam}
  `

  const { rows } = await dbQuery<EventRow>(query, params)

  let nextCursor: string | null = null
  if (rows.length > filters.limit) {
    rows.pop()
    const last = rows[rows.length - 1]
    nextCursor = encodeCursor(last.id, last.received_at)
  }

  return { rows, nextCursor }
}

export async function getEventById(id: number): Promise<EventRow | null> {
  const { rows } = await dbQuery<EventRow>(
    `SELECT e.*, l.action AS label_action, l.corrected_intent AS label_corrected_intent,
            l.labelled_by AS label_labelled_by, l.labelled_at AS label_labelled_at
     FROM events e
     LEFT JOIN LATERAL (
       SELECT action, corrected_intent, labelled_by, labelled_at
       FROM labels WHERE event_id = e.id ORDER BY labelled_at DESC LIMIT 1
     ) l ON true
     WHERE e.id = $1`,
    [id]
  )
  return rows[0] ?? null
}
