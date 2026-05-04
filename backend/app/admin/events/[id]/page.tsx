import { getEventById } from '@/lib/queries/events'
import LabelForm from './LabelForm'
import Link from 'next/link'
import { notFound } from 'next/navigation'

interface Props {
  params: Promise<{ id: string }>
  searchParams: Promise<Record<string, string>>
}

export default async function EventDetailPage({ params, searchParams }: Props) {
  const { id } = await params
  const sp = await searchParams
  const backParams = new URLSearchParams(sp as Record<string, string>)

  const event = await getEventById(parseInt(id, 10))
  if (!event) notFound()

  return (
    <div className="max-w-3xl">
      <Link href={`/admin/events?${backParams}`} className="text-sm text-blue-600 underline mb-4 block">
        &larr; Back to events
      </Link>

      <h1 className="text-xl font-semibold mb-4">Event #{id}</h1>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm mb-4">
        <dt className="text-gray-500">Received at</dt>   <dd>{event.received_at}</dd>
        <dt className="text-gray-500">Client time</dt>   <dd>{event.client_timestamp}</dd>
        <dt className="text-gray-500">Device</dt>        <dd className="font-mono text-xs">{event.device_id}</dd>
        <dt className="text-gray-500">Intent</dt>        <dd>{event.intent}</dd>
        <dt className="text-gray-500">Parser path</dt>   <dd>{event.parser_path}</dd>
        <dt className="text-gray-500">Outcome</dt>       <dd>{event.outcome}</dd>
        <dt className="text-gray-500">Locale</dt>        <dd>{event.locale}</dd>
        <dt className="text-gray-500">App version</dt>   <dd>{event.app_version}</dd>
        <dt className="text-gray-500">Model version</dt> <dd>{event.model_version}</dd>
        <dt className="text-gray-500">Flags</dt>         <dd>{(event.flags as string[]).join(', ') || '—'}</dd>
      </dl>

      <div className="mb-4">
        <p className="text-gray-500 text-sm mb-1">Transcription</p>
        <pre className="bg-gray-100 rounded p-3 text-sm font-mono whitespace-pre-wrap">
          {event.transcription_anonymised}
        </pre>
      </div>

      <div className="mb-4">
        <p className="text-gray-500 text-sm mb-1">Slots</p>
        <pre className="bg-gray-100 rounded p-3 text-sm font-mono">
          {JSON.stringify(event.slots_anonymised, null, 2)}
        </pre>
      </div>

      {event.label_action && (
        <div className="mb-4 p-3 bg-blue-50 rounded text-sm">
          <p>
            <strong>Current label:</strong> {event.label_action}
            {event.label_corrected_intent ? ` → ${event.label_corrected_intent}` : ''}
          </p>
          <p className="text-gray-500">
            By {event.label_labelled_by} at {event.label_labelled_at}
          </p>
        </div>
      )}

      <LabelForm
        eventId={id}
        currentAction={event.label_action}
        currentCorrectedIntent={event.label_corrected_intent}
      />
    </div>
  )
}
