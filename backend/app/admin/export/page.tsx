import { filtersFromSearchParams } from '@/lib/filters/events'

interface Props {
  searchParams: Promise<Record<string, string>>
}

export default async function ExportPage({ searchParams }: Props) {
  const sp = await searchParams
  const params = new URLSearchParams(sp as Record<string, string>)
  const filters = filtersFromSearchParams(params)

  // Build the download URL using only the export-relevant filter fields
  const exportParams = new URLSearchParams()
  if (filters.dateFrom) exportParams.set('dateFrom', filters.dateFrom)
  if (filters.dateTo)   exportParams.set('dateTo', filters.dateTo)
  if (filters.intent)   exportParams.set('intent', filters.intent)
  if (filters.locale)   exportParams.set('locale', filters.locale)
  if (filters.outcome)  exportParams.set('outcome', filters.outcome)

  return (
    <div>
      <h1 className="text-xl font-semibold mb-6">Export Labelled Events (CSV)</h1>

      {/* Filter form — GET submits to this page to preview filter values */}
      <form method="GET" className="flex flex-wrap gap-3 mb-8 p-4 border rounded bg-white">
        <div className="w-full text-sm font-medium text-gray-700 mb-1">Filter events to export</div>
        <input
          name="dateFrom"
          defaultValue={filters.dateFrom ?? ''}
          type="date"
          placeholder="From"
          className="border rounded px-2 py-1 text-sm"
        />
        <input
          name="dateTo"
          defaultValue={filters.dateTo ?? ''}
          type="date"
          placeholder="To"
          className="border rounded px-2 py-1 text-sm"
        />
        <input
          name="intent"
          defaultValue={filters.intent ?? ''}
          placeholder="Intent"
          className="border rounded px-2 py-1 text-sm"
        />
        <input
          name="locale"
          defaultValue={filters.locale ?? ''}
          placeholder="Locale (en-GB)"
          className="border rounded px-2 py-1 text-sm"
        />
        <select
          name="outcome"
          defaultValue={filters.outcome ?? ''}
          className="border rounded px-2 py-1 text-sm"
        >
          <option value="">All outcomes</option>
          {['confirmed', 'cancelled', 'timedOut', 'unknown'].map(o => (
            <option key={o} value={o}>{o}</option>
          ))}
        </select>
        <button type="submit" className="bg-gray-800 text-white px-3 py-1 rounded text-sm">
          Update filters
        </button>
      </form>

      {/* Download form — GET to the API route triggers a CSV download */}
      <form action="/api/admin/export" method="GET">
        {filters.dateFrom && <input type="hidden" name="dateFrom" value={filters.dateFrom} />}
        {filters.dateTo   && <input type="hidden" name="dateTo"   value={filters.dateTo} />}
        {filters.intent   && <input type="hidden" name="intent"   value={filters.intent} />}
        {filters.locale   && <input type="hidden" name="locale"   value={filters.locale} />}
        {filters.outcome  && <input type="hidden" name="outcome"  value={filters.outcome} />}
        <div className="p-4 border rounded bg-white flex items-center gap-4">
          <div>
            <p className="text-sm text-gray-700 font-medium mb-1">Download filtered export</p>
            <p className="text-xs text-gray-500">
              Only labelled events are included. Applies the filters selected above.
            </p>
            {exportParams.toString() && (
              <p className="text-xs text-gray-400 mt-1">
                Active filters: {exportParams.toString()}
              </p>
            )}
          </div>
          <button
            type="submit"
            className="ml-auto bg-gray-800 text-white px-4 py-2 rounded text-sm whitespace-nowrap"
          >
            Download CSV
          </button>
        </div>
      </form>
    </div>
  )
}
