import { headers } from 'next/headers'
import { redirect } from 'next/navigation'
import { getClientPrincipal } from '@/lib/auth/clientPrincipal'

export default async function AdminPage() {
  let principal = null
  try {
    const h = await headers()
    principal = getClientPrincipal(h)
  } catch {
    // Malformed header treated as unauthenticated
  }

  if (principal?.userRoles.includes('admin')) {
    redirect('/admin/events')
  }

  const isSignedIn = principal !== null

  return (
    <div className="max-w-lg mx-auto mt-16 px-4">
      <h1 className="text-2xl font-semibold text-gray-900 mb-4">Voxio Telemetry Admin</h1>

      {isSignedIn ? (
        <div>
          <p className="text-gray-700 mb-4">
            Your GitHub account (<strong>{principal?.userDetails}</strong>) does not have admin access.
            Contact the engineering lead to request access.
          </p>
          <a href="/.auth/logout?post_logout_redirect_uri=/" className="text-blue-600 underline">
            Sign out
          </a>
        </div>
      ) : (
        <div>
          <p className="text-gray-700 mb-6">
            Sign in with your invited GitHub account to access the admin dashboard.
          </p>
          <a
            href="/.auth/login/github"
            className="inline-block bg-gray-900 text-white px-4 py-2 rounded hover:bg-gray-700"
          >
            Sign in with GitHub
          </a>
          <div className="mt-8 p-4 bg-gray-100 rounded text-sm text-gray-600">
            <strong>Privacy notice:</strong> This dashboard provides access to anonymised telemetry data.
            All transcriptions are anonymised before storage. No personally identifiable information (PII)
            is stored. Device identifiers are random UUIDs with no link to user accounts.
            Data is processed under applicable GDPR provisions for legitimate interest in product quality.
          </div>
        </div>
      )}
    </div>
  )
}
