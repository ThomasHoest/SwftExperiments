import { MigrationBuilder, ColumnDefinitions } from 'node-pg-migrate'

export const shorthands: ColumnDefinitions | undefined = undefined

export async function up(pgm: MigrationBuilder): Promise<void> {
  pgm.sql(`
    CREATE TABLE labels (
      id                        BIGSERIAL    PRIMARY KEY,
      event_id                  BIGINT       NOT NULL REFERENCES events(id) ON DELETE CASCADE,
      action                    TEXT         NOT NULL CHECK (action IN ('correct', 'incorrect', 'discard')),
      corrected_intent          TEXT,
      labelled_by               TEXT         NOT NULL,
      labelled_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
      previous_action           TEXT,
      previous_corrected_intent TEXT
    )
  `)

  pgm.sql(`CREATE INDEX labels_event_id_idx    ON labels (event_id)`)
  pgm.sql(`CREATE INDEX labels_labelled_at_idx ON labels (labelled_at DESC)`)
  pgm.sql(`CREATE INDEX labels_labelled_by_idx ON labels (labelled_by)`)
}

export async function down(pgm: MigrationBuilder): Promise<void> {
  pgm.sql(`DROP TABLE IF EXISTS labels CASCADE`)
}
