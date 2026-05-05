# ADR E-35 — Telemetry Buffer and Consent

**Status:** Accepted
**Date:** 2026-05-05
**Epic:** E-35 (Voxio 1.3, Feature 1 — Flow A)

---

## Decision

Implement telemetry as a pure-Swift, no-SDK solution comprising four components: `TelemetryEvent` (value type), `TelemetryBuffer` (Core Data entity + manager class added to the shared `Voxio.xcdatamodeld` container), `TelemetryUploader` (network layer, `NWPathMonitor`-gated, `URLSession`-based), and a Keychain wrapper for the anonymous device ID. Consent state lives in `UserDefaults` (matching the `PersonalisationStore.isEnabled` pattern). The misparse detection window is maintained in-memory as a bounded dictionary keyed by `speakerId`. SHA-256 hashing is performed with `CryptoKit`. The 24-hour upload interval is tracked with a `UserDefaults` timestamp — no `BackgroundTasks` framework registration. The command count triggering the first-time prompt is stored in `UserDefaults`. `TELEMETRY_BASE_URL` requires creating new xcconfig files since none exist yet in the project; both files must also be registered in the Xcode project's build configuration — a manual step analogous to the `.xcdatamodeld` step in E-33.

---

## Context

- iOS 26, Xcode 16+, `PBXFileSystemSynchronizedRootGroup`. Any `.swift` file dropped into `iOS/Voxio/` compiles automatically. Non-Swift resources (xcconfig files) require manual Xcode project wiring.
- Swift strict concurrency is active: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` are set inline in `project.pbxproj` for the Voxio target.
- `PersistenceController.shared` is the single Core Data container, already in use by E-33's `Alias` and `ConfirmedCommand` entities. E-35 adds a third entity (`TelemetryEvent`) to the same container. The spec's Resolved Decisions table explicitly confirms this.
- `PersonalisationStore` (`@MainActor final class`) is the established CRUD pattern: uses `viewContext` directly on `@MainActor` and `NSBatchDeleteRequest` for bulk deletes. `TelemetryBuffer` must follow this pattern.
- `MozartClient` is the networking precedent: `URLSession` with a per-request 5-second timeout, typed error mapping.
- The project has no xcconfig files at all. Build settings are inline in `project.pbxproj`. `GENERATE_INFOPLIST_FILE = YES` is set for the Voxio target.
- The entitlements file (`Voxio.entitlements`) declares only `com.apple.security.application-groups`. No additional entitlement is needed for standard Keychain access under the app's own access group.
- Open Question 5 in the spec explicitly acknowledges the backend API shape is undefined. App-side types can be finalized; upload and deletion URLs must be treated as placeholders.
- Open Question 3 (per-day recording cap) resolves to 200 events per day per the spec's default assumption.

---

## Options Considered

### T-3502: TelemetryBuffer storage backend

**Option A — Core Data entity in the shared container (chosen)**

Add a `TelemetryEvent` entity to `Voxio.xcdatamodeld`. `TelemetryBuffer` is an `@MainActor final class` wrapping `PersistenceController.shared.viewContext`. Cap enforcement uses `NSBatchDeleteRequest` sorted by `timestamp` ascending when count exceeds 1,000.

- Pro: single container; consistent eviction and query semantics; no new dependency; matches the E-33 pattern exactly.
- Con: adds a third entity; future schema changes require lightweight migration discipline.

**Option B — Separate SQLite or JSON on disk**

- Con: no third-party SQLite wrapper available; JSON file lacks atomic batch semantics. Rejected.

### T-3505: Upload scheduling

**Option A — `BackgroundTasks` framework (`BGAppRefreshTask`)**

- Con: requires `BGTaskSchedulerPermittedIdentifiers` in `Info.plist`. With `GENERATE_INFOPLIST_FILE = YES`, Info.plist array keys cannot be added through a simple xcconfig key. System may defer tasks arbitrarily. Complex to test. The spec does not require uploads when the app is closed.

**Option B — UserDefaults timestamp + on-foreground check (chosen)**

On each app foreground event, compare `Date()` against `UserDefaults.standard.object(forKey: "lastTelemetryUploadDate")`. If > 24 hours, attempt an upload, gated on `NWPathMonitor` reporting `.satisfied` with `isExpensive == false` and Low Power Mode off.

- Pro: zero additional entitlements or Info.plist keys; matches the project's existing posture; straightforward to test.

### T-3507: Anonymous device ID storage

**Option A — Security framework Keychain (chosen)**

`SecItemAdd` / `SecItemCopyMatching` with service `"T-Creative.Voxio"`, account `"voxio.telemetry.deviceId"`. UUID string stored as `kSecValueData`. Regenerated on user-initiated personalisation clear.

- Pro: survives app updates; stable enough for server-side deletion requests.

**Option B — UserDefaults UUID**

- Con: wiped on app reinstall; cannot correlate with previously uploaded data for deletion. Rejected.

### T-3503: SHA-256 hashing

**CryptoKit (chosen)** — `CryptoKit.SHA256.hash(data:)` is available on iOS 13+, is `Sendable`-safe, requires no additional framework linkage.

### T-3504: Misparse detection window

**In-memory bounded dictionary (chosen)** — `[String: (objectID: NSManagedObjectID, timestamp: Date)]` keyed by `speakerId`. When a `confirmed` event of a different intent arrives within 30 seconds, the prior `cancelled` event is retroactively flagged. No persistence across launches — acceptable per spec.

---

## Rationale

The Core Data shared container approach mirrors the E-33 decision and the spec's Resolved Decisions table. The UserDefaults timestamp approach for upload scheduling avoids `BackgroundTasks` entitlement complexity that conflicts with `GENERATE_INFOPLIST_FILE = YES`. CryptoKit is the correct first-party SHA-256 implementation. The in-memory misparse window is the simplest correct solution for a 30-second scope. The Keychain device ID is the only viable solution for stable cross-update identity.

---

## Platform Constraint Violations and Flags

**FLAG 1 — xcconfig files do not exist; T-3509 is a project infrastructure creation task**

No xcconfig files exist anywhere in the project. The implementer must:
1. Create `iOS/Voxio/Config/Debug.xcconfig` and `iOS/Voxio/Config/Release.xcconfig`.
2. In Xcode's project editor (Project > Info > Configurations), manually assign each file to the corresponding build configuration for the Voxio target. Dropping files via `PBXFileSystemSynchronizedRootGroup` does NOT wire xcconfig files to build configurations.
3. Add `INFOPLIST_KEY_TELEMETRY_BASE_URL = $(TELEMETRY_BASE_URL)` in both xcconfig files so that `Bundle.main.infoDictionary["TELEMETRY_BASE_URL"]` resolves at runtime.

**FLAG 2 — Strict concurrency: `NSManagedObjectContext` on `@MainActor`**

`TelemetryBuffer` must be `@MainActor final class` and must only use `PersistenceController.shared.viewContext`. The implementer must not use `newBackgroundContext()` for `TelemetryBuffer`; doing so would conflict with being called from `HomeView.onResolved` (which is `@MainActor`).

**FLAG 3 — Keychain calls are synchronous blocking calls**

`SecItemAdd` / `SecItemCopyMatching` block the calling thread. The device ID must be read once at `TelemetryUploader` init and cached. Must not be called from hot paths.

**FLAG 4 — `NWPathMonitor` delivers updates on a non-main dispatch queue**

`TelemetryUploader` must store the current path state in a `@MainActor` property updated via `MainActor.run { self.currentPath = path }` from the monitor callback. Reading path properties directly from the callback inside a `@MainActor`-isolated method is a data race under Swift 6.

**FLAG 5 — Backend API shape is undefined (Open Question 5)**

Upload endpoint URL, batch JSON format, and `DELETE /telemetry/{deviceId}` URL are explicitly unresolved. The implementer must:
- Define placeholder `Codable` types with `// TODO: align with backend spec` comments.
- Guard all upload/delete calls with a `baseURL != nil` check; silently no-op when URL is `nil`.
- Ensure E-36 (Shared Data screen) can display "pending deletion" state without a live backend.

**FLAG 6 — ATS covers HTTPS to the open internet without additional config**

The current `NSAppTransportSecurity` config (`NSAllowsLocalNetworking = true`) does not interfere with outbound HTTPS. ATS default policy (TLS 1.2+) applies. The backend team must use a CA-signed certificate.

---

## Consequences

- `Voxio.xcdatamodeld` gains a `TelemetryEvent` entity. Since v1.3 is in active development and the schema has not yet shipped, adding the entity now incurs no migration overhead.
- `HomeView` — specifically the `onResolved` closure — must call `TelemetryBuffer.record(...)` alongside existing T-3305/T-3306 personalisation calls. Additive; no existing logic changes.
- `CommandParserRouter` must expose the parser path string from each `parse()` call via a `@MainActor var lastParserPath: String?` stored property updated at the end of `parse()`.
- `Voxio.entitlements` requires no changes.
- The 50-command threshold for the first-time consent prompt must be guarded by `@AppStorage("hasSeenTelemetryPrompt")` to prevent repeated display.

---

## File-Level Plan

### New files

| Path | Purpose |
|---|---|
| `iOS/Voxio/Core/Telemetry/TelemetryEvent.swift` | T-3501 — `TelemetryEvent` struct, `TelemetryOutcome` enum, `TelemetryFlags` OptionSet |
| `iOS/Voxio/Core/Telemetry/TelemetryBuffer.swift` | T-3502/T-3503/T-3504 — Core Data wrapper, `record()` with anonymisation and SHA-256, in-memory misparse window |
| `iOS/Voxio/Core/Telemetry/TelemetryUploader.swift` | T-3505/T-3506/T-3507/T-3508 — batch upload, `NWPathMonitor` gating, Keychain device ID, DELETE request, 50-command prompt trigger |
| `iOS/Voxio/Core/Telemetry/KeychainDeviceID.swift` | T-3507 — thin Security framework wrapper: `read()`, `write(_:)`, `delete()`, `readOrCreate()` |
| `iOS/Voxio/Config/Debug.xcconfig` | T-3509 — `TELEMETRY_BASE_URL` = staging placeholder |
| `iOS/Voxio/Config/Release.xcconfig` | T-3509 — `TELEMETRY_BASE_URL` = production placeholder |

### Modified files

| Path | Tasks |
|---|---|
| `iOS/Voxio/Core/Persistence/Voxio.xcdatamodeld/Voxio.xcdatamodel/contents` | T-3502 — add `TelemetryEvent` entity: `id` (UUID), `transcriptionAnonymised` (String), `intent` (String), `slotsAnonymised` (String), `parserPath` (String), `outcome` (String), `appVersion` (String), `modelVersion` (String), `locale` (String), `timestamp` (Date), `flagsJSON` (String), `speakerId` (String), `uploaded` (Boolean default NO) |
| `iOS/Voxio/Core/CommandParsing/CommandParserRouter.swift` | Add `@MainActor var lastParserPath: String?` updated after each `parse()` call |
| `iOS/Voxio/Features/Home/HomeView.swift` | T-3505/T-3506 — call `TelemetryBuffer.record()` from `onResolved`; increment `UserDefaults("confirmedCommandCount")`; present consent prompt when count reaches 50 and `hasSeenTelemetryPrompt == false` |

### Manual Xcode steps (cannot be automated via `PBXFileSystemSynchronizedRootGroup`)

1. Open `iOS/Voxio.xcodeproj` in Xcode, navigate to Project > Info > Configurations, and assign `Debug.xcconfig` to Debug and `Release.xcconfig` to Release for the Voxio target.
2. In the Voxio target's Build Settings, add `INFOPLIST_KEY_TELEMETRY_BASE_URL = $(TELEMETRY_BASE_URL)` so the key appears in `Bundle.main.infoDictionary`.

---

## Public Interface Contract

```swift
// TelemetryEvent.swift

enum TelemetryOutcome: String, Codable {
    case confirmed, cancelled, timedOut, unknown
}

struct TelemetryFlags: OptionSet, Codable {
    let rawValue: Int
    static let likelyMisparse     = TelemetryFlags(rawValue: 1 << 0)
    static let recoverableUnknown = TelemetryFlags(rawValue: 1 << 1)
    static let broadcast          = TelemetryFlags(rawValue: 1 << 2)
}

struct TelemetryEvent: Identifiable {
    let id: UUID
    let transcriptionAnonymised: String
    let intent: String
    let slotsAnonymised: String   // JSON string
    let parserPath: String
    let outcome: TelemetryOutcome
    let appVersion: String
    let modelVersion: String
    let locale: String
    let timestamp: Date
    var flags: TelemetryFlags
    let speakerId: String
}

// TelemetryBuffer.swift

@MainActor
final class TelemetryBuffer {
    static let maxEventCount = 1_000
    static let maxEventsPerDay = 200

    init(context: NSManagedObjectContext)

    func record(
        transcription: String,
        speakerName: String,
        intent: String,
        slots: [String: String],
        parserPath: String,
        outcome: TelemetryOutcome,
        locale: String,
        flags: TelemetryFlags
    ) throws

    func pendingBatch(limit: Int) throws -> [TelemetryEvent]
    func markUploaded(_ ids: [UUID]) throws
    func flagAsMisparse(eventId: UUID) throws
    func deleteAll() throws
    func uploadedCount(since: Date) throws -> Int
}

// TelemetryUploader.swift

@MainActor
final class TelemetryUploader {
    var isEnabled: Bool   // backed by UserDefaults "telemetryEnabled"

    init(buffer: TelemetryBuffer)

    func attemptUploadIfDue() async
    func requestDeletion() async -> DeletionResult

    enum DeletionResult {
        case success
        case pending
        case failed(Error)
    }
}

// KeychainDeviceID.swift (nonisolated — Security framework calls)

enum KeychainDeviceID {
    static func read() -> UUID?
    static func write(_ id: UUID)
    static func delete()
    static func readOrCreate() -> UUID
}
```

---

## Conflicts Flagged

1. **T-3509 is a project infrastructure task.** xcconfig files do not exist. If the manual Xcode wiring step is skipped, `Bundle.main.infoDictionary["TELEMETRY_BASE_URL"]` returns `nil` at runtime. `TelemetryUploader` must treat a `nil` URL as a graceful no-op, not a crash.

2. **`TelemetryBuffer.record()` requires `speakerName` for anonymisation.** The call site in `HomeView.onResolved` has access to `speaker.name` from the outer closure capture. Additive; no existing signature changes.

3. **`CommandParserRouter` does not currently expose `parserPath`.** The path is only emitted via `Log.info`. A `@MainActor var lastParserPath: String?` property is the least-invasive addition. Alternatively `parse()` can return `(VoiceCommand, parserPath: String)` — a breaking API change requiring HomeView and test updates.

4. **First-time prompt counter lives in `UserDefaults("confirmedCommandCount")`.** The prompt guard key is `@AppStorage("hasSeenTelemetryPrompt")`. Both are reset together with personalisation data.

5. **`DELETE /telemetry/{deviceId}` URL shape is undefined.** Placeholder URL: `baseURL?.appendingPathComponent("telemetry").appendingPathComponent(deviceId.uuidString)` with a `// TODO: verify endpoint with backend team` comment. E-36 deletion UI state machine must function without a live backend.

---

PROCEED
