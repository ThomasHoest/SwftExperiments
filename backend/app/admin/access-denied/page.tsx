export default function AccessDeniedPage() {
  return (
    <div className="max-w-lg mx-auto mt-16 px-4">
      <h1 className="text-2xl font-semibold text-gray-900 mb-4">Access Denied</h1>
      <p className="text-gray-700 mb-4">
        Your GitHub account does not have admin access to Voxio Telemetry.
        Contact the engineering lead to request access.
      </p>
      <a href="/.auth/logout?post_logout_redirect_uri=/" className="text-blue-600 underline">
        Sign out and try a different account
      </a>
    </div>
  )
}
