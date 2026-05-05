# ADR E-33 — PersonalisationParser and Core Data schema

**Status:** Accepted
**Date:** 2026-05-05
**Epic:** E-33 (Voxio 1.3, Feature 1)

---

## Decision

Introduce a shared `PersistenceController` singleton owning a single Core Data container (`Voxio.xcdatamodeld`) with two entity groups: `Alias` and `ConfirmedCommand`. A new `PersonalisationStore` class wraps all CRUD and LRU eviction against that container. A new `PersonalisationParser` struct is initialised with a `PersonalisationStore` reference and injected into `CommandParserRouter` at construction time (init-parameter injection), inserting it as Tier 0 before Stage 1 regex in `CommandParserRouter.parse()`. The `PersistenceController` singleton is created in `VoxioApp` and passed down.

---

## Context

- iOS 26, Xcode 16+, `PBXFileSystemSynchronizedRootGroup` — every `.swift` file in `iOS/Voxio/` compiles automatically; no pbxproj editing is required for Swift files. However, the `.xcdatamodeld` bundle is a non-Swift resource and **does require manual addition to the Xcode project** (Add Files to Voxio target, ensure "Copy items if needed" is unchecked and the target membership checkbox is ticked). This is the single manual step E-33 requires.
- No Core Data stack exists in the project yet. E-33 creates the first and only container.
- `CommandParserRouter` currently takes no constructor parameters (`init()` in `CommandParserRouter.swift`). The store must be injected before first use.
- `PersonalisationParser` must be consulted before `fallback.parseStage1()`.
- `HomeView` constructs `CommandParserRouter` as `@State private var commandRouter = CommandParserRouter()`. This instantiation site is the injection point.
- The spec's Resolved Decisions section confirms: aliases take precedence over confirmed-command entries; alias scope is per `Speaker.id`; aliases do not bypass the confirmation step.
- `CommandIntent` enum needs no new cases for E-33.
- The confirmed-command store cap is 200 entries per speaker, LRU eviction on `lastUsedAt`.

---

## Options Considered

**Option A — Init-parameter injection (chosen)**

`CommandParserRouter` gains an `init(personalisationStore: PersonalisationStore)` parameter. `HomeView` constructs both the store and the router, passing the store at init. `PersistenceController.shared` is the singleton source.

- Pro: explicit, testable (mock store can be injected in unit tests), no hidden global state in the parser.
- Pro: `CommandParserRouter` remains a plain `final class` with no SwiftUI dependencies.
- Con: `HomeView` must hold a reference to the store; minor boilerplate.

**Option B — Singleton access inside `CommandParserRouter`**

`CommandParserRouter.parse()` calls `PersonalisationStore.shared` directly.

- Pro: zero changes to `HomeView` call sites.
- Con: impossible to unit-test `CommandParserRouter` without hitting real Core Data. Unacceptable.

**Option C — SwiftUI `@Environment` injection**

- Con: `CommandParserRouter` is a plain class, not a SwiftUI view. Collapses to Option A anyway.

---

## Rationale

Option A keeps the parser layer testable and the dependency graph explicit. The only downside (minor `HomeView` boilerplate) is outweighed by the ability to inject a mock `PersonalisationStore` in unit tests.

---

## Consequences

- T-3304 requires modifying `CommandParserRouter.init()` and `CommandParserRouter.parse()`. The `parse()` method gains a `speakerId: String` parameter — see conflicts.
- `HomeView` must construct `PersonalisationStore` and pass it to `CommandParserRouter(personalisationStore:)`.
- T-3305 (write on confirm) and T-3306 (delete on cancel) both touch `HomeView`.
- The `.xcdatamodeld` file must be added manually to the Xcode project.
- E-35 (`TelemetryBuffer`) adds a third entity to the same container — no migration needed if added before first app store submission.

---

## File-Level Plan

### New files

| Path | Purpose |
|---|---|
| `iOS/Voxio/Core/Persistence/PersistenceController.swift` | Singleton; creates `NSPersistentContainer("Voxio")`, exposes `viewContext` and `newBackgroundContext()` |
| `iOS/Voxio/Core/Persistence/Voxio.xcdatamodeld` | Core Data model — `Alias` and `ConfirmedCommand` entities. **Requires manual Xcode project addition.** |
| `iOS/Voxio/Core/Personalisation/PersonalisationStore.swift` | CRUD class for `Alias` and `ConfirmedCommand`; LRU eviction; `isEnabled` toggle |
| `iOS/Voxio/Core/Personalisation/PersonalisationParser.swift` | `parse(_:speakerId:) -> ParsedCommand?`; logs `"PersonalisationAlias"` or `"PersonalisationMemory"` |

### Modified files

| Path | Change |
|---|---|
| `iOS/Voxio/Core/CommandParsing/CommandParserRouter.swift` | Add `init(personalisationStore:)`; insert Tier 0 call before `fallback.parseStage1()` |
| `iOS/Voxio/Features/Home/HomeView.swift` | Construct `PersonalisationStore`; pass to router; write on confirm (T-3305); delete on cancel (T-3306) |
| `iOS/Voxio/VoxioApp.swift` | Warm up `PersistenceController.shared` on launch |

---

## Public Interface Contract

```swift
// PersistenceController.swift
final class PersistenceController {
    static let shared: PersistenceController
    let viewContext: NSManagedObjectContext
    func newBackgroundContext() -> NSManagedObjectContext
    static let preview: PersistenceController  // for tests/previews
}

// PersonalisationStore.swift
@MainActor
final class PersonalisationStore {
    var isEnabled: Bool
    init(context: NSManagedObjectContext)

    func saveAlias(speakerId: String, phrase: String, intent: CommandIntent, slots: [String: String]) throws
    func aliases(for speakerId: String) -> [AliasRecord]
    func deleteAlias(_ id: UUID) throws
    func deleteAllAliases(for speakerId: String) throws

    func recordConfirmedCommand(speakerId: String, transcription: String, intent: CommandIntent, slots: [String: String]) throws
    func deleteConfirmedCommand(transcription: String, speakerId: String) throws
    func clearAllConfirmedCommands() throws

    func matchAlias(phrase: String, speakerId: String) -> ParsedCommand?
    func matchConfirmedCommand(transcription: String, speakerId: String) -> ParsedCommand?
}

struct AliasRecord {
    let id: UUID
    let speakerId: String
    let phrase: String
    let intent: CommandIntent
    let slots: [String: String]
    let createdAt: Date
}

// PersonalisationParser.swift
struct PersonalisationParser {
    init(store: PersonalisationStore)
    func parse(_ text: String, speakerId: String) -> ParsedCommand?
}
```

---

## Conflicts Flagged

**CONFLICT — `parse()` signature mismatch (T-3304 vs. existing call site)**

The current public signature of `CommandParserRouter.parse()` is `func parse(_ transcript: String) async -> VoiceCommand` — it receives only a speaker-stripped transcript with no `speakerId`. The router's `parse()` method must be extended:

```swift
// Required after E-33:
func parse(_ transcript: String, speakerId: String) async -> VoiceCommand
```

This is a breaking change to the existing public API. `HomeView` must be updated to pass `speaker.id` at the call site. The Test Writer should write tests against the updated signature.
