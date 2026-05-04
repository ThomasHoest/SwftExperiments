import { listEvents } from '@/lib/queries/events'
import { filtersFromSearchParams, filtersToSearchParams } from '@/lib/filters/events'
import Link from 'next/link'

interface Props {
  searchParams: Promise<Record<string, string>> | Record<string, string>
}

export default async function EventsPage({ searchParams }: Props) {
  const sp = await searchParams
  const params = new URLSearchParams(sp as Record<string, string>)
  const filters = filtersFromSearchParams(params)
  const { rows, nextCursor } = await listEvents(filters)

  const nextParams = nextCursor
    ? new URLSearchParams({ ...Object.fromEntries(params), cursor: nextCursor })
    : null
  const exportParams = filtersToSearchParams({ ...filters, cursor: null })

  return (
    <div>
      {/* Filter form */}
      <form method="GET" className="flex flex-wrap gap-3 mb-6">
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
        <select
          name="parserPath"
          defaultValue={filters.parserPath ?? ''}
          className="border rounded px-2 py-1 text-sm"
        >
          <option value="">All parsers</option>
          {['PersonalisationAlias', 'PersonalisationMemory', 'FoundationModels', 'NLModel', 'KeywordRegex', 'Unknown'].map(p => (
            <option key={p} value={p}>{p}</option>
          ))}
        </select>
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
        <input
          name="locale"
          defaultValue={filters.locale ?? ''}
          placeholder="Locale (en-GB)"
          className="border rounded px-2 py-1 text-sm"
        />
        <select
          name="flag"
          defaultValue={filters.flag ?? ''}
          className="border rounded px-2 py-1 text-sm"
        >
          <option value="">Any flag</option>
          {['likelyMisparse', 'recoverableUnknown', 'broadcast'].map(f => (
            <option key={f} value={f}>{f}</option>
          ))}
        </select>
        <input
          name="transcriptionContains"
          defaultValue={filters.transcriptionContains ?? ''}
          placeholder="Transcription contains…"
          className="border rounded px-2 py-1 text-sm"
        />
        <button type="submit" className="bg-gray-800 text-white px-3 py-1 rounded text-sm">
          Filter
        </button>
        <a
          href={`/admin/export?${exportParams}`}
          className="ml-auto text-sm text-blue-600 underline self-center"
        >
          Export CSV
        </a>
      </form>

      {/* Events table */}
      <table className="w-full text-sm border-collapse">
        <thead>
          <tr className="border-b">
            <th className="text-left py-2 pr-4">Time</th>
            <th className="text-left py-2 pr-4">Transcription</th>
            <th className="text-left py-2 pr-4">Intent</th>
            <th className="text-left py-2 pr-4">Parser</th>
            <th className="text-left py-2 pr-4">Outcome</th>
            <th className="text-left py-2 pr-4">Locale</th>
            <th className="text-left py-2 pr-4">Flags</th>
            <th className="text-left py-2">Label</th>
          </tr>
        </thead>
        <tbody>
          {rows.map(row => (
            <tr key={String(row.id)} className="border-b hover:bg-gray-50">
              <td className="py-1 pr-4 text-gray-500 whitespace-nowrap">
                <Link href={`/admin/events/${row.id}?${params}`} className="hover:underline">
                  {new Date(row.received_at).toLocaleString()}
                </Link>
              </td>
              <td className="py-1 pr-4 max-w-xs truncate" title={row.transcription_anonymised}>
                {row.transcription_anonymised.slice(0, 80)}
                {row.transcription_anonymised.length > 80 ? '…' : ''}
              </td>
              <td className="py-1 pr-4">{row.intent}</td>
              <td className="py-1 pr-4">{row.parser_path}</td>
              <td className="py-1 pr-4">{row.outcome}</td>
              <td className="py-1 pr-4">{row.locale}</td>
              <td className="py-1 pr-4">
                {(row.flags as string[]).map(f => (
                  <span key={f} className="inline-block bg-gray-200 rounded px-1 text-xs mr-1">
                    {f}
                  </span>
                ))}
              </td>
              <td className="py-1">
                {row.label_action === 'correct' && (
                  <span className="text-green-600" title="Correct">&#10003;</span>
                )}
                {row.label_action === 'incorrect' && (
                  <span className="text-red-600" title="Incorrect">&#10007;</span>
                )}
                {row.label_action === 'discard' && (
                  <span className="text-gray-400" title="Discard">&#8211;</span>
                )}
                {!row.label_action && (
                  <span className="text-gray-200">&#9675;</span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {/* Pagination */}
      <div className="flex justify-between mt-4">
        <a href="javascript:history.back()" className="text-sm text-gray-600 underline">
          &larr; Previous
        </a>
        {nextParams && (
          <Link href={`/admin/events?${nextParams}`} className="text-sm text-gray-600 underline">
            Next &rarr;
          </Link>
        )}
      </div>
    </div>
  )
}
