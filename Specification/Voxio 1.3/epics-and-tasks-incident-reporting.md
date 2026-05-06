# Epics & Tasks: Error Incident Reporting (Voxio 1.3)
**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-06
**References:** ADR-006 (`docs/decisions/ADR-006-incident-reporting.md`), `epics-and-tasks-agent-api.md` (E-48 – E-49, format reference and `AGENT_API_KEY` dependency), `epics-and-tasks-telemetry-backend.md` (E-41 – E-47, `TELEMETRY_API_KEY` and SWA + Neon stack), VoxioSpecification-1.3.md, CLAUDE.md
**Stack (iOS):** Swift 6, SwiftUI, `@Observable`, `NWPathMonitor`, `URLSession`, `CryptoKit`, `Logger.swift` `LogListener` protocol
**Stack (Backend):** TypeScript, Next.js 15 App Router (hybrid mode), Postgres (Neon serverless), deployed to Azure Static Web Apps Standard plan

---

## Overview

This document covers two epics — **E-50: On-Device Incident Capture** and
**E-51: Incident Backend & Agent Interface** — that introduce automated
error incident reporting for the Voxio iOS app. When the on-device logger
emits an `.error` line, the iOS client captures the surrounding context
(75 anonymised log lines + breadcrumb trail of recent screens), fingerprints
the error, deduplicates per fingerprint over a 24-hour window, and uploads
the incident to the existing telemetry backend over WiFi only. The backend
stores incidents grouped by fingerprint, and exposes them to the AI agent
via authenticated routes so the agent can read source files, open a draft
GitHub PR with a candidate fix, and link the PR back to the incident.

No user-visible UI is introduced on iOS — incident reporting is silent and
fire-and-forget. No new infrastructure is introduced on the backend: the
incident routes ship as additional Route Handlers under `app/api/incidents/*`
and `app/api/agent/incidents/*` in the same Next.js app, deployed to the
same Azure Static Web Apps instance, backed by the same Neon Postgres
database. iOS upload reuses `TELEMETRY_API_KEY` (already configured in SWA);
agent endpoints reuse `AGENT_API_KEY` (introduced in E-48).

This document is **additive** to `epics-and-tasks-agent-api.md` —
the auth middleware (`src/lib/agent-auth.ts` from T-4801), the
`AGENT_API_KEY` SWA setting (T-4802), and the `staticwebapp.config.json`
agent route surface (T-4803) are all reused. The GitHub PR flow runs on
the agent runtime only — the backend stores `pr_url` and `pr_number` but
never touches GitHub itself. `GITHUB_TOKEN` and `GITHUB_REPO` are agent-side
secrets, not SWA Application Settings.

Epic numbering begins at **E-50**, continuing from E-49 in the agent API
document. Task numbering begins at **T-5001**.

---

## Epic Index

| # | Epic | Tasks | Feature Area |
|---|---|---|---|
| E-50 | On-Device Incident Capture | T-5001 – T-5006 | Anonymisation, ring buffer, breadcrumb tracker, fingerprinting + dedup + upload, app-startup wiring, view integration |
| E-51 | Incident Backend & Agent Interface | T-5101 – T-5108 | Schema migration, ingest route, agent list/detail/patch routes, agent PR script, integration tests, SWA route config |

---

## E-50 — On-Device Incident Capture

Implement the iOS-side primitives that detect, contextualise, anonymise,
deduplicate, and upload error incidents. The pipeline runs entirely
inside the existing logger fan-out: `IncidentReporter` registers as a
`LogListener` at app startup, observes every emitted `.error` line, and
performs the capture-and-upload work asynchronously without blocking the
log call site.

The four core types — `LogAnonymiser`, the ring buffer extension to
`FileLogListener`, `BreadcrumbTracker`, and `IncidentReporter` — together
form the on-device capture surface. Views in the existing Home, Settings,
and LearnedPhrases features push and pop their screen names onto
`BreadcrumbTracker` so each incident report includes the navigation path
that led to the error.

**Depends on:** existing `Logger.swift` and `LogListener` protocol,
existing `FileLogListener.shared` at `iOS/Voxio/Core/Logging/FileLogListener.swift`,
the `NWPathMonitor` pattern from `iOS/Voxio/Core/Networking/MozartEvents.swift`.
**Unlocks:** E-51 (the backend ingest route at T-5102 cannot be exercised
end-to-end until the iOS pipeline is producing real incidents; the integration
test at T-5107 uses synthetic payloads).

---

### Anonymisation

- [ ] **T-5001** Create `LogAnonymiser` as a Swift value type at
  `iOS/Voxio/Core/Logging/LogAnonymiser.swift`. This type applies four
  ordered regex rules to a single log line before any incident leaves the
  device. It is used by `IncidentReporter` (T-5004) to scrub each context
  line and the originating error line.

  Define and expose the following:

  ```swift
  public struct LogAnonymiser {
      public init()
      public func anonymise(_ line: String) -> String
  }
  ```

  The `anonymise(_:)` method applies these rules **in order** (later rules
  see the output of earlier ones):

  1. **IPv4 addresses** — match `\b(?:\d{1,3}\.){3}\d{1,3}\b` and replace
     each match with the literal string `[IP]`.
  2. **UUIDs** — match `\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b`
     (case-insensitive) and replace each match with the literal string
     `[UUID]`.
  3. **JID strings** — match `\b[A-Za-z0-9]+\.jid\.[A-Za-z0-9.-]+\b` and
     replace each match with the literal string `[JID]`. (The pattern
     captures any token containing `.jid.` between alphanumeric prefix and
     dotted suffix, e.g. `abc123.jid.company.com`.)
  4. **Transcription content** — if the line contains the literal substring
     `[CommandParserRouter] parsing:`, strip everything after that marker
     including the colon's trailing whitespace and any quoted content,
     then append the literal string `[TRANSCRIPTION]`. The output line
     therefore preserves the prefix `... [CommandParserRouter] parsing: [TRANSCRIPTION]`
     and discards the actual transcribed words.

  Compile each `NSRegularExpression` once at `init()` (or via a `static let`)
  and reuse across calls — this method is called for every log line in the
  ring buffer (75 lines per incident) and must not allocate a new regex
  per call.

  Use Swift's standard `String` API and `NSRegularExpression`. Do not pull
  in any third-party regex library. Process the input line in `String`
  (not `NSString`) where possible; convert via `NSRange(line.startIndex..., in: line)`
  for each regex pass.

  **Files added:** `iOS/Voxio/Core/Logging/LogAnonymiser.swift`,
  `iOS/VoxioTests/LogAnonymiserTests.swift`.
  **Files changed:** none.
  **Acceptance criteria:**
  - `anonymise("Connecting to 192.168.1.42 on port 9339")` returns
    `"Connecting to [IP] on port 9339"`.
  - `anonymise("Device 550E8400-E29B-41D4-A716-446655440000 ready")` returns
    `"Device [UUID] ready"` (case-insensitive UUID match).
  - `anonymise("Resolved abc123.jid.company.com")` returns
    `"Resolved [JID]"`.
  - `anonymise("[CommandParserRouter] parsing: \"play kind of blue\"")` returns
    a string ending in `"[CommandParserRouter] parsing: [TRANSCRIPTION]"` —
    the literal phrase `play kind of blue` does not appear in the output.
  - A line with multiple IPs (`"from 10.0.0.1 to 10.0.0.2"`) replaces both
    independently — output is `"from [IP] to [IP]"`.
  - A line containing none of the four patterns is returned unchanged.
  - Rules apply in declared order: a UUID-shaped substring inside a
    transcription `parsing:` payload is stripped (the transcription rule
    runs last and removes the entire payload).
  - Unit-test coverage: 100% of the four rules plus the multi-match and
    no-match cases.

  *No dependencies within this document. Prerequisite for T-5004.*

### Ring buffer

- [ ] **T-5002** Extend `FileLogListener` (existing file at
  `iOS/Voxio/Core/Logging/FileLogListener.swift`) with an in-memory
  75-line circular ring buffer of the most recent log lines, exposed via
  a thread-safe snapshot method `ringBufferSnapshot()`.

  Add to `FileLogListener`:

  ```swift
  /// Maximum number of lines retained in the ring buffer.
  public static let ringBufferCapacity: Int = 75

  /// Returns a copy of the most recent log lines (oldest first, newest last).
  /// At most `ringBufferCapacity` entries.
  public func ringBufferSnapshot() -> [String]
  ```

  Internal state:
  - A private `[String]` storage of capacity 75, plus the index of the
    oldest entry (or use a Swift `Deque`-style approach — choose whichever
    is simpler given the existing file's style).
  - A private `DispatchQueue` (serial) — or reuse the existing serial
    queue inside `FileLogListener` if one exists — guarding both the
    file-write path and the ring-buffer mutation. `ringBufferSnapshot()`
    must `sync` onto this queue and return a defensive copy of the array.

  On every log line received by `FileLogListener` (already wired via the
  `LogListener` protocol), append the formatted line to the ring buffer.
  Use the **same** formatted string the file writer uses, so context
  lines in incidents match exactly what is written to disk. When the
  buffer reaches capacity, drop the oldest line.

  `ringBufferSnapshot()` returns a copy — the caller is free to mutate it.
  Do **not** return a reference to the internal storage.

  **Files changed:** `iOS/Voxio/Core/Logging/FileLogListener.swift`.
  **Files added:** `iOS/VoxioTests/FileLogListenerRingBufferTests.swift`.
  **Acceptance criteria:**
  - After a fresh `FileLogListener.shared` (or test instance) receives 10
    log lines, `ringBufferSnapshot()` returns those 10 lines in order
    (oldest first).
  - After receiving 100 lines, `ringBufferSnapshot()` returns exactly 75
    lines, all of which are the most recent 75 (lines 26..100).
  - `ringBufferSnapshot()` returns a copy: mutating the returned array
    does not affect a subsequent call's result.
  - Concurrent log writes from multiple threads do not corrupt the buffer
    (verified by a stress test that fans out 1000 log calls across 8
    `DispatchQueue.global()` workers and asserts `ringBufferSnapshot().count <= 75`
    plus all entries are well-formed strings).
  - The existing file-write behaviour of `FileLogListener` is unchanged
    (existing tests, if any, continue to pass).

  *No dependencies within this document. Prerequisite for T-5004.*

### Breadcrumb tracker

- [ ] **T-5003** Create `BreadcrumbTracker` at
  `iOS/Voxio/Core/Logging/BreadcrumbTracker.swift`. This is a
  `@MainActor @Observable final class` singleton that stores the current
  navigation stack as `[String]` and exposes the path as a single
  arrow-joined string. Views call `push(_:)` on `.onAppear` and `pop()` on
  `.onDisappear` (wired in T-5006).

  Define and expose the following:

  ```swift
  @MainActor
  @Observable
  public final class BreadcrumbTracker {
      public static let shared = BreadcrumbTracker()
      private init() {}

      private(set) public var stack: [String] = []

      public var currentPath: String {
          stack.joined(separator: " > ")
      }

      public func push(_ screenName: String)
      public func pop()
      public func reset()
  }
  ```

  Behaviour:
  - `push(_ screenName:)` appends `screenName` to `stack`. There is no
    deduplication — if a view re-appears, its name is pushed again.
  - `pop()` removes the **last** element of `stack`. If `stack` is empty,
    `pop()` is a no-op (do not crash, do not log a warning — SwiftUI
    `.onDisappear` may fire after `.onAppear` of a sibling view, leaving
    the stack briefly empty during transitions).
  - `reset()` empties the stack. Used by tests; not called by app code.
  - `currentPath` returns `""` when the stack is empty, otherwise the
    elements joined with the literal separator `" > "` (space, greater-than,
    space).

  This type lives on `@MainActor` because it is mutated only from view
  lifecycle hooks. `IncidentReporter` (T-5004) reads `currentPath` from
  the main actor when assembling a payload.

  **Files added:** `iOS/Voxio/Core/Logging/BreadcrumbTracker.swift`,
  `iOS/VoxioTests/BreadcrumbTrackerTests.swift`.
  **Files changed:** none.
  **Acceptance criteria:**
  - Fresh instance: `stack == []`, `currentPath == ""`.
  - After `push("Home")`: `stack == ["Home"]`, `currentPath == "Home"`.
  - After `push("Home"); push("Settings")`: `currentPath == "Home > Settings"`.
  - After `push("A"); push("B"); pop()`: `stack == ["A"]`, `currentPath == "A"`.
  - After `pop()` on an empty stack: no crash, `stack == []`, `currentPath == ""`.
  - `reset()` empties the stack regardless of prior contents.
  - Unit-test coverage: 100% lines, 100% branches.

  *No dependencies within this document. Prerequisite for T-5004 and T-5006.*

### Incident reporter

- [ ] **T-5004** Create `IncidentReporter` at
  `iOS/Voxio/Core/Logging/IncidentReporter.swift`. This is a
  `@MainActor final class` conforming to `LogListener` that captures,
  fingerprints, deduplicates, and uploads error incidents. It is the
  central type in this epic.

  Define and expose the following:

  ```swift
  @MainActor
  public final class IncidentReporter: LogListener {
      public static let shared = IncidentReporter()
      private init()

      // LogListener conformance
      public nonisolated func didLog(level: Logger.Level, message: String, file: String, line: Int)
  }
  ```

  Behaviour on each log call:

  1. If `level != .error`, return immediately. All non-error lines are
     ignored by `IncidentReporter`.
  2. Hop onto the main actor (the `LogListener` protocol method is
     `nonisolated` — use a `Task { @MainActor in ... }` to enter actor
     context).
  3. Build the **error line** = the formatted line as it would appear in
     `FileLogListener` (timestamp + level + message + file + line). To
     keep the format exactly consistent with the ring buffer entries,
     compute it the same way `FileLogListener` does. Anonymise it via
     `LogAnonymiser().anonymise(_:)`.
  4. Compute the **fingerprint**:
     - Take the anonymised error line's **message portion** only (strip
       the timestamp prefix — incidents that differ only in timestamp
       must produce the same fingerprint).
     - Strip all decimal digit runs (regex `\d+` → `""`) — this is the
       "normalised message". Two errors that differ only in numeric
       values (counts, IDs, etc.) produce the same fingerprint.
     - Concatenate the normalised message with the app version string
       from `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`
       (fallback to `"unknown"`).
     - Compute SHA-256 over the UTF-8 bytes of the concatenation using
       `CryptoKit.SHA256`.
     - Take the first 16 hex characters of the digest. Lowercase.
  5. Check 24-hour deduplication via `UserDefaults.standard`:
     - Key: `"incident_reported_" + fingerprint`.
     - Value: a `Double` Unix timestamp (seconds since 1970).
     - If the stored timestamp exists and is within the last 24 hours
       (`now - stored < 86_400`), return without uploading.
     - Otherwise, write `Date().timeIntervalSince1970` to that key and
       proceed.
  6. Capture context:
     - `contextLines` = `FileLogListener.shared.ringBufferSnapshot()`,
       with each entry passed through `LogAnonymiser().anonymise(_:)`.
     - `breadcrumbs` = `BreadcrumbTracker.shared.currentPath`.
  7. Assemble the payload:
     ```swift
     struct IncidentPayload: Encodable {
         let fingerprint: String
         let appVersion: String
         let osVersion: String
         let deviceModel: String
         let contextLines: [String]
         let breadcrumbs: String
         let errorLine: String
     }
     ```
     - `appVersion` = same string used in fingerprinting.
     - `osVersion` = `UIDevice.current.systemVersion`.
     - `deviceModel` = the hardware identifier (e.g. `"iPhone15,2"`)
       obtained via `utsname` / `uname()` — match whatever the existing
       telemetry layer uses if it already collects this; otherwise compute
       inline.
     - `errorLine` = the anonymised error line from step 3.
  8. Hand the payload off to the upload helper (defined in T-5005's WiFi
     guard) — fire-and-forget. The upload is awaited inside a `Task` but
     its result is not surfaced to any UI.

  Upload (synchronous within the `Task`, not awaited by the log call site):

  - Endpoint: `POST https://<telemetry-host>/api/incidents/report`. The
    base host is the same constant already used by the existing telemetry
    upload path. If a constant exists (e.g. `TelemetryConfig.baseURL`),
    reuse it; do not duplicate the literal.
  - Headers: `Content-Type: application/json`,
    `x-telemetry-key: <TELEMETRY_API_KEY value>` (loaded the same way the
    existing telemetry uploader loads it — match that pattern exactly).
  - Body: the JSON-encoded `IncidentPayload` (snake_case or camelCase
    must match what the backend at T-5102 accepts; this spec assumes
    camelCase, matching the field names in the struct).
  - **WiFi guard:** before the request, check `NWPathMonitor` (see T-5005)
    — if the current path is not WiFi, **abandon** the upload. Do not
    queue for later, do not retry on next launch. The dedup record from
    step 5 has already been written, so a subsequent error with the same
    fingerprint within 24 hours will not retry either. This is intentional
    and matches ADR-006.
  - **Retry:** on transient failure (`URLError.timedOut`,
    `URLError.networkConnectionLost`, HTTP 5xx), retry up to 3 attempts
    total with delays `2s`, `5s`, `10s`. On HTTP 4xx or any non-transient
    error, give up immediately.
  - On final failure, log via `Logger.error(...)` — but **guard against
    recursion**: prefix this log message with the literal token
    `[IncidentReporter:internal]` and have `IncidentReporter` skip any
    error line containing that token in step 1 of `didLog(...)`.

  Concurrency notes:
  - `didLog(...)` is `nonisolated` and must not block the caller's thread.
    All work happens inside `Task { @MainActor in ... }` plus a detached
    network task for the upload itself.
  - `URLSession` calls happen on a background queue; only the
    payload-assembly and dedup-check phases run on the main actor.

  **Files added:** `iOS/Voxio/Core/Logging/IncidentReporter.swift`,
  `iOS/VoxioTests/IncidentReporterTests.swift`.
  **Files changed:** none.
  **Acceptance criteria:**
  - A non-error log call (`Logger.info(...)`, `Logger.verbose(...)`)
    triggers no upload and no UserDefaults write.
  - An error log call with no prior dedup entry: writes one
    `incident_reported_<fingerprint>` key to `UserDefaults` and triggers
    one upload attempt.
  - Two error log calls within 24 hours producing the **same fingerprint**:
    one upload total. The second call returns immediately without
    capturing context.
  - Two error log calls producing **different fingerprints** (e.g. by
    differing app versions or by message content beyond just digits):
    two uploads.
  - Two error log calls 25 hours apart with the same fingerprint: two
    uploads. (Verified with a test that injects a clock or stubs
    `Date()`.)
  - Fingerprint of `"Connection failed (count=42)"` equals fingerprint of
    `"Connection failed (count=999)"` for the same app version
    (digit-stripping verified).
  - Fingerprint is exactly 16 lowercase hex characters.
  - Payload `contextLines` are **all** anonymised — no IPv4, UUID, JID,
    or transcription substring appears in the JSON body.
  - Payload `errorLine` is anonymised.
  - Payload `breadcrumbs` matches `BreadcrumbTracker.shared.currentPath`
    at the time of capture.
  - When `NWPathMonitor.currentPath` is **not** WiFi, no HTTP request is
    made (verified by mocking the path monitor and asserting zero calls
    on a stubbed `URLSession`).
  - On HTTP 503 from the server, the reporter retries 2 more times with
    the documented backoff and then gives up.
  - On HTTP 400, the reporter does not retry.
  - A failure log emitted by the reporter itself (with the
    `[IncidentReporter:internal]` token) does not trigger a recursive
    upload.

  *Depends on: T-5001 (anonymisation), T-5002 (ring buffer),
  T-5003 (breadcrumbs), T-5005 (WiFi guard helper).*

### App startup wiring

- [ ] **T-5005** Register `IncidentReporter.shared` as a `LogListener` at
  app startup, and provide a shared `NWPathMonitor`-based WiFi guard
  helper that `IncidentReporter` calls before each upload.

  Modify `iOS/Voxio/VoxioApp.swift`:

  Inside `init()` (creating one if absent), after the existing logger
  configuration calls, add:

  ```swift
  Logger.addListener(FileLogListener.shared)   // already there or move into init
  Logger.addListener(IncidentReporter.shared)
  WiFiPathMonitor.shared.start()
  ```

  Order matters: `FileLogListener.shared` must be registered **before**
  `IncidentReporter.shared`, so by the time the reporter receives an
  error event, the ring buffer in `FileLogListener` already contains that
  same line.

  Create `iOS/Voxio/Core/Networking/WiFiPathMonitor.swift`:

  ```swift
  import Network

  public final class WiFiPathMonitor {
      public static let shared = WiFiPathMonitor()
      private init() {}

      private let monitor = NWPathMonitor()
      private let queue = DispatchQueue(label: "WiFiPathMonitor")
      private var _isWiFi: Bool = false
      private let lock = NSLock()

      public func start()
      public func stop()
      public var isWiFi: Bool { /* lock-protected read of _isWiFi */ }
  }
  ```

  Behaviour:
  - `start()` is idempotent — calling it twice does not start two monitors.
    It assigns a `pathUpdateHandler` that updates `_isWiFi` (under `lock`)
    to `path.status == .satisfied && path.usesInterfaceType(.wifi)`. Then
    it calls `monitor.start(queue: queue)`.
  - `stop()` calls `monitor.cancel()`. Used by tests.
  - `isWiFi` is read by `IncidentReporter` (T-5004) before each upload.

  Match the pattern already used in
  `iOS/Voxio/Core/Networking/MozartEvents.swift` — if that file already
  has a reusable `NWPathMonitor` helper, lift it into a shared type
  rather than duplicating. Otherwise, the new file is the canonical home.

  **Files added:** `iOS/Voxio/Core/Networking/WiFiPathMonitor.swift`.
  **Files changed:** `iOS/Voxio/VoxioApp.swift`.
  **Acceptance criteria:**
  - At app launch, `Logger.listeners` contains `FileLogListener.shared`
    and `IncidentReporter.shared`, in that order (verified by an
    instrumented unit test or by introspection if `Logger` exposes the
    list).
  - `WiFiPathMonitor.shared.start()` is invoked exactly once during
    `VoxioApp.init()`.
  - On the simulator (which runs over the host's WiFi), `isWiFi` becomes
    `true` within 2 seconds of start.
  - Stopping and restarting `WiFiPathMonitor.shared` does not crash and
    resumes updates.
  - Calling `start()` twice in a row leaves a single underlying
    `NWPathMonitor` running (no leaked monitors).

  *Depends on: T-5004 (the listener that gets registered must exist).*

### View integration

- [ ] **T-5006** Wire breadcrumb push/pop into the existing top-level
  views so each incident report includes the navigation path that led to
  the error.

  Modify the following SwiftUI views (paths per the existing project
  layout in CLAUDE.md):

  - `iOS/Voxio/Features/Home/ContentView.swift` — push `"Home"`.
  - `iOS/Voxio/Features/Settings/...` — every top-level Settings screen
    pushes its own name (e.g. `"Settings"`, `"Settings.Telemetry"`,
    `"Settings.About"`). Match the actual file names that exist in the
    Settings feature folder; one breadcrumb per pushed screen.
  - `iOS/Voxio/Features/LearnedPhrases/...` — push `"LearnedPhrases"`
    on the top-level view; deeper screens (if any) push their own name.

  In each view, add the modifier pair to the root container:

  ```swift
  .onAppear { BreadcrumbTracker.shared.push("Home") }
  .onDisappear { BreadcrumbTracker.shared.pop() }
  ```

  Naming convention: use the feature name in PascalCase, optionally with
  a `.` separator for sub-screens. Do **not** use the SwiftUI type name
  (which can change with refactors). The strings appear in agent-facing
  payloads and should be human-readable but stable.

  Do not modify any other view this version — sheets, alerts, and
  transient overlays do not push breadcrumbs.

  **Files changed:**
  - `iOS/Voxio/Features/Home/ContentView.swift`
  - every top-level view file under `iOS/Voxio/Features/Settings/`
  - every top-level view file under `iOS/Voxio/Features/LearnedPhrases/`
  **Files added:** none.
  **Acceptance criteria:**
  - Launching the app and observing the Home screen yields
    `BreadcrumbTracker.shared.currentPath == "Home"`.
  - Navigating Home → Settings yields
    `currentPath == "Home > Settings"` (verified by a UI test or by an
    in-app debug overlay temporarily added during development).
  - Returning Settings → Home yields `currentPath == "Home"`.
  - Navigating Home → Settings → LearnedPhrases yields
    `currentPath == "Home > Settings > LearnedPhrases"`.
  - No view's normal rendering is affected by the breadcrumb modifiers
    (smoke-tested by running the app and exercising every screen).
  - The list of view files modified in the PR matches the actual list of
    top-level views under `Features/Settings/` and `Features/LearnedPhrases/`
    (no missed view, no over-reach into nested components).

  *Depends on: T-5003.*

---

## E-51 — Incident Backend & Agent Interface

Implement the four Route Handlers under `app/api/incidents/*` and
`app/api/agent/incidents/*` plus the agent-side PR script. The schema
migration introduces two new tables (`incidents` and `incident_occurrences`)
alongside the existing `events`, `labels`, and `devices`. The ingest
route is authenticated with `TELEMETRY_API_KEY` (the iOS app's existing
key); the three agent routes are authenticated with `AGENT_API_KEY` (the
agent's key from E-48). The PR-opening flow runs on the agent runtime
and uses `GITHUB_TOKEN` + `GITHUB_REPO`, both stored agent-side only.

**Depends on:** E-41 (SWA + Neon provisioned), E-42 (`events`, `labels`,
`devices` tables exist — used by the integration test for cascade
verification), E-48 (`requireAgentKey` middleware at
`src/lib/agent-auth.ts` from T-4801, `AGENT_API_KEY` SWA setting from
T-4802, `staticwebapp.config.json` agent route surface from T-4803),
existing `TELEMETRY_API_KEY` SWA setting (already configured for E-43).
**Unlocks:** the agent-side GitHub PR flow (T-5106) — once incidents are
flowing in from real iOS devices, the agent can read them, propose fixes,
and link draft PRs back to the incident record.

---

### Database schema

- [ ] **T-5101** Create the migration `migrations/NNNN_incident_tables.ts`
  (NNNN is the next sequential migration number — check the
  `migrations/` directory for the highest existing number and add 1).
  The migration adds the two incident tables and the lookup index.

  Up SQL:
  ```sql
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
  );

  CREATE TABLE incident_occurrences (
    id            BIGSERIAL PRIMARY KEY,
    fingerprint   TEXT NOT NULL REFERENCES incidents(fingerprint) ON DELETE CASCADE,
    reported_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    app_version   TEXT NOT NULL,
    os_version    TEXT NOT NULL,
    device_model  TEXT NOT NULL,
    context_lines JSONB NOT NULL,
    breadcrumbs   TEXT NOT NULL
  );

  CREATE INDEX incident_occurrences_fingerprint_reported_at_idx
    ON incident_occurrences (fingerprint, reported_at DESC);
  ```

  Down SQL:
  ```sql
  DROP INDEX IF EXISTS incident_occurrences_fingerprint_reported_at_idx;
  DROP TABLE IF EXISTS incident_occurrences;
  DROP TABLE IF EXISTS incidents;
  ```

  Notes:
  - `error_line` stores the **first** anonymised error line seen for that
    fingerprint. It is set on insert and never updated by subsequent
    occurrences (the upsert in T-5102 explicitly does not touch this
    column on conflict).
  - `status` defaults to `'open'`. The CHECK constraint enumerates the
    four allowed values; the PATCH route (T-5105) relies on this to reject
    invalid status writes at the DB layer as a defence-in-depth.
  - `pr_url` and `pr_number` are nullable until the agent links a PR.
  - `incident_occurrences.context_lines` is `JSONB` (not `JSON`) — this
    enables compact storage and future indexed search.
  - The `ON DELETE CASCADE` on `incident_occurrences.fingerprint` means
    deleting an incident row (e.g. for GDPR or cleanup) removes all its
    occurrences. There is no cascade from `devices` or `events` to
    `incidents` — incidents are not joined to a device id.

  Run the migration locally against the dev branch with
  `npm run migrate:up`, confirm both tables and the index appear via
  `\d incidents`, `\d incident_occurrences` in `psql`. Commit the
  migration. CI applies it to production on merge to `main`.

  **Files added:** `migrations/NNNN_incident_tables.ts`.
  **Files changed:** none.
  **Acceptance criteria:**
  - `npm run migrate:up` applies cleanly against an existing database.
  - `npm run migrate:down` reverses the schema without error.
  - `INSERT INTO incidents (fingerprint, error_line) VALUES ('abc', 'oops');`
    succeeds and produces a row with `status = 'open'`,
    `occurrence_count = 1`, `first_seen_at = now()`.
  - `INSERT INTO incidents (fingerprint, error_line, status) VALUES ('x', 'y', 'bogus');`
    fails with the CHECK constraint violation.
  - `DELETE FROM incidents WHERE fingerprint = 'abc';` cascade-deletes any
    associated `incident_occurrences` rows.
  - The migration file follows the existing `node-pg-migrate` TypeScript
    pattern used in earlier migrations.

  *Depends on: E-42 (the `events` table exists — for migration ordering,
  not for any FK relationship). No dependencies inside this document.*

### Route: incident ingest (iOS-facing)

- [ ] **T-5102** Create `app/api/incidents/report/route.ts` implementing
  `POST /api/incidents/report`. Authenticated with `TELEMETRY_API_KEY`
  (the same key used by the existing iOS telemetry upload at E-43, sent
  via the `x-telemetry-key` header). Upserts the `incidents` row by
  fingerprint and inserts a new `incident_occurrences` row.

  Authentication: import the existing telemetry-key validation helper
  from `src/lib/telemetry-auth.ts` (created in E-43). If the helper is
  named differently in the existing code, match that name. The validation
  shape mirrors `requireAgentKey` from T-4801: returns either
  `{ ok: true }` or `{ ok: false, response }`.

  Request body (validated with `zod`):
  ```typescript
  interface IncidentReportRequest {
    fingerprint: string;          // exactly 16 lowercase hex chars
    appVersion: string;           // 1..32 chars
    osVersion: string;            // 1..32 chars
    deviceModel: string;          // 1..64 chars
    contextLines: string[];       // 0..75 entries, each <= 4096 chars
    breadcrumbs: string;          // 0..1024 chars
    errorLine: string;            // 1..4096 chars
  }
  ```

  Validation rules:
  - `fingerprint` matches `/^[0-9a-f]{16}$/` — else 400
    `{ "error": "invalid_fingerprint" }`.
  - `contextLines.length` ≤ 75 — else 400
    `{ "error": "context_too_long", "detail": "max 75 lines" }`.
  - Each `contextLines[i]` length ≤ 4096 — else 400
    `{ "error": "line_too_long" }`.
  - `errorLine` length 1..4096 — else 400
    `{ "error": "invalid_error_line" }`.
  - All other fields validated by zod schema. Generic schema failures
    return 400 `{ "error": "invalid_payload", "detail": <zod message> }`.

  Execution: open a single Postgres transaction. Within it:

  1. Upsert into `incidents`:
     ```sql
     INSERT INTO incidents (fingerprint, error_line)
     VALUES ($1, $2)
     ON CONFLICT (fingerprint) DO UPDATE
       SET last_seen_at = now(),
           occurrence_count = incidents.occurrence_count + 1
     RETURNING fingerprint;
     ```
     Note: `error_line` is **only** set on initial insert. The
     `ON CONFLICT DO UPDATE` clause does not touch it.
  2. Insert into `incident_occurrences`:
     ```sql
     INSERT INTO incident_occurrences
       (fingerprint, app_version, os_version, device_model, context_lines, breadcrumbs)
     VALUES ($1, $2, $3, $4, $5::jsonb, $6);
     ```
     `context_lines` is bound as a JSON array (use `JSON.stringify(body.contextLines)`).

  Commit. On any DB error, rollback and return 500
  `{ "error": "internal_error" }` — log the underlying error at error
  level with the request id; do not include it in the response body.

  Success response: **201 Created**, body:
  ```json
  { "fingerprint": "<the 16-hex-char fingerprint>" }
  ```

  Auth failures:
  - Missing `x-telemetry-key` header → 401
    `{ "error": "missing_telemetry_key" }` (or whatever shape the existing
    telemetry-auth helper returns — match exactly).
  - Wrong key → 401 `{ "error": "invalid_telemetry_key" }`.

  No rate limiting beyond the SWA tier defaults. The iOS dedup at T-5004
  is the primary rate-limit mechanism.

  **Files added:** `app/api/incidents/report/route.ts`,
  `test/unit/api/incidents/report.test.ts`.
  **Acceptance criteria:**
  - First report for a new fingerprint: 201, one row in `incidents`
    (`occurrence_count = 1`), one row in `incident_occurrences`.
  - Second report for the same fingerprint: 201, the `incidents` row's
    `occurrence_count` is now 2, `last_seen_at` is updated, `error_line`
    is unchanged, two rows in `incident_occurrences`.
  - Reports with different fingerprints produce separate `incidents`
    rows.
  - Invalid fingerprint format (`"ABC"`, `"abc123"`, mixed case, or 17
    chars): 400 `invalid_fingerprint`.
  - `contextLines` of length 76: 400 `context_too_long`.
  - One context line of length 4097: 400 `line_too_long`.
  - Empty `contextLines` array (length 0): accepted, occurrence row
    contains `[]`.
  - Missing `x-telemetry-key` header: 401.
  - Wrong `x-telemetry-key`: 401.
  - DB transaction failure (e.g. simulated): 500 `internal_error`, no
    rows persisted.

  *Depends on: T-5101. Reuses the existing `TELEMETRY_API_KEY` and its
  validation helper from E-43 — no new SWA setting is added by this task.*

### Route: agent list incidents

- [ ] **T-5103** Create `app/api/agent/incidents/route.ts` implementing
  `GET /api/agent/incidents`. Authenticated with `AGENT_API_KEY` via
  `requireAgentKey` from T-4801. Cursor-paginated, supports a `status`
  filter.

  Query parameters (parsed via `zod`):
  - `status` — optional, one of `"open"`, `"investigating"`, `"resolved"`,
    `"ignored"`. Other values → 400
    `{ "error": "invalid_status" }`.
  - `cursor` — optional, opaque numeric string. Decoded server-side as
    `BIGINT` representing the lower bound (exclusive) for the
    `incident_occurrences.id`-equivalent cursor. **Decision: cursor is
    the `last_seen_at` ISO timestamp of the previous page's last incident,
    base64-encoded as JSON `{ "last_seen_at": "ISO8601", "fingerprint": "..." }`,
    matching the cursor pattern from T-4901.** Decode failures → 400
    `{ "error": "invalid_cursor" }`.

  Page size is fixed at **20** — no `limit` parameter is exposed.

  Response body:
  ```typescript
  interface AgentIncidentsResponse {
    incidents: AgentIncidentSummary[];
    nextCursor: string | null;        // null when has_more === false
  }
  interface AgentIncidentSummary {
    fingerprint: string;
    first_seen_at: string;            // ISO 8601 UTC
    last_seen_at: string;             // ISO 8601 UTC
    occurrence_count: number;
    error_line: string;
    status: "open" | "investigating" | "resolved" | "ignored";
    pr_url: string | null;
    pr_number: number | null;
  }
  ```

  SQL:
  ```sql
  SELECT fingerprint, first_seen_at, last_seen_at, occurrence_count,
         error_line, status, pr_url, pr_number
    FROM incidents
   WHERE ($1::text IS NULL OR status = $1)
     AND ($2::timestamptz IS NULL OR (last_seen_at, fingerprint) < ($2, $3))
   ORDER BY last_seen_at DESC, fingerprint DESC
   LIMIT 21;
  ```
  Parameter binding: `$1=status`, `$2=cursor.last_seen_at`,
  `$3=cursor.fingerprint`. Fetch one extra row to determine has-more —
  if 21 rows returned, drop the last and set `nextCursor` to the
  base64-JSON of `{ last_seen_at, fingerprint }` of the **20th** row.
  Otherwise `nextCursor: null`.

  The agent's typical access pattern is "highest occurrence_count among
  open incidents" (per ADR-006). This route returns by recency; the
  agent does the prioritisation client-side from the page contents. If
  the agent needs occurrence-count ordering in the future, that is a v2
  enhancement — not in this version.

  Error responses:
  - Invalid cursor → 400 `{ "error": "invalid_cursor" }`.
  - Invalid status → 400 `{ "error": "invalid_status" }`.
  - DB error → 500 `{ "error": "internal_error" }`.
  - Auth failures → 401 / 503 from `requireAgentKey`.

  **Files added:** `app/api/agent/incidents/route.ts`,
  `test/unit/api/agent/incidents-list.test.ts`.
  **Acceptance criteria:**
  - With no params: returns up to 20 incidents ordered by
    `last_seen_at DESC, fingerprint DESC`, plus `nextCursor` if there
    are more.
  - `?status=open` returns only open incidents.
  - `?status=resolved` returns only resolved incidents.
  - `?status=bogus` returns 400 `invalid_status`.
  - Following `nextCursor` returns the next 20, none overlapping the
    first page.
  - When fewer than 21 incidents match, `nextCursor` is `null`.
  - `?cursor=not-base64` returns 400 `invalid_cursor`.
  - Wrong agent key → 401.
  - `AGENT_API_KEY` unset → 503.

  *Depends on: T-5101, T-4801, T-4803.*

### Route: agent incident detail

- [ ] **T-5104** Create `app/api/agent/incidents/[fingerprint]/route.ts`
  implementing `GET /api/agent/incidents/:fingerprint`. Returns full
  incident metadata plus the most recent **10** occurrences (with
  `context_lines` and `breadcrumbs` included).

  Path parameter: `fingerprint` — must match `/^[0-9a-f]{16}$/`. Else
  400 `{ "error": "invalid_fingerprint" }`.

  SQL (two queries, run sequentially within the same request):

  1. Fetch the incident row:
     ```sql
     SELECT fingerprint, first_seen_at, last_seen_at, occurrence_count,
            error_line, status, pr_url, pr_number
       FROM incidents
      WHERE fingerprint = $1;
     ```
     If no row, return 404 `{ "error": "incident_not_found" }`.

  2. Fetch the recent occurrences:
     ```sql
     SELECT id, reported_at, app_version, os_version, device_model,
            context_lines, breadcrumbs
       FROM incident_occurrences
      WHERE fingerprint = $1
      ORDER BY reported_at DESC
      LIMIT 10;
     ```
     This query uses `incident_occurrences_fingerprint_reported_at_idx`
     from T-5101.

  Response body:
  ```typescript
  interface AgentIncidentDetailResponse {
    fingerprint: string;
    first_seen_at: string;
    last_seen_at: string;
    occurrence_count: number;
    error_line: string;
    status: "open" | "investigating" | "resolved" | "ignored";
    pr_url: string | null;
    pr_number: number | null;
    recent_occurrences: AgentIncidentOccurrence[];
  }
  interface AgentIncidentOccurrence {
    id: string;                    // BIGINT serialised as decimal string
    reported_at: string;
    app_version: string;
    os_version: string;
    device_model: string;
    context_lines: string[];       // unmarshalled from JSONB
    breadcrumbs: string;
  }
  ```

  `id` is serialised as a string to preserve full BIGINT precision
  through JSON.

  Error responses:
  - Invalid fingerprint format → 400 `invalid_fingerprint`.
  - No incident with that fingerprint → 404 `incident_not_found`.
  - DB error → 500 `internal_error`.
  - Auth failures → 401 / 503.

  **Files added:** `app/api/agent/incidents/[fingerprint]/route.ts`,
  `test/unit/api/agent/incidents-detail.test.ts`.
  **Acceptance criteria:**
  - For an incident with 3 occurrences: `recent_occurrences.length === 3`,
    ordered by `reported_at DESC`.
  - For an incident with 25 occurrences: `recent_occurrences.length === 10`,
    all are the most recent 10.
  - `context_lines` is returned as a JSON array of strings (not as a
    serialised JSON string).
  - `id` field is a decimal string (e.g. `"42"` not `42`).
  - For `fingerprint = "deadbeefdeadbeef"` with no row: 404
    `incident_not_found`.
  - `fingerprint = "ABC"` (wrong format): 400 `invalid_fingerprint`.
  - Wrong agent key → 401.

  *Depends on: T-5101, T-4801, T-4803.*

### Route: agent incident PATCH

- [ ] **T-5105** Create `app/api/agent/incidents/[fingerprint]/route.ts`
  PATCH handler in the same file as T-5104 (Next.js Route Handlers
  support multiple methods per file via named exports `GET`, `PATCH`,
  etc.). Allows the agent to update `status`, `pr_url`, and `pr_number`
  on an existing incident.

  Path parameter: `fingerprint` — same validation as T-5104.

  Request body (all fields optional, at least one required):
  ```typescript
  interface PatchIncidentRequest {
    status?: "open" | "investigating" | "resolved" | "ignored";
    pr_url?: string;        // 1..512 chars, must start with "https://"
    pr_number?: number;     // positive integer
  }
  ```

  Validation:
  - At least one of the three fields must be present — else 400
    `{ "error": "no_fields_to_update" }`.
  - `status`, if present, must be one of the four allowed values — else
    400 `{ "error": "invalid_status" }`.
  - `pr_url`, if present, must start with `"https://"` and have length
    1..512 — else 400 `{ "error": "invalid_pr_url" }`.
  - `pr_number`, if present, must be a positive integer — else 400
    `{ "error": "invalid_pr_number" }`.

  Execution: build a dynamic `UPDATE` with only the provided columns:
  ```sql
  UPDATE incidents
     SET status     = COALESCE($2, status),
         pr_url     = COALESCE($3, pr_url),
         pr_number  = COALESCE($4, pr_number)
   WHERE fingerprint = $1
   RETURNING fingerprint, status, pr_url, pr_number;
  ```
  Bind `null` for any field not provided — `COALESCE` then preserves the
  existing value. (Dynamic SQL with conditional `SET` clauses is also
  acceptable — choose whichever matches the existing codebase style.)

  If the `UPDATE` affects zero rows, return 404
  `{ "error": "incident_not_found" }`.

  Success response (200):
  ```json
  {
    "fingerprint": "...",
    "status": "investigating",
    "pr_url": "https://github.com/owner/repo/pull/42",
    "pr_number": 42
  }
  ```

  **Files changed:** `app/api/agent/incidents/[fingerprint]/route.ts`
  (add a `PATCH` named export).
  **Files added:** `test/unit/api/agent/incidents-patch.test.ts`.
  **Acceptance criteria:**
  - `PATCH` with `{ "status": "investigating" }` updates only status.
  - `PATCH` with `{ "pr_url": "https://...", "pr_number": 42, "status": "investigating" }`
    updates all three.
  - `PATCH` with `{}` returns 400 `no_fields_to_update`.
  - `PATCH` with `{ "status": "bogus" }` returns 400 `invalid_status`.
    (Both the zod check and the DB CHECK constraint protect this; the
    zod check fires first.)
  - `PATCH` with `{ "pr_url": "http://insecure.example.com" }` returns
    400 `invalid_pr_url`.
  - `PATCH` with `{ "pr_number": -1 }` returns 400 `invalid_pr_number`.
  - `PATCH` on a non-existent fingerprint returns 404
    `incident_not_found`.
  - The `GET` handler from T-5104 is unaffected (regression test).
  - Wrong agent key → 401.

  *Depends on: T-5101, T-5104 (same file), T-4801.*

### Agent-side PR script

- [ ] **T-5106** Create the agent-side PR-opening script at
  `agent/scripts/open-incident-pr.ts`. This script runs on the **agent
  runtime only** (a CI workflow, a developer machine, or the agent's
  scheduled worker — wherever the agent is deployed). It does **not**
  run inside the SWA Functions process. The backend already has the
  `pr_url` / `pr_number` columns from T-5101 but never touches GitHub
  itself.

  Inputs (environment variables — fail with a clear error if any is
  missing):
  - `AGENT_API_KEY` — the agent key for `/api/agent/*` routes.
  - `AGENT_API_BASE` — the SWA hostname, e.g. `"https://voxio-prod.azurestaticapps.net"`.
  - `GITHUB_TOKEN` — a GitHub personal access token (or fine-grained app
    token) with `contents:write` and `pull_requests:write` scopes on the
    target repo.
  - `GITHUB_REPO` — `"owner/repo"`, e.g. `"voxio-team/voxio"`.

  Flow:

  1. **Fetch open incidents.** Call
     `GET /api/agent/incidents?status=open` with header
     `x-agent-key: ${AGENT_API_KEY}`. Walk the cursor until the full list
     is gathered. Sort client-side by `occurrence_count DESC` and pick
     the highest. If the list is empty, log
     `"no open incidents"` and exit 0.
  2. **Fetch detail.** Call
     `GET /api/agent/incidents/${fingerprint}` with the same header.
     Read `error_line`, `recent_occurrences[0].context_lines`, and
     `recent_occurrences[0].breadcrumbs`.
  3. **Identify candidate source files.** Scan `error_line` for any
     `<filename>.swift:<line>` substring (the iOS logger format includes
     this). Also scan `context_lines` for the same pattern. Collect
     unique filenames. If none found, log
     `"no source files referenced in error"` and exit 0 — this incident
     cannot be fixed automatically.
  4. **Read source via GitHub API.** For each candidate file, call
     `GET /repos/${GITHUB_REPO}/contents/${path}` with
     `Authorization: Bearer ${GITHUB_TOKEN}`. Decode the base64 content.
     The script does **not** clone the repo — all reads are via the API.
  5. **Compose the fix.** This step is the agent's LLM reasoning; it is
     intentionally not a deterministic algorithm. Treat the source files,
     `error_line`, `context_lines`, and `breadcrumbs` as the prompt
     inputs. The script must:
     - Produce a unified diff against each modified file.
     - Generate a branch name `incident/${fingerprint}`.
     - Generate a PR title: `"Fix incident ${fingerprint}: ${first 60 chars of error_line}"`.
     - Generate a PR body containing: a link to the incident detail
       endpoint, the fingerprint, the occurrence count, the breadcrumbs,
       and the first 5 context lines.
  6. **Open the draft PR.** Use the GitHub API:
     - `POST /repos/${GITHUB_REPO}/git/refs` to create the branch from
       the default branch's HEAD.
     - `PUT /repos/${GITHUB_REPO}/contents/${path}` for each modified
       file (commit the diff).
     - `POST /repos/${GITHUB_REPO}/pulls` with `draft: true`.
     Capture the response's `html_url` and `number`.
  7. **Patch the incident.** Call
     `PATCH /api/agent/incidents/${fingerprint}` with body
     `{ "status": "investigating", "pr_url": <html_url>, "pr_number": <number> }`.
     Log success.

  Failure handling:
  - Any GitHub API error is fatal — log the error and exit 1. Do **not**
    PATCH the incident in this case (the incident remains `open` so the
    next run can retry).
  - Any agent-API error is fatal — exit 1.
  - The script is idempotent in the sense that re-running it on the same
    incident will fail at the branch-creation step (branch already exists)
    — that is acceptable behaviour for v1.

  Runtime: executable as `tsx agent/scripts/open-incident-pr.ts` or
  compiled to JS first; pick whichever the existing agent codebase uses.
  Match the dependency style of the existing agent scripts (if any
  `agent/scripts/*` directory already exists, look at its
  `package.json` and reuse the same SDK choices — `octokit/rest`,
  `node-fetch`, etc.).

  **Files added:** `agent/scripts/open-incident-pr.ts`,
  `agent/scripts/README.md` (a brief usage note documenting the four env
  vars and the exit codes).
  **Files changed:** none (specifically, **no** SWA Application Settings
  are added — `GITHUB_TOKEN` and `GITHUB_REPO` are agent-side only).
  **Acceptance criteria:**
  - Running the script with `AGENT_API_KEY` unset prints a clear error
    and exits non-zero.
  - Running the script when no open incidents exist exits 0 with the
    log line `"no open incidents"`.
  - Running the script when the highest-count open incident has no
    referenced source files exits 0 with the log line
    `"no source files referenced in error"`.
  - Running the script end-to-end against a test repo and a seeded
    incident: a draft PR appears in the repo, the incident's `status`
    becomes `investigating`, and `pr_url` + `pr_number` are populated.
  - The PR body contains the incident fingerprint, the occurrence count,
    and the first 5 anonymised context lines.
  - `GITHUB_TOKEN` does not appear in any log output.

  *Depends on: T-5103, T-5104, T-5105.*

### Tests

- [ ] **T-5107** Add an integration test at
  `test/integration/incident-flow.test.ts` exercising the full incident
  workflow end-to-end against a clean test database:

  1. **Seed.** Insert two incidents directly via SQL (one open, one
     resolved) so the test database has known content from non-iOS
     sources too. Truncate `incidents` and `incident_occurrences` at the
     start of each run.
  2. **Ingest 1.** `POST /api/incidents/report` with a synthetic payload
     for fingerprint `aaaa1111aaaa1111`. Assert 201, assert one row in
     each table.
  3. **Ingest 2.** `POST /api/incidents/report` with the same fingerprint.
     Assert 201, assert `incidents.occurrence_count = 2`, assert two
     rows in `incident_occurrences` with the correct `reported_at`
     ordering.
  4. **Ingest 3.** `POST /api/incidents/report` with a different
     fingerprint `bbbb2222bbbb2222`. Assert 201.
  5. **List.** `GET /api/agent/incidents?status=open` — assert at least
     three open incidents (the two seeded `open`-status incidents may or
     may not be present depending on truncation; assert the two
     test-created fingerprints are in the response).
  6. **Detail.** `GET /api/agent/incidents/aaaa1111aaaa1111` — assert
     `recent_occurrences.length === 2`, ordered by `reported_at DESC`.
  7. **Patch.** `PATCH /api/agent/incidents/aaaa1111aaaa1111` with
     `{ "status": "investigating", "pr_url": "https://github.com/x/y/pull/1", "pr_number": 1 }`.
     Assert 200.
  8. **Re-list with filter.** `GET /api/agent/incidents?status=open` —
     assert `aaaa1111aaaa1111` is no longer in the list. Assert
     `bbbb2222bbbb2222` still is.
  9. **Re-list investigating.** `GET /api/agent/incidents?status=investigating`
     — assert `aaaa1111aaaa1111` is in the list and its `pr_url` and
     `pr_number` match what was patched.
  10. **Auth.** Repeat steps 5–9 with the agent header omitted; assert
      every call returns 401. Repeat with the **wrong** key; assert 401.
  11. **Telemetry-key auth.** Repeat step 2 with the
      `x-telemetry-key` header omitted; assert 401.
  12. **Cascade.** `DELETE FROM incidents WHERE fingerprint = 'aaaa1111aaaa1111';`
      — assert all `incident_occurrences` rows for that fingerprint are
      gone.
  13. **Invalid input cases.** One call each:
      - Ingest with malformed fingerprint → 400 `invalid_fingerprint`.
      - Ingest with 76 context lines → 400 `context_too_long`.
      - List with `status=bogus` → 400 `invalid_status`.
      - Detail for `xxxxxxxxxxxxxxxx` (well-formed but unknown) → 404
        `incident_not_found`.
      - Patch with empty body → 400 `no_fields_to_update`.
      - Patch with `pr_url: "http://x"` → 400 `invalid_pr_url`.

  Run against a Neon dev branch dedicated to integration tests; teardown
  truncates `incidents` and `incident_occurrences` between runs.

  **Files added:** `test/integration/incident-flow.test.ts`.
  **Acceptance criteria:**
  - The full thirteen-step flow passes in CI in under 60 seconds.
  - No `device_id`, `transcription`, IPv4, UUID (other than the 16-hex
    fingerprint, which is **not** a UUID), or JID string appears in any
    response body (regex assertion on every response).

  *Depends on: T-5102, T-5103, T-5104, T-5105.*

### SWA route configuration

- [ ] **T-5108** Update `staticwebapp.config.json` at the repo root to
  declare the iOS-facing incident ingest route as
  anonymous-but-handler-gated, matching the pattern used for
  `/api/telemetry/*` (E-43) and `/api/agent/*` (T-4803).

  Add to the `routes` array:
  ```json
  {
    "route": "/api/incidents/*",
    "allowedRoles": ["anonymous"]
  }
  ```

  Place this entry **after** the existing `/api/telemetry/*` rule and
  **before** the `/api/agent/*` rule. Do not change any other routes.

  The `/api/agent/incidents` and `/api/agent/incidents/:fingerprint`
  routes are already covered by the existing `/api/agent/*` rule from
  T-4803 — no additional entry is needed for them.

  Confirm the resulting file is valid JSON
  (`cat staticwebapp.config.json | jq .`).

  **Files changed:** `staticwebapp.config.json`.
  **Files added:** none.
  **Acceptance criteria:**
  - The file remains valid JSON and SWA accepts it on deploy (no
    `Validation failed` in the deploy logs).
  - `POST /api/incidents/report` reaches the Route Handler when no SWA
    auth cookie is present (verified by observing a 401 from the
    handler-level telemetry-key check, not a 401 from SWA's auth layer
    with `WWW-Authenticate` header).
  - `GET /api/agent/incidents` continues to reach its handler via the
    existing `/api/agent/*` rule (regression check — no entry was
    accidentally introduced that overrides it).
  - The `/api/admin/*` and `/api/telemetry/*` routes continue to behave
    as before (regression check via existing tests).

  *Depends on: T-5102 (the route this configures must exist for the
  smoke test). Soft-blocks: T-5102 deployment — without this entry,
  SWA's default deny rule may intercept the request before the Route
  Handler runs.*
