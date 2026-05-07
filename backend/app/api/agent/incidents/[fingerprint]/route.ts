import { z } from 'zod'
import { query } from '@/lib/db'
import { requireAgentKey } from '@/lib/agent-auth'
import { logError } from '@/lib/logger'

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

const FINGERPRINT_REGEX = /^[0-9a-f]{16}$/

function validateFingerprint(fp: string): boolean {
  return FINGERPRINT_REGEX.test(fp)
}

// ---------------------------------------------------------------------------
// GET /api/agent/incidents/:fingerprint — T-5104
// ---------------------------------------------------------------------------

interface IncidentRow {
  fingerprint: string
  first_seen_at: string
  last_seen_at: string
  occurrence_count: number
  error_line: string
  status: string
  pr_url: string | null
  pr_number: number | null
}

interface OccurrenceRow {
  id: string | number | bigint
  reported_at: string
  app_version: string
  os_version: string
  device_model: string
  context_lines: string[]
  breadcrumbs: string
}

export async function GET(
  request: Request,
  { params }: { params: Promise<{ fingerprint: string }> }
): Promise<Response> {
  // Auth
  const auth = requireAgentKey(request)
  if (!auth.ok) {
    return auth.response
  }

  const { fingerprint } = await params

  if (!validateFingerprint(fingerprint)) {
    return Response.json({ error: 'invalid_fingerprint' }, { status: 400 })
  }

  try {
    // Fetch incident row
    const incidentResult = await query<IncidentRow>(
      `SELECT fingerprint, first_seen_at, last_seen_at, occurrence_count,
              error_line, status, pr_url, pr_number
         FROM incidents
        WHERE fingerprint = $1`,
      [fingerprint]
    )

    if (incidentResult.rows.length === 0) {
      return Response.json({ error: 'incident_not_found' }, { status: 404 })
    }

    const incident = incidentResult.rows[0]

    // Fetch recent occurrences (last 10)
    const occurrenceResult = await query<OccurrenceRow>(
      `SELECT id, reported_at, app_version, os_version, device_model,
              context_lines, breadcrumbs
         FROM incident_occurrences
        WHERE fingerprint = $1
        ORDER BY reported_at DESC
        LIMIT 10`,
      [fingerprint]
    )

    const recentOccurrences = occurrenceResult.rows.map((row) => ({
      id: String(row.id),
      reported_at: row.reported_at,
      app_version: row.app_version,
      os_version: row.os_version,
      device_model: row.device_model,
      context_lines: row.context_lines,
      breadcrumbs: row.breadcrumbs,
    }))

    return Response.json({
      ...incident,
      recent_occurrences: recentOccurrences,
    })
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    logError('agent incident detail error', {
      handler: 'GET /api/agent/incidents/[fingerprint]',
      fingerprint,
      error: message,
    })
    return Response.json({ error: 'internal_error' }, { status: 500 })
  }
}

// ---------------------------------------------------------------------------
// PATCH /api/agent/incidents/:fingerprint — T-5105
// ---------------------------------------------------------------------------

const VALID_STATUSES = ['open', 'investigating', 'resolved', 'ignored'] as const

const patchSchema = z.object({
  status: z.enum(VALID_STATUSES).optional(),
  pr_url: z
    .string()
    .min(1)
    .max(512)
    .refine((v) => v.startsWith('https://'), { message: 'invalid_pr_url' })
    .optional(),
  pr_number: z
    .number()
    .int()
    .positive()
    .optional(),
})

interface PatchResult {
  fingerprint: string
  status: string
  pr_url: string | null
  pr_number: number | null
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ fingerprint: string }> }
): Promise<Response> {
  // Auth
  const auth = requireAgentKey(request)
  if (!auth.ok) {
    return auth.response
  }

  const { fingerprint } = await params

  if (!validateFingerprint(fingerprint)) {
    return Response.json({ error: 'invalid_fingerprint' }, { status: 400 })
  }

  // Parse body
  let raw: unknown
  try {
    raw = await request.json()
  } catch {
    return Response.json({ error: 'invalid_payload', detail: 'Malformed JSON' }, { status: 400 })
  }

  // Validate body
  const result = patchSchema.safeParse(raw)
  if (!result.success) {
    const firstError = result.error.errors[0]

    if (firstError?.path[0] === 'status') {
      return Response.json({ error: 'invalid_status' }, { status: 400 })
    }
    if (firstError?.path[0] === 'pr_url') {
      return Response.json({ error: 'invalid_pr_url' }, { status: 400 })
    }
    if (firstError?.path[0] === 'pr_number') {
      return Response.json({ error: 'invalid_pr_number' }, { status: 400 })
    }

    return Response.json({ error: 'invalid_payload' }, { status: 400 })
  }

  const body = result.data

  // At least one field must be present
  if (body.status === undefined && body.pr_url === undefined && body.pr_number === undefined) {
    return Response.json({ error: 'no_fields_to_update' }, { status: 400 })
  }

  try {
    const updateResult = await query<PatchResult>(
      `UPDATE incidents
          SET status    = COALESCE($2, status),
              pr_url    = COALESCE($3, pr_url),
              pr_number = COALESCE($4, pr_number)
        WHERE fingerprint = $1
        RETURNING fingerprint, status, pr_url, pr_number`,
      [
        fingerprint,
        body.status ?? null,
        body.pr_url ?? null,
        body.pr_number ?? null,
      ]
    )

    if (updateResult.rows.length === 0) {
      return Response.json({ error: 'incident_not_found' }, { status: 404 })
    }

    return Response.json(updateResult.rows[0])
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    logError('agent incident patch error', {
      handler: 'PATCH /api/agent/incidents/[fingerprint]',
      fingerprint,
      error: message,
    })
    return Response.json({ error: 'internal_error' }, { status: 500 })
  }
}
