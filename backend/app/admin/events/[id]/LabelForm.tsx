'use client'

import { useState } from 'react'
import { CANONICAL_INTENTS } from '@/lib/constants/intents'

interface Props {
  eventId: string
  currentAction: string | null
  currentCorrectedIntent: string | null
}

export default function LabelForm({ eventId, currentAction, currentCorrectedIntent }: Props) {
  const [action, setAction] = useState<string>(currentAction ?? '')
  const [correctedIntent, setCorrectedIntent] = useState<string>(currentCorrectedIntent ?? '')
  const [status, setStatus] = useState<string>('')

  async function submit() {
    const body: Record<string, string> = { action }
    if (action === 'incorrect') body.correctedIntent = correctedIntent
    const res = await fetch(`/api/admin/events/${eventId}/label`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    })
    if (res.ok) {
      setStatus('Label saved.')
    } else if (res.status === 404) {
      setStatus('Event no longer exists. It may have been deleted.')
    } else {
      setStatus('Error saving label.')
    }
  }

  return (
    <div className="mt-6 p-4 border rounded bg-gray-50">
      <h2 className="font-semibold mb-3">Label this event</h2>
      <div className="flex gap-2 mb-3">
        {(['correct', 'incorrect', 'discard'] as const).map(a => (
          <button
            key={a}
            onClick={() => setAction(a)}
            className={`px-3 py-1 rounded text-sm border ${
              action === a ? 'bg-gray-800 text-white' : 'bg-white text-gray-700'
            }`}
          >
            {a.charAt(0).toUpperCase() + a.slice(1)}
          </button>
        ))}
      </div>

      {action === 'incorrect' && (
        <div className="mb-3">
          <label htmlFor="correctedIntent" className="text-sm text-gray-600 block mb-1">
            Corrected intent
          </label>
          <select
            id="correctedIntent"
            value={correctedIntent}
            onChange={e => setCorrectedIntent(e.target.value)}
            className="border rounded px-2 py-1 text-sm"
          >
            <option value="">Select intent…</option>
            {CANONICAL_INTENTS.map(i => (
              <option key={i} value={i}>{i}</option>
            ))}
          </select>
        </div>
      )}

      <button
        onClick={submit}
        disabled={!action || (action === 'incorrect' && !correctedIntent)}
        className="bg-gray-800 text-white px-3 py-1 rounded text-sm disabled:opacity-50"
      >
        Save label
      </button>

      {status && <p className="mt-2 text-sm text-gray-600">{status}</p>}
    </div>
  )
}
