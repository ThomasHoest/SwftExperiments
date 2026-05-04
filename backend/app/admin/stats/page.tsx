import { getStats } from '@/lib/queries/stats'

interface Props {
  searchParams: Promise<Record<string, string>>
}

function defaultDateRange(): { dateFrom: string; dateTo: string } {
  const dateTo   = new Date().toISOString().slice(0, 10)
  const dateFrom = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10)
  return { dateFrom, dateTo }
}

export default async function StatsPage({ searchParams }: Props) {
  const sp = await searchParams
  const params = new URLSearchParams(sp as Record<string, string>)

  const defaults = defaultDateRange()
  const dateFrom = params.get('dateFrom') || defaults.dateFrom
  const dateTo   = params.get('dateTo')   || defaults.dateTo

  const stats = await getStats(dateFrom, dateTo)

  return (
    <div>
      <h1 className="text-xl font-semibold mb-6">Stats</h1>

      {/* Date range filter */}
      <form method="GET" className="flex items-center gap-3 mb-8 p-4 border rounded bg-white">
        <label className="text-sm text-gray-700 font-medium">Date range</label>
        <input
          name="dateFrom"
          defaultValue={dateFrom}
          type="date"
          className="border rounded px-2 py-1 text-sm"
        />
        <span className="text-sm text-gray-500">to</span>
        <input
          name="dateTo"
          defaultValue={dateTo}
          type="date"
          className="border rounded px-2 py-1 text-sm"
        />
        <button type="submit" className="bg-gray-800 text-white px-3 py-1 rounded text-sm">
          Apply
        </button>
        <span className="text-xs text-gray-400 ml-2">
          Showing: {dateFrom} to {dateTo}
        </span>
      </form>

      {/* Summary tiles */}
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4 mb-8">
        <Tile label="Total events"   value={stats.totalEvents} />
        <Tile label="Distinct devices" value={stats.distinctDevices} />
        <Tile label="Labelled events"  value={stats.labelledCount} />
        <Tile label="Likely misparses" value={stats.likelyMisparseCount} />
      </div>

      {/* Labels by action */}
      <section className="mb-8">
        <h2 className="text-base font-semibold mb-3">Labels by action</h2>
        <div className="grid grid-cols-3 gap-4 max-w-lg">
          <Tile label="Correct"   value={stats.labelsByAction.correct}   />
          <Tile label="Incorrect" value={stats.labelsByAction.incorrect} />
          <Tile label="Discard"   value={stats.labelsByAction.discard}   />
        </div>
      </section>

      {/* Breakdown tables — two column layout */}
      <div className="grid grid-cols-1 gap-8 sm:grid-cols-2">
        <BreakdownTable title="By intent"      data={stats.byIntent}     />
        <BreakdownTable title="By outcome"     data={stats.byOutcome}    />
        <BreakdownTable title="By parser path" data={stats.byParserPath} />
        <BreakdownTable title="By locale"      data={stats.byLocale}     />
      </div>
    </div>
  )
}

function Tile({ label, value }: { label: string; value: number }) {
  return (
    <div className="p-4 border rounded bg-white">
      <p className="text-2xl font-bold text-gray-900">{value.toLocaleString()}</p>
      <p className="text-sm text-gray-500 mt-1">{label}</p>
    </div>
  )
}

function BreakdownTable({ title, data }: { title: string; data: Record<string, number> }) {
  const entries = Object.entries(data).sort((a, b) => b[1] - a[1])
  return (
    <div>
      <h2 className="text-base font-semibold mb-2">{title}</h2>
      {entries.length === 0 ? (
        <p className="text-sm text-gray-400">No data</p>
      ) : (
        <table className="w-full text-sm border-collapse">
          <thead>
            <tr className="border-b">
              <th className="text-left py-1 pr-4">Value</th>
              <th className="text-right py-1">Count</th>
            </tr>
          </thead>
          <tbody>
            {entries.map(([key, count]) => (
              <tr key={key} className="border-b hover:bg-gray-50">
                <td className="py-1 pr-4 text-gray-700">{key || <em className="text-gray-400">(empty)</em>}</td>
                <td className="py-1 text-right text-gray-900">{count.toLocaleString()}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}
