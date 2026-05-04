import DeletionForm from './DeletionForm'

export default function DeletionPage() {
  return (
    <div>
      <h1 className="text-xl font-semibold mb-2">Delete Device Data</h1>
      <p className="text-sm text-gray-600 mb-6 max-w-prose">
        Permanently delete all data for a device ID. This removes the device record, all
        associated events, and all labels attached to those events. This action cannot be undone.
      </p>
      <DeletionForm />
    </div>
  )
}
