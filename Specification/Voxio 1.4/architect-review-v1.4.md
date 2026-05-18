# Architect Review — Voxio 1.4

**Version:** 1.0
**Date:** 2026-05-11
**Reviewer:** Architect (Claude)
**Inputs reviewed:** `VoxioSpecification-1.4.md`, `ADR-002-voxio-1.4-ios.md`, `spec-home-screen-redesign.md`, `spec-touch-playback-controls.md`, `spec-multiroom-grouping.md`, `design-spec-home-screen-redesign.md`, `design-spec-touch-playback-controls.md`, `design-spec-multiroom-grouping.md`, `epics-and-tasks-home-screen-redesign.md`, `epics-and-tasks-touch-playback-controls.md`, `epics-and-tasks-multiroom-grouping.md`, project `CLAUDE.md`.

---

## Summary

**Verdict: PROCEED with fixes.** The spec suite is unusually thorough — every UQ is resolved, every user story has acceptance criteria, error states are enumerated, NFRs are quantified. ADR-002 covers six architectural decisions soundly and includes a platform-availability matrix. There are no platform-incompatibility blockers.

Three classes of issue need fixing before implementation starts:

1. **ADR ↔ spec/epics contradictions** in two places (Transferable approach; 10 s join timeout location) where the ADR text and the epic tasks describe different implementations.
2. **Naming drift** across HapticEngine method names and the F1 group-volume helper.
3. **Shared-file coordination risk** at `SpeakerCard.swift` — F1, F3/E-53, and F3/E-54 all modify it concurrently.

None of these block ADR acceptance. They need to be either fixed in the docs (preferred — cheap) or explicitly converted to "implementer's choice" with rationale.

---

## ADR-002 assessment

ADR-002 is well-structured: each decision states the chosen option, alternatives considered, evaluation against the platform, and risks. The platform constraint matrix (ADR §6) explicitly checks each iOS API used against introduction version — every API is available on iOS 26 with headroom. Sendable/actor isolation is addressed in D3. The risk register in §5 covers the right things (scroll-position stability, off-main-thread callbacks, gesture conflicts, partial-failure volume).

Two ADR-internal issues:

**ADR-1 — D3 transferable mechanism contradicts the specs and epics.**
ADR D3 specifies a `struct SpeakerTransfer: Transferable, Codable { let stableId: String }` wrapper and resolves the live `Speaker` "from `SpeakerStore.shared.allSpeakers` on the main actor". Both the F2 spec (TR-1) and `epics-and-tasks-multiroom-grouping.md` T-5901 instead make `SpeakerIdentifier` itself conform to `Transferable` via `CodableRepresentation(contentType: .data)` and resolve via `SessionViewModel.resolveSpeaker(_:)` against `discovery.allSpeakers`. The spec/epics approach is simpler and consistent with the existing `SpeakerIdentifier` value type that `SpeakerClient.join(peer:)` already accepts. `SpeakerStore.shared` is not documented in `CLAUDE.md` and does not appear to exist; `SpeakerDiscoveryService` is the actual source of truth.

**Recommendation:** revise ADR-002 D3 to match the specs — `SpeakerIdentifier: Transferable` via `CodableRepresentation`, resolved through `SpeakerDiscoveryService` (or the per-card `SessionViewModel`). Remove the `SpeakerTransfer` wrapper and the `SpeakerStore.shared` reference.

**ADR-2 — D5 timeout location contradicts the epics.**
ADR D5 specifies the 10 s timeout is "implemented via `withThrowingTaskGroup` with a sleep-and-throw child task" with the join `Task` "stored on `SpeakerGroup` so it can be cancelled if the view disappears". F2 spec TR-4 step 5 explicitly says the join `Task` is **not** cancelled on view teardown ("let the API call complete to keep the speaker state consistent"). Epic task T-6001 stores tasks on `SessionViewModel.joinTasks: [String: Task<Void, Never>]`, not on `SpeakerGroup`, and includes no timeout wrapper code at all — `try await source.client.join(peer: target.identifier)` is called directly.

**Recommendation:** revise ADR-002 D5 to (a) locate the join-tracking state on `SessionViewModel`, not `SpeakerGroup` (matches spec/epics); (b) state explicitly that the task is NOT cancelled on teardown (matches TR-4 step 5); (c) add an implementation note to epic T-6001 to wrap the `client.join(peer:)` call in a `withThrowingTaskGroup` with a 10 s timeout sibling — the current task code does not enforce the 10 s budget the spec and design promise.

---

## Per-feature findings

### F1 — Touch Playback Controls

Functionally sound. The spec is consistent with the design spec and with the existing `Speaker` API. Three issues:

**F1-1 — Group-volume helper name drift.**
ADR D4 calls it `SpeakerGroup.setVolume(_ level: Int)`. F1 spec §Technical Context and epic T-5704 call it `SpeakerGroup.setVolumeOnAllMembers(_ level: Int) async -> [(speaker: Speaker, result: Result<Void, Error>)]`. F1 open question Q1 explicitly defers the decision. Either name works; pick one before T-5704 lands. The `Result`-returning signature is preferable to `async throws` because partial failure is the design intent — losing per-speaker error attribution to `throws` would lose information.

**F1-2 — `speaker.playbackState` enum cases unverified.**
Epic T-5601 refactors `cardContent` to switch on `speaker.playbackState` with cases `.playing / .paused / .buffering / .stopped`. `CLAUDE.md` describes a `Playback` model and notes `"started"` is equivalent to `"playing"` (Mozart API string), but does not confirm a Swift `enum PlaybackState` exists with those four cases. If the speaker exposes a `String` instead, the switch must map strings. **Verify before T-5601.**

**F1-3 — `MozartError` vs `SpeakerError`.**
F1 spec error-states table references `MozartError.timeout / .unreachable / .httpError`. F2 spec uses `SpeakerError.timeout / .unreachable`. The two protocols (`MozartClient` and `BNRClient`) likely both map to a common `SpeakerError` at the abstraction layer; otherwise F1 toasts for a BNR speaker would render the wrong error. **Verify the error-type abstraction is in place** — if not, F1 needs a small additional task to introduce or extend `SpeakerError`.

### F2 — Multiroom Grouping

The largest spec by volume, and the one with the most cross-cutting dependencies. Issues:

**F2-1 — HapticEngine method names contradict the ADR REVISE.**
ADR §7 REVISE 1 says the design spec was revised to reference `HapticEngine.shared.dragLifted()`, `dragEnteredDropZone()`, `dragCancelled()` — and design-spec §6.2 indeed lists those three names. But `epics-and-tasks-multiroom-grouping.md` invents two new ones:
- T-5904 calls `HapticEngine.shared.dragInitiated()` (should be `dragLifted()`).
- T-5905 calls `HapticEngine.shared.dropZoneEntered()` (should be `dragEnteredDropZone()`).

**Recommendation:** correct T-5904 and T-5905 to the names in design-spec §6.2 and ADR REVISE 1. These methods do not exist on `HapticEngine` today — they must be added as part of T-5901 prereq work (this is correctly identified in `project_spec_structure` memory and the ADR risk row).

**F2-2 — Stack-version inconsistency.**
F2 epics declare `Stack: Swift 5.10, SwiftUI (iOS 16+)`. F1 and F3 epics declare `Swift 6 / iOS 26`. Deployment target is iOS 26. Pick the project's actual stack — Swift 6 if the project has migrated, otherwise 5.10 — and align all three epic docs.

**F2-3 — `SpeakerStore.shared` reference in ADR D3 only.**
Already covered under ADR-1. No `SpeakerStore` exists; resolution goes through `SpeakerDiscoveryService` / `SessionViewModel.resolveSpeaker(_:)`.

**F2-4 — Coach-mark dismiss plumbing.**
T-5909 dismisses on `NotificationCenter.default.post(name: .groupingDropCompleted, ...)` triggered from T-6001. This is an ad-hoc Notification name not documented elsewhere in the codebase. Cleaner alternative: have `SessionViewModel.handleJoinDrop` set a `@Published` `lastDropCompletedAt: Date?` (or similar) on a shared `HomeViewModel`, and have the coach mark observe that. Notification routing for cross-component coordination tends to rot. Not a blocker.

**F2-5 — Multi-card drop-destination across the strip — verify `isTargeted` independence.**
T-5907 documents the pattern correctly ("drop destination is per-card — do not lift to the strip"), but the actual independence of `isTargeted` callbacks across simultaneously-visible cards (including a peeking card at the edge) is iOS-platform behaviour that should be smoke-tested on device early, not at end-of-epic. If two cards both flash gold when the ghost is between them, the strip needs a manual hit-test.

### F3 — Home Screen Redesign

The cleanest of the three from an architecture standpoint — most of the new components are small additive views. Issues:

**F3-1 — `SpeakerDiscoveryService.didSettle` setter visibility.**
T-5510 (`restart()`) writes `didSettle = false`. The task notes "already true since the property is `private(set)`" — but `private(set)` makes the setter *internal-private*, which means only code inside the same file/extension can reassign it. If `restart()` is added in an extension in the same file as the property declaration, this works. If it lands in a separate file, the compiler will reject. **Confirm placement** — keep `restart()` in the same file as `SpeakerDiscoveryService.swift`, or relax visibility deliberately.

**F3-2 — VoiceOver vs ScrollView paging gesture conflict.**
US-60 acceptance criterion says "VoiceOver users navigate session cards in standard element-focus order; the swipe gesture does not interfere with the VoiceOver swipe." `ScrollView(.horizontal)` with `.scrollTargetBehavior(.viewAligned)` and `.scrollPosition(id:)` doesn't, by default, expose its paging gesture as a VoiceOver-routable swipe — VoiceOver swipes move element focus regardless of the underlying scroll. This is fine, but it means **VoiceOver users do not get the paging affordance**; they navigate every accessibility element in order. T-5210 tests this. If product wants VoiceOver to drive paging directly, an additional `accessibilityScrollAction(_:)` per card would be needed. Flagging as a UX-product call rather than an architecture issue.

**F3-3 — `NetworkMonitor` lifecycle on backgrounding.**
T-5502 starts the monitor in `onAppear`, stops in `onDisappear`. iOS app-suspend cycles invoke `onDisappear` on the root view. When the user returns to foreground, the monitor is restarted. There is a brief window after foreground where `isOnWifi` may still be `false` (default) before the first path update arrives — the home screen may flash the Offline state for a few hundred ms even when Wi-Fi is fine. Mitigation: initialize `isOnWifi` to `true` until the first path callback arrives, OR drive `NetworkMonitor` from app lifecycle (`@SceneStorage`/`UIApplication.willEnterForegroundNotification`) instead of view lifecycle. Not a blocker — flag for test on resume.

**F3-4 — 30 s auto-retry interaction with backgrounding.**
T-5511 schedules a 30 s `Task.sleep` that may outlive the view or even backgrounding. If the app is suspended during the sleep, iOS may extend the sleep arbitrarily; on resume, the sleep wakes and immediately fires `restart()`. Usually benign, but worth testing the long-background path. Could be capped by checking `Date()` delta inside the task and re-scheduling if more than 30 s has passed.

**F3-5 — `Speaker` identity for ScrollView `scrollPosition(id:)`.**
T-5202 binds `scrollHostId: Speaker.ID?`. The ADR (risk row 1) correctly identifies that `SpeakerGroup.id` must remain stable across mutations — but the epic actually binds to `Speaker.ID`, not `SpeakerGroup.id`. The two are different. The matching code uses `groups.first(where: { $0.hostSpeaker.id == scrollHostId })`. This is consistent and works, but the ADR risk row is worded against `SpeakerGroup.id`. **Align the ADR risk text** to talk about `Speaker.ID` stability (which is mDNS-derived and stable, so the actual risk is lower than the ADR suggests).

---

## Cross-feature consistency

The three specs are coherent in big-picture terms (gold = playing, no new design tokens, additive over the existing view-model stack). Issues:

**X-1 — Shared file: `SpeakerCard.swift`.**
F1 (E-56/E-57/E-58) and F3 (E-53 chip row mount, E-54 `PlaybackBars` extraction) all modify `SpeakerCard.swift`. F1 restructures `cardContent` to switch on `playbackState`. F3/E-53 adds a `groupMembers: [Speaker] = []` input and renders `GroupChipRow` after the volume track. F3/E-54 extracts the private `PlaybackBars` struct out to a shared component. The F3 epics doc notes the merge-conflict risk (Recommended Implementation Order §1 says "T-5401 lifts first... avoids merge conflicts"). F1 does not acknowledge the conflict.

**Recommendation:** explicit two-step preamble before either feature lands:
1. Land T-5401 (extract `PlaybackBars` to `Features/Home/Components/PlaybackBars.swift`) as a standalone PR. Both F1 and F3 then build on top.
2. Pick which of F1 or F3/E-53 lands first by team availability. The second to land does the rebase.

This is captured in the Feature Dependencies section being added to the master spec, but is worth stating as an explicit precondition in the implementation plan.

**X-2 — Shared file: `SpeakerSelectorPill.swift`.**
F3/E-54 (T-5403–T-5406) rewrites the pill: takes `Speaker` instead of `String name`, renders `PlaybackBars`, adds connector line. F2/E-59 (T-5903–T-5904) attaches `.draggable(_:)` to the same pill and reads the `isDraggable(_:)` eligibility helper. F2 explicitly depends on the F3 rewrite (`"or its replacement in F3 / E-53"` in F2 spec TR-2). Fine — but the dependency is stated against E-53 in the F2 doc, whereas the actual rewrite happens in E-54. **Correct the F2 references** to say E-54 (T-5403/T-5404) rather than E-53. Same correction in the master-spec dependencies section.

**X-3 — `SpeakerGroup.broadcastVolume` / `setVolumeOnAllMembers` ownership.**
F1 puts this helper on `SpeakerGroup`. F2 doesn't use it. F1 epic T-5704 notes "the SpeakerGroup location is preferred for reuse by Feature 2 and Feature 3" — but neither F2 nor F3 actually calls it. The helper is F1-only consumer. That's fine; just don't pretend F2 reuses it.

**X-4 — `withTaskGroup` usage patterns.**
ADR D4 and F1 use `withTaskGroup` for fan-out. F2 uses individual detached `Task` blocks per join (no `withTaskGroup`). Both patterns are correct; just note that there is no consistent project-wide convention being established for "concurrent fan-out across speakers" — future features that need similar patterns should align with the F1 helper.

**X-5 — Localisation strings duplicated across design specs.**
Each design spec has its own Appendix B with new localisation keys. There's no duplicate key collision today, but `state.playing`/`state.paused`/`state.stopped`/`state.connecting` appear in F3 Appendix B with a note "may already exist under `Speaker.stateDisplay`". F1 design spec adds `controls.play` = "Play" — same English label as F3's existing button copy. Run a final pre-merge audit of `Localizable.strings` to deduplicate.

---

## Inter-feature dependencies

Explicit graph:

```
                      ┌─────────────────────────────────────┐
                      │  F3 / E-52  SessionStripView        │
                      │             page dots               │
                      │             2-way binding w/ bar    │
                      └───────────┬──────────────────┬──────┘
                                  │                  │
                                  │            ┌─────▼─────────────────────┐
                                  │            │  F3 / E-55                │
                                  │            │  NetworkMonitor +         │
                                  │            │  Discovery/Offline state  │
                                  │            │  machine (wraps strip)    │
                                  │            └───────────────────────────┘
                                  │
            ┌─────────────────────┴────────────────────┐
            │                                          │
   ┌────────▼──────────┐                  ┌────────────▼─────────────┐
   │  F3 / E-53        │                  │  F3 / E-54               │
   │  GroupChipRow     │                  │  SpeakerSelectorPill     │
   │  (display-only)   │                  │  rewrite +               │
   │                   │                  │  PlaybackBars extract    │
   └────────┬──────────┘                  └────────────┬─────────────┘
            │                                          │
            └──────────────┬───────────────────────────┘
                           │
                ┌──────────▼──────────────┐
                │  F2  E-59 / E-60 / E-61 │
                │  drag/drop + chip taps  │
                │  (binds to E-53 row +   │
                │   E-54 pill +           │
                │   E-52 card root)       │
                └─────────────────────────┘


   F1 / E-56–E-58 — independent epic chain on SpeakerCard internals.
                    Soft merge dependency with F3 / E-53 (same file).
                    Provides `SpeakerGroup.setVolumeOnAllMembers` —
                    not consumed by F2 or F3.
```

**Hard ordering constraints:**
- F2 cannot ship before F3/E-53 (chip row container), F3/E-54 (pill rewrite for `.draggable`), and F3/E-52 (session card root for `.dropDestination`). F2 may *develop* in parallel against stubs but cannot ship.
- F3/E-55 wraps the entire `cardArea` body produced by F3/E-52, so E-55 lands strictly after E-52's `cardArea` routing.
- F3/E-54 T-5401 (PlaybackBars extraction) is a prerequisite for the new `SpeakerSelectorPill` rendering AND for any safe co-modification of `SpeakerCard.swift` — land it first as standalone.

**Parallelisable:**
- F1 and F3 can be worked simultaneously by separate engineers. Merge in `SpeakerCard.swift` at integration time.
- F2/E-59 (Transferable conformance, eligibility helper, coach mark) can start as soon as F3/E-54 T-5403 has a stable interface.

The Feature Dependencies section being added to `VoxioSpecification-1.4.md` captures this as the authoritative cross-feature view.

---

## Open questions / risks

| # | Item | Severity | Owner | Recommended resolution |
|---|---|---|---|---|
| OQ-1 | ADR D3 wrapper vs SpeakerIdentifier direct conformance | Medium | Eng lead | Revise ADR to match spec/epics (drop `SpeakerTransfer`, drop `SpeakerStore`) |
| OQ-2 | ADR D5 timeout placement and task-cancellation policy | Medium | Eng lead | Revise ADR; add a 10 s timeout wrapper into T-6001 |
| OQ-3 | HapticEngine method names in F2 epics (T-5904, T-5905) contradict design spec | Low | F2 author | Correct epic task copy |
| OQ-4 | Swift version inconsistency across epic docs (5.10 vs 6) | Low | Eng lead | Confirm project Swift target, align all three docs |
| OQ-5 | F1 group-volume helper name (`setVolume` vs `setVolumeOnAllMembers`) | Low | F1 author | Pick the `Result`-returning signature (T-5704); update ADR D4 |
| OQ-6 | `speaker.playbackState` enum surface (cases vs string) | Medium | F1 implementer | Verify before T-5601 lands |
| OQ-7 | `SpeakerError` exists at the abstraction layer (used by F2; F1 mentions `MozartError`) | Medium | F2 implementer | Verify; if absent, add as part of T-5901 prereq |
| OQ-8 | `SpeakerCard.swift` merge plan between F1 + F3/E-53 + F3/E-54 | Medium | Both teams | Land T-5401 first; then sequence F1 vs E-53 by team availability |
| OQ-9 | `NetworkMonitor` flash on app foreground (initial `isOnWifi = false`) | Low | F3 implementer | Default `isOnWifi = true`; flip on first path callback |
| OQ-10 | F2 design-spec dependency text references E-53; pill rewrite is actually E-54 | Low | F2 author | Correct cross-references |
| OQ-11 | `HapticEngine.dragLifted/dragEnteredDropZone/dragCancelled` do not exist today | Medium | F2 implementer | Add in T-5901 prereq (already tracked in `project_spec_structure` memory) |
| OQ-12 | `SpeakerDiscoveryService.didSettle` setter visibility from `restart()` (T-5510) | Low | F3 implementer | Confirm `restart()` is added in the same file as the property |

None of these are merge-blocking. OQ-1, OQ-2, OQ-6, OQ-7, OQ-8, OQ-11 should be settled before implementation starts; the rest can be resolved during implementation.

---

## Recommendation

**PROCEED with the fixes above.** Specifically, before implementation kickoff:

1. Revise ADR-002 D3 and D5 to match the spec/epics. (One paragraph each.)
2. Correct F2 epic haptic names (T-5904, T-5905) and Swift-version banner.
3. Land T-5401 (`PlaybackBars` extraction) as a standalone PR.
4. Add a "Feature Dependencies" section to `VoxioSpecification-1.4.md` (in progress alongside this review).
5. Confirm `speaker.playbackState` enum cases and `SpeakerError` abstraction-layer type exist before T-5601 / T-5901.

After those: F1 and F3 can begin in parallel; F2 can begin against stubs but ships after F3/E-52, E-53, and E-54.

The spec quality is high. The architecture is conservative and matches the established iOS patterns (`@Observable @MainActor`, `SpeakerClient` abstraction, `BeoColor`/`BeoType`/`Spacing` token reuse without additions). No new platform risks introduced.
