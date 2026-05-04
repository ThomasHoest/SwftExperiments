import { type NextRequest } from 'next/server'
import { getClientPrincipal } from '@/lib/auth/clientPrincipal'
import { filtersFromSearchParams } from '@/lib/filters/events'
import { exportLabelledEvents } from '@/lib/queries/export'
import { logError } from '@/lib/logger'

function csvField(val: string): string {
  if (/[,"\n]/.test(val)) return '"' + val.replace(/"/g, '""') + '"'
  return val
}

const BOM = '﻿'
const HEADERS = [
  'event_id', 'timestamp', 'locale', 'transcription_anonymised', 'original_intent',
  'parser_path', 'outcome', 'flags', 'label_action', 'corrected_intent', 'labelled_by', 'labelled_at',
]

export async function GET(request: NextRequest) {
  try {
    const principal = getClientPrincipal(request.headers)
    if (!principal) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const params = request.nextUrl.searchParams
    const filters = filtersFromSearchParams(params)
    const rows = await exportLabelledEvents(filters)

    const lines = [
      BOM + HEADERS.join(','),
      ...rows.map(r => [
        r.event_id,
        r.timestamp,
        r.locale,
        r.transcription_anonymised,
        r.original_intent,
        r.parser_path,
        r.outcome,
        r.flags.join(';'),
        r.label_action,
        r.label_action === 'incorrect' ? (r.corrected_intent ?? '') : '',
        r.labelled_by,
        r.labelled_at,
      ].map(f => csvField(String(f ?? ''))).join(',')),
    ]
    const body = lines.join('\n') + '\n'

    const filename = `voxio-labelled-events-${new Date().toISOString().slice(0, 10)}.csv`

    return new Response(body, {
      status: 200,
      headers: {
        'Content-Type': 'text/csv; charset=utf-8',
        'Content-Disposition': `attachment; filename="${filename}"`,
      },
    })
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    logError('admin export error', { error: message })
    return Response.json({ error: 'Server error' }, { status: 500 })
  }
}
