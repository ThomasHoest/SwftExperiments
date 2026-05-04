/**
 * schema.test.ts — E-42 schema contract unit tests
 *
 * These tests verify the public contract of the three migration files without
 * a live database. They import each migration module and:
 *   1. Confirm the required exports exist (up, down, shorthands).
 *   2. Use a mock MigrationBuilder to capture the SQL emitted and assert that
 *      every required table name, column name, index name, and CHECK constraint
 *      phrase appears in the collected SQL.
 *   3. Document the cascade delete chain and verify it is expressed in events
 *      and labels migrations.
 *
 * Real schema correctness (column types, FK constraints firing, etc.) is
 * validated in E-47 integration tests against a live Neon dev branch.
 */

import { describe, it, expect, beforeEach } from 'vitest'

// ── Mock MigrationBuilder ────────────────────────────────────────────────────

class MockMigrationBuilder {
  readonly statements: string[] = []

  sql(query: string): void {
    this.statements.push(query)
  }

  allSql(): string {
    return this.statements.join('\n')
  }
}

// ── Import migrations ────────────────────────────────────────────────────────

// Dynamic imports so TypeScript doesn't choke on the missing node-pg-migrate
// types at test time; we verify structure at runtime.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type MigrationModule = {
  shorthands: unknown
  up: (pgm: MockMigrationBuilder) => Promise<void>
  down: (pgm: MockMigrationBuilder) => Promise<void>
}

async function loadMigration(filename: string): Promise<MigrationModule> {
  // Vitest resolves paths relative to project root
  const mod = await import(`../../migrations/${filename}`) as MigrationModule
  return mod
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('Migration: create_devices', () => {
  let pgm: MockMigrationBuilder
  let mod: MigrationModule

  beforeEach(async () => {
    pgm = new MockMigrationBuilder()
    mod = await loadMigration('1746350000000_create_devices')
  })

  it('exports up and down functions', () => {
    expect(typeof mod.up).toBe('function')
    expect(typeof mod.down).toBe('function')
  })

  it('exports shorthands (may be undefined)', () => {
    expect('shorthands' in mod).toBe(true)
  })

  it('up() creates the devices table', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('devices')
    expect(sql).toContain('CREATE TABLE')
  })

  it('up() includes device_id as UUID PRIMARY KEY', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('device_id')
    expect(sql).toContain('UUID')
    expect(sql).toContain('PRIMARY KEY')
  })

  it('up() includes all required columns', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    const requiredColumns = [
      'device_id',
      'first_seen_at',
      'last_seen_at',
      'last_upload_at',
      'app_version',
      'model_version',
      'locale',
    ]
    for (const col of requiredColumns) {
      expect(sql, `Missing column: ${col}`).toContain(col)
    }
  })

  it('up() creates devices_last_seen_at_idx', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('devices_last_seen_at_idx')
    expect(sql).toContain('last_seen_at')
  })

  it('down() drops the devices table', async () => {
    await mod.down(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('devices')
    expect(sql.toUpperCase()).toContain('DROP')
  })
})

// ─────────────────────────────────────────────────────────────────────────────

describe('Migration: create_events', () => {
  let pgm: MockMigrationBuilder
  let mod: MigrationModule

  beforeEach(async () => {
    pgm = new MockMigrationBuilder()
    mod = await loadMigration('1746350001000_create_events')
  })

  it('exports up and down functions', () => {
    expect(typeof mod.up).toBe('function')
    expect(typeof mod.down).toBe('function')
  })

  it('up() creates the events table', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('events')
    expect(sql).toContain('CREATE TABLE')
  })

  it('up() includes all 13 required columns (verbatim ADR names)', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    const requiredColumns = [
      'id',
      'device_id',
      'received_at',
      'client_timestamp',
      'app_version',
      'model_version',
      'locale',
      'transcription_anonymised',
      'intent',
      'slots_anonymised',
      'parser_path',
      'outcome',
      'flags',
    ]
    for (const col of requiredColumns) {
      expect(sql, `Missing column: ${col}`).toContain(col)
    }
  })

  it('up() references devices(device_id) with ON DELETE CASCADE', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('REFERENCES devices(device_id)')
    expect(sql).toContain('ON DELETE CASCADE')
  })

  it('up() uses BIGSERIAL for id', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('BIGSERIAL')
  })

  it('up() uses JSONB for slots_anonymised', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('JSONB')
    expect(sql).toContain('slots_anonymised')
  })

  it('up() uses TEXT[] for flags', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('TEXT[]')
    expect(sql).toContain('flags')
  })

  it('up() creates all 8 required indexes', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    const expectedIndexes = [
      'events_received_at_idx',
      'events_client_timestamp_idx',
      'events_device_id_idx',
      'events_intent_idx',
      'events_parser_path_idx',
      'events_outcome_idx',
      'events_locale_idx',
      'events_flags_gin_idx',
    ]
    for (const idx of expectedIndexes) {
      expect(sql, `Missing index: ${idx}`).toContain(idx)
    }
  })

  it('up() creates flags GIN index using USING GIN', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('USING GIN')
    expect(sql).toContain('events_flags_gin_idx')
  })

  it('down() drops the events table', async () => {
    await mod.down(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('events')
    expect(sql.toUpperCase()).toContain('DROP')
  })
})

// ─────────────────────────────────────────────────────────────────────────────

describe('Migration: create_labels', () => {
  let pgm: MockMigrationBuilder
  let mod: MigrationModule

  beforeEach(async () => {
    pgm = new MockMigrationBuilder()
    mod = await loadMigration('1746350002000_create_labels')
  })

  it('exports up and down functions', () => {
    expect(typeof mod.up).toBe('function')
    expect(typeof mod.down).toBe('function')
  })

  it('up() creates the labels table', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('labels')
    expect(sql).toContain('CREATE TABLE')
  })

  it('up() includes all 8 required columns (verbatim ADR names)', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    const requiredColumns = [
      'id',
      'event_id',
      'action',
      'corrected_intent',
      'labelled_by',
      'labelled_at',
      'previous_action',
      'previous_corrected_intent',
    ]
    for (const col of requiredColumns) {
      expect(sql, `Missing column: ${col}`).toContain(col)
    }
  })

  it('up() includes CHECK constraint on action with all three allowed values', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('CHECK')
    expect(sql).toContain("'correct'")
    expect(sql).toContain("'incorrect'")
    expect(sql).toContain("'discard'")
  })

  it('up() references events(id) with ON DELETE CASCADE', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('REFERENCES events(id)')
    expect(sql).toContain('ON DELETE CASCADE')
  })

  it('up() uses BIGINT for event_id FK (references BIGSERIAL events.id)', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('BIGINT')
    expect(sql).toContain('event_id')
  })

  it('up() creates all 3 required indexes', async () => {
    await mod.up(pgm)
    const sql = pgm.allSql()
    const expectedIndexes = [
      'labels_event_id_idx',
      'labels_labelled_at_idx',
      'labels_labelled_by_idx',
    ]
    for (const idx of expectedIndexes) {
      expect(sql, `Missing index: ${idx}`).toContain(idx)
    }
  })

  it('down() drops the labels table', async () => {
    await mod.down(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('labels')
    expect(sql.toUpperCase()).toContain('DROP')
  })
})

// ─────────────────────────────────────────────────────────────────────────────

describe('Cascade delete chain documentation', () => {
  it('is correctly expressed: devices → events → labels via ON DELETE CASCADE', async () => {
    /**
     * Chain: DELETE FROM devices WHERE device_id = $1
     *   → deletes all events rows (events.device_id FK ON DELETE CASCADE)
     *   → deletes all labels rows (labels.event_id FK ON DELETE CASCADE)
     *
     * One SQL statement, one round-trip. This satisfies the GDPR hard-delete
     * requirement without application-level multi-DELETE logic (ADR-001 §7).
     */
    const pgmEvents = new MockMigrationBuilder()
    const eventsMod = await loadMigration('1746350001000_create_events')
    await eventsMod.up(pgmEvents)
    const eventsSql = pgmEvents.allSql()

    const pgmLabels = new MockMigrationBuilder()
    const labelsMod = await loadMigration('1746350002000_create_labels')
    await labelsMod.up(pgmLabels)
    const labelsSql = pgmLabels.allSql()

    // events must reference devices with CASCADE
    expect(eventsSql).toContain('REFERENCES devices(device_id)')
    expect(eventsSql).toContain('ON DELETE CASCADE')

    // labels must reference events with CASCADE
    expect(labelsSql).toContain('REFERENCES events(id)')
    expect(labelsSql).toContain('ON DELETE CASCADE')
  })
})
