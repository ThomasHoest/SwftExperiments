# ADR-E55 — Discovery and Offline States (E-55): NetworkMonitor, HomeState Machine, DiscoveryStateView, ConnectionStatusChip Rewrite

**Status:** Accepted
**Date:** 2026-05-11
**Deciders:** Engineering Lead
**Refs:** ADR-002-voxio-1.4-ios.md (D2), ADR-E52-session-card-strip.md (§5 Consequences CF-2), spec-home-screen-redesign.md v1.0 (US-63–US-66, §Technical Requirements, §Resolved Decisions), design-spec-home-screen-redesign.md v1.2 (§4, §5, §6, §7, Appendix B), epics-and-tasks-home-screen-redesign.md v1.0 (E-55 T-5501–T-5517), VoxioSpecification-1.4.md v1.4.1 (§Shared platform changes, §Recommended sequencing), CLAUDE.md

---

## 1. Decision

`NWPathMonitor` is wrapped in a new `NetworkMonitor` `@Observable @MainActor final class` owned as `@State` on `HomeView`, per ADR-002 D2. The home-screen state machine is modelled as a computed `enum HomeState` derived from `(network.isOnWifi, discovery.didSettle, discoveredSpeakerCount)` and switched on in `cardArea`, producing four branches: `.offline`, `.discovering`, `.noSpeakersFound`, and `.hasContent`. The existing E-52 three-branch `cardArea` body (shipped as T-5206) is preserved verbatim as the `.hasContent` branch. A new `DiscoveryStateView` renders all three non-content states by switching on the injected `HomeState`; `PulseRingsView` is its animated sub-component. `ConnectionStatusChip` is rewritten with three inputs (`isOnWifi`, `didSettle`, `speakerCount`) replacing the single `speakerCount` input, and a private `ChipState` enum drives copy and symbol selection. `SpeakerDiscoveryService` gains a `restart()` method and a 30-second auto-retry `Task` for the post-settle empty state.

---

## 2. Context

### Prior decisions this epic depends on

**ADR-002 D2 (NetworkMonitor placement)** mandates that `NWPathMonitor` lives in a new `NetworkMonitor` `@Observable @MainActor` class owned by `HomeView` as `@State private var network = NetworkMonitor()`. `isOnWifi` defaults to `true` to avoid an offline-state flash during the brief window between view mount and the first `pathUpdateHandler` callback. This ADR does not revisit that decision; it only specifies how `NetworkMonitor` is wired into the state machine and how the state machine is expressed.

**ADR-E52 §5 Consequences CF-2** records that E-55 T-5505 wraps the entire `cardArea` body produced by E-52 T-5206. The E-52 body is now present in the codebase (`HomeView.swift` lines 269–293) as a `@ViewBuilder` property with three branches (`!playingGroups.isEmpty` → `SessionStripView`; idle speaker → `SpeakerCard`; else → `emptyState`). T-5505 must preserve this body intact inside the `.hasContent` branch of the new state machine — it must not be re-implemented or replaced.

**Resolved UQ-8** (spec §Resolved Decisions) confirms that `ConnectionStatusChip` splits into three copy states driven by `NWPathMonitor` + `discovery.didSettle`. Resolved UQ-9 confirms auto-retry every 30 s, "Still looking…" after 10 s, and "Search again" for immediate manual retry.

**Codebase state at E-55 start.**

- `HomeView.cardArea` — E-52 T-5206 complete. Three-branch routing in place.
- `SpeakerSelectorPill` — E-54 T-5403–T-5408 complete. Bottom bar threshold is `>= 1`. `groups:` parameter in place.
- `ConnectionStatusChip` — single `speakerCount: Int` parameter only. Symbol and copy driven by `speakerCount > 0` proxy. This is the pre-E-55 state.
- `SpeakerDiscoveryService` — `@MainActor ObservableObject` (not `@Observable`). Has `start()` / `stop()`. No `restart()`. `didSettle: Bool` is `@Published private(set)` — writable from within the class.
- `NetworkMonitor.swift` — does not exist.
- `DiscoveryStateView.swift` / `PulseRingsView.swift` — do not exist.
- Localisation — done via Swift structs at `iOS/Voxio/Core/Strings/` (e.g. `GroupChipStrings`, `UIStrings`). No `.strings` or `.xcstrings` files exist in the project.

**Architecture invariant.** `SpeakerDiscoveryService` uses `ObservableObject` / `@Published`, not `@Observable`. `NetworkMonitor` will use `@Observable @MainActor`. These two observation mechanisms coexist in the same `HomeView` without conflict — SwiftUI merges `@StateObject` (`SpeakerDiscoveryService`) and `@State` (`NetworkMonitor`) update cycles correctly. No migration of `SpeakerDiscoveryService` to `@Observable` is required or permitted in E-55.

### Platform constraints

`NWPathMonitor` (iOS 12+), `@Observable` macro (iOS 17+), `Network.framework` — all available on the iOS 26 deployment target. No constraint violations.

---

## 3. Options Considered

### Option A — Enum-driven `HomeState` computed from inputs (chosen)

Define `private enum HomeState { case offline, discovering, noSpeakersFound, hasContent }` computed from `(network.isOnWifi, discovery.didSettle, discoveredSpeakerCount)`. `cardArea` switches on `homeState`, delegating each non-content branch to `DiscoveryStateView(state:onSearchAgain:)` and preserving the existing E-52 three-branch body as the `.hasContent` case.

Advantages: the enum is the single source of truth for the current layout branch. The switch statement is exhaustive — the compiler enforces that all states are handled. `DiscoveryStateView` is a clean, independently testable view receiving a value-type input. The E-52 `cardArea` body is unchanged and sits inside a single `case .hasContent:` block, satisfying the ADR-E52 CF-2 wrapping requirement. Adding a new state (e.g. a future "Wi-Fi but LAN blocked" state) requires only a new enum case and a new switch arm — no refactoring of existing branches.

### Option B — Inline `if/else` ladder in `HomeView.cardArea`

Add `!network.isOnWifi`, `!discovery.didSettle`, and `discovery.didSettle && discoveredSpeakerCount == 0` as guard conditions at the top of `cardArea`. Rejected: not exhaustive-checked; harder to extend.

---

## 4. Rationale

Option A is chosen because exhaustiveness enforcement from the compiler prevents regression when conditions change, the enum communicates intent clearly in `cardArea`, and `DiscoveryStateView` becomes a pure function of `HomeState` — independently testable without a running `HomeView`. The wrapping requirement from ADR-E52 CF-2 is satisfied trivially: the E-52 block drops unchanged into `case .hasContent`. The approach is also symmetric with the `ChipState` enum chosen for the `ConnectionStatusChip` rewrite, establishing a consistent pattern across E-55.

`DiscoveryStateView` receives the `HomeState` enum directly (not the three raw inputs) so it has one injection point. The `onSearchAgain` closure is non-nil only for `.noSpeakersFound` — the view ignores it in `.offline` and `.discovering` branches.

The `PulseRingsView` is extracted as a separate struct rather than embedded in `DiscoveryStateView` because it owns three `@State` animation phases and a `@Environment(\.accessibilityReduceMotion)` read — testable in isolation and reusable if a future feature needs the same animation.

---

## 5. Consequences

### Bottom bar and voice feedback in non-content states

The bottom bar (`SpeakerSelectorPill`) and voice feedback area (`voiceFeedback`) in `HomeView.body` currently sit outside `cardArea` in the enclosing `VStack`. The state machine gating for these elements is distinct from `cardArea` gating and must be applied explicitly:

- In `.offline` state: both `voiceFeedback` and `SpeakerSelectorPill` must be hidden (US-65). T-5512 gates both on `network.isOnWifi`.
- In `.discovering` and `.noSpeakersFound`: the existing `>= 1` guard (T-5408) already hides the bar because `discoveredSpeakerCount == 0`.
- In `.hasContent`: existing logic applies unchanged.

The voice recognition pipeline (`startListening`) must be gated on `network.isOnWifi` (T-5513). An `.onChange(of: network.isOnWifi)` observer in `HomeView` must call `startListening()` when Wi-Fi is restored — guarded by `hasCompletedOnboarding && langService.hasExplicitlyChosen`.

### E-52 session strip preserved

The E-52 three-branch `cardArea` body is not modified. It is relocated inside `case .hasContent:` of the `cardArea` switch.

### E-54 bottom bar condition unchanged

The `>= 1` threshold from T-5408 is the correct guard for the `.hasContent` state. The offline state needs an additional explicit `network.isOnWifi` gate (T-5512) for the offline-with-cached-speakers edge case.

### F1 / F2 impact

None. Both features operate entirely within the `.hasContent` branch.

### `SpeakerDiscoveryService.restart()` — allSpeakers reset required

`restart()` must clear `allSpeakers`, `groups`, `didSettle`, AND call a new `MdnsDiscovery.reset()` method that clears `foundHosts`, `serviceNameToHost`, `serviceNameToType`, `pendingServices` — otherwise duplicate-host guards prevent re-discovery of the same speakers. T-5510 must include this `MdnsDiscovery.reset()` call.

### Auto-retry Task and actor isolation

The `autoRetryTask` (T-5511) is a non-isolated `Task` that performs `try? await Task.sleep(...)` and then calls `await self.restart()` to hop back to the main actor.

### Localisation file

New strings for E-55 follow the `GroupChipStrings` / `UIStrings` pattern: a new `DiscoveryStrings` struct at `iOS/Voxio/Core/Strings/DiscoveryStrings.swift`.

---

## 6. File-Level Plan

### New files

| Path | Type | Description |
|---|---|---|
| `iOS/Voxio/Core/Discovery/NetworkMonitor.swift` | `@Observable @MainActor final class NetworkMonitor` | Wraps `NWPathMonitor`. `isOnWifi: Bool = true`, `isAvailable: Bool = true`. `start()`, `stop()`. Background queue + `Task { @MainActor in ... }` hop per ADR-002 D2. |
| `iOS/Voxio/Features/Home/DiscoveryStateView.swift` | `struct DiscoveryStateView: View` | Receives `state: HomeState` and `onSearchAgain: () -> Void`. Three render branches. `@State stillLookingShown`, `lastAnnouncedState`, `isSearching`. |
| `iOS/Voxio/Features/Home/PulseRingsView.swift` | `struct PulseRingsView: View` | Three concentric `Circle().stroke` rings; staggered expand-and-fade per design spec §4.2. Reduce Motion: single static ring. `accessibilityHidden(true)`. |
| `iOS/Voxio/Core/Strings/DiscoveryStrings.swift` | `struct DiscoveryStrings` | EN/DA copy via `forLanguage(_:)` factory. Covers all E-55 design-spec Appendix B keys not already in `UIStrings`. |

### Modified files

| Path | Change | Tasks |
|---|---|---|
| `iOS/Voxio/Features/Home/HomeView.swift` | Add `@State network = NetworkMonitor()`; `network.start()` in `onAppear`, `network.stop()` in `onDisappear`; `private var homeState: HomeState`; rewrite `cardArea` as switch; `private var discoveredSpeakerCount: Int`; wrap `voiceFeedback` + `SpeakerSelectorPill` with `network.isOnWifi` guard; `.onChange(of: network.isOnWifi)` to gate `startListening`; update `ConnectionStatusChip` call site; `.animation(BeoAnimation.toast, value: homeState.layoutKey)`. | T-5502, T-5504, T-5505, T-5509, T-5512, T-5513 |
| `iOS/Voxio/Features/Home/ConnectionStatusChip.swift` | Full rewrite. New init `(isOnWifi:didSettle:speakerCount:)`. Private `enum ChipState { case searching, offline, connected(Int) }`. Three rendering branches per US-66. | T-5503 |
| `iOS/Voxio/Core/Discovery/SpeakerDiscoveryService.swift` | Add `func restart()`: cancel `autoRetryTask`, `stop()`, `discovery.reset()`, clear `allSpeakers = []`, `groups = []`, `didSettle = false`, `start()`. Add `private var autoRetryTask: Task<Void, Never>?`. Schedule via `scheduleAutoRetry` from the `didSettle` setter (when `allSpeakers.isEmpty`); cancel from `addSpeaker` and `restart`. | T-5510, T-5511 |
| `iOS/Voxio/Core/Discovery/MdnsDiscovery.swift` | Add `func reset()`: clears `foundHosts`, `serviceNameToHost`, `serviceNameToType`, `pendingServices`. Called by `SpeakerDiscoveryService.restart()` before `start()`. | T-5510 prerequisite |

---

## 7. Public Interface Contract

```swift
// MARK: - NetworkMonitor
// File: iOS/Voxio/Core/Discovery/NetworkMonitor.swift

@Observable @MainActor final class NetworkMonitor {
    var isOnWifi: Bool = true
    var isAvailable: Bool = true

    func start()
    func stop()

    // Internal:
    // private let monitor = NWPathMonitor()
    // private let queue = DispatchQueue(label: "com.voxio.networkmonitor", qos: .utility)
    // pathUpdateHandler runs on `queue`; state forwarded via Task { @MainActor in self?.update(from: path) }
    // update(from:) sets:
    //   isOnWifi = path.status == .satisfied && path.usesInterfaceType(.wifi)
    //   isAvailable = path.status == .satisfied
}
```

```swift
// MARK: - HomeState (private enum on HomeView)

private enum HomeState: Equatable {
    case offline             // !network.isOnWifi
    case discovering         // isOnWifi && !didSettle && speakerCount == 0
    case noSpeakersFound     // isOnWifi && didSettle && speakerCount == 0
    case hasContent          // isOnWifi && speakerCount > 0

    var layoutKey: String {
        switch self {
        case .offline:         return "offline"
        case .discovering:     return "discovering"
        case .noSpeakersFound: return "noSpeakersFound"
        case .hasContent:      return "hasContent"
        }
    }
}

private var discoveredSpeakerCount: Int {
    discovery.groups.flatMap(\.members).count
}

private var homeState: HomeState {
    guard network.isOnWifi else { return .offline }
    if discoveredSpeakerCount > 0 { return .hasContent }
    if discovery.didSettle { return .noSpeakersFound }
    return .discovering
}
```

State priority: `!isOnWifi` wins over everything. `speakerCount > 0` wins over settle state — first speaker found immediately transitions to `.hasContent` regardless of `didSettle`.

```swift
// MARK: - DiscoveryStateView
// File: iOS/Voxio/Features/Home/DiscoveryStateView.swift

struct DiscoveryStateView: View {
    let state: HomeState                  // only .offline / .discovering / .noSpeakersFound used
    let onSearchAgain: () -> Void         // ignored when state != .noSpeakersFound

    // Behavioural contracts:
    //
    // 1. .discovering — PulseRingsView behind orb at full opacity. Below: Text(strings.searching)
    //    in BeoType.body, BeoColor.muted. After 10 s without state change: Text(strings.stillLooking)
    //    appears (BeoType.caption, BeoColor.muted at 0.6 opacity).
    //    @State stillLookingShown driven by .task(id: state) { try? await sleep(10s); if still .discovering -> true }
    //
    // 2. .noSpeakersFound — orb at 0.4 opacity (no pulse). Title (BeoType.nowPlaying) + body (BeoType.body).
    //    DarkGlassButton labelled strings.searchAgain; @State isSearching shows inline ProgressView.
    //    On tap: isSearching = true; onSearchAgain(). Reset isSearching on state change.
    //
    // 3. .offline — orb at 0.2 opacity (no animation). Title + body + autoRecovery sub-label.
    //    No button.
    //
    // 4. A11y announcements (T-5508):
    //    @State lastAnnouncedState; on state change, post AccessibilityNotification.Announcement:
    //      offline → discovering (from offline): strings.a11y.wifiRestored
    //      nil → discovering: strings.a11y.searching
    //      * → offline: strings.a11y.offline
    //    Set lastAnnouncedState = state after posting.
    //
    // 5. All copy via DiscoveryStrings.forLanguage(LanguageService.shared.activeLanguage).
    //
    // 6. Orb is NOT inside DiscoveryStateView — it sits in HomeView ZStack above. The view
    //    receives or computes orb opacity via the state:
    //      .discovering -> 1.0 with pulse; .noSpeakersFound -> 0.4 no pulse; .offline -> 0.2 no anim.
    //    If the orb is currently inline in HomeView, extract it to OrbView(opacity:isPulsing:) as
    //    part of T-5507 (preferred) or pass as a closure.
}
```

```swift
// MARK: - PulseRingsView
// File: iOS/Voxio/Features/Home/PulseRingsView.swift

struct PulseRingsView: View {
    // No public inputs.
    //
    // 3 Circle().stroke(BeoColor.accent, lineWidth: 1).
    // Each: 96 pt → 200 pt over 2.0 s, .easeOut, repeatForever(autoreverses: false).
    // Opacity 0.15 → 0 over same 2.0 s.
    // Ring 2 delay 0.6 s; Ring 3 delay 1.2 s.
    // @State active: Bool; animation kicks off in .onAppear.
    //
    // Reduce Motion: single Circle().stroke(BeoColor.accent.opacity(0.1), lineWidth: 1).frame(200).
    //
    // .accessibilityHidden(true) on the whole view.
    // Z-order: rings behind orb in caller's ZStack.
}
```

```swift
// MARK: - ConnectionStatusChip (rewritten)
// File: iOS/Voxio/Features/Home/ConnectionStatusChip.swift

struct ConnectionStatusChip: View {
    var isOnWifi: Bool
    var didSettle: Bool
    var speakerCount: Int

    private enum ChipState: Equatable {
        case searching       // isOnWifi && !didSettle
        case offline         // !isOnWifi
        case connected(Int)  // isOnWifi && didSettle
    }

    private var chipState: ChipState {
        guard isOnWifi else { return .offline }
        guard didSettle else { return .searching }
        return .connected(speakerCount)
    }

    // body per chipState:
    //   .searching    → Image("wifi"),       label strings.chipSearching, muted
    //   .offline      → Image("wifi.slash"), label strings.chipNoWifi,    secondary
    //   .connected(n) → Image("wifi"),       label "\(n)",                 green (existing)
    //
    // Existing glass-capsule styling unchanged.
    //
    // accessibilityLabel per state:
    //   .searching    → strings.a11y.chipSearching
    //   .offline      → strings.a11y.chipOffline
    //   .connected(n) → existing "n speaker(s) connected"
    //
    // The chip remains .accessibilityElement(children: .ignore).
    //
    // Edge case: isOnWifi && didSettle && speakerCount == 0 → .connected(0) — renders "0" with wifi
    // symbol (not "No Wi-Fi"). This is the correct post-settle-zero behaviour per US-66.
}

// Call site (T-5504):
ConnectionStatusChip(
    isOnWifi: network.isOnWifi,
    didSettle: discovery.didSettle,
    speakerCount: discovery.groups.flatMap(\.members).count
)
```

```swift
// MARK: - SpeakerDiscoveryService additions

private var autoRetryTask: Task<Void, Never>?

func restart() {
    autoRetryTask?.cancel()
    autoRetryTask = nil
    initialSettleTask?.cancel()
    stop()
    discovery.reset()        // new method on MdnsDiscovery
    allSpeakers = []
    groups = []
    didSettle = false
    start()
}

private func scheduleAutoRetry() {
    autoRetryTask?.cancel()
    autoRetryTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(30))
        guard !Task.isCancelled, let self else { return }
        guard self.didSettle && self.allSpeakers.isEmpty else { return }
        await self.restart()
    }
}

// scheduleAutoRetry() invoked from scheduleInitialSettle after setting didSettle = true (when allSpeakers.isEmpty).
// Cancelled in addSpeaker() (when allSpeakers becomes non-empty) and at the start of restart().

// MdnsDiscovery additions:
func reset() {
    foundHosts.removeAll()
    serviceNameToHost.removeAll()
    serviceNameToType.removeAll()
    pendingServices.removeAll()
}

// Behavioural contracts:
// 1. After restart(): didSettle == false, groups.isEmpty == true → homeState becomes .discovering.
// 2. restart() is idempotent.
// 3. autoRetryTask cancelled before stop() in restart() to prevent re-entry.
// 4. allSpeakers and groups cleared synchronously so HomeView immediately reads 0.
```

```swift
// MARK: - DiscoveryStrings
// File: iOS/Voxio/Core/Strings/DiscoveryStrings.swift

struct DiscoveryStrings {
    var searching:           String
    var stillLooking:        String
    var noSpeakersTitle:     String
    var noSpeakersBody:      String
    var searchAgain:         String
    var offlineTitle:        String
    var offlineBody:         String
    var offlineAutoRecovery: String
    var chipSearching:       String
    var chipNoWifi:          String

    struct A11y {
        var offline:           String
        var wifiRestored:      String
        var searching:         String
        var chipSearching:     String
        var chipOffline:       String
        var searchAgainButton: String
    }
    var a11y: A11y

    static let english: DiscoveryStrings = ...
    static let danish:  DiscoveryStrings = ...
    static func forLanguage(_ language: Language) -> DiscoveryStrings { ... }
}
```

---

## 8. Conflicts Flagged

### CF-1: `SpeakerDiscoveryService` is `ObservableObject`, not `@Observable`

The spec describes it as `@Observable @MainActor` but the actual class uses `@MainActor ObservableObject` with `@Published`. Both observation mechanisms coexist in SwiftUI. **Do NOT migrate `SpeakerDiscoveryService` to `@Observable` as part of E-55.** It would require unrelated refactors.

### CF-2: `MdnsDiscovery.stop()` does not clear `foundHosts`

Without `MdnsDiscovery.reset()`, calling `stop()` then `start()` won't re-discover known hosts (duplicate-host guards). T-5510 must add and call `MdnsDiscovery.reset()` to clear `foundHosts`, `serviceNameToHost`, `serviceNameToType`, `pendingServices`.

### CF-3: Orb is inline in `HomeView`, not an extracted `OrbView`

T-5507 must either (a) extract the orb into `OrbView(opacity: CGFloat, isPulsing: Bool)` (preferred) or (b) pass the orb as a closure/view parameter. The recommended approach is extraction for testability.

### CF-4: `voiceFeedback` gating scope

`voiceFeedback` is hidden only when offline (per US-65). It must NOT be hidden in `.discovering` or `.noSpeakersFound` — the waveform is visible while listening regardless of speaker count.

### CF-5: E-54 bottom bar gate handles discovery/no-speakers, but offline needs explicit gate

The `>= 1` condition correctly hides the bar in `.discovering` and `.noSpeakersFound` (zero speakers). The `.offline` state could coexist with a non-empty `groups` array (Wi-Fi drops while speakers were already discovered) — T-5512 must explicitly gate `SpeakerSelectorPill` on `network.isOnWifi`.

### CF-6: `HomeState` enum is private to `HomeView`

Test seam: `DiscoveryStateView`'s `state: HomeState` parameter is the testable surface. If the Test Writer needs `HomeState` to be instantiated from tests, promote to `internal` and move to a separate file.

### CF-7: F1/F2 — no conflicts

Both operate entirely inside the `.hasContent` branch.

---

## 9. Task Gate

| Task | Status |
|---|---|
| T-5501 Create `NetworkMonitor.swift` | UNBLOCKED |
| T-5502 Wire `NetworkMonitor` into `HomeView` | UNBLOCKED (after T-5501) |
| T-5503 Rewrite `ConnectionStatusChip` | UNBLOCKED (after T-5501) |
| T-5504 Update `ConnectionStatusChip` call site | UNBLOCKED (after T-5502, T-5503) |
| T-5505 Refactor `cardArea` with four-state routing | UNBLOCKED (after T-5502, T-5408 shipped) |
| T-5506 Create `PulseRingsView.swift` | UNBLOCKED |
| T-5507 Create `DiscoveryStateView.swift` | UNBLOCKED (after T-5506) |
| T-5508 A11y announcements in `DiscoveryStateView` | UNBLOCKED (after T-5507) |
| T-5509 `.animation` on `cardArea` transitions | UNBLOCKED (after T-5505) |
| T-5510 `restart()` + `MdnsDiscovery.reset()` | UNBLOCKED |
| T-5511 30 s auto-retry `Task` | UNBLOCKED (after T-5510) |
| T-5512 Hide `voiceFeedback`/pill offline | UNBLOCKED (after T-5502) |
| T-5513 Gate `startListening` on `isOnWifi` | UNBLOCKED (after T-5502) |
| T-5514 `DiscoveryStrings.swift` | UNBLOCKED |
| T-5515 Manual full-state-machine verification | DEFERRED (manual on device) |
| T-5516 VoiceOver verification | DEFERRED (manual on device) |
| T-5517 Reduce Motion verification | DEFERRED (manual on device) |

All 14 implementation tasks are unblocked. T-5515/T-5516/T-5517 are device-only manual verification — defer with `(deferred: manual verification on device)` per established pattern.

---

**Verdict: PROCEED**
