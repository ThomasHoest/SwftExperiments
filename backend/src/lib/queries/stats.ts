import { query as dbQuery } from '@/lib/db'

export interface StatsResult {
  totalEvents: number
  distinctDevices: number
  byIntent: Record<string, number>
  byOutcome: Record<string, number>
  byParserPath: Record<string, number>
  byLocale: Record<string, number>
  likelyMisparseCount: number
  labelledCount: number
  labelsByAction: { correct: number; incorrect: number; discard: number }
}

export async function getStats(
  dateFrom: string | null,
  dateTo: string | null
): Promise<StatsResult> {
  const params: unknown[] = []
  let pIdx = 1
  function addParam(val: unknown): string {
    params.push(val)
    return `$${pIdx++}`
  }

  const conds: string[] = []
  if (dateFrom) conds.push(`e.received_at >= ${addParam(dateFrom)}::timestamptz`)
  if (dateTo)   conds.push(`e.received_at <  ${addParam(dateTo)}::timestamptz`)
  const whereClause = conds.length > 0 ? `WHERE ${conds.join(' AND ')}` : ''

  // Finalize params before Promise.all — addParam must not be called concurrently
  const finalParams = params.slice()

  const [
    totalRes,
    distinctRes,
    byIntentRes,
    byOutcomeRes,
    byParserPathRes,
    byLocaleRes,
    misparseRes,
    labelledRes,
    labelsByActionRes,
  ] = await Promise.all([
    // 1. Total events
    dbQuery<{ n: string }>(
      `SELECT COUNT(*) AS n FROM events e ${whereClause}`,
      finalParams
    ),
    // 2. Distinct devices
    dbQuery<{ n: string }>(
      `SELECT COUNT(DISTINCT device_id) AS n FROM events e ${whereClause}`,
      finalParams
    ),
    // 3. By intent
    dbQuery<{ intent: string; n: string }>(
      `SELECT intent, COUNT(*) AS n FROM events e ${whereClause} GROUP BY intent ORDER BY n DESC`,
      finalParams
    ),
    // 4. By outcome
    dbQuery<{ outcome: string; n: string }>(
      `SELECT outcome, COUNT(*) AS n FROM events e ${whereClause} GROUP BY outcome`,
      finalParams
    ),
    // 5. By parser_path
    dbQuery<{ parser_path: string; n: string }>(
      `SELECT parser_path, COUNT(*) AS n FROM events e ${whereClause} GROUP BY parser_path`,
      finalParams
    ),
    // 6. By locale
    dbQuery<{ locale: string; n: string }>(
      `SELECT locale, COUNT(*) AS n FROM events e ${whereClause} GROUP BY locale`,
      finalParams
    ),
    // 7. likelyMisparse count
    dbQuery<{ n: string }>(
      `SELECT COUNT(*) AS n FROM events e ${whereClause} ${whereClause ? 'AND' : 'WHERE'} 'likelyMisparse' = ANY(e.flags)`,
      finalParams
    ),
    // 8. Labelled count (DISTINCT to avoid double-counting events with multiple label rows)
    dbQuery<{ n: string }>(
      `SELECT COUNT(DISTINCT e.id) AS n FROM events e INNER JOIN labels l ON l.event_id = e.id ${whereClause}`,
      finalParams
    ),
    // 9. Labels by action
    dbQuery<{ action: string; n: string }>(
      `SELECT l.action, COUNT(*) AS n FROM labels l INNER JOIN events e ON e.id = l.event_id ${whereClause} GROUP BY l.action`,
      finalParams
    ),
  ])

  const byIntent: Record<string, number> = {}
  for (const row of byIntentRes.rows) {
    byIntent[row.intent] = Number(row.n)
  }

  const byOutcome: Record<string, number> = {}
  for (const row of byOutcomeRes.rows) {
    byOutcome[row.outcome] = Number(row.n)
  }

  const byParserPath: Record<string, number> = {}
  for (const row of byParserPathRes.rows) {
    byParserPath[row.parser_path] = Number(row.n)
  }

  const byLocale: Record<string, number> = {}
  for (const row of byLocaleRes.rows) {
    byLocale[row.locale] = Number(row.n)
  }

  const labelsByAction = { correct: 0, incorrect: 0, discard: 0 }
  for (const row of labelsByActionRes.rows) {
    if (row.action === 'correct' || row.action === 'incorrect' || row.action === 'discard') {
      labelsByAction[row.action] = Number(row.n)
    }
  }

  return {
    totalEvents:        Number(totalRes.rows[0]?.n ?? 0),
    distinctDevices:    Number(distinctRes.rows[0]?.n ?? 0),
    byIntent,
    byOutcome,
    byParserPath,
    byLocale,
    likelyMisparseCount: Number(misparseRes.rows[0]?.n ?? 0),
    labelledCount:       Number(labelledRes.rows[0]?.n ?? 0),
    labelsByAction,
  }
}
