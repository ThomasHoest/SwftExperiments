/**
 * Unit tests — E-46 T-4601: exportLabelledEvents and GET /api/admin/export
 *
 * Contract source: backend/docs/adr/E-46-admin-export-stats.md §7
 *
 * All database calls and auth are mocked; tests run fully offline.
 *
 * Covers:
 *   Part A — exportLabelledEvents (src/lib/queries/export.ts)
 *     - Filter application (dateFrom, dateTo, intent, locale, outcome, flag)
 *     - Empty result set
 *     - Returns ExportRow[]
 *
 *   Part B — GET /api/admin/export (app/api/admin/export/route.ts)
 *     - 401 when principal is null
 *     - 200 with BOM + header row only on zero rows
 *     - 200 with correct Content-Type
 *     - Content-Disposition contains filename prefix and .csv suffix
 *     - CSV RFC 4180 quoting: comma in field → quoted
 *     - CSV RFC 4180 quoting: double-quote in field → doubled
 *     - corrected_intent is empty string when label_action is 'correct'
 *     - corrected_intent is empty string when label_action is 'discard'
 *     - corrected_intent is non-empty when label_action is 'incorrect'
 *     - flags array joined with semicolons
 *     - empty flags array produces empty string column
 *     - response body starts with UTF-8 BOM character
 *
 * Run with: pnpm test:unit
 */

import { vi, describe, it, expect, beforeEach } from 'vitest'

vi.mock('@/lib/db', () => ({
  sql: vi.fn(),
  query: vi.fn(),
}))

vi.mock('@/lib/auth/clientPrincipal', () => ({
  getClientPrincipal: vi.fn(),
}))

import { NextRequest } from 'next/server'
import { query } from '@/lib/db'
import { getClientPrincipal } from '@/lib/auth/clientPrincipal'
import { exportLabelledEvents } from '../../src/lib/queries/export'
import { GET } from '../../app/api/admin/export/route'

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const UTF8_BOM = '﻿'

const VALID_PRINCIPAL = {
  identityProvider: 'github' as const,
  userId: 'user123',
  userDetails: 'admin-user',
  userRoles: ['authenticated', 'admin'],
}

const BASE_FILTERS = {
  dateFrom: null,
  dateTo: null,
  intent: null,
  parserPath: null,
  outcome: null,
  locale: null,
  flag: null,
  transcriptionContains: null,
  limit: 50,
  cursor: null,
}

/** Column index map matching the HEADERS array in the route handler. */
const HEADER_INDEX: Record<string, number> = {
  event_id: 0,
  timestamp: 1,
  locale: 2,
  transcription_anonymised: 3,
  original_intent: 4,
  parser_path: 5,
  outcome: 6,
  flags: 7,
  label_action: 8,
  corrected_intent: 9,
  labelled_by: 10,
  labelled_at: 11,
}

/** A minimal valid ExportRow. */
function makeExportRow(overrides: Partial<{
  event_id: string
  timestamp: string
  locale: string
  transcription_anonymised: string
  original_intent: string
  parser_path: string
  outcome: string
  flags: string[]
  label_action: string
  corrected_intent: string | null
  labelled_by: string
  labelled_at: string
}> = {}) {
  return {
    event_id: '42',
    timestamp: '2026-05-04T10:00:00Z',
    locale: 'en-GB',
    transcription_anonymised: 'play something',
    original_intent: 'playFavorite',
    parser_path: 'NLModel',
    outcome: 'confirmed',
    flags: [],
    label_action: 'correct',
    corrected_intent: null,
    labelled_by: 'admin-user',
    labelled_at: '2026-05-04T11:00:00Z',
    ...overrides,
  }
}

/**
 * Constructs a NextRequest to the export endpoint.
 * The route handler reads `request.nextUrl.searchParams`, so we must use NextRequest
 * rather than plain Request.
 */
function makeGetRequest(params: Record<string, string> = {}): NextRequest {
  const url = new URL('http://localhost/api/admin/export')
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v)
  return new NextRequest(url.toString(), { method: 'GET' })
}

// ---------------------------------------------------------------------------
// Part A: exportLabelledEvents
// ---------------------------------------------------------------------------

describe('exportLabelledEvents — empty result', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns an empty array when the DB returns no rows', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    const rows = await exportLabelledEvents(BASE_FILTERS)
    expect(rows).toEqual([])
  })

  it('calls query exactly once', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    await exportLabelledEvents(BASE_FILTERS)
    expect(vi.mocked(query)).toHaveBeenCalledTimes(1)
  })
})

describe('exportLabelledEvents — filter application', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('passes no params when all filters are null', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    await exportLabelledEvents(BASE_FILTERS)
    const [, params] = vi.mocked(query).mock.calls[0]
    expect(params).toEqual([])
  })

  it('includes dateFrom in params when provided', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    await exportLabelledEvents({ ...BASE_FILTERS, dateFrom: '2026-01-01' })
    const [, params] = vi.mocked(query).mock.calls[0]
    expect(params).toContain('2026-01-01')
  })

  it('includes dateTo in params when provided', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    await exportLabelledEvents({ ...BASE_FILTERS, dateTo: '2026-06-01' })
    const [, params] = vi.mocked(query).mock.calls[0]
    expect(params).toContain('2026-06-01')
  })

  it('includes intent in params when provided', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    await exportLabelledEvents({ ...BASE_FILTERS, intent: 'stop' })
    const [, params] = vi.mocked(query).mock.calls[0]
    expect(params).toContain('stop')
  })

  it('includes locale in params when provided', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    await exportLabelledEvents({ ...BASE_FILTERS, locale: 'en-GB' })
    const [, params] = vi.mocked(query).mock.calls[0]
    expect(params).toContain('en-GB')
  })

  it('includes outcome in params when provided', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    await exportLabelledEvents({ ...BASE_FILTERS, outcome: 'confirmed' })
    const [, params] = vi.mocked(query).mock.calls[0]
    expect(params).toContain('confirmed')
  })

  it('includes flag in params when provided', async () => {
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    await exportLabelledEvents({ ...BASE_FILTERS, flag: 'likelyMisparse' })
    const [, params] = vi.mocked(query).mock.calls[0]
    expect(params).toContain('likelyMisparse')
  })

  it('returns rows passed through from the DB', async () => {
    const row = makeExportRow()
    vi.mocked(query).mockResolvedValueOnce({ rows: [row] })
    const rows = await exportLabelledEvents(BASE_FILTERS)
    expect(rows).toHaveLength(1)
    expect(rows[0].event_id).toBe('42')
  })
})

// ---------------------------------------------------------------------------
// Part B: GET /api/admin/export route handler
// ---------------------------------------------------------------------------

describe('GET /api/admin/export — 401 when principal is null', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns 401 when getClientPrincipal returns null', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(null)
    const req = makeGetRequest()
    const res = await GET(req)
    expect(res.status).toBe(401)
  })

  it('returns { error: "Unauthorized" } when principal is null', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(null)
    const req = makeGetRequest()
    const res = await GET(req)
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Unauthorized')
  })
})

describe('GET /api/admin/export — zero rows', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
  })

  it('returns 200 when there are no matching rows', async () => {
    const res = await GET(makeGetRequest())
    expect(res.status).toBe(200)
  })

  it('returns Content-Type text/csv; charset=utf-8', async () => {
    const res = await GET(makeGetRequest())
    const ct = res.headers.get('content-type')
    expect(ct).toContain('text/csv')
    expect(ct).toContain('charset=utf-8')
  })

  it('body starts with UTF-8 BOM bytes (EF BB BF)', async () => {
    const res = await GET(makeGetRequest())
    const buf = await res.arrayBuffer()
    const bytes = new Uint8Array(buf)
    // UTF-8 encoding of U+FEFF is EF BB BF
    expect(bytes[0]).toBe(0xEF)
    expect(bytes[1]).toBe(0xBB)
    expect(bytes[2]).toBe(0xBF)
  })

  it('body contains header row', async () => {
    const res = await GET(makeGetRequest())
    const text = await res.text()
    expect(text).toContain('event_id')
    expect(text).toContain('timestamp')
    expect(text).toContain('locale')
    expect(text).toContain('transcription_anonymised')
    expect(text).toContain('original_intent')
    expect(text).toContain('parser_path')
    expect(text).toContain('outcome')
    expect(text).toContain('flags')
    expect(text).toContain('label_action')
    expect(text).toContain('corrected_intent')
    expect(text).toContain('labelled_by')
    expect(text).toContain('labelled_at')
  })

  it('body has only header row and no data rows when zero matches', async () => {
    const res = await GET(makeGetRequest())
    const text = await res.text()
    // BOM + header + trailing newline => only 1 non-empty line
    const lines = text.split('\n').filter(l => l.trim() !== '')
    expect(lines).toHaveLength(1)
  })
})

describe('GET /api/admin/export — Content-Disposition header', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
  })

  it('Content-Disposition header contains voxio-labelled-events- prefix', async () => {
    const res = await GET(makeGetRequest())
    const cd = res.headers.get('content-disposition')
    expect(cd).toContain('voxio-labelled-events-')
  })

  it('Content-Disposition header contains .csv suffix', async () => {
    const res = await GET(makeGetRequest())
    const cd = res.headers.get('content-disposition')
    expect(cd).toContain('.csv')
  })

  it('Content-Disposition header indicates attachment', async () => {
    const res = await GET(makeGetRequest())
    const cd = res.headers.get('content-disposition')
    expect(cd).toContain('attachment')
  })
})

describe('GET /api/admin/export — CSV RFC 4180 quoting', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('wraps field containing a comma in double quotes', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeExportRow({ transcription_anonymised: 'play, something' })],
    })
    const res = await GET(makeGetRequest())
    const text = await res.text()
    expect(text).toContain('"play, something"')
  })

  it('doubles interior double-quote characters', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeExportRow({ transcription_anonymised: 'say "hello"' })],
    })
    const res = await GET(makeGetRequest())
    const text = await res.text()
    expect(text).toContain('"say ""hello"""')
  })

  it('does not quote a plain field with no special characters', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeExportRow({ label_action: 'correct' })],
    })
    const res = await GET(makeGetRequest())
    const text = await res.text()
    // 'correct' appears as label_action; should not be double-quoted since it has no special chars
    const lines = text.split('\n').filter(l => l.trim() !== '')
    const dataRow = lines[1]
    const cols = dataRow.split(',')
    expect(cols[HEADER_INDEX.label_action]).toBe('correct')
  })
})

describe('GET /api/admin/export — corrected_intent semantics', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('corrected_intent column is empty string when label_action is "correct"', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeExportRow({
        label_action: 'correct',
        corrected_intent: 'playFavorite', // DB may have a value; CSV must blank it
      })],
    })
    const res = await GET(makeGetRequest())
    const text = await res.text()
    const lines = text.split('\n').filter(l => l.trim() !== '')
    const dataRow = lines[1]
    const cols = dataRow.split(',')
    expect(cols[HEADER_INDEX.corrected_intent]).toBe('')
  })

  it('corrected_intent column is empty string when label_action is "discard"', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeExportRow({
        label_action: 'discard',
        corrected_intent: null,
      })],
    })
    const res = await GET(makeGetRequest())
    const text = await res.text()
    const lines = text.split('\n').filter(l => l.trim() !== '')
    const dataRow = lines[1]
    const cols = dataRow.split(',')
    expect(cols[HEADER_INDEX.corrected_intent]).toBe('')
  })

  it('corrected_intent column is non-empty when label_action is "incorrect"', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeExportRow({
        label_action: 'incorrect',
        corrected_intent: 'stop',
      })],
    })
    const res = await GET(makeGetRequest())
    const text = await res.text()
    const lines = text.split('\n').filter(l => l.trim() !== '')
    const dataRow = lines[1]
    const cols = dataRow.split(',')
    expect(cols[HEADER_INDEX.corrected_intent]).toBe('stop')
  })
})

describe('GET /api/admin/export — flags serialization', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('joins flags array with semicolons', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeExportRow({ flags: ['likelyMisparse', 'lowConfidence'] })],
    })
    const res = await GET(makeGetRequest())
    const text = await res.text()
    expect(text).toContain('likelyMisparse;lowConfidence')
  })

  it('produces empty string column for empty flags array', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
    vi.mocked(query).mockResolvedValueOnce({
      rows: [makeExportRow({ flags: [] })],
    })
    const res = await GET(makeGetRequest())
    const text = await res.text()
    const lines = text.split('\n').filter(l => l.trim() !== '')
    const dataRow = lines[1]
    const cols = dataRow.split(',')
    expect(cols[HEADER_INDEX.flags]).toBe('')
  })
})

describe('GET /api/admin/export — UTF-8 BOM', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('response body starts with UTF-8 BOM bytes (EF BB BF)', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
    vi.mocked(query).mockResolvedValueOnce({ rows: [] })
    const res = await GET(makeGetRequest())
    const buf = await res.arrayBuffer()
    const bytes = new Uint8Array(buf)
    // UTF-8 encoding of U+FEFF is EF BB BF
    expect(bytes[0]).toBe(0xEF)
    expect(bytes[1]).toBe(0xBB)
    expect(bytes[2]).toBe(0xBF)
  })
})

describe('GET /api/admin/export — 500 on DB error', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it('returns 500 when the DB query throws', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
    vi.mocked(query).mockRejectedValueOnce(new Error('DB connection refused'))
    const res = await GET(makeGetRequest())
    expect(res.status).toBe(500)
  })

  it('returns { error: "Server error" } when the DB query throws', async () => {
    vi.mocked(getClientPrincipal).mockReturnValue(VALID_PRINCIPAL)
    vi.mocked(query).mockRejectedValueOnce(new Error('DB connection refused'))
    const res = await GET(makeGetRequest())
    const body = await res.json() as Record<string, unknown>
    expect(body.error).toBe('Server error')
  })
})
