import { getEventById } from '@/lib/queries/events'
import { logError } from '@/lib/logger'

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id: idStr } = await params
    const id = parseInt(idStr, 10)
    if (!Number.isFinite(id) || id <= 0) {
      return Response.json({ error: 'Invalid id' }, { status: 400 })
    }
    const event = await getEventById(id)
    if (!event) return Response.json({ error: 'Not found' }, { status: 404 })
    return Response.json(event)
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    logError('admin event get error', { error: message })
    return Response.json({ error: 'Server error' }, { status: 500 })
  }
}
