import { headers } from 'next/headers'
import { getClientPrincipal } from '@/lib/auth/clientPrincipal'
import Link from 'next/link'

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  let username = 'Admin'
  try {
    const h = await headers()
    const principal = getClientPrincipal(h)
    if (principal) username = principal.userDetails
  } catch {
    // Malformed header — fall back to generic label
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white border-b border-gray-200 px-6 py-3 flex items-center justify-between">
        <div className="flex items-center gap-6">
          <span className="font-semibold text-gray-900">Voxio Admin</span>
          <Link href="/admin/events"   className="text-sm text-gray-700 hover:text-gray-900">Events</Link>
          <Link href="/admin/stats"    className="text-sm text-gray-700 hover:text-gray-900">Stats</Link>
          <Link href="/admin/export"   className="text-sm text-gray-700 hover:text-gray-900">Export</Link>
          <Link href="/admin/deletion" className="text-sm text-gray-700 hover:text-gray-900">Deletion</Link>
        </div>
        <div className="flex items-center gap-4">
          <span className="text-sm text-gray-600">{username}</span>
          <a href="/.auth/logout?post_logout_redirect_uri=/" className="text-sm text-gray-700 hover:text-gray-900">
            Sign out
          </a>
        </div>
      </nav>
      <main className="p-6">{children}</main>
    </div>
  )
}
