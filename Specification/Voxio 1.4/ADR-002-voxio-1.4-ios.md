# ADR-002 — Voxio 1.4 iOS Architecture: Touch Playback Controls, Multiroom Grouping, Home Screen Redesign

**Status:** Accepted — revised 2026-05-11 per architect-review-v1.4.md (D3, D4, D5 amendments — see Section 7)
**Date:** 2026-05-10 (rev 2026-05-11)
**Deciders:** Engineering Lead
**Refs:** VoxioSpecification-1.4.md v1.4.0, spec-touch-playback-controls.md v1.0, spec-multiroom-grouping.md v1.0, spec-home-screen-redesign.md v1.0, design-spec-touch-playback-controls.md v1.2, design-spec-multiroom-grouping.md v1.1, design-spec-home-screen-redesign.md v1.2, architect-review-v1.4.md v1.0, CLAUDE.md

---

## 1. Decision

The Voxio 1.4 iOS release adds touch playback controls, multiroom join/leave, and a home screen redesign as a strictly additive layer over the existing `@Observable @MainActor` view-model stack. The six primary architectural decisions are: (D1) the session-card strip uses `ScrollView(.horizontal)` with `.scrollTargetBehavior(.viewAligned)` rather than `TabView(.page)`; (D2) `NWPathMonitor` is owned by a new `NetworkMonitor` `@Observable @MainActor` class as `isOnWifi: Bool`, not by `SpeakerDiscoveryService` and not by the view layer directly; (D3) multiroom join uses SwiftUI `.draggable()/.dropDestination()` with `SpeakerIdentifier` itself conforming to `Transferable` via `CodableRepresentation` — the live `Speaker` reference is resolved on the main actor from `SpeakerDiscoveryService.allSpeakers` via a `SessionViewModel.resolveSpeaker(_:)` helper; (D4) volume broadcast to all group members uses `withTaskGroup` with partial-failure tolerance, housed in a new `SpeakerGroup.setVolumeOnAllMembers(_:)` helper that returns per-speaker `Result` values so the caller can surface a count of failed members; (D5) the non-optimistic join chip enforces a hard 10-second client-side timeout via `withThrowingTaskGroup` wrapping `SpeakerClient.join(peer:)`; the in-flight `Task` is stored on `SessionViewModel.joinTasks` (not on `SpeakerGroup`) and is **not** cancelled on view teardown — the API call is allowed to complete so model state stays consistent with the speaker; (D6) favorites are loaded lazily on first card appearance and cached on `Speaker`.

---

## 2. Context

### Problem being solved

Voxio was voice-only. Version 1.4 introduces touch as a peer interaction channel: users must be able to play, pause, adjust volume, start a favorite, and join or unjoin speakers from a group entirely via touch. In parallel, the home screen must evolve from a single static card to a swipeable multi-session strip with network-state awareness.

### Constraints

- **Platform:** iOS 26. `ScrollView(.scrollTargetBehavior)`, `Transferable`, `withTaskGroup`, and `NWPathMonitor` are all available without deployment-target risk.
- **Architecture invariant:** the `@Observable @MainActor Speaker` and `SpeakerGroup` view-model pattern is established and must not be bypassed. Mutation must always happen on the main actor.
- **No voice pipeline changes:** touch controls are additive. The command parser, `VoiceCommand` enum, and orb state machine are frozen for v1.4.
- **No backend changes:** telemetry, incidents, and the agent API are out of scope.
- **Existing card surface:** `SpeakerCard` is a SwiftUI `View` backed by a `Speaker` reference. F1, F2, and F3 all extend it — changes must not break the existing single-session (no-group) layout.
- **Design-token lock:** no new `BeoColor`, `Spacing`, `Radius`, `BeoAnimation`, or `BeoType` tokens are introduced in v1.4.
- **`SpeakerDiscoveryService`** is `@MainActor ObservableObject`, publishes `groups: [SpeakerGroup]` and `didSettle: Bool`. New published properties must follow the same pattern.
- **`SpeakerClient` protocol** already exposes `join(peer:)` and `leave()`. The protocol surface does not change.

---

## 3. Options Considered

### D1 — Session strip: ScrollView+viewAligned vs TabView(.page)

**Option A — `ScrollView(.horizontal)` + `.scrollTargetBehavior(.viewAligned)` (chosen)**
Native `ScrollView` allows the adjacent card to peek at 8 pt on the trailing edge (design-spec-home-screen-redesign.md UQ-5 resolution). Items sized to full-width minus `Spacing.s16` per side. Scroll position bound bidirectionally with the bottom bar via `scrollPosition(id:)`. Compatible with `@Observable` data — `ForEach` over `@Published groups` drives identity via `SpeakerGroup.id`.

**Option B — `TabView(selection:).tabViewStyle(.page)`**
Built-in paging with crisp snap, but does not support card-peek: each page fills the viewport. The 8 pt trailing-card peek is a resolved spec requirement (UQ-5) and cannot be achieved with `TabView(.page)` without undocumented hacks. Rejected.

**Evaluation:** `scrollPosition(id:)` (iOS 17+) provides the required two-way binding. `SpeakerGroup.makeId(for:)` supplies stable, unique IDs. No platform constraint violation.

---

### D2 — NWPathMonitor placement

**Option A — Separate `NetworkMonitor` `@Observable @MainActor` class (chosen)**
A new `@Observable @MainActor final class NetworkMonitor` wraps `NWPathMonitor` and publishes `isOnWifi: Bool` and `isAvailable: Bool`. `NWPathMonitor` starts in `start()` and cancels in `stop()`. The `pathUpdateHandler` runs on a background queue and hops back to the main actor via `Task { @MainActor in self.update(from: path) }`. The monitor is owned by `HomeView` (`@State private var network = NetworkMonitor()`), started in `onAppear` and stopped in `onDisappear`. `isOnWifi` defaults to `true` so that a freshly-mounted home screen does not flash the Offline state in the brief window before the first path update arrives; the first `pathUpdateHandler` callback corrects this within ~tens of milliseconds.

**Option B — Inside `SpeakerDiscoveryService` as `@Published isOnWifi: Bool`**
`SpeakerDiscoveryService` is already `@MainActor`, and consolidating WiFi + didSettle + speakerCount in one place reads tidily. Rejected because it conflates two concerns with different lifecycles: discovery starts/stops with the home screen, but `NWPathMonitor` benefits from being addressable independently (e.g. an "is the device on Wi-Fi?" probe before the home screen mounts). Keeping the monitor in its own type also makes it trivial to mock in previews and unit tests.

**Option C — In the view layer**
`NWPathMonitor` requires a background queue and explicit cancellation on disappear. Fragile in navigation hierarchies; WiFi state inaccessible to `ConnectionStatusChip` in a different view subtree. Rejected.

**Evaluation:** `NWPathMonitor` `updateHandler` runs off-main-thread; a `Task { @MainActor in ... }` hop is mandatory. Lifecycle mirrors `start()`/`stop()` on `NetworkMonitor`. No platform constraint violation.

---

### D3 — SwiftUI drag-and-drop for multiroom join

**Option A — `.draggable()` / `.dropDestination()` with `SpeakerIdentifier` itself conforming to `Transferable` (chosen)**
`Speaker` is `@Observable @MainActor` with an `any SpeakerClient` property — not safely `Transferable` directly. `SpeakerIdentifier`, however, is the existing `Codable` value-type identity already accepted by `SpeakerClient.join(peer:)`. Adding `extension SpeakerIdentifier: Transferable { static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .data) } }` is a one-line addition with no new wrapper type. The drop closure receives the `SpeakerIdentifier` and resolves the live `Speaker` on the main actor through a small `SessionViewModel.resolveSpeaker(_ id: SpeakerIdentifier) -> Speaker?` helper that consults `SpeakerDiscoveryService.allSpeakers` (matching by `jid`, falling back to `host`). Returns `nil` if no live speaker matches — the drop is rejected (`return false`).

**Option B — A wrapper struct (`struct SpeakerTransfer: Transferable, Codable { let stableId: String }`)**
An earlier draft of this ADR proposed a separate `SpeakerTransfer` value type. Rejected on revision because `SpeakerIdentifier` is already the codable identity used at the API boundary; introducing a parallel wrapper adds a type with no information not already in `SpeakerIdentifier`.

**Option C — Custom `DragGesture` + hit-testing**
Pre-iOS 16 technique. Brittle across animated scroll positions. Unnecessary on iOS 26.

**Option D — `Speaker` conforms directly to `Transferable`**
`any SpeakerClient` is not `Codable`. Would require reimplementing serialisation for a type whose live reference is what is actually needed. Rejected.

**Gesture conflict evaluation:** The 0.35 s long-press threshold gives the scroll recogniser priority for fast lateral swipes. Disambiguation is correct per SwiftUI gesture arbitration rules.

**Sendable / actor isolation:** `SpeakerIdentifier` is a `Codable` value type and implicitly `Sendable`. Resolution happens synchronously from `SpeakerDiscoveryService.allSpeakers` on `@MainActor`. No cross-actor boundary at transfer time.

---

### D4 — Volume broadcast to group members

**Option A — `withTaskGroup` in a new `SpeakerGroup.setVolumeOnAllMembers(_:)` (chosen)**
`SpeakerGroup` is `@Observable @MainActor`. A new `func setVolumeOnAllMembers(_ level: Int) async -> [(speaker: Speaker, result: Result<Void, Error>)]` fans out using `withTaskGroup`, one child per member. Each child returns a tuple of the member speaker and a `Result<Void, Error>` describing that speaker's outcome. The function does not `throw`: per-speaker error attribution is preserved so the caller can surface "Volume failed on N speakers" with the correct count. Partial failure (some members fail) and total failure both reach the caller through the returned array.

The name disambiguates from `Speaker.setVolume(_:)` (single-speaker REST call); the `OnAllMembers` suffix signals fan-out. F1 / E-57 T-5704 implements this helper. F2 does not consume it.

**Option B — `async let` fan-out**
Requires fixed bindings at compile time. Dynamic group size makes this equivalent to `withTaskGroup`.

**Option C — Sequential `await` per member**
Serialises worst-case to `n × timeout`. Unacceptable UX.

**Option D — Fan-out at the call site in the view**
Duplicates grouping logic in untestable view code. Rejected.

---

### D5 — Non-optimistic join with 10 s spinner

**Option A — Client-side 10 s `Task` stored on `SessionViewModel`, NOT cancelled on view teardown (chosen)**
The in-flight join `Task` is stored in `SessionViewModel.joinTasks: [String: Task<Void, Never>]`, keyed by the source `SpeakerIdentifier.id`, alongside `joinsInFlight: Set<String>` which drives source-pill lockout and the loading-chip variant in the group chip row. The join body wraps `client.join(peer:)` in `withThrowingTaskGroup` with two children: one that awaits `client.join(peer:)`, one that awaits `Task.sleep(for: .seconds(10))` and then throws a timeout error. The task group's first-completed-cancels-the-rest semantics implement the 10-second budget; timeout fires → chip failure state, identical to an API error.

**Cancellation policy: the task is NOT cancelled on view teardown.** Per F2 spec TR-4 step 5, the join call is allowed to complete even if the user navigates away. The trailing `discovery.mergeIntoSpeakerGroup` call is a no-op if the target group has disappeared; if it succeeded server-side, the model picks up the new group on the next `reconstructGroupsAsync` cycle. Cancelling the task would risk a state where the speaker has joined the group on the network but the local model has dropped the request — and the next refresh would surface a chip that the user did not expect.

**Option B — Rely on `MozartClient`'s 5 s `URLSession` timeout**
The 5 s timeout applies per HTTP request, not per logical join operation. Leaves the spinner running indefinitely if the server hangs past 5 s. Rejected.

**Option C — Task stored on `SpeakerGroup` with `cancelJoin()` on view teardown**
An earlier draft of this ADR. Rejected on revision: cancelling at view teardown can leave the model and the speaker disagreeing about group membership, and `SessionViewModel` is the natural per-card owner of in-flight state.

**`joinsInFlight: Set<String>`** lives on `SessionViewModel`. The home view aggregates these across cards via a `joinsInFlightUnion: Set<String>` so the bottom-bar pill renderer can render source pills at 0.5 opacity for the full call duration regardless of which card the drop landed on. Only one join per source speaker can be in-flight at a time (the source pill is non-draggable during flight).

---

### D6 — Favorites data source

**Option A — Lazy load on first `.onAppear`, cached on `Speaker` (chosen)**
`Speaker` gains `var favorites: [Favorite] = []` and `var favoritesState: FavoritesLoadState` (`.idle / .loading / .loaded / .failed(Error)`). On first appearance, a `Task` calls `client.getSources()`. Subsequent appearances read the cache. A retry button appears on `.failed`.

**Option B — Load at `Speaker.initialize()` time**
Adds latency to speaker resolution for all speakers, including idle ones never shown in the session strip. `SpeakerDiscoveryService` rejects speakers where `initialize()` throws — a favorites failure would silently swallow. Rejected.

---

## 4. Decision Rationale Summary

| Decision | Choice | Primary reason |
|---|---|---|
| D1 Session strip | `ScrollView` + `.viewAligned` | Card-peek requirement rules out `TabView(.page)`; `scrollPosition(id:)` enables bidirectional sync |
| D2 NWPathMonitor | Owned by a new `NetworkMonitor` `@Observable @MainActor` class; `isOnWifi` defaults to `true` | Independent lifecycle from discovery; trivially mockable; avoids offline-flash on home-screen mount |
| D3 Drag-and-drop | `SpeakerIdentifier: Transferable` via `CodableRepresentation`, resolved via `SessionViewModel.resolveSpeaker(_:)` | Reuses the existing API-boundary identity; no parallel wrapper type |
| D4 Volume broadcast | `withTaskGroup` in `SpeakerGroup.setVolumeOnAllMembers`, returning per-speaker `Result` | Dynamic group size; encapsulated; preserves per-speaker error attribution |
| D5 Join timeout | 10 s `withThrowingTaskGroup` budget; `Task` stored on `SessionViewModel`; not cancelled on teardown | Bounds spinner; avoids local/server model divergence from premature cancellation |
| D6 Favorites | Lazy `.onAppear` load, cached on `Speaker` | Avoids blocking speaker init; avoids loading idle speakers' favorites |

---

## 5. Consequences and Risks

| Risk | Severity | Mitigation |
|---|---|---|
| `scrollPosition(id:)` requires stable `SpeakerGroup.id` across mutations | Medium | `makeId(for:)` is already sorted and stable. Membership mutations must update `group.id` — already done in `mergeIntoSpeakerGroup` and `removeMember`. Do not mutate `group.id` during an active join/leave; only update on `reconstructGroupsAsync`. |
| `NWPathMonitor` `updateHandler` runs off-main-thread | Medium | `@Published` mutation must use `Task { @MainActor in ... }`. Flag as mandatory code-review check. |
| Drag-and-drop gesture conflict with horizontal bottom-bar scroll | Low-Medium | 0.35 s long-press threshold gives scroll priority for fast swipes. Validate on device. |
| `withTaskGroup` partial failure leaving volume inconsistent | Low | WS events deliver the speaker's actual volume within seconds. No permanent inconsistency. |
| 10 s spinner degrading perceived quality on slow LAN | Medium | Haptic on drop gives immediate confirmation; spinner communicates active progress. Hardware/API constraint. |
| `SpeakerGroup` identity change causing `ScrollView` scroll-position reset | Low | Do not mutate `group.id` during live join/leave. Only update on background `reconstructGroupsAsync`. |
| `HapticEngine` missing `dragLifted()`, `dragEnteredDropZone()`, `dragCancelled()` methods | Low | These three methods must be added to `HapticEngine.swift` as part of E-59 (T-5901). |

---

## 6. Platform Constraint Checks

All three features target iOS 26. All APIs confirmed available:

| API | Introduced | Used by |
|---|---|---|
| `ScrollView` + `.scrollTargetBehavior(.viewAligned)` | iOS 17 | D1 |
| `scrollPosition(id:)` modifier | iOS 17 | D1 |
| `.draggable()` / `.dropDestination()` / `Transferable` | iOS 16 | D3 |
| `NWPathMonitor` | iOS 12 | D2 |
| `withTaskGroup` | iOS 15 | D4 |

No platform constraint violations detected.

---

## 7. Spec Revisions Required

### REVISE 1 — Haptic references in `design-spec-multiroom-grouping.md` (D3)
**Status: Applied.** Sections 1.1, 2.2, and 6.2 now reference `HapticEngine.shared.dragLifted()`, `HapticEngine.shared.dragEnteredDropZone()`, and `HapticEngine.shared.dragCancelled()` — consistent with the `HapticEngine` abstraction used throughout F1. These three methods must be added to `HapticEngine.swift` (T-5901 prereq).

### REVISE 2 — 10-second join timeout outcome in `design-spec-multiroom-grouping.md` (D5)
**Status: Applied.** Section 4.1 step 4 and §6.3 now explicitly state: "If the join call does not complete within 10 seconds, it is treated as a failure — the chip fades out, the source pill restores to full draggable opacity, and an error toast is shown."

### REVISE 3 — ADR D3 transferable mechanism (2026-05-11)
**Status: Applied.** Per architect-review-v1.4.md OQ-1, Section 3 D3 has been rewritten: `SpeakerIdentifier` itself conforms to `Transferable` via `CodableRepresentation(contentType: .data)`. The earlier `SpeakerTransfer` wrapper and the `SpeakerStore.shared` reference (which does not exist in the codebase) have been removed. Drop-handler resolution goes through `SessionViewModel.resolveSpeaker(_:)` against `SpeakerDiscoveryService.allSpeakers`.

### REVISE 4 — ADR D4 helper name (2026-05-11)
**Status: Applied.** Per architect-review-v1.4.md OQ-5, the group-volume helper is `SpeakerGroup.setVolumeOnAllMembers(_:)` returning `[(speaker: Speaker, result: Result<Void, Error>)]`, matching F1 spec Q1 / epic T-5704. The earlier `setVolume(_:)` name collided with the per-speaker REST call.

### REVISE 5 — ADR D5 task location and cancellation policy (2026-05-11)
**Status: Applied.** Per architect-review-v1.4.md OQ-2, the in-flight join `Task` is stored on `SessionViewModel.joinTasks` (not on `SpeakerGroup`) and is **not** cancelled on view teardown — matching F2 spec TR-4 step 5. The 10-second timeout is implemented via `withThrowingTaskGroup` inside the join body, not via external `Task.cancel()`. F2 epic T-6001 has been updated to include the timeout wrapper code.

### REVISE 6 — ADR D2 NetworkMonitor location and default (2026-05-11)
**Status: Applied.** Per architect-review-v1.4.md OQ-9, `NWPathMonitor` lives in a new `NetworkMonitor` `@Observable @MainActor` class (not on `SpeakerDiscoveryService`), and `isOnWifi` defaults to `true` to avoid an offline-state flash during the brief window between view mount and the first `pathUpdateHandler` callback. F3 epic T-5501 has been updated.

---

**Verdict: PROCEED** (post-revision)
