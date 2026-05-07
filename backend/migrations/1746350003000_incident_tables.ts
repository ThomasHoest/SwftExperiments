import type { MigrationBuilder } from 'node-pg-migrate'

export const shorthands = undefined

export async function up(pgm: MigrationBuilder): Promise<void> {
  pgm.sql(`
    CREATE TABLE incidents (
      fingerprint      TEXT PRIMARY KEY,
      first_seen_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      last_seen_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
      occurrence_count INT NOT NULL DEFAULT 1,
      error_line       TEXT NOT NULL,
      status           TEXT NOT NULL DEFAULT 'open'
                       CHECK (status IN ('open', 'investigating', 'resolved', 'ignored')),
      pr_url           TEXT,
      pr_number        INT
    )
  `)

  pgm.sql(`
    CREATE TABLE incident_occurrences (
      id            BIGSERIAL PRIMARY KEY,
      fingerprint   TEXT NOT NULL REFERENCES incidents(fingerprint) ON DELETE CASCADE,
      reported_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
      app_version   TEXT NOT NULL,
      os_version    TEXT NOT NULL,
      device_model  TEXT NOT NULL,
      context_lines JSONB NOT NULL,
      breadcrumbs   TEXT NOT NULL
    )
  `)

  pgm.sql(`
    CREATE INDEX incident_occurrences_fingerprint_reported_at_idx
      ON incident_occurrences (fingerprint, reported_at DESC)
  `)
}

export async function down(pgm: MigrationBuilder): Promise<void> {
  pgm.sql(`DROP INDEX IF EXISTS incident_occurrences_fingerprint_reported_at_idx`)
  pgm.sql(`DROP TABLE IF EXISTS incident_occurrences`)
  pgm.sql(`DROP TABLE IF EXISTS incidents`)
}
