/**
 * Integration tests — cascade-delete behaviour (T-4704)
 *
 * Verifies that deleting a row from `devices` cascades to `events` and
 * `labels` via the ON DELETE CASCADE foreign-key constraints defined in the
 * migrations, and that the DELETE route handler returns the expected counts.
 *
 * Prerequisites
 * - DATABASE_URL must be set to a live Neon Postgres branch.
 * - The suite is skipped entirely when DATABASE_URL is absent so it never
 *   blocks a local unit-test run.
 *
 * Run with:
 *   DATABASE_URL=<url> TELEMETRY_API_KEY=test-key \
 *   pnpm vitest run tests/integration/cascade-delete.test.ts
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { neon, type NeonQueryFunction } from '@neondatabase/serverless'

// ---------------------------------------------------------------------------
// Deterministic test constants — hard-coded so cleanup is always reliable
// ---------------------------------------------------------------------------

const DEVICE_ID = 'a1b2c3d4-0001-0002-0003-test00000001'

// Five event surrogate IDs are not known ahead of time (BIGSERIAL), so we
// identify them via the device_id FK instead. The labels reference two of the
// five events, resolved at runtime after insertion.

const TEST_APP_VERSION  = 'test_cascade_delete_v0.0.1'
const TEST_MODEL        = 'test_cascade_delete_model'
const TEST_LOCALE       = 'test_cascade_delete_en'
const TEST_INTENT       = 'test_cascade_delete_intent'
const TEST_TRANSCRIPT   = 'test cascade delete transcript'

// ---------------------------------------------------------------------------
// Conditional skip — skip the entire suite if DATABASE_URL is absent
// ---------------------------------------------------------------------------

const DATABASE_URL = process.env.DATABASE_URL

const describeIf = DATABASE_URL
  ? describe
  : describe.skip

// ---------------------------------------------------------------------------
// Module-level sql handle — initialised lazily inside beforeAll
// ---------------------------------------------------------------------------

let sql: NeonQueryFunction<false, false>

// ---------------------------------------------------------------------------
// Helper: delete the device row (cascade removes events + labels)
// ---------------------------------------------------------------------------

async function cleanUp(): Promise<void> {
  if (!sql) return
  await sql`DELETE FROM devices WHERE device_id = ${DEVICE_ID}`
}

// ---------------------------------------------------------------------------
// Helper: insert the full fixture (1 device, 5 events, 3 labels)
// Returns the IDs of the two events that get labels.
// ---------------------------------------------------------------------------

async function insertFixture(): Promise<{ labelledEventIds: bigint[] }> {
  const now = new Date().toISOString()

  // 1 device
  await sql`
    INSERT INTO devices (
      device_id,
      first_seen_at,
      last_seen_at,
      last_upload_at,
      app_version,
      model_version,
      locale
    ) VALUES (
      ${DEVICE_ID},
      ${now},
      ${now},
      ${now},
      ${TEST_APP_VERSION},
      ${TEST_MODEL},
      ${TEST_LOCALE}
    )
    ON CONFLICT (device_id) DO NOTHING
  `

  // 5 events
  const insertedEventIds: bigint[] = []
  for (let i = 0; i < 5; i++) {
    const rows = await sql`
      INSERT INTO events (
        device_id,
        received_at,
        client_timestamp,
        app_version,
        model_version,
        locale,
        transcription_anonymised,
        intent,
        slots_anonymised,
        parser_path,
        outcome,
        flags
      ) VALUES (
        ${DEVICE_ID},
        ${now},
        ${now},
        ${TEST_APP_VERSION},
        ${TEST_MODEL},
        ${TEST_LOCALE},
        ${TEST_TRANSCRIPT},
        ${TEST_INTENT},
        ${{ slot: `value_${i}` }},
        ${'test_cascade_delete_parser'},
        ${'success'},
        ${['test_cascade_delete_flag']}
      )
      RETURNING id
    `
    insertedEventIds.push(BigInt((rows[0] as { id: string | number }).id))
  }

  // 3 labels across the first 2 events (2 on event[0], 1 on event[1])
  const labelledEventIds = [insertedEventIds[0], insertedEventIds[1]]

  await sql`
    INSERT INTO labels (
      event_id,
      action,
      corrected_intent,
      labelled_by,
      labelled_at
    ) VALUES
      (${String(insertedEventIds[0])}, ${'correct'},   ${null}, ${'test_cascade_delete_user'}, ${now}),
      (${String(insertedEventIds[0])}, ${'incorrect'}, ${'test_cascade_delete_other_intent'}, ${'test_cascade_delete_user'}, ${now}),
      (${String(insertedEventIds[1])}, ${'discard'},   ${null}, ${'test_cascade_delete_user'}, ${now})
  `

  return { labelledEventIds }
}

// ---------------------------------------------------------------------------
// Suite
// ---------------------------------------------------------------------------

describeIf('T-4704 — cascade-delete constraints', () => {
  beforeAll(() => {
    // Initialise the Neon client lazily — DATABASE_URL is guaranteed to be set
    // here because describeIf already skipped the suite otherwise.
    sql = neon(DATABASE_URL!)

    // Ensure TELEMETRY_API_KEY is set for the route-handler sub-test
    if (!process.env.TELEMETRY_API_KEY) {
      process.env.TELEMETRY_API_KEY = 'test-key'
    }
  })

  afterAll(async () => {
    await cleanUp()
  })

  // -------------------------------------------------------------------------
  // Part 1 — raw SQL cascade
  // -------------------------------------------------------------------------

  describe('Part 1: raw SQL DELETE FROM devices', () => {
    let labelledEventIds: bigint[] = []

    beforeAll(async () => {
      // Guarantee a clean slate before inserting
      await cleanUp()
      ;({ labelledEventIds } = await insertFixture())
    })

    it('fixture: 1 device row exists after insertion', async () => {
      const rows = await sql`
        SELECT count(*)::int AS n FROM devices WHERE device_id = ${DEVICE_ID}
      `
      expect((rows[0] as { n: number }).n).toBe(1)
    })

    it('fixture: 5 event rows exist after insertion', async () => {
      const rows = await sql`
        SELECT count(*)::int AS n FROM events WHERE device_id = ${DEVICE_ID}
      `
      expect((rows[0] as { n: number }).n).toBe(5)
    })

    it('fixture: 3 label rows exist after insertion', async () => {
      const eventIdStrings = labelledEventIds.map(String)
      const rows = await sql`
        SELECT count(*)::int AS n
        FROM labels
        WHERE event_id = ANY(${eventIdStrings}::bigint[])
      `
      expect((rows[0] as { n: number }).n).toBe(3)
    })

    it('DELETE FROM devices removes the device row and cascades to events', async () => {
      await sql`DELETE FROM devices WHERE device_id = ${DEVICE_ID}`

      const deviceRows = await sql`
        SELECT count(*)::int AS n FROM devices WHERE device_id = ${DEVICE_ID}
      `
      expect((deviceRows[0] as { n: number }).n).toBe(0)

      const eventRows = await sql`
        SELECT count(*)::int AS n FROM events WHERE device_id = ${DEVICE_ID}
      `
      expect((eventRows[0] as { n: number }).n).toBe(0)
    })

    it('cascade also removes all label rows for the deleted events', async () => {
      const eventIdStrings = labelledEventIds.map(String)
      const rows = await sql`
        SELECT count(*)::int AS n
        FROM labels
        WHERE event_id = ANY(${eventIdStrings}::bigint[])
      `
      expect((rows[0] as { n: number }).n).toBe(0)
    })
  })

  // -------------------------------------------------------------------------
  // Part 2 — route handler DELETE /api/telemetry/[deviceId]
  // -------------------------------------------------------------------------

  describe('Part 2: DELETE route handler', () => {
    beforeAll(async () => {
      // Re-insert after Part 1 wiped everything
      await cleanUp()
      await insertFixture()
    })

    it('handler returns HTTP 200 with deleted.events >= 5 and deleted.labels >= 3', async () => {
      // Force the env var to a known value for this test
      const originalKey = process.env.TELEMETRY_API_KEY
      process.env.TELEMETRY_API_KEY = 'test-key'

      let response: Response | undefined

      try {
        // Import the route handler dynamically so the module only loads when
        // DATABASE_URL is available (avoids import-time side-effects).
        const { DELETE } = await import('../../app/api/telemetry/[deviceId]/route')

        const fakeRequest = new Request(
          `http://localhost/api/telemetry/${DEVICE_ID}`,
          {
            method: 'DELETE',
            headers: {
              'x-api-key': 'test-key',
            },
          },
        )

        // The route handler uses the Next.js App Router `params` convention:
        // { params: Promise<{ deviceId: string }> }
        response = await DELETE(fakeRequest, {
          params: Promise.resolve({ deviceId: DEVICE_ID }),
        })
      } finally {
        // Restore original value regardless of outcome
        if (originalKey === undefined) {
          delete process.env.TELEMETRY_API_KEY
        } else {
          process.env.TELEMETRY_API_KEY = originalKey
        }
      }

      expect(response).toBeDefined()
      expect(response!.status).toBe(200)

      const body = await response!.json() as {
        deleted: { devices: number; events: number; labels: number }
      }

      expect(body.deleted).toBeDefined()
      expect(body.deleted.events).toBeGreaterThanOrEqual(5)
      expect(body.deleted.labels).toBeGreaterThanOrEqual(3)
    })

    it('database has 0 events for the device after the handler ran', async () => {
      const rows = await sql`
        SELECT count(*)::int AS n FROM events WHERE device_id = ${DEVICE_ID}
      `
      expect((rows[0] as { n: number }).n).toBe(0)
    })

    it('database has 0 devices after the handler ran', async () => {
      const rows = await sql`
        SELECT count(*)::int AS n FROM devices WHERE device_id = ${DEVICE_ID}
      `
      expect((rows[0] as { n: number }).n).toBe(0)
    })
  })
})
