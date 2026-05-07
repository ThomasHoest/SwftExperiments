import { z } from 'zod'
import { query } from '@/lib/db'
import { requireAgentKey } from '@/lib/agent-auth'
import { logError } from '@/lib/logger'

// ---------------------------------------------------------------------------
// Cursor encode / decode (inline — do not reuse events cursor)
// ---------------------------------------------------------------------------

interface IncidentCursor {
  last_seen_at: string
  fingerprint: string
}

function encodeCursor(last_seen_at: string, fingerprint: string): string {
  return Buffer.from(JSON.stringify({ last_seen_at, fingerprint })).toString('base64')
}

function decodeCursor(cursor: string): IncidentCursor | null {
  try {
    const parsed = JSON.parse(Buffer.from(cursor, 'base64').toString('utf-8')) as unknown
    if (
      typeof parsed !== 'object' ||
      parsed === null ||
      typeof (parsed as Record<string, unknown>).last_seen_at !== 'string' ||
      typeof (parsed as Record<string, unknown>).fingerprint !== 'string'
    ) {
      return null
    }
    return parsed as IncidentCursor
  } catch {
    return null
  }
}

// ---------------------------------------------------------------------------
// Zod schema for query params
// ---------------------------------------------------------------------------

const VALID_STATUSES = ['open', 'investigating', 'resolved', 'ignored'] as const

const querySchema = z.object({
  status: z.enum(VALID_STATUSES).optional(),
  cursor: z.string().optional(),
})

// ---------------------------------------------------------------------------
// Route handler
// ---------------------------------------------------------------------------

const PAGE_SIZE = 20

export async function GET(request: Request): Promise<Response> {
  // Auth
  const auth = requireAgentKey(request)
  if (!auth.ok) {
    return auth.response
  }

  // Parse query params
  const url = new URL(request.url)
  const rawParams = {
    status: url.searchParams.get('status') ?? undefined,
    cursor: url.searchParams.get('cursor') ?? undefined,
  }

  const parsed = querySchema.safeParse(rawParams)
  if (!parsed.success) {
    const firstError = parsed.error.errors[0]
    if (firstError?.path[0] === 'status') {
      return Response.json({ error: 'invalid_status' }, { status: 400 })
    }
    return Response.json({ error: 'invalid_cursor' }, { status: 400 })
  }

  const { status, cursor: cursorStr } = parsed.data

  // Decode cursor
  let cursorData: IncidentCursor | null = null
  if (cursorStr !== undefined) {
    cursorData = decodeCursor(cursorStr)
    if (cursorData === null) {
      return Response.json({ error: 'invalid_cursor' }, { status: 400 })
    }
  }

  try {
    const result = await query<{
      fingerprint: string
      first_seen_at: string
      last_seen_at: string
      occurrence_count: number
      error_line: string
      status: string
      pr_url: string | null
      pr_number: number | null
    }>(
      `SELECT fingerprint, first_seen_at, last_seen_at, occurrence_count,
              error_line, status, pr_url, pr_number
         FROM incidents
        WHERE ($1::text IS NULL OR status = $1)
          AND ($2::timestamptz IS NULL OR (last_seen_at, fingerprint) < ($2, $3))
        ORDER BY last_seen_at DESC, fingerprint DESC
        LIMIT $4`,
      [
        status ?? null,
        cursorData?.last_seen_at ?? null,
        cursorData?.fingerprint ?? null,
        PAGE_SIZE + 1,
      ]
    )

    const rows = result.rows
    const hasMore = rows.length > PAGE_SIZE
    const pageRows = hasMore ? rows.slice(0, PAGE_SIZE) : rows

    const lastRow = pageRows[pageRows.length - 1]
    const nextCursor =
      hasMore && lastRow
        ? encodeCursor(
            typeof lastRow.last_seen_at === 'string'
              ? lastRow.last_seen_at
              : (lastRow.last_seen_at as unknown as Date).toISOString(),
            lastRow.fingerprint
          )
        : null

    return Response.json({ incidents: pageRows, nextCursor })
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    logError('agent incidents list error', {
      handler: 'GET /api/agent/incidents',
      error: message,
    })
    return Response.json({ error: 'internal_error' }, { status: 500 })
  }
}
