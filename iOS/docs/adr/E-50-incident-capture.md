# ADR: E-50 — On-Device Incident Capture

**Status:** Approved — gates Implementer and Test Writer start
**Date:** 2026-05-07
**Epic:** E-50 (T-5001 – T-5006)

---

## Decision

`IncidentReporter` is implemented as a `LogListener` registered in the existing fan-out inside `VoxioApp.init()`, downstream of `FileLogListener.shared`. It is `@MainActor` with a `nonisolated didLog` entry point that hops to the main actor for dedup/assembly before dispatching a detached `Task` for the network upload. `WiFiPathMonitor` is a new dedicated singleton wrapping `NWPathMonitor`; it does not reuse the per-instance monitor inside `MozartEvents` (which is per-speaker and cannot be shared). All four new types (`LogAnonymiser`, ring-buffer extension on `FileLogListener`, `BreadcrumbTracker`, `IncidentReporter`) live under `iOS/Voxio/Core/Logging/`.

---

## Context

- `Logger.swift` defines `Log` (not `Logger`) as an enum and `LogListener` as `protocol LogListener: AnyObject { func didLog(level: Log.Level, line: String, timestamp: Date) }`. The spec uses `Logger.Level` and a four-argument `didLog(level:message:file:line:)` signature — neither matches the existing protocol (see Conflicts).
- `FileLogListener` already formats a `fileLine` string (full ISO timestamp + level tag + message) on its serial `DispatchQueue`. The ring buffer must append this same `fileLine`, not the raw `line` passed into `didLog`.
- `TelemetryUploader` sends the telemetry key as `x-api-key`. T-5004 specifies `x-telemetry-key` for the incident upload — these are separate endpoints, intentionally distinct.
- `MozartEvents` creates a private, per-instance `NWPathMonitor`. There is no shared monitor to reuse — `WiFiPathMonitor` is a genuinely new file.
- The top-level Home view is `HomeView.swift`, not `ContentView.swift` as stated in T-5006.
- `VoxioApp.init()` already calls `Log.addListener(FileLogListener.shared)` — T-5005 appends `IncidentReporter.shared` after it.

---

## Options Considered

**Option A — LogListener fan-out (chosen).** `IncidentReporter` conforms to the existing `LogListener` protocol. Zero changes to `Log.emit`. Dedup and upload are fire-and-forget on a detached task. Ring buffer is a sidecar inside `FileLogListener` guarded by the existing serial queue.
Trade-off: `didLog` is `nonisolated` by protocol requirement, requiring a main-actor hop per error line; adds minor overhead on every log call (gated cheaply by the `.error` level check).

**Option B — Dedicated error hook on `Log`.** Add a separate `onError: ((String) -> Void)?` closure to `Log.emit`.
Trade-off: avoids per-call overhead but requires modifying `Log` (a shared infrastructure type). Rejected.

---

## Rationale

Option A keeps `Log` untouched, matches the established fan-out pattern, and requires no changes to any existing call site. The per-call overhead for non-error lines is a single integer comparison (`level != .error`) and an immediate return — negligible.

---

## Consequences

1. Context lines in incident payloads carry the full `yyyy-MM-dd HH:mm:ss.SSS` timestamp prefix (the `fileLine` format), not a short time.
2. If an error fires before any view pushes a breadcrumb, `currentPath` will be `""` — acceptable per spec.
3. The 24-hour dedup key is written **before** the WiFi check. A device on cellular will suppress upload for 24 hours even if WiFi becomes available shortly after. This matches ADR-006 intent.
4. `WiFiPathMonitor.shared.stop()` is for test teardown only — production code must not call it.

---

## File-Level Plan

**New files:**

| Path | Type | Task |
|---|---|---|
| `iOS/Voxio/Core/Logging/LogAnonymiser.swift` | struct | T-5001 |
| `iOS/Voxio/Core/Logging/BreadcrumbTracker.swift` | @MainActor @Observable class | T-5003 |
| `iOS/Voxio/Core/Logging/IncidentReporter.swift` | @MainActor LogListener class | T-5004 |
| `iOS/Voxio/Core/Networking/WiFiPathMonitor.swift` | final class | T-5005 |
| `iOS/VoxioTests/LogAnonymiserTests.swift` | unit tests | T-5001 |
| `iOS/VoxioTests/FileLogListenerRingBufferTests.swift` | unit tests | T-5002 |
| `iOS/VoxioTests/BreadcrumbTrackerTests.swift` | unit tests | T-5003 |
| `iOS/VoxioTests/IncidentReporterTests.swift` | unit tests | T-5004 |

**Modified files:**

| Path | Change | Task |
|---|---|---|
| `iOS/Voxio/Core/Logging/FileLogListener.swift` | Add `ringBufferCapacity` + `ringBufferSnapshot()` | T-5002 |
| `iOS/Voxio/VoxioApp.swift` | Add `Log.addListener(IncidentReporter.shared)` + `WiFiPathMonitor.shared.start()` in `init()` | T-5005 |
| `iOS/Voxio/Features/Home/HomeView.swift` | `.onAppear`/`.onDisappear` breadcrumb push/pop | T-5006 |
| `iOS/Voxio/Features/Settings/SettingsView.swift` | breadcrumb push/pop + child destination views | T-5006 |

---

## Public Interface Contract

```swift
// LogAnonymiser.swift
public struct LogAnonymiser {
    public init()
    public func anonymise(_ line: String) -> String
}

// FileLogListener.swift (additions)
extension FileLogListener {
    public static let ringBufferCapacity: Int = 25
    public func ringBufferSnapshot() -> [String]
}

// BreadcrumbTracker.swift
@MainActor
@Observable
public final class BreadcrumbTracker {
    public static let shared = BreadcrumbTracker()
    private init() {}
    private(set) public var stack: [String] = []
    public var currentPath: String { stack.joined(separator: " > ") }
    public func push(_ screenName: String)
    public func pop()
    public func reset()
}

// IncidentReporter.swift
@MainActor
public final class IncidentReporter: LogListener {
    public static let shared = IncidentReporter()
    private init()
    // Matches existing LogListener protocol — NOT Logger.Level or (level:message:file:line:)
    public nonisolated func didLog(level: Log.Level, line: String, timestamp: Date)
}

// IncidentPayload (internal in IncidentReporter.swift)
struct IncidentPayload: Encodable {
    let fingerprint: String      // 16 lowercase hex chars
    let appVersion: String
    let osVersion: String
    let deviceModel: String
    let contextLines: [String]
    let breadcrumbs: String
    let errorLine: String
}

// WiFiPathMonitor.swift
public final class WiFiPathMonitor {
    public static let shared = WiFiPathMonitor()
    private init() {}
    public func start()
    public func stop()
    public var isWiFi: Bool
}
```

Key implementation notes:
- `didLog` receives the already-formatted `line` string. `IncidentReporter` derives its `errorLine` from this `line` directly.
- Fingerprint = first 16 lowercase hex chars of SHA-256(`normalised_anonymised_message + appVersion`). "Normalised" = strip timestamp prefix, then strip all `\d+` runs.
- Dedup key: `"incident_reported_" + fingerprint` in `UserDefaults.standard` as `Double` Unix seconds.
- Upload: `POST https://<TELEMETRY_HOSTNAME>/api/incidents/report`, header `x-telemetry-key`, JSON body with camelCase keys.
- Recursion guard: skip when `line` contains literal `[IncidentReporter:internal]`.
- Retry on transient errors: 2s, 5s, 10s. HTTP 4xx: no retry.
- `WiFiPathMonitor.start()` is idempotent (Bool flag under NSLock).

---

## Conflicts Flagged

**CONFLICT 1 — Protocol signature mismatch (resolved by this ADR).**
Spec T-5004 defines `didLog(level: Logger.Level, message: String, file: String, line: Int)`. Actual protocol: `didLog(level: Log.Level, line: String, timestamp: Date)`. The ADR's interface contract above is authoritative — use it, not the spec text.

**CONFLICT 2 — `ContentView.swift` does not exist (T-5006).**
The home view file is `HomeView.swift`. Breadcrumb name `"Home"` is unchanged.

**CONFLICT 3 — `Logger.addListener` vs `Log.addListener` (T-5005).**
Use `Log.addListener(...)` — `Logger` does not exist in this codebase.

**CONFLICT 4 — `x-api-key` vs `x-telemetry-key` header (informational).**
Incident upload uses `x-telemetry-key`. Do not reuse the `x-api-key` constant from `TelemetryUploader`.

---

**Verdict: PROCEED**
