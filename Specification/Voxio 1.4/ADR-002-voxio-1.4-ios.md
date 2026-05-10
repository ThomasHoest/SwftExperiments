# ADR-002 — Voxio 1.4 iOS Architecture: Touch Playback Controls, Multiroom Grouping, Home Screen Redesign

**Status:** Accepted (two spec items revised per REVISE verdict — see Section 7)
**Date:** 2026-05-10
**Deciders:** Engineering Lead
**Refs:** VoxioSpecification-1.4.md v1.4.0, design-spec-touch-playback-controls.md v1.2, design-spec-multiroom-grouping.md v1.1, design-spec-home-screen-redesign.md v1.2, CLAUDE.md

---

## 1. Decision

The Voxio 1.4 iOS release adds touch playback controls, multiroom join/leave, and a home screen redesign as a strictly additive layer over the existing `@Observable @MainActor` view-model stack. The six primary architectural decisions are: (D1) the session-card strip uses `ScrollView(.horizontal)` with `.scrollTargetBehavior(.viewAligned)` rather than `TabView(.page)`; (D2) `NWPathMonitor` is owned by `SpeakerDiscoveryService` as a `@Published isOnWifi: Bool`, not by the view layer; (D3) multiroom join uses SwiftUI `.draggable()/.dropDestination()` backed by a lightweight `Transferable` wrapper — `Speaker` itself does not conform; (D4) volume broadcast to all group members uses `withTaskGroup` with partial-failure tolerance, housed in a new `SpeakerGroup.setVolume(_:)` helper rather than at the call site; (D5) the non-optimistic join chip enforces a hard 10-second client-side timeout via a `Task` wrapping `SpeakerClient.join(peer:)`, stored on `SpeakerGroup` so it can be cancelled if the view disappears; (D6) favorites are loaded lazily on first card appearance and cached on `Speaker`.

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

**Option A — Inside `SpeakerDiscoveryService` as `@Published isOnWifi: Bool` (chosen)**
`SpeakerDiscoveryService` is already `@MainActor`. `NWPathMonitor` starts in `start()` and cancels in `stop()`. The `updateHandler` dispatches back to `MainActor` via `Task { @MainActor in self.isOnWifi = ... }`. Keeps the full state machine (WiFi / didSettle / speakerCount) in one place.

**Option B — Separate `NetworkMonitor` observable**
Adds a new injection point and requires composing two sources of truth in the view. No benefit over Option A.

**Option C — In the view layer**
`NWPathMonitor` requires a background queue and explicit cancellation on disappear. Fragile in navigation hierarchies; WiFi state inaccessible to `ConnectionStatusChip` in a different view subtree. Rejected.

**Evaluation:** `NWPathMonitor` `updateHandler` runs off-main-thread; a `Task { @MainActor in ... }` hop is mandatory. Lifecycle mirrors `start()`/`stop()` on `SpeakerDiscoveryService`. No platform constraint violation.

---

### D3 — SwiftUI drag-and-drop for multiroom join

**Option A — `.draggable()` / `.dropDestination()` with a thin `SpeakerTransfer` wrapper (chosen)**
`Speaker` is `@Observable @MainActor` with a `any SpeakerClient` property — not `Codable` and not safely `Transferable` directly. A `struct SpeakerTransfer: Transferable, Codable` carries only `stableId: String`. The drop closure resolves the live `Speaker` from `SpeakerStore.shared.allSpeakers` on the main actor.

**Option B — Custom `DragGesture` + hit-testing**
Pre-iOS 16 technique. Brittle across animated scroll positions. Unnecessary on iOS 26.

**Option C — `Speaker` conforms directly to `Transferable`**
`any SpeakerClient` is not `Codable`. Would require reimplementing serialisation for a type whose live reference is what is actually needed. Rejected.

**Gesture conflict evaluation:** The 0.35 s long-press threshold gives the scroll recogniser priority for fast lateral swipes. Disambiguation is correct per SwiftUI gesture arbitration rules.

**Sendable / actor isolation:** `SpeakerTransfer` is a `Codable struct` and implicitly `Sendable`. Resolution happens synchronously from `SpeakerStore.shared.allSpeakers` on `@MainActor`. No cross-actor boundary at transfer time.

---

### D4 — Volume broadcast to group members

**Option A — `withTaskGroup` in a new `SpeakerGroup.setVolume(_:)` (chosen)**
`SpeakerGroup` is `@Observable @MainActor`. A new `func setVolume(_ level: Int) async throws` fans out using `withTaskGroup`, one child per member. Partial failure (some members fail): error toast enumerating failed speaker names; successful updates stand. Total failure: rethrows to call site → standard error toast.

**Option B — `async let` fan-out**
Requires fixed bindings at compile time. Dynamic group size makes this equivalent to `withTaskGroup`.

**Option C — Sequential `await` per member**
Serialises worst-case to `n × timeout`. Unacceptable UX.

**Option D — Fan-out at the call site in the view**
Duplicates grouping logic in untestable view code. Rejected.

---

### D5 — Non-optimistic join with 10 s spinner

**Option A — Client-side 10 s `Task` stored on `SpeakerGroup` (chosen)**
Join `Task` stored as `private var joinTask: Task<Void, Never>?` on `SpeakerGroup`. On view `onDisappear`, `group.cancelJoin()` cancels the task. Join wraps `client.join(peer:)` in a 10-second timeout (implemented via `withThrowingTaskGroup` with a sleep-and-throw child task). Timeout fires → chip failure state, identical to API error.

**Option B — Rely on `MozartClient`'s 5 s `URLSession` timeout**
The 5 s timeout applies per HTTP request, not per logical join operation. Leaves the spinner running indefinitely if the server hangs past 5 s. Rejected.

**Task cancellation:** `joinTask` set/cancelled on `@MainActor`. Cooperative cancellation — `Task.isCancelled` checked post-timeout. If `beolinkExpand` completed server-side during cancellation, `reconstructGroupsAsync` picks it up on the next settle.

**`isJoining`** is a new `Bool` on `SpeakerGroup` (not `Speaker`) — joining is a group-level operation. Only one join can be in-flight per group (source pill is non-draggable during flight).

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
| D2 NWPathMonitor | Owned by `SpeakerDiscoveryService` | Single lifecycle owner; keeps state machine in one place |
| D3 Drag-and-drop | Thin `SpeakerTransfer` wrapper | `Speaker` not safely `Codable`; wrapper recovers live reference without cross-actor transfer |
| D4 Volume broadcast | `withTaskGroup` in `SpeakerGroup.setVolume` | Dynamic group size; encapsulated; partial-failure tolerant |
| D5 Join timeout | 10 s `Task` stored on `SpeakerGroup` | Bounds spinner; `Task.cancel()` on view disappear prevents orphaned calls |
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
**Status: Applied.** Sections 1.1, 2.2, and 6.2 now reference `HapticEngine.shared.dragLifted()`, `HapticEngine.shared.dragEnteredDropZone()`, and `HapticEngine.shared.dragCancelled()` — consistent with the `HapticEngine` abstraction used throughout F1. These three methods must be added to `HapticEngine.swift` (T-5901).

### REVISE 2 — 10-second join timeout outcome in `design-spec-multiroom-grouping.md` (D5)
**Status: Applied.** Section 4.1 step 4 and §6.3 now explicitly state: "If the join call does not complete within 10 seconds, it is treated as a failure — the chip fades out, the source pill restores to full draggable opacity, and an error toast is shown."

---

**Verdict: PROCEED**
