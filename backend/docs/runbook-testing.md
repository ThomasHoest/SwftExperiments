# Runbook — Testing

## Unit tests

Tool: vitest 3.x  
Config: `backend/vitest.config.ts`

```sh
pnpm test:unit          # single run (used in CI)
pnpm test:unit --watch  # watch mode for development (alias: vitest)
pnpm test:coverage      # run with v8 coverage report
```

Test files live in `backend/tests/unit/`. Coverage HTML report is written to `backend/coverage/`.

All unit tests are fully offline — database calls are mocked with `vi.mock('@/lib/db', ...)`. No `DATABASE_URL` is required.

**Current test count:** 291 tests across 15 files.

### Adding a new unit test

1. Create `tests/unit/<module>.test.ts`.
2. Mock `@/lib/db` if the module under test calls the database:
   ```ts
   vi.mock('@/lib/db', () => ({ sql: vi.fn(), query: vi.fn() }))
   import { query } from '@/lib/db'
   ```
3. Run `pnpm test:unit` to confirm all tests pass.
4. The `unit` CI job will run your new tests automatically on push.

---

## Integration tests

Tool: vitest (same runner, different include pattern)  
Config: `backend/vitest.config.ts` — integration tests are in `tests/integration/` which is excluded from the unit run.

```sh
export DATABASE_URL="postgresql://..."   # your Neon dev branch
pnpm test:integration
```

Integration tests connect to a real Neon database. They are **not** run in CI until a separate CI job is added (post T-4704).

**Planned integration test:** `tests/integration/cascade-delete.test.ts` — inserts a device + events + labels, deletes the device, asserts full cascade (T-4704).

---

## E2E tests

Tool: Playwright 1.x  
Config: `backend/playwright.config.ts`

```sh
pnpm test:e2e                   # headless Chromium (requires a running app)
pnpm test:e2e --ui              # Playwright UI mode
```

E2E tests require a running SWA deployment. In CI, `PLAYWRIGHT_BASE_URL` is set to the SWA preview URL from the `deploy` job. Locally, it defaults to `http://localhost:3000` — run `pnpm dev` first, or use the SWA CLI for admin auth emulation.

Test files live in `backend/tests/e2e/`. The `cleanup_pr` CI job destroys the preview environment after the PR is closed.

**Planned E2E tests (T-4608, T-4702):**
- Navigate `/admin/events`, filter by intent, assert rows appear.
- Navigate `/admin/stats`, assert tiles show non-zero values.
- Navigate `/admin/export`, download CSV, assert Content-Type and header row.
- Navigate `/admin/deletion`, submit a device ID, assert confirmation message.

The admin auth fixture (`tests/e2e/fixtures.ts`) requires a GitHub service account with `admin` role — see `docs/runbook-e2e-auth.md` (T-4702).

---

## Test coverage targets

There is no enforced coverage minimum in v1. Run `pnpm test:coverage` to see the current coverage report. Key modules to keep covered:

| Module | Priority |
|---|---|
| `src/lib/filters/events.ts` | High — pure functions, easy to test |
| `src/lib/schemas/` | High — Zod validation, critical correctness |
| `app/api/telemetry/batch/route.ts` | High — ingest pipeline |
| `src/lib/queries/events.ts` | Medium — SQL is mocked |
| `app/admin/**` | Low — Server Components are hard to unit-test |
