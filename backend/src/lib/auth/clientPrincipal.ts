/**
 * clientPrincipal.ts — E-44 T-4403
 *
 * Decodes the Azure Static Web Apps `x-ms-client-principal` header into a
 * typed ClientPrincipal object.
 *
 * Contract:
 *   - Returns null  → header is absent
 *   - Throws Error  → header is present but malformed or missing required fields
 */

export interface ClientPrincipal {
  identityProvider: 'github'
  userId: string
  userDetails: string   // GitHub username
  userRoles: string[]   // includes 'admin' for invited admins
}

/**
 * Decodes the `x-ms-client-principal` header value (base64-encoded JSON) into
 * a typed `ClientPrincipal` object.
 *
 * @param headers - The `Headers` object from a Next.js Route Handler
 *                  (`request.headers`) or Server Component
 *                  (`await import('next/headers').then(m => m.headers())`).
 * @returns The decoded principal, or `null` if the header is absent.
 * @throws {Error} `'Malformed x-ms-client-principal header'` if the header is
 *                 present but cannot be decoded, is not valid JSON, or is
 *                 missing required fields.
 */
export function getClientPrincipal(headers: Headers): ClientPrincipal | null {
  const raw = headers.get('x-ms-client-principal')

  if (raw === null) {
    return null
  }

  let decoded: string
  try {
    decoded = Buffer.from(raw, 'base64').toString('utf-8')
  } catch {
    throw new Error('Malformed x-ms-client-principal header')
  }

  let parsed: unknown
  try {
    parsed = JSON.parse(decoded)
  } catch {
    throw new Error('Malformed x-ms-client-principal header')
  }

  if (
    typeof parsed !== 'object' ||
    parsed === null ||
    typeof (parsed as Record<string, unknown>).userId !== 'string' ||
    typeof (parsed as Record<string, unknown>).userDetails !== 'string' ||
    !Array.isArray((parsed as Record<string, unknown>).userRoles)
  ) {
    throw new Error('Malformed x-ms-client-principal header')
  }

  const obj = parsed as Record<string, unknown>

  return {
    identityProvider: 'github',
    userId: obj.userId as string,
    userDetails: obj.userDetails as string,
    userRoles: obj.userRoles as string[],
  }
}
