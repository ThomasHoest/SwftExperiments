import { MigrationBuilder, ColumnDefinitions } from 'node-pg-migrate'

export const shorthands: ColumnDefinitions | undefined = undefined

export async function up(pgm: MigrationBuilder): Promise<void> {
  pgm.sql(`
    CREATE TABLE devices (
      device_id      UUID         PRIMARY KEY,
      first_seen_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
      last_seen_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
      last_upload_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
      app_version    TEXT,
      model_version  TEXT,
      locale         TEXT
    )
  `)

  pgm.sql(`
    CREATE INDEX devices_last_seen_at_idx ON devices (last_seen_at DESC)
  `)
}

export async function down(pgm: MigrationBuilder): Promise<void> {
  pgm.sql(`DROP TABLE IF EXISTS devices CASCADE`)
}
