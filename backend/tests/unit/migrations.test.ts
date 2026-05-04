/**
 * Unit tests — database migration files (E-42)
 *
 * These tests verify that each migration file exports the right shape and
 * calls the MigrationBuilder with the correct table names, column names,
 * foreign-key references, CASCADE rules, and CHECK constraints.
 *
 * All assertions run offline — no database connection is required.
 *
 * Contract source: backend/docs/adr/E-42-database-schema.md §7
 *
 * Run with: pnpm test:unit
 */

import { describe, it, expect, beforeEach } from 'vitest'
import { readdir } from 'node:fs/promises'
import path from 'node:path'

// ---------------------------------------------------------------------------
// Mock MigrationBuilder — captures pgm.sql() calls as raw SQL strings
// ---------------------------------------------------------------------------

class MockMigrationBuilder {
  readonly statements: string[] = []

  sql(query: string): void {
    this.statements.push(query)
  }

  allSql(): string {
    return this.statements.join('\n')
  }
}

type MigrationModule = {
  shorthands: unknown
  up: (pgm: MockMigrationBuilder) => Promise<void>
  down: (pgm: MockMigrationBuilder) => Promise<void>
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const MIGRATIONS_DIR = path.resolve(
  path.dirname(new URL(import.meta.url).pathname),
  '../../migrations',
)

async function findMigrationFile(suffix: string): Promise<string | null> {
  let files: string[]
  try {
    files = await readdir(MIGRATIONS_DIR)
  } catch {
    return null
  }
  const match = files
    .filter((f) => f.endsWith('.ts') && f.includes(suffix))
    .sort()
    .pop()
  return match ? path.join(MIGRATIONS_DIR, match) : null
}

async function importMigration(filePath: string | null): Promise<MigrationModule | null> {
  if (!filePath) return null
  return await import(filePath) as MigrationModule
}

// ---------------------------------------------------------------------------
// devices migration
// ---------------------------------------------------------------------------

describe('devices migration', () => {
  let pgm: MockMigrationBuilder
  let mod: MigrationModule | null

  beforeEach(async () => {
    pgm = new MockMigrationBuilder()
    const filePath = await findMigrationFile('_create_devices')
    mod = await importMigration(filePath)
  })

  it('exports an `up` function', () => {
    if (!mod) expect.fail('Migration file *_create_devices.ts not found — Implementer must create it first.')
    expect(typeof mod.up).toBe('function')
  })

  it('exports a `down` function', () => {
    if (!mod) expect.fail('Migration file *_create_devices.ts not found — Implementer must create it first.')
    expect(typeof mod.down).toBe('function')
  })

  it('`up` creates the devices table', async () => {
    if (!mod) expect.fail('Migration file *_create_devices.ts not found — Implementer must create it first.')
    await mod.up(pgm)
    expect(pgm.allSql()).toContain('CREATE TABLE')
    expect(pgm.allSql()).toContain('devices')
  })

  it.each(['device_id', 'first_seen_at', 'last_seen_at', 'last_upload_at'])(
    '`up` includes required column: %s',
    async (column) => {
      if (!mod) expect.fail('Migration file *_create_devices.ts not found — Implementer must create it first.')
      await mod.up(pgm)
      expect(pgm.allSql()).toContain(column)
    },
  )

  it('`down` drops the devices table', async () => {
    if (!mod) expect.fail('Migration file *_create_devices.ts not found — Implementer must create it first.')
    await mod.down(pgm)
    expect(pgm.allSql().toUpperCase()).toContain('DROP')
    expect(pgm.allSql()).toContain('devices')
  })
})

// ---------------------------------------------------------------------------
// events migration
// ---------------------------------------------------------------------------

describe('events migration', () => {
  let pgm: MockMigrationBuilder
  let mod: MigrationModule | null

  beforeEach(async () => {
    pgm = new MockMigrationBuilder()
    const filePath = await findMigrationFile('_create_events')
    mod = await importMigration(filePath)
  })

  it('exports an `up` function', () => {
    if (!mod) expect.fail('Migration file *_create_events.ts not found — Implementer must create it first.')
    expect(typeof mod.up).toBe('function')
  })

  it('exports a `down` function', () => {
    if (!mod) expect.fail('Migration file *_create_events.ts not found — Implementer must create it first.')
    expect(typeof mod.down).toBe('function')
  })

  it('`up` creates the events table', async () => {
    if (!mod) expect.fail('Migration file *_create_events.ts not found — Implementer must create it first.')
    await mod.up(pgm)
    expect(pgm.allSql()).toContain('CREATE TABLE')
    expect(pgm.allSql()).toContain('events')
  })

  it.each(['id', 'device_id', 'received_at', 'client_timestamp', 'intent', 'outcome'])(
    '`up` includes required column: %s',
    async (column) => {
      if (!mod) expect.fail('Migration file *_create_events.ts not found — Implementer must create it first.')
      await mod.up(pgm)
      expect(pgm.allSql()).toContain(column)
    },
  )

  it('`up` sets ON DELETE CASCADE on device_id → devices', async () => {
    if (!mod) expect.fail('Migration file *_create_events.ts not found — Implementer must create it first.')
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('REFERENCES devices(device_id)')
    expect(sql).toContain('ON DELETE CASCADE')
  })

  it('`down` drops the events table', async () => {
    if (!mod) expect.fail('Migration file *_create_events.ts not found — Implementer must create it first.')
    await mod.down(pgm)
    expect(pgm.allSql().toUpperCase()).toContain('DROP')
    expect(pgm.allSql()).toContain('events')
  })
})

// ---------------------------------------------------------------------------
// labels migration
// ---------------------------------------------------------------------------

describe('labels migration', () => {
  let pgm: MockMigrationBuilder
  let mod: MigrationModule | null

  beforeEach(async () => {
    pgm = new MockMigrationBuilder()
    const filePath = await findMigrationFile('_create_labels')
    mod = await importMigration(filePath)
  })

  it('exports an `up` function', () => {
    if (!mod) expect.fail('Migration file *_create_labels.ts not found — Implementer must create it first.')
    expect(typeof mod.up).toBe('function')
  })

  it('exports a `down` function', () => {
    if (!mod) expect.fail('Migration file *_create_labels.ts not found — Implementer must create it first.')
    expect(typeof mod.down).toBe('function')
  })

  it('`up` creates the labels table', async () => {
    if (!mod) expect.fail('Migration file *_create_labels.ts not found — Implementer must create it first.')
    await mod.up(pgm)
    expect(pgm.allSql()).toContain('CREATE TABLE')
    expect(pgm.allSql()).toContain('labels')
  })

  it.each(['id', 'event_id', 'action', 'labelled_by'])(
    '`up` includes required column: %s',
    async (column) => {
      if (!mod) expect.fail('Migration file *_create_labels.ts not found — Implementer must create it first.')
      await mod.up(pgm)
      expect(pgm.allSql()).toContain(column)
    },
  )

  it('`up` sets ON DELETE CASCADE on event_id → events', async () => {
    if (!mod) expect.fail('Migration file *_create_labels.ts not found — Implementer must create it first.')
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('REFERENCES events(id)')
    expect(sql).toContain('ON DELETE CASCADE')
  })

  it('`up` includes CHECK constraint for action IN (correct, incorrect, discard)', async () => {
    if (!mod) expect.fail('Migration file *_create_labels.ts not found — Implementer must create it first.')
    await mod.up(pgm)
    const sql = pgm.allSql()
    expect(sql).toContain('CHECK')
    expect(sql).toContain("'correct'")
    expect(sql).toContain("'incorrect'")
    expect(sql).toContain("'discard'")
  })

  it('`down` drops the labels table', async () => {
    if (!mod) expect.fail('Migration file *_create_labels.ts not found — Implementer must create it first.')
    await mod.down(pgm)
    expect(pgm.allSql().toUpperCase()).toContain('DROP')
    expect(pgm.allSql()).toContain('labels')
  })
})
