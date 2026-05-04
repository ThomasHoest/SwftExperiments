import { query as dbQuery } from '@/lib/db'
import { EventFilters } from '@/lib/filters/events'

export interface ExportRow {
  event_id: string                // e.id::text
  timestamp: string               // e.received_at
  locale: string
  transcription_anonymised: string
  original_intent: string         // e.intent aliased
  parser_path: string
  outcome: string
  flags: string[]
  label_action: string            // l.action (guaranteed non-null by INNER JOIN)
  corrected_intent: string | null // l.corrected_intent
  labelled_by: string
  labelled_at: string
}

export async function exportLabelledEvents(
  filters: EventFilters
): Promise<ExportRow[]> {
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

  const whereClause = where.length > 0 ? `WHERE ${where.join(' AND ')}` : ''

  const queryText = `
    SELECT
      e.id::text AS event_id,
      e.received_at AS timestamp,
      e.locale,
      e.transcription_anonymised,
      e.intent AS original_intent,
      e.parser_path,
      e.outcome,
      e.flags,
      l.action AS label_action,
      l.corrected_intent,
      l.labelled_by,
      l.labelled_at
    FROM events e
    INNER JOIN LATERAL (
      SELECT action, corrected_intent, labelled_by, labelled_at
      FROM labels
      WHERE event_id = e.id
        AND action IS NOT NULL
      ORDER BY labelled_at DESC
      LIMIT 1
    ) l ON true
    ${whereClause}
    ORDER BY e.received_at DESC, e.id DESC
  `

  const { rows } = await dbQuery<ExportRow>(queryText, params)
  return rows
}
