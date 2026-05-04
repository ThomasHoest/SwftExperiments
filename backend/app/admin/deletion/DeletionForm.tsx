'use client'

import { useState } from 'react'

type Status = 'idle' | 'pending' | 'success' | 'error'

interface DeletedCounts {
  devices: number
  events: number
  labels: number
}

interface SuccessResult {
  counts: DeletedCounts
  submittedDeviceId: string
}

export default function DeletionForm() {
  const [deviceId, setDeviceId]         = useState<string>('')
  const [confirmation, setConfirmation] = useState<string>('')
  const [status, setStatus]             = useState<Status>('idle')
  const [result, setResult]             = useState<SuccessResult | null>(null)
  const [clientError, setClientError]   = useState<string | null>(null)

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setClientError(null)
    setResult(null)

    if (confirmation !== 'DELETE') {
      setClientError('You must type DELETE (all caps) to confirm.')
      return
    }

    setStatus('pending')

    // Capture deviceId before clearing inputs
    const submittedDeviceId = deviceId

    try {
      const res = await fetch('/api/admin/deletion', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ deviceId: submittedDeviceId, confirmation }),
      })

      if (res.ok) {
        const data = await res.json() as { deleted: DeletedCounts }
        setResult({ counts: data.deleted, submittedDeviceId })
        setStatus('success')
        setDeviceId('')
        setConfirmation('')
      } else {
        const data = await res.json() as { error?: string }
        setClientError(data.error ?? 'Deletion failed. Please try again or contact engineering.')
        setStatus('idle')
      }
    } catch {
      setStatus('error')
    }
  }

  const successMessage = result
    ? result.counts.devices === 0
      ? `No data found for device ${result.submittedDeviceId}. Nothing to delete.`
      : `Deleted ${result.counts.events} events and ${result.counts.labels} labels for device ${result.submittedDeviceId}.`
    : null

  return (
    <form onSubmit={handleSubmit} className="max-w-lg p-6 border rounded bg-white space-y-4">
      <div>
        <label htmlFor="deviceId" className="block text-sm font-medium text-gray-700 mb-1">
          Device ID (UUID)
        </label>
        <input
          id="deviceId"
          type="text"
          value={deviceId}
          onChange={e => setDeviceId(e.target.value)}
          placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
          className="w-full border rounded px-3 py-2 text-sm font-mono"
          required
        />
      </div>

      <div>
        <label htmlFor="confirmation" className="block text-sm font-medium text-gray-700 mb-1">
          Type <strong>DELETE</strong> to confirm
        </label>
        <input
          id="confirmation"
          type="text"
          value={confirmation}
          onChange={e => setConfirmation(e.target.value)}
          placeholder="DELETE"
          className="w-full border rounded px-3 py-2 text-sm"
          required
        />
      </div>

      {clientError && (
        <p className="text-sm text-red-600">{clientError}</p>
      )}

      {status === 'success' && successMessage && (
        <p className="text-sm text-green-700">{successMessage}</p>
      )}

      {status === 'error' && (
        <p className="text-sm text-red-600">
          Deletion failed. Please try again or contact engineering.
        </p>
      )}

      <button
        type="submit"
        disabled={status === 'pending' || !deviceId}
        className="bg-red-700 text-white px-4 py-2 rounded text-sm disabled:opacity-50"
      >
        {status === 'pending' ? 'Deleting…' : 'Delete device data'}
      </button>
    </form>
  )
}
