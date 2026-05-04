import { neon, NeonQueryFunction, type FullQueryResults } from '@neondatabase/serverless'

const _neon: NeonQueryFunction<false, false> = neon(process.env.DATABASE_URL!)

/**
 * Tagged-template query helper — returns rows directly as T[].
 * Use for static queries only.
 *
 * Example: const rows = await sql`SELECT * FROM events`
 */
export const sql: NeonQueryFunction<false, false> = _neon

/**
 * Parameterised query helper — wraps neon(text, params, { fullResults: true })
 * so dynamic queries can safely build parameterised strings.
 *
 * Returns `{ rows: T[] }` matching the pg-compatible FullQueryResults shape.
 * Destructure `.rows` at the call site.
 *
 * Example: const { rows } = await query<Row>('SELECT * FROM events WHERE id = $1', [id])
 */
export async function query<T = Record<string, unknown>>(
  text: string,
  params?: unknown[]
): Promise<{ rows: T[] }> {
  const result = (await _neon(
    text,
    params as never[],
    { fullResults: true }
  )) as FullQueryResults<false>
  return { rows: result.rows as T[] }
}
