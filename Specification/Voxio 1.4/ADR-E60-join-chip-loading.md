# ADR-E60 — Join Chip Loading State (E-60): handleJoinDrop Implementation, ChipKind.loading, joinsInFlight Lifecycle

**Status:** Accepted
**Date:** 2026-05-12
**Deciders:** Engineering Lead
**Refs:** ADR-E59-drag-to-join-infrastructure.md (§5 Consequences), ADR-E53-group-chip-row.md (§5 CF-3/CF-4, §7 contract), ADR-003-listener-based-grouping.md (§5 contract 6), ADR-002-voxio-1.4-ios.md (D5, @MainActor invariant), spec-multiroom-grouping.md v1.0 (TR-4, TR-5, US-81), design-spec-multiroom-grouping.md v1.1 (§4.1, §4.2, §6.3), epics-and-tasks-multiroom-grouping.md v1.0 (E-60 T-6001–T-6005), CLAUDE.md

---

## 1. Decision

`SessionViewModel.handleJoinDrop(source:target:)` is fully implemented in E-60 by: (1) inserting the source speaker's `SpeakerIdentifier.id` into `joinsInFlight` immediately on the main actor; (2) launching a detached `Task` that races `source.client.join(peer: target.identifier)` against a 10-second `Task.sleep` timeout via `withThrowingTaskGroup`; (3) on success calling `discovery.mergeIntoSpeakerGroup` and scheduling `discovery.refreshGroups()` after a ≥ 300 ms debounce per ADR-003 §5 contract 6; (4) on failure or timeout firing `HapticEngine.shared.errorOccurred()` and surfacing an error toast via an injected `onError: (String) -> Void` callback. A new `case loading(name: String)` is added to `ChipKind` in `GroupChipRow.swift`. `SpeakerCard.chipData` is extended to union the settled-members chips with loading chips produced from the card's `SessionViewModel.joinsInFlight`. The `joinsInFlightUnion` aggregation on `HomeView` is wired reactively from `SessionStripView` via `.onChange(of: sessionVMs.values.map(\.joinsInFlight))` so the bottom-bar pill eligibility gates correctly for the duration of every in-flight join.

---

## 2. Context

### Prior ADRs that constrain this epic

**ADR-E59 §5 Consequences.** E-59 shipped `handleJoinDrop` as a stub. `joinsInFlight: Set<String>` and `joinTasks: [String: Task<Void, Never>]` are in place. `joinsInFlightUnion: Set<String>` is `@State` on `HomeView` and threaded through `SessionStripView`'s `$joinsInFlightUnionBinding`. E-60 must NOT add `@unknown default` to `GroupChipRow.body`'s `switch chip.kind` — that switch was deliberately left exhaustive over `.member` / `.overflow(Int)` so adding `.loading` produces a compile-time break that forces the implementer to add the rendering branch.

**ADR-E53 §5 CF-3.** Adding `case loading` to `ChipKind` breaks the exhaustive switch in `GroupChipRow.body`. Intentional. No `@unknown default`.

**ADR-E53 §5 CF-4 / §8.** E-61 will add `var onTap: (@MainActor () -> Void)? = nil` to `ChipData`. E-60 must not add stored properties to `ChipData`; only `ChipKind` grows in E-60.

**ADR-003 §5 contract 6.** A successful `beolinkExpand`/`expandExperience` write must trigger `discovery.refreshGroups()` after a ≥ 300 ms debounce. E-60 owns this trigger.

**ADR-002 D5.** A 10-second client-side timeout must be enforced on the `join(peer:)` call. Implemented via `withThrowingTaskGroup` racing the join task against `Task.sleep(for: .seconds(10))`.

### Current codebase state (post commit `26b5698`)

- `SessionViewModel.handleJoinDrop` and `handleRemoveTap` are stubs (log + return).
- `joinsInFlight` / `joinTasks` are live stored properties on `SessionViewModel`.
- `GroupChipRow.swift`'s `ChipKind` has only `.member` and `.overflow(Int)`. Body switch is exhaustive over these two.
- `HomeView.@State joinsInFlightUnion: Set<String> = []` exists and forwards to `SpeakerSelectorPill`.
- `SessionStripView` has a `joinsInFlightUnion` computed (`sessionVMs.values.reduce(into: Set<String>()) { $0.formUnion($1.joinsInFlight) }`) and a `@Binding var joinsInFlightUnionBinding: Set<String>`. The binding is currently written only inside `.onChange(of: groups.map(\.id))` — E-60 T-6004 adds a second write triggered by `joinsInFlight` changes.
- `SpeakerError.timeout` exists (`/iOS/Voxio/Core/Errors/SpeakerError.swift`).
- `Toast` / `ToastKind` exist; `HomeView.showErrorToast(_:)` is private. `SessionViewModel` cannot call it directly — must route via injected callback.
- `discovery.mergeIntoSpeakerGroup(source:target:)` and `discovery.refreshGroups()` exist.
- `SpeakerIdentifier.id` (`jid ?? host`) exists from E-59.
- `GroupingStrings.swift` has only `coachMark` — E-60 adds error toast strings.

---

## 3. Options Considered

### 3.1 — API dispatch direction

**Option A — `source.client.join(peer: target.identifier)` (chosen)**
Matches the Mozart Open API's follower-initiates model. `SpeakerClient.join(peer:)` is already declared on the protocol with conformances in both Mozart and BNR clients. Same path used by the existing voice command dispatch.

**Option B — `target.client.beolinkExpand(jid: source.identifier.jid!)` (rejected)**
Calls the wrong direction (leader pulling follower). `beolinkExpand` is documented as a follower-initiated request. Also `beolinkExpand` is concrete on `MozartClient`, not exposed on `SpeakerClient` — would require casts.

### 3.2 — Loading chip mounting

**Option A — Extend `SpeakerCard.chipData` to inject `.loading` chips from `joinsInFlight` (chosen)**
Preserves `GroupChipRow` as a pure-data renderer. Composes with the existing `ForEach`-driven chip diffing — loading-to-settled transitions render smoothly as `ForEach` mutations rather than overlay swaps. Loading chips are appended AFTER overflow computation; they never count toward the overflow threshold.

**Option B — Render a separate overlay above `GroupChipRow` (rejected)**
Overlay geometry conflicts with the row's `HStack` layout; cannot animate smoothly into a settled chip in place; produces jump cuts on completion.

### 3.3 — Error toast delivery from `SessionViewModel`

**Option A — `onError: (String) -> Void` callback injected at init (chosen)**
`HomeView.showErrorToast(_:)` is private; the existing pipeline is `cardErrorMessage` `@State` → `.onChange` → `Toast`. `SessionStripView` injects an `onError` closure that writes to `$errorMessage` binding — same plumbing E-56 already uses.

**Option B — Singleton `ToastCenter.shared.show(.error(…))` (rejected)**
No `ToastCenter` exists. Adding a singleton increases surface area with no benefit at this scope. The epics doc T-6001's reference to `ToastCenter.shared` is pseudocode — guidance, not contract.

---

## 4. Rationale

`source.client.join(peer:)` is the only semantically correct API dispatch. `chipData` extension preserves `GroupChipRow`'s pure-renderer architecture from ADR-E53. `onError` callback reuses the existing `@Binding` error pipeline without introducing new shared state.

---

## 5. Consequences

### E-61 must not be precluded

E-61 adds `var onTap: (@MainActor () -> Void)? = nil` to `ChipData`. E-60 must not add stored properties to `ChipData` — only `ChipKind` grows. The `ChipData` memberwise initialiser used at all E-53 construction sites must remain compatible.

E-61 attaches a tap gesture to `.member` chips only. E-60 must ensure `.loading` chips are rendered without any tap gesture or `Button` wrapper (US-81: loading chips are non-interactive).

E-61's `onTap: (@MainActor () -> Void)?` makes `ChipData` non-`Sendable`. E-60 documents this in `GroupChipRow.swift` so E-61 implementer knows to add `@unchecked Sendable` or `@MainActor` isolation.

### ChipKind enum growth policy

`ChipKind` now has three cases: `.member`, `.overflow(Int)`, `.loading(name: String)`. Only exhaustive switch is `GroupChipRow.body`. No `@unknown default` — future cases must compile-break.

### Reactive `joinsInFlightUnion` write

E-60 T-6004 adds `.onChange(of: sessionVMs.values.map { $0.joinsInFlight })` in `SessionStripView` so the binding writes propagate on every `joinsInFlight` mutation, not only on group-array changes.

### Debounce implementation

The ≥ 300 ms debounce is `Task.sleep(for: .milliseconds(350))` inside the success branch of the join task, BEFORE calling `refreshGroups()`. Not `DispatchQueue.main.asyncAfter` (not concurrency-safe).

### Coach-mark dismiss path

E-59's `GroupingCoachMark` has three dismiss paths: 3-second timeout, screen tap, successful drop. The third needs a notification from `SessionViewModel`. Add `var lastDropCompletedAt: Date? = nil` on `SessionViewModel` (plain stored property — `@Observable` handles observation automatically). Set it on successful join. `HomeView` or `SessionStripView` observes via `.onChange(of:)` and triggers coach-mark `onDismiss`.

### Loading chip name resolution

`SpeakerCard.chipData` resolves the speaker name for a loading chip from the `joinsInFlight` id via `sessionVM.resolveSpeaker`. For Mozart speakers whose id is the JID, the synthetic `SpeakerIdentifier(host: inFlightId, jid: nil, platform: .mozart)` lookup will miss the JID-first match and the chip falls back to displaying the raw JID string. Acceptable degradation; documented as cosmetic limitation. If observed in T-6005, fix by storing the resolved name alongside the id in a `[String: String]` dictionary on `SessionViewModel`.

---

## 6. File-Level Plan

### Modified files

| Path | Change | Tasks |
|---|---|---|
| `iOS/Voxio/Features/Home/SessionViewModel.swift` | Replace `handleJoinDrop(source:target:)` stub with full async implementation per §7. Add `onError: (String) -> Void` to `init`. Add `private(set) var pulsingChips: Set<String> = []`. Add `var lastDropCompletedAt: Date? = nil`. Add `private static func joinWithTimeout(source:target:seconds:)` helper. Add `private static func errorToastText(for:speakerName:)` mapper. | T-6001, T-6003 |
| `iOS/Voxio/Features/Home/Components/GroupChipRow.swift` | Add `case loading(name: String)` to `ChipKind`. Add rendering branch for `.loading` (dimmed label + 10 pt inline `ProgressView`, no tap gesture, accessibility label `Connecting %@…`). | T-6002 |
| `iOS/Voxio/Features/Home/SpeakerCard.swift` | Extend `chipData` computed property to append `.loading(name:)` chips for each id in `sessionVM?.joinsInFlight` that is NOT already in `groupMembers`. Loading chips appended AFTER overflow computation — never count toward overflow threshold. | T-6002 |
| `iOS/Voxio/Features/Home/SessionStripView.swift` | (a) Update `resolvedSessionVM(for:)` to inject the `onError` closure that writes `errorMessage` binding. (b) Add `.onChange(of: sessionVMs.values.map { $0.joinsInFlight })` that writes `joinsInFlightUnionBinding = joinsInFlightUnion`. | T-6004 |
| `iOS/Voxio/Core/Strings/GroupingStrings.swift` | Add `joinFailed`, `joinFailedGeneric`, `joinFailedTimeout`, `joinFailedUnreachable`, `connectingFormat` (EN/DA each). | T-6001, T-6002 |

### New files

None.

---

## 7. Public Interface Contract

```swift
// MARK: - SessionViewModel — handleJoinDrop full implementation (E-60 T-6001)
// File: iOS/Voxio/Features/Home/SessionViewModel.swift

@Observable @MainActor
final class SessionViewModel {
    let group: SpeakerGroup
    let discovery: SpeakerDiscoveryService
    /// Delivers a user-facing error string to the enclosing view hierarchy.
    /// SessionStripView injects a closure that writes to HomeView's errorMessage binding.
    let onError: (String) -> Void

    // Existing E-59 state
    var dropZoneActive: Bool = false
    var joinsInFlight: Set<String> = []
    private(set) var joinTasks: [String: Task<Void, Never>] = [:]

    // E-60 additions
    /// Chip ids currently in the 0.4 s success-pulse animation window.
    private(set) var pulsingChips: Set<String> = []
    /// Set on every successful join completion. Observed by coach-mark to trigger dismiss.
    var lastDropCompletedAt: Date? = nil

    init(group: SpeakerGroup, discovery: SpeakerDiscoveryService, onError: @escaping (String) -> Void)

    func resolveSpeaker(_ identifier: SpeakerIdentifier) -> Speaker?

    /// E-60 T-6001 — replaces E-59 stub. Non-throwing; errors flow via onError.
    func handleJoinDrop(source: Speaker, target: Speaker) {
        let key = source.identifier.id
        guard !joinsInFlight.contains(key) else { return }
        joinsInFlight.insert(key)
        HapticEngine.shared.commandRecognised()

        let task = Task { [weak self] in
            do {
                try await Self.joinWithTimeout(source: source, target: target, seconds: 10)
                await MainActor.run {
                    guard let self else { return }
                    self.discovery.mergeIntoSpeakerGroup(source: source, target: target)
                    self.joinsInFlight.remove(key)
                    self.joinTasks.removeValue(forKey: key)
                    self.pulseChip(for: source)
                    self.lastDropCompletedAt = Date()
                    UIAccessibility.post(notification: .announcement,
                                         argument: "\(source.name) joined \(target.name)")
                }
                // ≥ 300 ms debounce per ADR-003 §5 contract 6.
                try? await Task.sleep(for: .milliseconds(350))
                await self?.discovery.refreshGroups()
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.joinsInFlight.remove(key)
                    self.joinTasks.removeValue(forKey: key)
                    HapticEngine.shared.errorOccurred()
                    self.onError(Self.errorToastText(for: error, speakerName: source.name))
                }
            }
        }
        joinTasks[key] = task
    }

    private static func joinWithTimeout(
        source: Speaker, target: Speaker, seconds: Int
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await source.client.join(peer: target.identifier) }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw SpeakerError.timeout
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func pulseChip(for speaker: Speaker) {
        let id = speaker.identifier.id
        pulsingChips.insert(id)
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            pulsingChips.remove(id)
        }
    }

    private static func errorToastText(for error: Error, speakerName: String) -> String {
        let strings = GroupingStrings.forLanguage(LanguageService.shared.activeLanguage)
        switch error as? SpeakerError {
        case .timeout:     return String(format: strings.joinFailed, speakerName, strings.joinFailedTimeout)
        case .unreachable: return String(format: strings.joinFailed, speakerName, strings.joinFailedUnreachable)
        default:           return String(format: strings.joinFailedGeneric, speakerName)
        }
    }
}

// Behavioural contracts:
// 1. handleJoinDrop is idempotent — re-entry while joinsInFlight contains the key returns immediately.
// 2. HapticEngine.shared.commandRecognised() fires synchronously on the main actor.
// 3. The detached Task is NOT cancelled on view teardown — let the API call complete (spec TR-4 step 5).
// 4. On success: mergeIntoSpeakerGroup fires BEFORE joinsInFlight.remove — model update visible
//    while loading chip is still mounted; chip resolves to .member in the same render pass.
// 5. On success: refreshGroups() runs after 350 ms sleep (satisfies ≥ 300 ms contract).
// 6. pulsingChips.insert fires immediately on success, before the 350 ms sleep.
// 7. lastDropCompletedAt = Date() fires on every successful join (coach-mark dismiss hook).
// 8. onError is always called on the main actor; injected closure forwards to errorMessage binding.
// 9. SpeakerError.timeout → "Couldn't add NAME — connection timed out".
//    SpeakerError.unreachable → "Couldn't add NAME — speaker unreachable".
//    Other → "Couldn't add NAME".
```

```swift
// MARK: - ChipKind.loading (E-60 T-6002)
// File: iOS/Voxio/Features/Home/Components/GroupChipRow.swift

internal struct ChipData: Identifiable {
    let id: UUID = UUID()
    let speakerName: String
    let kind: ChipKind

    // F2 / E-61 RESERVED: var onTap: (@MainActor () -> Void)? = nil
    //                    Will break implicit Sendable when added — E-61 must add
    //                    @unchecked Sendable or @MainActor isolation.

    internal enum ChipKind: Equatable {
        case member
        case overflow(Int)
        /// E-60 T-6002. Renders dimmed label + inline ProgressView. Non-interactive.
        case loading(name: String)
        // Exhaustive switch in GroupChipRow.body MUST handle every case.
        // Do NOT add @unknown default — future cases must compile-break.
    }
}
```

```swift
// MARK: - GroupChipRow rendering for .loading (E-60 T-6002)
// File: iOS/Voxio/Features/Home/Components/GroupChipRow.swift

// Inside chipView(_ chip: ChipData) switch:

case .loading(let name):
    let strings = GroupingStrings.forLanguage(LanguageService.shared.activeLanguage)
    HStack(spacing: Spacing.s4) {
        ProgressView()
            .progressViewStyle(.circular)
            .frame(width: 10, height: 10)
            .tint(BeoColor.muted)
        Text(name)
            .font(BeoType.caption)
            .foregroundStyle(BeoColor.muted)
            .lineLimit(1)
            .truncationMode(.tail)
    }
    .opacity(0.6)
    .padding(.horizontal, Spacing.s8)
    .padding(.vertical, Spacing.s4)
    .background(.white.opacity(0.07), in: Capsule())
    .accessibilityLabel(String(format: strings.connectingFormat, name))
    // No .onTapGesture — loading chips are non-interactive (US-81)

// Behavioural contracts:
// 1. 10 pt circular ProgressView on the leading edge of the chip label.
// 2. Entire chip at 0.6 opacity (design-spec §4.2).
// 3. .accessibilityLabel uses strings.connectingFormat = "Connecting %@…" / "Forbinder %@…".
// 4. No tap gesture, no .contentShape — non-interactive chip.
// 5. ProgressView respects @Environment(\.accessibilityReduceMotion) natively (SwiftUI handles).
```

```swift
// MARK: - SpeakerCard.chipData extension for loading chips (E-60 T-6002)
// File: iOS/Voxio/Features/Home/SpeakerCard.swift

private var chipData: [ChipData] {
    let settled = groupMembers
    var chips: [ChipData]
    if settled.count <= 3 {
        chips = settled.map { ChipData(speakerName: $0.name, kind: .member) }
    } else {
        chips = settled.prefix(2).map { ChipData(speakerName: $0.name, kind: .member) }
        chips.append(ChipData(speakerName: "", kind: .overflow(settled.count - 2)))
    }
    // E-60 addition: append loading chips for in-flight joins NOT already settled.
    if let vm = sessionVM {
        let settledIds = Set(groupMembers.map { $0.identifier.id })
        for inFlightId in vm.joinsInFlight where !settledIds.contains(inFlightId) {
            let name = vm.resolveSpeaker(
                SpeakerIdentifier(host: inFlightId, jid: nil, platform: .mozart)
            )?.name ?? inFlightId
            chips.append(ChipData(speakerName: name, kind: .loading(name: name)))
        }
    }
    return chips
}

// Behavioural contracts:
// 1. Loading chips append AFTER overflow chip. Never count toward overflow threshold.
// 2. If a speaker is in both groupMembers AND joinsInFlight (model/task race), the settled
//    chip wins; loading chip is omitted (settledIds guard).
// 3. resolveSpeaker uses synthetic identifier with jid: nil — host-fallback path. Mozart
//    speakers whose joinsInFlight key is a JID may miss and fall back to displaying the
//    raw JID string. Cosmetic degradation acceptable; verify in T-6005.
```

```swift
// MARK: - SessionStripView wiring (E-60 T-6004)
// File: iOS/Voxio/Features/Home/SessionStripView.swift

// (a) resolvedSessionVM(for:) — update to inject onError:
private func resolvedSessionVM(for group: SpeakerGroup) -> SessionViewModel {
    if let existing = sessionVMs[group.id] { return existing }
    let new = SessionViewModel(
        group: group,
        discovery: discovery,
        onError: { [errorMessageBinding = $errorMessage] msg in
            errorMessageBinding.wrappedValue = msg
        }
    )
    DispatchQueue.main.async { sessionVMs[group.id] = new }
    return new
}

// (b) Reactive write of joinsInFlightUnionBinding on joinsInFlight changes:
.onChange(of: sessionVMs.values.map { $0.joinsInFlight }) { _, _ in
    joinsInFlightUnionBinding = joinsInFlightUnion
}

// Behavioural contracts:
// 1. Fires on every joinsInFlight mutation (insert on drop, remove on success/failure).
// 2. joinsInFlightUnion computed: sessionVMs.values.reduce(into: Set<String>()) { $0.formUnion($1.joinsInFlight) }
// 3. Write propagates to HomeView's @State within the same render cycle.
```

```swift
// MARK: - GroupingStrings additions (E-60 T-6001 + T-6002)
// File: iOS/Voxio/Core/Strings/GroupingStrings.swift

struct GroupingStrings {
    var coachMark: String                  // existing (E-59)
    var joinFailed: String                 // "Couldn't add %@ — %@" / "Kunne ikke tilslutte %@ — %@"
    var joinFailedGeneric: String          // "Couldn't add %@" / "Kunne ikke tilslutte %@"
    var joinFailedTimeout: String          // "connection timed out" / "forbindelsen fik timeout"
    var joinFailedUnreachable: String      // "speaker unreachable" / "højttaleren kan ikke nås"
    var connectingFormat: String           // "Connecting %@…" / "Forbinder %@…"

    static let english: GroupingStrings = ...
    static let danish:  GroupingStrings = ...
    static func forLanguage(_ language: Language) -> GroupingStrings { ... }
}
```

---

## 8. Conflicts Flagged

### CF-1: `ToastCenter.shared.show(.error(…))` in epics doc T-6001 — type does not exist

No `ToastCenter` exists in the codebase. The existing error pipeline is `cardErrorMessage` `@State` → `.onChange` → `Toast`. **Resolution: inject `onError: (String) -> Void` closure into `SessionViewModel.init`. SessionStripView builds the closure to write `$errorMessage.wrappedValue = msg`. No new shared state.**

### CF-2: `@Published var lastDropCompletedAt: Date?` in epics doc T-6001 — wrong observation mechanism

`SessionViewModel` is `@Observable`, not `ObservableObject`. **Resolution: plain stored property `var lastDropCompletedAt: Date? = nil`. `@Observable` handles observation automatically.**

### CF-3: Loading chip name resolution may degrade for Mozart JID-keyed sources

Synthetic `SpeakerIdentifier(host: inFlightId, jid: nil)` lookup misses the JID-first match when `inFlightId` is actually a JID. **Resolution: documented as cosmetic limitation; verify in T-6005. If observed, fix by storing the resolved name alongside the id in a `[String: String]` dictionary on `SessionViewModel`.**

### CF-4: `SpeakerError.timeout` confirmed present

`/iOS/Voxio/Core/Errors/SpeakerError.swift` defines `case timeout`. OQ-7 from architect-review is resolved.

### CF-5: Synthetic `SpeakerIdentifier.platform` field is safe

Hard-coded to `.mozart` in the chipData resolution. `resolveSpeaker` matches on `jid` and `host` only — `platform` is not consulted. Safe.

### CF-6: `SessionViewModel.init` signature change — `SessionStripView.resolvedSessionVM` must update

Adding `onError: @escaping (String) -> Void` to `init` requires updating the construction site. Localised one-line change.

---

## 9. Platform Constraint Checks

| API | Introduced | Status |
|---|---|---|
| `withThrowingTaskGroup` | iOS 15+ | Safe |
| `Task.sleep(for: .milliseconds(350))` | iOS 16+ | Safe |
| `ProgressView().progressViewStyle(.circular)` | iOS 14+ | Safe |
| `UIAccessibility.post(notification: .announcement, argument:)` | iOS 7+ | Safe |
| `@Observable` stored property observation | iOS 17+ | Safe |

No new entitlements, frameworks, or platform features.

---

## 10. Task Gate

| Task | Status | Dependency |
|---|---|---|
| T-6001 — `handleJoinDrop` full implementation + onError callback + GroupingStrings additions | UNBLOCKED | E-59 shipped; `SpeakerError.timeout` present; `discovery.refreshGroups()` + `mergeIntoSpeakerGroup` present |
| T-6002 — `ChipKind.loading`, `GroupChipRow.body` rendering branch, `SpeakerCard.chipData` extension | UNBLOCKED | E-53 and E-59 shipped |
| T-6003 — `pulseChip(for:)` + `pulsingChips: Set<String>` + chip opacity keyframe | UNBLOCKED (in same PR as T-6001/T-6002) | T-6001 + T-6002 first |
| T-6004 — `joinsInFlightUnion` reactive write in `SessionStripView` + `onError` injection | UNBLOCKED (in same PR as T-6001) | T-6001 first |
| T-6005 — Manual LAN integration test | DEFERRED (device required) | T-6001–T-6004 merged |

---

**Verdict: PROCEED**
