import { neon } from '@neondatabase/serverless'

// Prod guard — refuse to seed production databases
if (process.env.NODE_ENV === 'production') {
  console.error('Refusing to seed production')
  process.exit(1)
}

const dbUrl = process.env.DATABASE_URL
if (!dbUrl) {
  console.error('DATABASE_URL is not set')
  process.exit(1)
}

try {
  const urlObj = new URL(dbUrl)
  const hostname = urlObj.hostname.toLowerCase()
  if (hostname.includes('prod') || hostname.includes('production')) {
    console.error(`Refusing to seed — hostname "${hostname}" looks like production`)
    process.exit(1)
  }
} catch {
  console.error('DATABASE_URL is not a valid URL')
  process.exit(1)
}

const sql = neon(dbUrl)

// ── Helpers ──────────────────────────────────────────────────────────────────

function randomUUID(): string {
  // Node 20+ has crypto.randomUUID() globally
  return crypto.randomUUID()
}

function randomFrom<T>(arr: readonly T[]): T {
  return arr[Math.floor(Math.random() * arr.length)]
}

function randomDate(daysAgo: number): string {
  const ms = Date.now() - Math.random() * daysAgo * 24 * 60 * 60 * 1000
  return new Date(ms).toISOString()
}

// ── Seed data constants ───────────────────────────────────────────────────────

const APP_VERSIONS = ['1.0.0', '1.1.0', '1.2.0']
const MODEL_VERSIONS = ['whisper-tiny', 'whisper-base', 'whisper-small']
const LOCALES = ['en-US', 'en-GB', 'da-DK', 'de-DE', 'fr-FR']
const INTENTS = [
  'playback.play',
  'playback.pause',
  'playback.stop',
  'volume.set',
  'volume.up',
  'volume.down',
  'source.select',
  'favorite.play',
  'unknown',
]
const PARSER_PATHS = [
  'keyword→playback',
  'keyword→volume',
  'keyword→source',
  'keyword→favorite',
  'nlp→openai',
  'fallback',
]
const OUTCOMES = ['success', 'partial', 'failure', 'no_match']
const ALL_FLAGS = ['low_confidence', 'ambiguous', 'retried', 'fallback_used', 'timeout']
const LABEL_ACTIONS = ['correct', 'incorrect', 'discard'] as const

// ── Main ──────────────────────────────────────────────────────────────────────

async function seed(): Promise<void> {
  console.log('Seeding dev database...')

  // ── 1. Insert 5 devices ────────────────────────────────────────────────────
  const deviceIds: string[] = []
  for (let i = 0; i < 5; i++) {
    const id = randomUUID()
    deviceIds.push(id)
    const firstSeen = randomDate(90)
    const lastSeen = randomDate(7)
    const lastUpload = randomDate(1)
    await sql`
      INSERT INTO devices (device_id, first_seen_at, last_seen_at, last_upload_at, app_version, model_version, locale)
      VALUES (
        ${id}::uuid,
        ${firstSeen}::timestamptz,
        ${lastSeen}::timestamptz,
        ${lastUpload}::timestamptz,
        ${randomFrom(APP_VERSIONS)},
        ${randomFrom(MODEL_VERSIONS)},
        ${randomFrom(LOCALES)}
      )
    `
  }
  console.log(`  Inserted ${deviceIds.length} devices`)

  // ── 2. Insert ~500 events spread across those devices ──────────────────────
  const insertedEventIds: bigint[] = []
  const EVENT_COUNT = 500
  for (let i = 0; i < EVENT_COUNT; i++) {
    const deviceId = randomFrom(deviceIds)
    const clientTimestamp = randomDate(30)
    const appVersion = randomFrom(APP_VERSIONS)
    const modelVersion = randomFrom(MODEL_VERSIONS)
    const locale = randomFrom(LOCALES)
    const transcription = `[redacted-${Math.floor(Math.random() * 10000)}]`
    const intent = randomFrom(INTENTS)
    const parserPath = randomFrom(PARSER_PATHS)
    const outcome = randomFrom(OUTCOMES)

    // Build a small random set of flags
    const flags: string[] = ALL_FLAGS.filter(() => Math.random() < 0.15)
    const slotsJson = JSON.stringify(
      intent.startsWith('volume') ? { level: Math.floor(Math.random() * 100) } : {}
    )

    const rows = await sql`
      INSERT INTO events (
        device_id, client_timestamp, app_version, model_version, locale,
        transcription_anonymised, intent, slots_anonymised, parser_path, outcome, flags
      )
      VALUES (
        ${deviceId}::uuid,
        ${clientTimestamp}::timestamptz,
        ${appVersion},
        ${modelVersion},
        ${locale},
        ${transcription},
        ${intent},
        ${slotsJson}::jsonb,
        ${parserPath},
        ${outcome},
        ${flags}::text[]
      )
      RETURNING id
    `
    if (rows.length > 0 && rows[0].id != null) {
      insertedEventIds.push(BigInt(rows[0].id as number))
    }
  }
  console.log(`  Inserted ${insertedEventIds.length} events`)

  // ── 3. Label ~10% of events ────────────────────────────────────────────────
  const labelCount = Math.ceil(insertedEventIds.length * 0.1)
  // Shuffle and pick first labelCount unique event IDs
  const shuffled = [...insertedEventIds].sort(() => Math.random() - 0.5)
  const toLabel = shuffled.slice(0, labelCount)

  let labelledCount = 0
  for (const eventId of toLabel) {
    const action = randomFrom(LABEL_ACTIONS)
    const correctedIntent = action === 'incorrect' ? randomFrom(INTENTS) : null
    const labelledBy = `seed-script-user-${Math.floor(Math.random() * 3) + 1}`
    const labelledAt = randomDate(14)

    await sql`
      INSERT INTO labels (event_id, action, corrected_intent, labelled_by, labelled_at)
      VALUES (
        ${String(eventId)}::bigint,
        ${action},
        ${correctedIntent},
        ${labelledBy},
        ${labelledAt}::timestamptz
      )
    `
    labelledCount++
  }
  console.log(`  Inserted ${labelledCount} labels`)

  // ── 4. Print final row counts ──────────────────────────────────────────────
  const [deviceRow] = await sql`SELECT COUNT(*)::int AS count FROM devices`
  const [eventRow] = await sql`SELECT COUNT(*)::int AS count FROM events`
  const [labelRow] = await sql`SELECT COUNT(*)::int AS count FROM labels`

  console.log('\nFinal row counts:')
  console.log(`  devices: ${(deviceRow as { count: number }).count}`)
  console.log(`  events:  ${(eventRow as { count: number }).count}`)
  console.log(`  labels:  ${(labelRow as { count: number }).count}`)
  console.log('\nSeed complete.')
}

seed().catch((err: unknown) => {
  console.error('Seed failed:', err)
  process.exit(1)
})
