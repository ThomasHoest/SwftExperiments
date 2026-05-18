# ADR-E59 — Drag-to-Join Infrastructure (E-59): Transferable Conformance, SessionViewModel, Ghost Pill, Drop Destination, Coach Mark

**Status:** Accepted
**Date:** 2026-05-12
**Deciders:** Engineering Lead
**Refs:** ADR-002-voxio-1.4-ios.md (D3, D5), ADR-003-listener-based-grouping.md (§5, §8 CF-1), ADR-E53-group-chip-row.md (§5 CF-3/CF-4), ADR-E54-bottom-bar-redesign.md (§7 public interface), ADR-E55-discovery-offline-states.md (§5 F1/F2 impact), spec-multiroom-grouping.md v1.0 (TR-1 through TR-9), design-spec-multiroom-grouping.md v1.1, epics-and-tasks-multiroom-grouping.md v1.0 (E-59 T-5901–T-5910), CLAUDE.md

---

## 1. Decision

E-59 delivers the drag infrastructure for multiroom join by:

1. Adding `extension SpeakerIdentifier: Transferable` via `CodableRepresentation(contentType: .data)` — the existing `Codable` value type already consumed by `SpeakerClient.join(peer:)` becomes the drag payload. The live `Speaker` is resolved on drop by `SessionViewModel.resolveSpeaker(_:)` against `discovery.groups.flatMap(\.members)`.
2. Introducing `SessionViewModel` — a new `@Observable @MainActor final class` owning per-card drag-drop state: `dropZoneActive: Bool`, `joinsInFlight: Set<String>`, `joinTasks: [String: Task<Void, Never>]`, and `resolveSpeaker(_:) -> Speaker?`. `handleJoinDrop` and `handleRemoveTap` — used by E-60/E-61 — are stubbed here with the correct signatures and implemented fully in those later epics.
3. Attaching `.draggable(speaker.identifier) { dragPreviewView }` to eligible bottom-bar pills via a helper `isDraggable(_ speaker: Speaker) -> Bool` computed against `discovery.groups` and the union of all session view models' `joinsInFlight` sets (`joinsInFlightUnion: Set<String>` parameter on `SpeakerSelectorPill`).
4. Attaching `.dropDestination(for: SpeakerIdentifier.self)` at the session-card root, driving a gold-border overlay from `sessionVM.dropZoneActive`; invalid drops are rejected silently.
5. Adding `dragLifted()`, `dragEnteredDropZone()`, and `dragCancelled()` to `HapticEngine.swift`.
6. Rendering the coach mark as a new `GroupingCoachMark` view modifier on the bottom bar, gated by `@AppStorage("hasSeenGroupingCoachMark")` and auto-dismissing after 3 seconds.

Ghost-cancel fallback: SwiftUI's default ghost-return animation is relied on for iOS 26; the `dragCancelled()` haptic is fired from a drag-end observer at the pill level. If SwiftUI does not surface a cancel callback (absent in iOS 16/17, unverified in iOS 26), the haptic is a best-effort nicety documented as non-blocking per design-spec §2.2.

---

## 2. Context

### Groups vs. peers — ADR-003 §8 CF-1

ADR-003 rewrote `SpeakerDiscoveryService.reconstructGroupsAsync()` to derive groups from `GET /beolink/listeners` (Mozart, leader-side) and `activeSources.primaryJid` (ASE, follower-side):
- `discovery.groups` — AUTHORITATIVE current group membership. E-59 reads this to determine which pills are non-draggable.
- `speaker.client.getPeers()` (Mozart) — eligible expansion targets. E-59's `isDraggable` check does NOT call `getPeers()` directly for drop-target eligibility: the drop destination accepts any `SpeakerIdentifier`, and the drop handler's self-drop guard plus the pill-eligibility gate achieve the same exclusion without a per-drop async call.

Post-drop, `handleJoinDrop` (implemented in E-60 T-6001) calls `discovery.refreshGroups()` after a ≥ 300 ms debounce per ADR-003 §5 contract 6. E-59 must not call `refreshGroups()` itself — that is E-60's responsibility.

### HapticEngine gap — ADR-002 §5

ADR-002 §5 flags "HapticEngine missing `dragLifted()`, `dragEnteredDropZone()`, `dragCancelled()` methods" as a known consequence. The current `HapticEngine.swift` (five methods: `commandRecognised`, `sheetAppeared`, `actionConfirmed`, `errorOccurred`, `limitReached`) confirms the gap. These three methods are a hard prerequisite for T-5904, T-5905, T-5908.

### ChipData extension hooks — ADR-E53 §5 CF-3/CF-4

E-53 ships `GroupChipRow.swift` with `ChipKind` containing only `.member` and `.overflow(Int)`. The switch in `GroupChipRow.body` is deliberately exhaustive over these two cases. ADR-E53 §5 CF-3 documents that adding `case loading` in E-60 will cause a compile-time break in `GroupChipRow.body` — this is intended and expected. E-59 must NOT add `.loading` or any `@unknown default` to the switch. ADR-E53 §5 CF-4 documents that E-61's `onTap: (() -> Void)? = nil` will break `Sendable` conformance; F2's E-61 ADR will handle that.

### F3 surface dependency

E-52 (`SessionStripView`), E-53 (`GroupChipRow`), and E-54 (refactored `SpeakerSelectorPill`) have all been merged. E-59 implementation can proceed against the live surfaces. The `SessionStripView` already exists and passes `groupMembers:` to `SpeakerCard` — it is the natural host for `SessionViewModel` instances. `SpeakerSelectorPill` already exists with the `groups: [SpeakerGroup]` parameter (E-54 shipped).

### SpeakerIdentifier — existing shape

`SpeakerIdentifier` is a `struct` conforming to `Hashable, Codable`, carrying `host: String`, `jid: String?`, and `platform: SpeakerPlatform`. It does not yet conform to `Transferable`. Adding the conformance in a separate file is the correct approach given the project uses `PBXFileSystemSynchronizedRootGroup` auto-compilation.

### SpeakerIdentifier lacks a stable string `id` — CF-1

The epics doc repeatedly references `source.identifier.id` (e.g. as the key for `joinsInFlight: Set<String>`). `SpeakerIdentifier` as shipped has no `.id` property. A computed `var id: String { jid ?? host }` must be derived — JID is the more stable Mozart identity; host is the fallback for ASE. This property is added alongside the `Transferable` conformance in the new file.

---

## 3. Options Considered

### Transferable payload

**Option A — `SpeakerIdentifier: Transferable` via `CodableRepresentation` (chosen)**
Zero new types. Resolution on drop uses `discovery.groups.flatMap(\.members)` (matching by `jid` then `host`). Matches ADR-002 D3.

**Option B — A thin wrapper `struct SpeakerTransfer: Transferable, Codable`**
Rejected: parallel type with no information not already in `SpeakerIdentifier`.

**Option C — `Speaker` conforms directly to `Transferable`**
`Speaker` is `@MainActor @Observable` reference type with no `Codable` conformance and an `any SpeakerClient` property. Not feasible.

**Option D — JSON envelope struct**
Less type safety than reusing `SpeakerIdentifier`. Rejected.

### Drop-target eligibility computation

**Option A — Compute `isDraggable` in `SessionViewModel` per card (rejected)**
Eligibility depends on `discovery.groups` (global) and `joinsInFlight` across ALL cards (global). A per-card view model cannot observe sibling view models' `joinsInFlight`.

**Option B — Compute `isDraggable` as a helper on `SpeakerSelectorPill`, consuming `discovery.groups` and a `joinsInFlightUnion: Set<String>` parameter aggregated from all `SessionViewModel`s (chosen)**
`joinsInFlightUnion` is a `@State` property on `HomeView`, recomputed via `.onChange(of:)` whenever any session view model's `joinsInFlight` changes. Matches spec TR-5 and the epics doc T-5903/T-6004.

### SessionViewModel placement

**Option A — `SessionViewModel` as `@State` on `SessionStripView` (chosen)**
A `@State private var sessionVMs: [SpeakerGroup.ID: SessionViewModel]` dictionary in `SessionStripView` matches the existing `@State scrollHostId` pattern. Lifecycle: created on first card appear, persists across re-renders for the same group ID.

**Option B — Owned by a HomeViewModel**
Heavier; complicates lifecycle; aggregation is simpler when child view models are self-contained.

---

## 4. Rationale

`SpeakerIdentifier: Transferable` wins because it is the existing API-boundary identity (ADR-002 D3), requires zero new model types, and round-trips cleanly as JSON. The per-card `SessionViewModel` wins because it matches card lifecycle and keeps drop state local. Eligibility lives in `SpeakerSelectorPill` because it depends on global state no single card can see.

Three concrete `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator` wrappers on `HapticEngine` follows the established pattern of the five existing methods.

The coach mark as a dedicated `ViewModifier` with `@AppStorage` persistence mirrors `ConnectionStatusChip`/`DiscoveryStateView` from E-55: a small view receiving visible state as a computed property, dismissing via side-effect on `@AppStorage`.

---

## 5. Consequences

### E-60 must not be precluded

E-60 (T-6001–T-6004) implements `handleJoinDrop` on `SessionViewModel`. E-59 leaves it as a stub with the correct signature:

```swift
func handleJoinDrop(source: Speaker, target: Speaker)
```

E-59's drop handler calls this stub; E-60 fills it in. The stub must not throw, must not mutate `joinsInFlight`, and must log the call.

E-60 adds `ChipKind.loading` to `GroupChipRow.swift`. **E-59 must not touch `GroupChipRow.swift` at all.** The exhaustive switch in `GroupChipRow.body` must remain exactly `.member` / `.overflow` — adding `@unknown default` in E-59 would suppress the compile-time signal E-60 depends on.

### E-61 must not be precluded

E-61 adds `var onTap: (@MainActor () -> Void)? = nil` to `ChipData` and wires tap handling. E-59 must not add any tap handling to chips. The existing `ChipData` struct must remain unchanged.

E-61 also adds `handleRemoveTap(_ speaker: Speaker)` to `SessionViewModel`. E-59 stubs this method with the same pattern as `handleJoinDrop`.

### `joinsInFlight` aggregation — E-60 T-6004

E-60 T-6004 wires `joinsInFlightUnion` on `HomeView` from per-card `joinsInFlight` sets. E-59 ensures `SessionViewModel.joinsInFlight` is observable (stored property on `@Observable` class). The `isDraggable` helper takes `joinsInFlightUnion: Set<String>` as a parameter (not a captured reference) so T-6004's wiring can be added without changing the helper's signature.

### `refreshGroups()` debounce — post E-60

ADR-003 §5 contract 6 requires `discovery.refreshGroups()` after each successful `beolinkExpand`, with a ≥ 300 ms debounce. E-59 does NOT call `refreshGroups()` — that is E-60's responsibility.

### `dragCancelled()` haptic is best-effort

SwiftUI's `.draggable` does not expose a cancel callback in iOS 16/17. iOS 26 availability is unverified. T-5908 tests on device. If no cancel callback is available, the haptic is silently omitted or fires from a fallback observer. Non-blocking per design-spec §2.2.

---

## 6. File-Level Plan

### New files

| Path | Description |
|---|---|
| `iOS/Voxio/Core/Models/SpeakerIdentifier+Transferable.swift` | `extension SpeakerIdentifier: Transferable` via `CodableRepresentation(contentType: .data)`. Also adds `var id: String { jid ?? host }`. |
| `iOS/Voxio/Features/Home/SessionViewModel.swift` | `@Observable @MainActor final class SessionViewModel`. State: `dropZoneActive`, `joinsInFlight`, `joinTasks`, `group`, `discovery`. Methods: `resolveSpeaker(_:)`, `handleJoinDrop(source:target:)` (stub), `handleRemoveTap(_:)` (stub). |
| `iOS/Voxio/Features/Home/GroupingCoachMark.swift` | `struct GroupingCoachMark: ViewModifier`. `@AppStorage("hasSeenGroupingCoachMark")`. 3-second auto-dismiss. |
| `iOS/Voxio/Core/Strings/GroupingStrings.swift` | EN/DA strings for coach mark. Follows `GroupChipStrings` pattern. |

### Modified files

| Path | Change | Tasks |
|---|---|---|
| `iOS/Voxio/Core/HapticEngine.swift` | Add `dragLifted()` (medium impact), `dragEnteredDropZone()` (light impact), `dragCancelled()` (warning notification). | T-5904/T-5905/T-5908 prereq |
| `iOS/Voxio/Features/Home/SpeakerSelectorPill.swift` | Add `joinsInFlightUnion: Set<String> = []` parameter. Add private `isDraggable(_ speaker: Speaker) -> Bool` helper. Apply `.opacity(isDraggable(...) ? 1.0 : 0.5)`. Attach `.draggable(speaker.identifier) { dragPreviewCapsule(speaker) }` to eligible pills only. Long-press haptic via `.simultaneousGesture`. | T-5903, T-5904 |
| `iOS/Voxio/Features/Home/SessionStripView.swift` | Add `@State private var sessionVMs: [SpeakerGroup.ID: SessionViewModel] = [:]`. Look up / create per ForEach iteration. Pass `sessionVM:` to `SpeakerCard`. | T-5905, T-5906 |
| `iOS/Voxio/Features/Home/SpeakerCard.swift` | Add `sessionVM: SessionViewModel? = nil` parameter (default keeps pre-E-59 call sites valid). Attach `.dropDestination(for: SpeakerIdentifier.self)` and gold-border overlay driven by `sessionVM?.dropZoneActive`. | T-5905, T-5906 |
| `iOS/Voxio/Features/Home/HomeView.swift` | Apply `.modifier(GroupingCoachMark(...))` to the bottom bar region. Aggregate eligibility flag (`hasEligiblePill`). | T-5909 |

### Files explicitly NOT touched in E-59

| Path | Reason |
|---|---|
| `iOS/Voxio/Features/Home/Components/GroupChipRow.swift` | E-60 owns `.loading` ChipKind; E-61 owns `onTap`. E-59 leaves this file unchanged. |
| `iOS/Voxio/Core/Discovery/SpeakerDiscoveryService.swift` | `refreshGroups()` already exists (ADR-003). |
| `iOS/Voxio/Core/Protocols/SpeakerClient.swift` | `getPeers()` already present. |

---

## 7. Public Interface Contract

```swift
// MARK: - SpeakerIdentifier additions (E-59 T-5901)
// File: iOS/Voxio/Core/Models/SpeakerIdentifier+Transferable.swift

extension SpeakerIdentifier: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

extension SpeakerIdentifier {
    /// Stable string key used as the joinsInFlight Set<String> key and for
    /// task dictionary lookup. JID preferred (Mozart); host fallback (ASE).
    var id: String { jid ?? host }
}

// Behavioural contracts:
// 1. A SpeakerIdentifier round-tripped through JSONEncoder/JSONDecoder produces
//    an equal value (== on all three fields: host, jid, platform).
// 2. .id is always non-empty (host is non-empty per SpeakerDiscovery contract).
// 3. Two SpeakerIdentifiers with the same JID have the same .id even when host differs.
```

```swift
// MARK: - SessionViewModel (E-59 T-5902)
// File: iOS/Voxio/Features/Home/SessionViewModel.swift

@Observable @MainActor
final class SessionViewModel {
    /// True while a drag ghost is inside this card's bounds.
    /// Drives the gold-border overlay in SpeakerCard.
    var dropZoneActive: Bool = false

    /// Identifiers of sources currently in-flight for this card.
    /// Set<String> keyed by SpeakerIdentifier.id.
    var joinsInFlight: Set<String> = []

    /// Join tasks keyed by SpeakerIdentifier.id.
    private(set) var joinTasks: [String: Task<Void, Never>] = [:]

    let group: SpeakerGroup
    let discovery: SpeakerDiscoveryService

    init(group: SpeakerGroup, discovery: SpeakerDiscoveryService)

    /// Resolves a transferred SpeakerIdentifier to a live Speaker.
    /// Matches by jid first (when non-nil), then by host. Returns nil if no match.
    /// Searches discovery.groups.flatMap(\.members) — every assigned speaker is here
    /// (reconstructGroupsAsync assigns every speaker to at least a solo group).
    func resolveSpeaker(_ id: SpeakerIdentifier) -> Speaker?

    /// E-59: stub — logs the call and returns. E-60 T-6001: full implementation.
    /// Post-drop: E-60 calls discovery.refreshGroups() after ≥ 300 ms debounce.
    func handleJoinDrop(source: Speaker, target: Speaker)

    /// E-59: stub — logs the call and returns. E-61 T-6101: full implementation.
    func handleRemoveTap(_ speaker: Speaker)
}

// Behavioural contracts:
// 1. resolveSpeaker(_:) checks discovery.groups.flatMap(\.members), matches by
//    identifier.jid first (when non-nil), then by identifier.host. Returns nil
//    when no match found.
// 2. dropZoneActive and joinsInFlight mutations are on @MainActor.
// 3. Stub log lines:
//    handleJoinDrop: Log.info("[SessionVM] handleJoinDrop stub: \(source.name) → \(target.name)")
//    handleRemoveTap: Log.info("[SessionVM] handleRemoveTap stub: \(speaker.name)")
```

```swift
// MARK: - HapticEngine additions (E-59 prerequisite)
// File: iOS/Voxio/Core/HapticEngine.swift

@MainActor
final class HapticEngine {
    // ... existing methods unchanged ...

    /// Fired on long-press hold (drag initiated). Medium impact.
    func dragLifted() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }

    /// Fired when the drag ghost enters a session card's drop-zone bounds. Light impact.
    func dragEnteredDropZone() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }

    /// Fired when a drag is released outside any valid drop destination. Warning notification.
    func dragCancelled() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
```

```swift
// MARK: - SpeakerSelectorPill additions (E-59 T-5903 + T-5904)
// File: iOS/Voxio/Features/Home/SpeakerSelectorPill.swift

struct SpeakerSelectorPill: View {
    // ... existing properties unchanged ...

    /// E-59: union of joinsInFlight across all SessionViewModels. Supplied by HomeView.
    /// Default keeps pre-E-59 call sites valid.
    var joinsInFlightUnion: Set<String> = []

    /// Returns true when the pill may be dragged.
    /// False when:
    ///   a) speaker is hostSpeaker of any group in `groups` with playbackState == .playing
    ///   b) speaker is a member of any group in `groups` with members.count > 1
    ///   c) speaker.identifier.id is in joinsInFlightUnion
    private func isDraggable(_ speaker: Speaker) -> Bool
}

// Pill rendering contract:
// All pills: .opacity(isDraggable(speaker) ? 1.0 : 0.5)
// Draggable pills get:
//   .draggable(speaker.identifier) {
//       dragPreviewCapsule(speaker)   // Capsule with pill style, 0.85 opacity, 1.06× scale
//   }
//   .simultaneousGesture(
//       LongPressGesture(minimumDuration: 0.35).onEnded { _ in
//           HapticEngine.shared.dragLifted()
//       }
//   )
// Non-draggable pills: .draggable modifier OMITTED (not nil — absent).
```

```swift
// MARK: - SpeakerCard additions (E-59 T-5905 + T-5906)
// File: iOS/Voxio/Features/Home/SpeakerCard.swift

struct SpeakerCard: View {
    // ... existing properties unchanged ...

    /// E-59: session view model supplying drop state.
    /// Nil on pre-E-59 call sites (HomeView idle card, previews) — no drop destination attached.
    var sessionVM: SessionViewModel? = nil

    // body additions (applied AFTER existing modifiers):
    //
    // .dropDestination(for: SpeakerIdentifier.self) { items, _ in
    //     guard let vm = sessionVM,
    //           let droppedId = items.first,
    //           let source = vm.resolveSpeaker(droppedId),
    //           source.id != vm.group.hostSpeaker.id else { return false }
    //     vm.handleJoinDrop(source: source, target: vm.group.hostSpeaker)
    //     return true
    // } isTargeted: { isOver in
    //     guard let vm = sessionVM else { return }
    //     withAnimation(BeoAnimation.spring) { vm.dropZoneActive = isOver }
    //     if isOver { HapticEngine.shared.dragEnteredDropZone() }
    // }
    //
    // // Gold-border overlay applied LAST (above hairline borders):
    // .overlay(
    //     RoundedRectangle(cornerRadius: Radius.card)
    //         .stroke(BeoColor.accent,
    //                 lineWidth: (sessionVM?.dropZoneActive == true) ? 1.5 : 0)
    // )
}

// Behavioural contracts:
// 1. sessionVM == nil → no .dropDestination, no gold-border overlay.
// 2. Self-drop (source.id == hostSpeaker.id) returns false; no side effects.
// 3. Unresolvable identifier (resolveSpeaker returns nil) returns false.
// 4. dropZoneActive transitions to false within one spring cycle after ghost leaves bounds.
```

```swift
// MARK: - GroupingCoachMark (E-59 T-5909)
// File: iOS/Voxio/Features/Home/GroupingCoachMark.swift

struct GroupingCoachMark: ViewModifier {
    @AppStorage("hasSeenGroupingCoachMark") private var hasSeen: Bool = false

    let hasEligiblePill: Bool
    let onDismiss: () -> Void

    // Contracts:
    // 1. Shows when hasEligiblePill && !hasSeen.
    // 2. Auto-dismisses after 3 seconds via Task { try? await Task.sleep(for: .seconds(3)); onDismiss() }.
    // 3. On dismiss: hasSeen = true (persisted).
    // 4. Position: overlay above first eligible pill, Spacing.s8 above pill top.
    // 5. Text: BeoType.caption, BeoColor.muted. .transition(.opacity).
    // 6. .allowsHitTesting(false) on the label.
}

// Strings via GroupingStrings (NEW file in Core/Strings/, NOT .strings catalogue):
// struct GroupingStrings {
//     var coachMark: String   // EN: "Drag to join this session" / DA: "Træk for at tilslutte"
//     static let english: GroupingStrings = ...
//     static let danish:  GroupingStrings = ...
//     static func forLanguage(_ language: Language) -> GroupingStrings { ... }
// }
```

```swift
// MARK: - SessionStripView wiring (E-59 T-5905 call-site update)
// File: iOS/Voxio/Features/Home/SessionStripView.swift

struct SessionStripView: View {
    // ... existing properties unchanged ...

    @State private var sessionVMs: [SpeakerGroup.ID: SessionViewModel] = [:]

    // Inside ForEach(groups) { group in ... }:
    //
    // let sessionVM = sessionVMs[group.id] ?? {
    //     let new = SessionViewModel(group: group, discovery: discovery)
    //     sessionVMs[group.id] = new
    //     return new
    // }()
    //
    // SpeakerCard(
    //     speaker: group.hostSpeaker,
    //     isExpanded: isCommandActive,
    //     roll: isFrontmost ? roll : 0,
    //     pitch: isFrontmost ? pitch : 0,
    //     groupMembers: group.members.filter { $0.id != group.hostSpeaker.id },
    //     errorMessage: $errorMessage,
    //     sessionVM: sessionVM   // E-59 T-5905
    // )
    // .frame(width: cardWidth)
    // .id(group.hostSpeaker.id)
    //
    // // Clean up sessionVMs for groups that no longer exist:
    // .onChange(of: groups.map(\.id)) { _, newIds in
    //     let validIds = Set(newIds)
    //     sessionVMs = sessionVMs.filter { validIds.contains($0.key) }
    // }

    // joinsInFlightUnion aggregation (read by HomeView for SpeakerSelectorPill):
    // var joinsInFlightUnion: Set<String> {
    //     sessionVMs.values.reduce(into: Set<String>()) { $0.formUnion($1.joinsInFlight) }
    // }
}
```

---

## 8. Conflicts Flagged

### CF-1: `SpeakerIdentifier` lacks `.id` — spec references it throughout

The epics doc (T-5902, T-5903, T-6001, T-6004) consistently uses `source.identifier.id` as the `joinsInFlight` Set key. T-5901 must add `var id: String { jid ?? host }`. Without this, downstream tasks won't compile.

**Resolution:** T-5901 adds the computed property alongside the `Transferable` conformance.

### CF-2: `SpeakerCard` modifier order matters for hit-test geometry

`SpeakerCard.body` chains `.glassEffect`, two `.overlay` strokes, `.scaleEffect`, `.animation`. The `.dropDestination` must be applied BEFORE the scale so the hit area matches visible geometry. The gold-border overlay must be applied as the FINAL overlay above hairline borders.

**Resolution:** Implementer follows the modifier order documented in §7.

### CF-3: `SessionStripView` `sessionVMs: [SpeakerGroup.ID: SessionViewModel]` must persist across re-renders

`SessionViewModel` must be stable across ForEach re-renders for the same group. Inline construction would create a new instance on every render. The `@State` dictionary keyed by `group.id` is the correct stabilisation pattern (mirrors the existing `@State scrollHostId` approach).

**Resolution:** §7 documents the dictionary pattern with the `.onChange(of: groups.map(\.id))` cleanup.

### CF-4: `discovery.allSpeakers` is `private`

`SessionViewModel.resolveSpeaker(_:)` cannot directly read `allSpeakers`. Use `discovery.groups.flatMap(\.members)` — every speaker is assigned to at least a solo group by ADR-003's reconstruct algorithm. Race-window caveat: a speaker discovered by mDNS but not yet through `reconstructGroupsAsync()` would be absent. Returning `nil` (and rejecting the drop) is safe — that speaker's pill wouldn't be draggable yet either.

**Resolution:** §7 contracts and §6 inline comment document the resolve path.

### CF-5: Localisation follows `UIStrings` pattern, not `.strings` files

Epics doc T-5909 references `Localizable.strings`. The codebase has no such files. New strings (`grouping.coachMark`) follow the `GroupChipStrings`/`DiscoveryStrings` pattern: a new `GroupingStrings.swift` struct in `iOS/Voxio/Core/Strings/`. Same situation as ADR-E53 CF-1, ADR-E55 §5, ADR-E58 §6.

### CF-6: `dragCancelled()` haptic may be undeliverable

SwiftUI's `.draggable` does not expose a cancel callback in iOS 16/17. iOS 26 availability unverified. T-5908 tests on device. If unavailable, haptic omitted. Non-blocking per design-spec §2.2.

### CF-7: `SpeakerCard.group` vs `sessionVM.group` — same instance required

E-56 added `var group: SpeakerGroup? = nil` to `SpeakerCard` for transport dispatch. `SessionViewModel` also carries a `let group: SpeakerGroup`. Both must be the same `SpeakerGroup` instance — `SessionStripView`'s ForEach should pass the iteration variable to both. No code conflict if respected.

---

## 9. Platform Constraint Checks

| API | Introduced | Used by | Status |
|---|---|---|---|
| `.draggable()` / `.dropDestination()` / `Transferable` | iOS 16 | T-5901–T-5906 | Safe |
| `CodableRepresentation(contentType:)` | iOS 16 | T-5901 | Safe |
| `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` | iOS 10 | HapticEngine | Safe |
| `@AppStorage` | iOS 14 | T-5909 | Safe |
| `LongPressGesture` | iOS 13 | T-5904 | Safe |
| `withAnimation(BeoAnimation.spring)` | existing | T-5905/T-5906 | Safe |

No platform constraint violations.

---

## 10. Task Gate

| Task | Status | Dependency |
|---|---|---|
| T-5901 — `SpeakerIdentifier+Transferable.swift` + `.id` property | UNBLOCKED | None |
| T-5902 — `SessionViewModel.swift` scaffolding | UNBLOCKED after T-5901 | T-5901 |
| T-5903 — `isDraggable` + opacity on `SpeakerSelectorPill` | UNBLOCKED after T-5902 | T-5902 |
| T-5904 — `.draggable` + ghost preview + lift haptic | UNBLOCKED after HapticEngine prereq | HapticEngine additions (same PR) |
| T-5905 — `.dropDestination` on session card | UNBLOCKED after T-5902 + HapticEngine | T-5902, HapticEngine |
| T-5906 — Gold-border overlay | UNBLOCKED after T-5905 | T-5905 |
| T-5907 — Multi-card support verification | UNBLOCKED after T-5905 (F3 / E-54 already merged) | T-5905 |
| T-5908 — Ghost cancel + `dragCancelled()` haptic | UNBLOCKED after HapticEngine prereq | HapticEngine additions |
| T-5909 — `GroupingCoachMark` + strings | UNBLOCKED after T-5902 + T-5903 | T-5902, T-5903 |
| T-5910 — Manual verification on device | DEFERRED (device required) | All prior tasks merged |

**Recommended implementation order:** HapticEngine additions + T-5901 first (small, isolated, unblocks majority). Then T-5902 → T-5903 → T-5904/T-5905/T-5906 (interlocked) → T-5907/T-5909 (parallel) → T-5908 (last, depends on cancel-callback investigation). T-5910 deferred to device verification.

---

**Verdict: PROCEED**
