/**
 * Minimal type stub for node-pg-migrate.
 *
 * This stub satisfies TypeScript's module resolver when node-pg-migrate is not
 * yet installed (e.g. before `pnpm install` runs in CI). It is NOT a full
 * re-declaration of the package — only the surface used by the migration files
 * in this repo is declared here. Once `pnpm install` runs and the real
 * node-pg-migrate package is present, these declarations are superseded by the
 * package's own typings (TypeScript prefers node_modules over ambient declarations).
 */

declare module 'node-pg-migrate' {
  export type ColumnDefinitions = Record<string, unknown>

  export interface MigrationBuilder {
    sql(query: string): void
    createTable(
      tableName: string,
      columns: Record<string, unknown>,
      options?: Record<string, unknown>
    ): void
    addIndex(
      tableName: string,
      columns: string | string[],
      options?: Record<string, unknown>
    ): void
    dropTable(tableName: string, options?: Record<string, unknown>): void
  }
}
