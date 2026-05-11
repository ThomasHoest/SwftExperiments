# ADR-E52 — Session Card Strip (E-52): SessionStripView, SessionPageDots, Two-Way Binding

**Status:** Accepted
**Date:** 2026-05-11
**Deciders:** Engineering Lead
**Refs:** ADR-002-voxio-1.4-ios.md (D1, D2), ADR-E54-bottom-bar-redesign.md (§7, §8), spec-home-screen-redesign.md v1.0 (US-60, US-62, TR Component table), design-spec-home-screen-redesign.md v1.2 (§3, §7 UQ-5/UQ-7), epics-and-tasks-home-screen-redesign.md v1.0 (E-52 T-5201–T-5210), VoxioSpecification-1.4.md v1.4.1 (Feature Dependencies, Recommended sequencing), CLAUDE.md

---

## 1. Decision

`HomeView.cardArea` is replaced by `SessionStripView` — a `ScrollView(.horizontal)` with `.scrollTargetBehavior(.viewAligned)` wrapping one `SpeakerCard` per playing `SpeakerGroup` — per ADR-002 D1. A companion `SessionPageDots` view renders below the strip when more than one session exists. Two-way synchronisation between the visible session card and `selectedSpeaker: Binding<Speaker?>` is implemented via `scrollPosition(id:)` and two `onChange` observers inside `SessionStripView`, providing the symmetric counterpart to the pill-side scroll already shipped in `SpeakerSelectorPill` (ADR-E54 §7). No new data model wrapper type (`SessionsModel`) is introduced; the existing `SpeakerGroup` and `Speaker` types are sufficient.

---

## 2. Context

### Prior decisions this epic depends on

- **ADR-002 D1** — the session strip control is `ScrollView(.horizontal)` with `.scrollTargetBehavior(.viewAligned)`. `TabView(.page)` was explicitly rejected because it cannot produce the 8 pt trailing-card peek required by design spec §3.3. `scrollPosition(id:)` (iOS 17+) provides bidirectional scroll-position sync. No platform constraint risk on iOS 26.
- **ADR-002 D2** — `NetworkMonitor` is a separate `@Observable @MainActor` class. E-52 does not consume `NetworkMonitor` directly; it is consumed by E-55's `HomeView` routing layer that wraps `SessionStripView`. E-52's `cardArea` routing (T-5206) is a prerequisite for E-55 T-5505.
- **ADR-002 Architecture invariant** — `@Observable @MainActor Speaker` and `SpeakerGroup` must never be mutated off the main actor. All `onChange` handlers and `scrollPosition` callbacks in `SessionStripView` run synchronously on `@MainActor`.
- **ADR-002 Design-token lock** — no new `BeoColor`, `Spacing`, `Radius`, `BeoAnimation`, or `BeoType` tokens are introduced. E-52 uses `Spacing.s8`, `Spacing.s16`, `BeoColor.accent`, `BeoColor.muted`, `BeoAnimation.spring`, `BeoAnimation.toast`, and `Radius.card` — all pre-existing.
- **ADR-E54 §7 (Conflicts)** — T-5407 (tap-to-scroll wiring confirmation), T-5409 (manual e2e verification), and the scroll-related portion of T-5410 (VoiceOver) are explicitly blocked on E-52 T-5202. ADR-E54 §8 documents the current pill-side `onChange(of: selectedSpeaker?.id)` that scrolls `SpeakerSelectorPill`'s internal `ScrollView` when the binding changes externally. E-52 T-5202 must implement the symmetric behaviour on the strip side.
- **E-54 completed state** — `SpeakerSelectorPill` already reads and writes `@Binding var selectedSpeaker: Speaker?`. `HomeView` already holds `@State private var selectedSpeaker: Speaker?` and passes it as a binding to the pill. E-52 must wire into the same binding; no new state variable is introduced in `HomeView` for the strip.
- **`SpeakerCard.swift` is consumed unchanged** — `SessionStripView` wraps `SpeakerCard` instances without modification. E-53 adds `groupMembers:` to `SpeakerCard` after E-52 ships; the default `groupMembers: [Speaker] = []` means the E-52 call site compiles correctly before E-53 lands.
- **`PlaybackBars.swift` is already extracted** — T-5401 (E-54) is marked complete. `SessionStripView` does not call `PlaybackBars` directly; the `SpeakerCard` it hosts does, via the shared component file.
- **Screen-width workaround** — `SpeakerSelectorPill` documents an iOS 26 ZStack inflation issue and reads true screen width from `UIApplication.shared.connectedScenes`. `SessionStripView` must use the identical workaround when computing `cardWidth`.

### Current `cardArea` state (codebase observed)

`HomeView.cardArea` is a `@ViewBuilder` property that renders a single `SpeakerCard(speaker: displayedSpeaker, …)` when `displayedSpeaker != nil`, or the `emptyState` view otherwise. There is no `SessionStripView`, no `SessionPageDots`, and no `scrollPosition` binding on the card side. The `SpeakerSelectorPill` scroll position IS already bound (`scrollPosition(id: $scrollPosition, anchor: .center)` with `onChange(of: selectedSpeaker?.id)`), creating a one-way relationship; E-52 T-5202 closes the other direction.

### Session model decision

`SpeakerGroup` already provides `id: String`, `members: [Speaker]`, and `hostSpeaker: Speaker`. The playing-session list is a pure filter: `discovery.groups.filter { $0.hostSpeaker.isPlaying }`. No additional wrapper type (`SessionsModel`) is needed. Introducing a `SessionsModel` would add an indirection layer with no information gain, contradict the ADR-002 invariant that mutation must stay on `@Observable @MainActor` types, and require mocking in tests. Verdict: **`SessionsModel` is not introduced.**

---

## 3. Options Considered

### Option A — `ScrollView(.horizontal)` + `.scrollTargetBehavior(.viewAligned)` with `scrollPosition(id:)` (chosen)

Provides the 8 pt card-peek affordance by sizing cards to `screenWidth - Spacing.s16 * 2` inside a full-width `ScrollView`. `scrollPosition(id:)` gives a writable `Binding<Speaker.ID?>` that drives bidirectional sync with `selectedSpeaker` via two `onChange` observers. `LazyHStack` with per-card `.id(group.id)` enables SwiftUI diffing for card insertion/removal without losing scroll position. Reduce Motion is handled inside `SpeakerCard.specularHighlight` (already implemented) and `SessionPageDots` dot animation (opacity-only). No new SwiftUI primitives beyond iOS 17.

Disadvantage: the two-way `onChange` loop requires care to avoid re-entrancy (scroll → selectedSpeaker → scroll). The guard in T-5202 (`if matchedGroup.hostSpeaker.id != scrollHostId`) prevents the loop.

### Option B — `TabView(selection:).tabViewStyle(.page)`

Built-in paging, simpler code. Cannot produce 8 pt card peek. Rejected per ADR-002 D1; confirmed not revisitable.

### Option C — Custom `DragGesture`-driven horizontal pager

Full control over peek and snap geometry. High implementation complexity, brittle on iOS 26, unnecessary given `ScrollView` capabilities. Rejected.

---

## 4. Rationale

Option A is the only choice consistent with ADR-002 D1. It uses exclusively shipping SwiftUI APIs (iOS 17+, well inside the iOS 26 deployment target), requires no new model layer, and the bidirectional `scrollPosition(id:)` binding pattern exactly mirrors the already-implemented pill side in `SpeakerSelectorPill`, producing a symmetric, understandable architecture. The re-entrancy guard on the `onChange` chain is a known and documented pattern in the codebase. The `LazyHStack` diffing approach for card insertion/removal is safe because `SpeakerGroup.id` is already stable and sorted (per `makeId(for:)` in `Group.swift`).

---

## 5. Consequences

- **E-54 T-5407/T-5409/T-5410 unblocked by T-5202.** Once `SessionStripView.onChange(of: selectedSpeaker?.id)` exists and scrolls the strip to the matching host, T-5407 (zero-code confirmation), T-5409 (manual e2e), and the scroll-related assertions of T-5410 (VoiceOver) can all proceed. ADR-E54 §8 documents these three tasks as blocked; T-5202 is the gate that clears them.
- **E-53 T-5306 blocked on T-5201.** `GroupChipRow` is wired through `SessionStripView`. T-5306 depends on `SessionStripView` existing. E-53 can build `GroupChipRow.swift` and `SpeakerCard` mount (T-5301–T-5305) in parallel, but T-5306 requires T-5201 to be in place.
- **E-55 T-5505 blocked on T-5206.** The E-55 home-screen state machine wraps the entire `cardArea` body that T-5206 creates. T-5505 cannot be written until T-5206 lands.
- **F2 E-59 drop destination.** F2 T-5905 attaches `.dropDestination(for: SpeakerIdentifier.self)` to each session card root. The session card root is the `SpeakerCard` wrapper inside `SessionStripView`. T-5905 is unblocked after T-5201.
- **`SpeakerCard` call site changes.** `HomeView.cardArea` currently calls `SpeakerCard(speaker:isExpanded:roll:pitch:)` with four parameters. `SessionStripView` replaces this call site and adds a fifth parameter `groupMembers:` (E-53 T-5306), which defaults to `[]` — backwards-compatible until E-53 wires it.
- **Screen-width workaround must be applied.** If the UIKit workaround is omitted, cards will be oversized on iPhone 14 Pro due to the iOS 26 ZStack inflation issue. This is a compile-time-silent runtime bug; code review must verify the workaround is present in `SessionStripView`.
- **Re-entrancy prevention required.** The `onChange(of: scrollHostId)` → `selectedSpeaker =` → `onChange(of: selectedSpeaker?.id)` → `scrollHostId =` cycle is broken by checking whether the incoming `selectedSpeaker` host ID already matches `scrollHostId` before animating. Implementer must include this guard.
- **Single-session no-regression.** When `groups.count == 1`, the `ScrollView` must be disabled (`.scrollDisabled(true)`) or the card must fill the full available width without a peek; no page dots must appear. This is a verified acceptance criterion (US-60, T-5207).

---

## 6. File-Level Plan

### New files

| Path | Type | Description |
|---|---|---|
| `iOS/Voxio/Features/Home/SessionStripView.swift` | `struct SessionStripView: View` | Horizontal paging strip. Owns `@State private var scrollHostId: Speaker.ID?`. Renders `SpeakerCard` per playing group. Implements two-way `selectedSpeaker` binding. |
| `iOS/Voxio/Features/Home/SessionPageDots.swift` | `struct SessionPageDots: View` | Page dot indicator. Returns `EmptyView()` when `count <= 1`. `accessibilityHidden(true)`. |

### Modified files

| Path | Change | Tasks |
|---|---|---|
| `iOS/Voxio/Features/Home/HomeView.swift` | Replace `cardArea` body with three-branch routing: `playingGroups.isEmpty && displayedSpeaker != nil` → existing `SpeakerCard`; `playingGroups.isEmpty && displayedSpeaker == nil` → existing `emptyState`; `!playingGroups.isEmpty` → `SessionStripView`. Add `playingGroups` computed property. | T-5206 |

No modifications to `SpeakerCard.swift`, `SpeakerSelectorPill.swift`, `SpeakerGroup`, `Speaker`, or any design-token file are required for E-52.

---

## 7. Public Interface Contract

The Implementer must expose exactly the following surfaces. The Test Writer may write against this contract without seeing the implementation.

```swift
// MARK: - SessionStripView
// File: iOS/Voxio/Features/Home/SessionStripView.swift

struct SessionStripView: View {
    /// Playing groups only — caller (HomeView) is responsible for pre-filtering.
    /// Passed as `discovery.groups.filter { $0.hostSpeaker.isPlaying }`.
    let groups: [SpeakerGroup]

    /// Two-way binding shared with SpeakerSelectorPill via HomeView state.
    /// Writing this binding scrolls the strip; swiping the strip updates this binding.
    @Binding var selectedSpeaker: Speaker?

    /// Parallax inputs forwarded to the front-most card only (T-5208).
    /// All non-visible cards receive 0/0.
    let roll: Double
    let pitch: Double

    /// Passed to each SpeakerCard for the isExpanded card-expand animation.
    let isCommandActive: Bool

    // Internal (listed for Test Writer reference — not exposed to callers):

    /// Bound to .scrollPosition(id:anchor:center) on the inner ScrollView.
    /// Drives the page-dot active index and the selectedSpeaker update.
    @State private var scrollHostId: Speaker.ID?

    // Behavioural contracts:
    //
    // 1. On onChange(of: scrollHostId): derive the matching SpeakerGroup whose
    //    hostSpeaker.id == scrollHostId. If found, set selectedSpeaker = group.hostSpeaker.
    //    If scrollHostId resolves to nil (edge case: strip empty), do not change selectedSpeaker.
    //
    // 2. On onChange(of: selectedSpeaker?.id): find the SpeakerGroup where
    //    selectedSpeaker is either the hostSpeaker OR a member. If found and
    //    group.hostSpeaker.id != scrollHostId, animate scrollHostId = group.hostSpeaker.id
    //    using withAnimation(BeoAnimation.spring). If the selected speaker belongs to no
    //    playing group (idle speaker tap), do NOT change scrollHostId — the strip stays
    //    where it was (US-62 acceptance criterion).
    //
    // 3. Re-entrancy guard: the onChange(of: selectedSpeaker?.id) handler must check
    //    group.hostSpeaker.id != scrollHostId before setting scrollHostId to prevent
    //    the two onChange observers from triggering each other in a loop.
    //
    // 4. Card sizing: cardWidth = screenWidth - (Spacing.s16 * 2) when groups.count > 1,
    //    giving an 8 pt trailing peek via natural overflow. When groups.count == 1,
    //    effectiveCardWidth = screenWidth - (Spacing.s16 * 2) with .scrollDisabled(true)
    //    and no page dots — indistinguishable from the v1.3 single-card layout.
    //
    // 5. Screen width is read from UIApplication.shared.connectedScenes (UIKit workaround
    //    matching SpeakerSelectorPill) — not from SwiftUI geometry, which is inflated on iOS 26.
    //
    // 6. Card insertion/removal: LazyHStack with .id(group.id) per card. On groups change,
    //    onChange(of: groups.map(\.id)) fires. If the previously-visible host is no longer
    //    in the new set, set scrollHostId = groups.first?.hostSpeaker.id.
    //
    // 7. Parallax: roll and pitch are passed only to the card whose group.hostSpeaker.id
    //    == scrollHostId. All other cards receive roll: 0, pitch: 0 (T-5208).
}
```

```swift
// MARK: - SessionPageDots
// File: iOS/Voxio/Features/Home/SessionPageDots.swift

struct SessionPageDots: View {
    /// Total number of sessions. Returns EmptyView() when count <= 1.
    let count: Int

    /// Zero-based index of the currently visible session.
    let selectedIndex: Int

    // Behavioural contracts:
    //
    // 1. Active dot: Circle(), diameter 8 pt, fill BeoColor.accent.
    // 2. Inactive dots: Circle(), diameter 6 pt, fill BeoColor.muted at 0.4 opacity.
    // 3. Spacing between dots: Spacing.s8.
    // 4. Active-index changes animate with BeoAnimation.toast (200 ms cross-fade).
    //    On Reduce Motion (@Environment(\.accessibilityReduceMotion)):
    //    opacity-only transition — no scale change.
    // 5. .accessibilityHidden(true) applied to the entire view.
    // 6. Returns EmptyView() when count <= 1 — no empty HStack, no zero-height space.
}
```

```swift
// MARK: - HomeView cardArea routing (T-5206)
// The Implementer must replace HomeView.cardArea with the following shape:

private var playingGroups: [SpeakerGroup] {
    discovery.groups.filter { $0.hostSpeaker.isPlaying }
}

@ViewBuilder
private var cardArea: some View {
    if !playingGroups.isEmpty {
        SessionStripView(
            groups: playingGroups,
            selectedSpeaker: $selectedSpeaker,
            roll: motionManager.roll,
            pitch: motionManager.pitch,
            isCommandActive: isCommandActive
        )
    } else if let speaker = displayedSpeaker {
        SpeakerCard(
            speaker: speaker,
            isExpanded: isCommandActive,
            roll: motionManager.roll,
            pitch: motionManager.pitch
        )
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.96)
    } else {
        emptyState
    }
}
```

Key behavioural contracts the Test Writer should assert:

1. Swiping the strip from card i to card i+1 causes `selectedSpeaker` to become the host of group at index i+1 within one SwiftUI update cycle.
2. Setting `selectedSpeaker` to a speaker who is the host of a playing group scrolls the strip to that group's card (verify via `scrollHostId`).
3. Setting `selectedSpeaker` to a speaker who is a non-host member of a playing group scrolls the strip to that group's card (not to a non-existent host card).
4. Setting `selectedSpeaker` to an idle speaker (not present in any playing group) does NOT change `scrollHostId`.
5. When `groups.count == 1`, the `ScrollView` is scroll-disabled, no page dots are rendered, and the card occupies `screenWidth - Spacing.s16 * 2` with no trailing peek.
6. When `groups.count > 1`, `SessionPageDots(count: groups.count, selectedIndex: activeIndex)` is rendered below the strip, separated by `Spacing.s8` vertical padding.
7. When a group is removed from `groups` while its card is visible, `scrollHostId` moves to `groups.first?.hostSpeaker.id`.
8. When a group is added to `groups`, the currently-visible card remains visible (scrollHostId unchanged).
9. `SessionPageDots` applies `.accessibilityHidden(true)` — confirmed absent from VoiceOver element tree.
10. Only the card whose `group.hostSpeaker.id == scrollHostId` receives non-zero `roll`/`pitch` values; all others receive `0`/`0`.
11. **Initial mount:** `scrollHostId` is initialised in `onAppear` to `selectedSpeaker`'s group host if it matches a playing group, otherwise to `groups.first?.hostSpeaker.id`. This assignment must be guarded by `if scrollHostId == nil` so it does not run a second time on view re-render. No animation fires on the initial assignment.
12. **`discovery.groups` ordering:** the array is appended in discovery order and not re-sorted across renders within a discovery cycle. The Implementer must not introduce a `.sorted(by:)` on the input — doing so would cause spurious page reflows via the `onChange(of: groups.map(\.id))` handler.

---

## 8. Conflicts Flagged

### CF-1: T-5202 gates three E-54 tasks (cross-epic hard dependency)

ADR-E54 §8 explicitly lists T-5407, T-5409, and the scroll assertions of T-5410 as blocked on E-52 T-5202. T-5202 must land before any of those E-54 tasks can be verified or closed. This is the primary cross-epic dependency for v1.4 F3. There is no workaround — the `SessionStripView.onChange(of: selectedSpeaker?.id)` handler literally does not exist until T-5202 is implemented.

### CF-2: E-55 T-5505 (home-screen state machine) requires T-5206

The E-55 `cardArea` state machine wraps the entire body produced by T-5206. T-5505 cannot be written without T-5206 being in place. This is a within-F3 serial dependency; it is documented in the epics doc and does not conflict with any spec.

### CF-3: No `SessionsModel` — verify E-59 drop-destination compatibility

F2 / E-59 T-5905 attaches `.dropDestination(for: SpeakerIdentifier.self)` to each session card. ADR-002 D3 specifies that resolution goes through `SessionViewModel.resolveSpeaker(_:)` against `SpeakerDiscoveryService.allSpeakers`. The E-52 public interface passes raw `SpeakerGroup` values from `HomeView.discovery.groups` — F2 must resolve speakers from `discovery.groups.flatMap(\.members)`, not from a `SessionsModel` type that does not exist. This is consistent with the codebase and ADR-002 D3; no spec conflict exists, but F2 implementers must be aware that no `SessionsModel` indirection layer is present.

### CF-4: `SpeakerCard` currently has no `groupMembers:` parameter

`SpeakerCard` in the current codebase has four initialiser parameters: `speaker`, `isExpanded`, `roll`, `pitch`. E-52's `SessionStripView` calls `SpeakerCard` with these four. E-53 T-5304 adds `var groupMembers: [Speaker] = []` (default empty). The E-52 call site is forward-compatible because of the default value, but if E-53 lands first, E-52's call site is also valid. No conflict; note for merge sequencing only.

### CF-5: `SpeakerCard.accessibilityElement(children: .ignore)` covers chip accessibility

Design spec §3.7 requires each session card's accessibility label to include the "also playing" group members. This is handled by E-53 T-5305 (extending `accessibilityDescription` on `SpeakerCard`). E-52's `SessionStripView` wraps `SpeakerCard` as-is; the `.accessibilityElement(children: .ignore)` already on `SpeakerCard` means `SessionStripView` adds no accessibility modifiers — the card is the element. No conflict; E-52 implementer need not add accessibility logic to `SessionStripView`.

### CF-6: No new design tokens (ADR-002 token-lock confirmed)

All values used by E-52 (`Spacing.s8`, `Spacing.s16`, `BeoColor.accent`, `BeoColor.muted` at 0.4 opacity, `BeoAnimation.spring`, `BeoAnimation.toast`, `Radius.card`) are pre-existing in `DesignTokens.swift` and `BeoColor.swift`. The design-spec §3.3 active dot size (8 pt) and inactive dot size (6 pt) are hard-coded geometry values, not tokens — consistent with ADR-002's token-lock.

---

**Verdict: PROCEED**
