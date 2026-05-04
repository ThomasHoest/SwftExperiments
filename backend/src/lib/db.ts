import { neon, NeonQueryFunction, type FullQueryResults } from '@neondatabase/serverless'

let _neon: NeonQueryFunction<false, false> | null = null

function getClient(): NeonQueryFunction<false, false> {
  if (!_neon) {
    if (!process.env.DATABASE_URL) {
      throw new Error('DATABASE_URL environment variable is not set')
    }
    _neon = neon(process.env.DATABASE_URL)
  }
  return _neon
}

export const sql: NeonQueryFunction<false, false> = (...args) =>
  (getClient() as (...a: typeof args) => ReturnType<NeonQueryFunction<false, false>>)(...args)

export async function query<T = Record<string, unknown>>(
  text: string,
  params?: unknown[]
): Promise<{ rows: T[] }> {
  const result = (await getClient()(
    text,
    params as never[],
    { fullResults: true }
  )) as FullQueryResults<false>
  return { rows: result.rows as T[] }
}
