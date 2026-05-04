export interface EventFilters {
  dateFrom:              string | null
  dateTo:                string | null
  intent:                string | null
  parserPath:            string | null
  outcome:               string | null
  locale:                string | null
  flag:                  string | null
  transcriptionContains: string | null
  limit:                 number
  cursor:                string | null
}

export function filtersFromSearchParams(params: URLSearchParams): EventFilters {
  const limitRaw = parseInt(params.get('limit') ?? '', 10)
  const limit = Number.isFinite(limitRaw) && limitRaw > 0 ? Math.min(limitRaw, 200) : 50
  return {
    dateFrom:              params.get('dateFrom') ?? null,
    dateTo:                params.get('dateTo') ?? null,
    intent:                params.get('intent') ?? null,
    parserPath:            params.get('parserPath') ?? null,
    outcome:               params.get('outcome') ?? null,
    locale:                params.get('locale') ?? null,
    flag:                  params.get('flag') ?? null,
    transcriptionContains: params.get('transcriptionContains') ?? null,
    limit,
    cursor:                params.get('cursor') ?? null,
  }
}

export function filtersToSearchParams(f: EventFilters): URLSearchParams {
  const p = new URLSearchParams()
  if (f.dateFrom)              p.set('dateFrom', f.dateFrom)
  if (f.dateTo)                p.set('dateTo', f.dateTo)
  if (f.intent)                p.set('intent', f.intent)
  if (f.parserPath)            p.set('parserPath', f.parserPath)
  if (f.outcome)               p.set('outcome', f.outcome)
  if (f.locale)                p.set('locale', f.locale)
  if (f.flag)                  p.set('flag', f.flag)
  if (f.transcriptionContains) p.set('transcriptionContains', f.transcriptionContains)
  if (f.limit !== 50)          p.set('limit', String(f.limit))
  if (f.cursor)                p.set('cursor', f.cursor)
  return p
}

export function encodeCursor(id: bigint | number, receivedAt: string): string {
  return Buffer.from(JSON.stringify({ id: String(id), received_at: receivedAt })).toString('base64')
}

export function decodeCursor(cursor: string): { id: string; received_at: string } | null {
  try {
    const parsed = JSON.parse(Buffer.from(cursor, 'base64').toString('utf-8'))
    if (typeof parsed.id !== 'string' || typeof parsed.received_at !== 'string') return null
    return parsed as { id: string; received_at: string }
  } catch {
    return null
  }
}
