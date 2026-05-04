import { MigrationBuilder, ColumnDefinitions } from 'node-pg-migrate'

export const shorthands: ColumnDefinitions | undefined = undefined

export async function up(pgm: MigrationBuilder): Promise<void> {
  pgm.sql(`
    CREATE TABLE events (
      id                       BIGSERIAL    PRIMARY KEY,
      device_id                UUID         NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
      received_at              TIMESTAMPTZ  NOT NULL DEFAULT now(),
      client_timestamp         TIMESTAMPTZ  NOT NULL,
      app_version              TEXT         NOT NULL,
      model_version            TEXT         NOT NULL,
      locale                   TEXT         NOT NULL,
      transcription_anonymised TEXT         NOT NULL,
      intent                   TEXT         NOT NULL,
      slots_anonymised         JSONB        NOT NULL DEFAULT '{}'::jsonb,
      parser_path              TEXT         NOT NULL,
      outcome                  TEXT         NOT NULL,
      flags                    TEXT[]       NOT NULL DEFAULT '{}'::text[]
    )
  `)

  pgm.sql(`CREATE INDEX events_received_at_idx      ON events (received_at DESC)`)
  pgm.sql(`CREATE INDEX events_client_timestamp_idx ON events (client_timestamp DESC)`)
  pgm.sql(`CREATE INDEX events_device_id_idx        ON events (device_id)`)
  pgm.sql(`CREATE INDEX events_intent_idx           ON events (intent)`)
  pgm.sql(`CREATE INDEX events_parser_path_idx      ON events (parser_path)`)
  pgm.sql(`CREATE INDEX events_outcome_idx          ON events (outcome)`)
  pgm.sql(`CREATE INDEX events_locale_idx           ON events (locale)`)
  pgm.sql(`CREATE INDEX events_flags_gin_idx        ON events USING GIN (flags)`)
}

export async function down(pgm: MigrationBuilder): Promise<void> {
  pgm.sql(`DROP TABLE IF EXISTS events CASCADE`)
}
