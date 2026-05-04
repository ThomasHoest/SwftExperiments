import { type NextRequest } from 'next/server'
import { listEvents } from '@/lib/queries/events'
import { filtersFromSearchParams } from '@/lib/filters/events'
import { getClientPrincipal } from '@/lib/auth/clientPrincipal'
import { logInfo, logError } from '@/lib/logger'

export async function GET(request: NextRequest) {
  try {
    const principal = getClientPrincipal(request.headers)
    const filters = filtersFromSearchParams(request.nextUrl.searchParams)
    const { rows, nextCursor } = await listEvents(filters)
    logInfo('admin events list', {
      admin: principal?.userDetails ?? 'unknown',
      filterKeys: Object.keys(filters).filter(k => filters[k as keyof typeof filters] !== null),
      rowCount: rows.length,
    })
    return Response.json({ rows, nextCursor, total: null })
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    logError('admin events list error', { error: message })
    return Response.json({ error: 'Server error' }, { status: 500 })
  }
}
