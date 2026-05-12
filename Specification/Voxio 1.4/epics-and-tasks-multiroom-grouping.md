# Epics & Tasks: Multiroom Grouping (Voxio 1.4 — Feature 2)
**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-09
**References:** `spec-multiroom-grouping.md` v1.0, `design-spec-multiroom-grouping.md` v1.1, `VoxioSpecification-1.4.md` Feature 2, `epics-and-tasks-telemetry-backend.md` (format reference), `epics-and-tasks-home-screen-redesign.md` (E-53 — chip row, cross-feature dependency), CLAUDE.md
**Stack:** Swift 6, SwiftUI (iOS 26 — `.draggable()` / `.dropDestination()` / `Transferable` introduced iOS 16, fully available), `@Observable @MainActor`, `SpeakerClient.join(peer:)` / `.leave()`, `SpeakerDiscoveryService.mergeIntoSpeakerGroup` / `.removeMember`

---

## Overview

This document breaks the approved Multiroom Grouping spec (v1.0) into epics and constituent tasks. F2 turns F3's display-only group chip row into a fully interactive surface: bottom-bar pills become drag sources, session cards become drop destinations, and group member chips become tap targets. The underlying API layer (`SpeakerClient.join(peer:)` / `.leave()`) and model mutations (`SpeakerDiscoveryService.mergeIntoSpeakerGroup` / `.removeMember`) already exist and are unchanged.

All paths in tasks below are relative to the iOS Xcode project root (`iOS/Voxio.xcodeproj`) unless otherwise noted. The project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+) — any `.swift` file added under `iOS/Voxio/` is auto-compiled; no pbxproj edits required.

Epic numbering begins at **E-59**, continuing from F1 (E-56–E-58) and F3 (E-50–E-55 in the v1.4 spec set). Task numbering: E-59 → T-5901+, E-60 → T-6001+, E-61 → T-6101+.

### Cross-feature dependency

F2 depends on **F3 / E-53 (Group chip row — display-only)**. E-53 introduces the chip row inside the F3 session card; F2 transforms it from labels into tap targets (E-61) and adds the loading-state chip variant (E-60). F2 development can begin in parallel with E-53 against a stub chip-row view, but verification (T-5910, T-6005, T-6107) requires E-53 to be merged first.

---

## Epic Index

| # | Epic | User Stories | Feature Area |
|---|---|---|---|
| E-59 | Drag-to-join infrastructure | US-80, US-84 | `Speaker` Transferable conformance, bottom-bar pill drag source, session card drop destination, ghost pill, drop-zone gold border, coach mark |
| E-60 | Join chip loading state | US-81, US-82 | Loading-chip variant in chip row, `Task` lifecycle for in-flight joins, success/failure transitions, source-pill lockout |
| E-61 | Tap-to-remove | US-83 | Chip tap target, optimistic remove, `leave()` call, failure rollback, VoiceOver alternate action |

---

## E-59 — Drag-to-join infrastructure

Build the drag side of the gesture: make `Speaker`/`SpeakerIdentifier` conform to `Transferable`, wire the bottom-bar pills as drag sources with the eligibility gating from spec TR-2, attach a `.dropDestination` to each session card with the gold-border isTargeted treatment, render the ghost pill following the finger, and ship the one-time coach mark from US-84. This epic produces a working drag gesture that can call into the join handler from E-60 — but does not yet display the loading chip or apply the model mutation; those land in E-60.

**Depends on:** F3 / E-53 (chip row container exists), F3 / E-52 (session card root exists with a stable bound for drop targeting). E-59 implementation can start against stubbed F3 components but verification requires the real components.
**Unlocks:** E-60 (consumes the drop callback to enqueue the join task), E-61 (reuses the eligibility helpers from TR-2).

---

### Transferable conformance

- [x] **T-5901** Add `iOS/Voxio/Core/Models/SpeakerIdentifier+Transferable.swift`. Make `SpeakerIdentifier` conform to `Transferable` via `CodableRepresentation(contentType: .data)` per spec TR-1. `SpeakerIdentifier` is the existing `Codable` value type used by `SpeakerClient.join(peer:)` — choosing it (rather than `Speaker`) is correct because `Speaker` is `@MainActor @Observable` and cannot cross the drag boundary. Add a unit test `iOS/VoxioTests/SpeakerIdentifierTransferableTests.swift` that round-trips a `SpeakerIdentifier` through `JSONEncoder` / `JSONDecoder` and confirms `jid` and `host` survive.
  *Depends on: none (pure model layer).*

### Drop helper on the session view model

- [x] **T-5902** Add `iOS/Voxio/Features/Home/SessionViewModel.swift` (or extend the F3 equivalent if it already exists with a different name). Introduce a `@MainActor` `@Observable` view model owning per-card state:
  ```swift
  @Observable @MainActor
  final class SessionViewModel {
      var dropZoneActive: Bool = false
      var joinsInFlight: Set<String> = []
      private var joinTasks: [String: Task<Void, Never>] = [:]
      let group: SpeakerGroup
      let discovery: SpeakerDiscoveryService
      // handleJoinDrop and handleRemoveTap implemented in E-60 / E-61
      func resolveSpeaker(_ id: SpeakerIdentifier) -> Speaker? { /* lookup in discovery.allSpeakers */ }
  }
  ```
  `resolveSpeaker(_:)` matches by `identifier.jid` first, falling back to `identifier.host`. Returns `nil` if no live speaker matches (defensive — drop is rejected). Document the contract inline.
  *Depends on: T-5901.*

### Bottom-bar pill drag source

- [x] **T-5903** In `iOS/Voxio/Features/Home/SpeakerSelectorPill.swift` (or the F3 replacement bottom-bar component if E-52 has renamed/replaced it), add an `isDraggable(_ speaker: Speaker)` helper computed against the home view's discovery snapshot per spec TR-2:
  - Returns `false` if `speaker` is the `hostSpeaker` of any group in `discovery.groups` whose `playbackState == .playing`.
  - Returns `false` if `speaker` is a member of any group in `discovery.groups` with `members.count > 1`.
  - Returns `false` if `speaker.identifier.id` is in any session view model's `joinsInFlight` set (consumed via the home view's aggregated `Set<String>` from T-6004).
  - Returns `true` otherwise.

  Render every pill at `.opacity(isDraggable(speaker) ? 1.0 : 0.5)` per design-spec §1.2 / §4.1 step 6. Do **not** call `.draggable(_:)` on non-draggable pills — omit the modifier entirely so the long-press gesture is cleanly disabled (calling `.draggable(nil)` is incorrect and behaves inconsistently across iOS versions).
  *Depends on: T-5902.*

- [x] **T-5904** For draggable pills (T-5903), attach `.draggable(speaker.identifier) { dragPreview }` where `dragPreview` is a `DarkGlassButton`-styled capsule rendering the speaker name at 0.85 opacity, 1.06× scale per design-spec §2.1. Use the same `BeoType.caption` font and pill geometry as the source pill so the ghost is a near-perfect copy. Add the long-press initiation haptic via `.simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in HapticEngine.shared.dragLifted() })` per design-spec §1.1 and §6.2 — the haptic fires on long-press hold, not on drag start, so it precedes the system drag.

  **Prereq:** `HapticEngine.dragLifted()` does not exist today. It must be added to `iOS/Voxio/Core/HapticEngine.swift` (a `UIImpactFeedbackGenerator(style: .medium).impactOccurred()` wrapper) alongside the other new methods listed under T-5901. Land the `HapticEngine` additions as a small standalone change before T-5904.

  Note: SwiftUI's `.draggable` already handles ghost rendering; the closure provides only the preview view. The 1.06× scale and 0.85 opacity are applied within the preview view itself.
  *Depends on: T-5903.*

### Session card drop destination

- [x] **T-5905** In the F3 session card root view (file `iOS/Voxio/Features/Home/SessionCardView.swift` or the E-52 equivalent), attach `.dropDestination(for: SpeakerIdentifier.self)` per spec TR-3:
  ```swift
  .dropDestination(for: SpeakerIdentifier.self) { items, _ in
      guard let droppedId = items.first,
            let source = sessionVM.resolveSpeaker(droppedId),
            source.id != sessionVM.group.hostSpeaker.id else { return false }
      sessionVM.handleJoinDrop(source: source, target: sessionVM.group.hostSpeaker)
      return true
  } isTargeted: { isOver in
      withAnimation(BeoAnimation.spring) { sessionVM.dropZoneActive = isOver }
      if isOver { HapticEngine.shared.dragEnteredDropZone() } // UIImpactFeedbackGenerator(style: .light) under the hood
  }
  ```
  Self-drop (source == host) is rejected with `return false`. The drop handler delegates to `handleJoinDrop` from E-60 T-6001 — until that lands, define the method as a stub that logs and returns.

  **Prereq:** `HapticEngine.dragEnteredDropZone()` does not exist today and must be added alongside `dragLifted()` and `dragCancelled()` per the T-5904 prereq note.
  *Depends on: T-5902, T-5901.*

- [x] **T-5906** Add the gold-border + inner-glow visual treatment driven by `sessionVM.dropZoneActive` per design-spec §3:
  ```swift
  .overlay(
      RoundedRectangle(cornerRadius: Radius.card)
          .stroke(BeoColor.accent, lineWidth: sessionVM.dropZoneActive ? 1.5 : 0)
  )
  .background(
      RoundedRectangle(cornerRadius: Radius.card)
          .fill(BeoColor.accent.opacity(sessionVM.dropZoneActive ? 0.04 : 0))
  )
  ```
  Animation is implicit because `dropZoneActive` is updated inside `withAnimation(BeoAnimation.spring)` in T-5905. Verify visually on device — the border should fade in within one spring cycle as the ghost crosses the card bounds.
  *Depends on: T-5905.*

- [x] **T-5907** Multiple-card support per spec TR-8. The F3 session strip (E-54) renders multiple cards in a horizontal `ScrollView`. Each card hosts its own `SessionViewModel` with its own `dropZoneActive` flag, so isTargeted callbacks fire independently. No additional wiring needed beyond confirming each card's drop destination is attached at the card level (not the strip level). Document the pattern inline at the strip's container view: "Drop destination is per-card — do not lift to the strip." Do **not** implement drag-scroll (out of scope per design-spec §9).
  *Depends on: T-5905, F3 / E-54.*

### Ghost cancel and invalid-drop handling

- [x] **T-5908** Verify SwiftUI's default cancel behaviour matches design-spec §2.1: releasing the ghost outside any drop destination animates it back to the source pill automatically. If the default animation does not feel right (no spring return), add an `.onDrop(of:)` observer at the parent view that detects "drag ended without drop" and triggers an explicit return animation. For invalid-drop haptic: add `HapticEngine.shared.dragCancelled()` via `UINotificationFeedbackGenerator().notificationOccurred(.warning)` per design-spec §6.2. Hook this haptic into the drag-cancel detection (use `.onDrag` end notification or a custom drag controller if SwiftUI's `.draggable` doesn't surface this directly).

  Note: SwiftUI's `.draggable` does not expose a drag-cancelled callback in iOS 16/17. If iOS 26 still lacks one, accept the limitation and document it as a non-blocking visual nicety; the warning haptic can fire from the bottom-bar `onDrop(of:)` if the drop falls back to the bar's space.
  *Depends on: T-5904.*

### Coach mark

- [x] **T-5909** Add `iOS/Voxio/Features/Home/GroupingCoachMark.swift` per spec TR-7 / design-spec §1.3:
  - A small overlay view rendering `"Drag to join this session"` (DA: `"Træk for at tilslutte"`) in `BeoType.caption`, `BeoColor.muted`, positioned above the first eligible draggable pill in the bottom bar.
  - Storage: `@AppStorage("hasSeenGroupingCoachMark") private var hasSeenGroupingCoachMark: Bool = false`.
  - Trigger: `.onChange(of: hasEligibleDraggablePill)` where `hasEligibleDraggablePill` is computed against `discovery.groups` and the eligibility helper from T-5903. When it transitions to `true` and `hasSeenGroupingCoachMark == false`, set `coachMarkVisible = true` and start a 3-second auto-dismiss `Task`.
  - Dismiss on: (a) `Task` timeout (3 s), (b) successful drop (notified by E-60 T-6001 setting `coachMarkVisible = false`), or (c) screen tap (via `.simultaneousGesture(TapGesture().onEnded { … })` at the home view root).
  - On any dismiss path: set `hasSeenGroupingCoachMark = true` and `coachMarkVisible = false`. Once `hasSeenGroupingCoachMark` is `true`, the mark never appears again (UQ-4).

  Add string keys `grouping.coachMark.en` / `grouping.coachMark.da` to `iOS/Voxio/Resources/Localizable.strings` per design-spec Appendix B.
  *Depends on: T-5903, T-5902.*

### Verification

- [ ] **T-5910** (deferred: manual verification on device) Manual interaction test on device (iPhone 15 / iOS 26): with one playing speaker (host) and at least one idle speaker, confirm:
  1. The idle pill long-presses and lifts with the ghost following the finger.
  2. The playing-host pill renders at 0.5 opacity and does not respond to long-press.
  3. A speaker that has been joined to the host (post E-60) renders at 0.5 opacity and is non-draggable (UQ-2).
  4. Dragging the ghost over the session card activates the gold border within one frame.
  5. Dragging the ghost off the card returns it to idle within one frame.
  6. Releasing outside any card returns the ghost to the source pill.
  7. The coach mark appears on first launch with an eligible pill present, fades after 3 s, and never reappears after dismissal (delete and reinstall the app to re-verify).

  Document the test session in `Specification/Voxio 1.4/test-notes-multiroom-grouping.md` with screenshots of each state. Drop release behaviour (loading chip, success, failure) is verified in T-6005, not here.
  *Depends on: T-5901–T-5909, F3 / E-52, F3 / E-53.*

---

## E-60 — Join chip loading state

Implement the join handler that the E-59 drop destination invokes. After a drop, immediately render a loading chip in the chip row (spinner + dimmed label), launch a detached `Task` running `client.join(peer:)`, and on completion either resolve the chip to full opacity (with the brief pulse) or fade it out and toast the error. Manage source-pill lockout via the `joinsInFlight` set so the source pill stays at 0.5 opacity for the full call duration. Per UQ-3 the spinner persists for up to 10 seconds and the join is **not** optimistic.

**Depends on:** E-59 (drop destination calls into `handleJoinDrop`), F3 / E-53 (chip row renders chips and accepts a "loading" variant).
**Unlocks:** E-61 (shares the toast and haptic infrastructure).

---

### `handleJoinDrop` implementation

- [ ] **T-6001** Implement `handleJoinDrop(source:target:)` on `SessionViewModel` (T-5902) per spec TR-4 and ADR-002 D5. The join body wraps `client.join(peer:)` in a `withThrowingTaskGroup` that enforces a 10-second client-side timeout (per UQ-3 / ADR D5 / design-spec §4.1 step 4):

  ```swift
  @MainActor
  func handleJoinDrop(source: Speaker, target: Speaker) {
      let key = source.identifier.id
      guard !joinsInFlight.contains(key) else { return }
      joinsInFlight.insert(key)
      HapticEngine.shared.commandRecognised() // step 1 of design-spec §4.1
      lastDropCompletedAt = Date()           // dismisses coach mark via SessionViewModel observer (T-5909)
      let task = Task { [weak self] in
          do {
              try await Self.joinWithTimeout(source: source, target: target, seconds: 10)
              await MainActor.run {
                  guard let self else { return }
                  self.discovery.mergeIntoSpeakerGroup(source: source, target: target)
                  self.joinsInFlight.remove(key)
                  self.joinTasks.removeValue(forKey: key)
                  self.pulseChip(for: source) // T-6003
                  UIAccessibility.post(notification: .announcement,
                                       argument: "\(source.name) joined \(target.name)")
              }
          } catch {
              await MainActor.run {
                  guard let self else { return }
                  self.joinsInFlight.remove(key)
                  self.joinTasks.removeValue(forKey: key)
                  HapticEngine.shared.errorOccurred()
                  ToastCenter.shared.show(.error("Couldn't add \(source.name) — \(self.reasonText(for: error))"))
              }
          }
      }
      joinTasks[key] = task
  }

  private static func joinWithTimeout(source: Speaker, target: Speaker, seconds: Int) async throws {
      try await withThrowingTaskGroup(of: Void.self) { group in
          group.addTask { try await source.client.join(peer: target.identifier) }
          group.addTask {
              try await Task.sleep(for: .seconds(seconds))
              throw SpeakerError.timeout
          }
          // First child to complete (success or thrown) wins; cancel the rest.
          try await group.next()
          group.cancelAll()
      }
  }
  ```

  `reasonText(for:)` maps `SpeakerError.timeout → "connection timed out"`, `SpeakerError.unreachable → "speaker unreachable"`, default → empty (no suffix). Per spec TR-4 step 5 and ADR D5, the outer `Task` is **not** cancelled on view teardown — let the API call complete; the merge is a no-op if the host group disappeared (`mergeIntoSpeakerGroup` already handles this).

  Coach-mark dismiss plumbing: rather than a `NotificationCenter` post, set a `@Published var lastDropCompletedAt: Date? = nil` on `SessionViewModel` (or on the shared `HomeViewModel` if E-59 introduced one). T-5909's coach-mark view observes that property and dismisses on change.
  *Depends on: T-5902, T-5905. Requires `SpeakerError.timeout` to exist at the abstraction layer — verify before this lands (architect-review OQ-7).*

### Loading chip in the chip row

- [ ] **T-6002** Extend the F3 chip-row view (`iOS/Voxio/Features/Home/GroupChipRow.swift` or the E-53 equivalent) to render two chip variants per spec US-81:
  - **Settled** (existing F3 behaviour): full opacity, label only, optionally a `+` prefix per F3 design.
  - **Loading**: dimmed label (0.6 opacity), inline 10 pt `ProgressView()` replacing the `+` prefix per design-spec §4.1 step 3 / §4.2.

  The chip row computes its data source as: `group.members.filter { $0.id != group.hostSpeaker.id }` (settled chips) ∪ `joinsInFlight.compactMap { sessionVM.resolveSpeaker(SpeakerIdentifier(id: $0)) }` minus duplicates already in `members` (loading chips — these are speakers being joined that have not yet completed). Order: settled members first, then loading chips.

  Loading chips are non-interactive (no `.onTapGesture`, no `.draggable` — they cannot be removed mid-flight nor re-dragged).
  *Depends on: T-6001, F3 / E-53.*

### Chip pulse on success

- [ ] **T-6003** Add `pulseChip(for: Speaker)` on `SessionViewModel`. Implementation: maintain a `pulsingChips: Set<String>` `@State` that the chip view observes. On success, insert the speaker's identifier id into the set, schedule a `Task` to remove it after 0.4 s. The chip view applies `.scaleEffect(pulsingChips.contains(id) ? 1.0 : 1.0)` with a manual opacity keyframe `1.0 → 0.7 → 1.0` over 0.4 s per design-spec §4.1 step 7. Use `withAnimation(.easeInOut(duration: 0.2))` twice (in then out) or a single keyframe animator.

  Respect `@Environment(\.accessibilityReduceMotion)` per spec NFR — if reduced, replace the pulse with a single 0.2-second opacity flash.
  *Depends on: T-6002.*

### Source-pill lockout

- [ ] **T-6004** Aggregate `joinsInFlight` across all session view models at the home view level so the bottom bar can render correct opacity per spec TR-5. Add an `@State` `joinsInFlightUnion: Set<String>` on `HomeView` (or on a shared `@Observable HomeViewModel`), recomputed via `.onChange(of: sessionVMs.flatMap(\.joinsInFlight))`. The bottom-bar pill renderer (T-5903) consumes this set: a pill whose identifier is in `joinsInFlightUnion` renders at 0.5 opacity and is non-draggable (the `isDraggable` helper from T-5903 already checks `joinsInFlight`; this task just plumbs the set through).

  When the API call resolves (success or failure) and `joinsInFlight` clears the entry, the source pill regains full opacity within one animation frame.
  *Depends on: T-6001, T-5903.*

### Verification

- [ ] **T-6005** Manual integration test on device with two speakers (Mozart): one playing host, one idle source.
  1. Drag the idle pill onto the playing card. Confirm the loading chip appears within one frame, the source pill dims to 0.5 immediately, and the spinner spins for the full `beolinkExpand` duration (typically 1–3 s on LAN, up to 10 s in degraded conditions).
  2. On success: chip transitions to full opacity, brief pulse plays, source pill regains full opacity, chip remains in the row, bottom-bar pill connector to the host shows up (per F3 §2.3).
  3. Force a failure: airplane-mode the host speaker mid-call (or use a stub client that throws `.timeout`). Confirm the loading chip fades out, source pill regains full opacity, error toast appears with reason text, error haptic fires.
  4. While a join is in flight, confirm the source pill cannot be re-dragged (long-press has no effect at 0.5 opacity).
  5. Background the app for 2 seconds during an in-flight join, return to foreground — confirm the join completes correctly (model updated; chip resolves) per spec NFR.

  Document with screenshots and `os_log` excerpts in `Specification/Voxio 1.4/test-notes-multiroom-grouping.md`.
  *Depends on: T-6001, T-6002, T-6003, T-6004, F3 / E-53.*

---

## E-61 — Tap-to-remove

Make the F3 group chip row's member chips tappable. Tap → optimistic remove (chip fades immediately, `discovery.removeMember` updates the model) → detached `Task` running `client.leave()`. On API failure, re-insert the chip via `mergeIntoSpeakerGroup` and toast the error. Per UQ-1 there is no confirmation dialog. Per design-spec §8 add the VoiceOver alternate path (chip is a `.button` role with the "Tap to remove" label, success posts an announcement).

**Depends on:** F3 / E-53 (chip row renders chips), E-59 (shares the eligibility helpers — though only indirectly; the source pill of a removed speaker becomes draggable again), E-60 (shares the toast and haptic infrastructure).
**Unlocks:** F2 verification suite (T-6107) and the F2 → F3 user-story acceptance pass.

---

### `handleRemoveTap` implementation

- [ ] **T-6101** Implement `handleRemoveTap(_ speaker: Speaker)` on `SessionViewModel` per spec TR-6:
  ```swift
  @MainActor
  func handleRemoveTap(_ speaker: Speaker) {
      // Capture rollback state BEFORE optimistic removal
      let originalGroup = discovery.groups.first { g in g.members.contains { $0.id == speaker.id } }
      guard let host = originalGroup?.hostSpeaker else { return }
      // Optimistic remove
      discovery.removeMember(speaker)
      Task { [weak self] in
          do {
              try await speaker.client.leave()
              await MainActor.run {
                  HapticEngine.shared.commandRecognised()
                  UIAccessibility.post(notification: .announcement,
                                       argument: "\(speaker.name) removed from group")
              }
          } catch {
              await MainActor.run {
                  guard let self else { return }
                  // Rollback: re-insert into the original group
                  self.discovery.mergeIntoSpeakerGroup(source: speaker, target: host)
                  HapticEngine.shared.errorOccurred()
                  ToastCenter.shared.show(.error("Couldn't remove \(speaker.name)"))
              }
          }
      }
  }
  ```
  Note: `mergeIntoSpeakerGroup` re-inserts even if the original group has collapsed to solo or the host has disappeared — it falls back to creating a new group with `[host, speaker]`. Document this behaviour inline.
  *Depends on: T-5902.*

### Chip tap target

- [ ] **T-6102** In the F3 chip-row chip view, add `.onTapGesture { sessionVM.handleRemoveTap(chipSpeaker) }` to **settled** member chips only (not loading chips per T-6002). Add `.contentShape(Capsule())` to ensure the entire chip area is tappable, not just the text. The tap is the sole interaction — no confirmation dialog (UQ-1).

  Visual feedback during the tap (the optimistic fade) is driven by the chip row's `.transition(.opacity)` on member-array diff: when `discovery.removeMember` removes the speaker from `group.members`, the chip view's identity disappears and SwiftUI fades it out.
  *Depends on: T-6101, F3 / E-53.*

### Group collapses to solo

- [ ] **T-6103** Verify and document the chip-row collapse behaviour per design-spec §5.4: when the last member chip is removed (`group.members.count` drops to 1, leaving only the host), the chip row disappears entirely. This is already implemented by F3 / E-53 if the chip row uses an `if !memberChips.isEmpty` guard at its container — confirm in code review. If F3 renders an empty row container instead, add the guard. Add a UI test asserting the chip row is absent when `group.members == [host]`.
  *Depends on: T-6101, T-6102, F3 / E-53.*

### Failure-path rollback

- [ ] **T-6104** Verify the rollback path in T-6101 against `SpeakerDiscoveryService.mergeIntoSpeakerGroup`:
  - If `originalGroup.hostSpeaker` is still in `discovery.allSpeakers`, the merge re-attaches `speaker` to that host's group.
  - If `originalGroup` had only `[host, speaker]` (so removing `speaker` left a solo `[host]`), `mergeIntoSpeakerGroup` finds the host's solo group and re-appends `speaker` — restoring the original two-member group.
  - If the host has disappeared entirely between the optimistic remove and the failure (rare), `mergeIntoSpeakerGroup` creates a new group `[host, speaker]` — but `host` is nil, so this path returns early. Document this corner case as: "If host disappeared during the leave call, no rollback is attempted; the chip stays gone and the error toast is the only signal."

  Add unit tests against a mocked `SpeakerClient` that throws to cover (a) successful rollback into existing host group, (b) rollback into a host that is now solo, (c) host disappeared (no rollback, toast still fires).
  *Depends on: T-6101.*

### VoiceOver accessibility

- [ ] **T-6105** Per spec TR-9 / design-spec §8, on each settled member chip add:
  - `.accessibilityRole(.button)` so VoiceOver announces it as actionable.
  - `.accessibilityLabel("\(speaker.name), in group. Tap to remove.")` (DA equivalent from string catalogue: `"\(speaker.name), i gruppe. Tryk for at fjerne."`). Add string keys `a11y.chip.member.en` / `a11y.chip.member.da` to `Localizable.strings` per design-spec Appendix B.
  - `.accessibilityHint("Removes this speaker from the group.")` — optional; iOS 26 reads roles + labels naturally, but the hint helps first-time users.

  On loading chips (from T-6002), add `.accessibilityLabel("Connecting \(speaker.name)…")` (DA: `"Forbinder \(speaker.name)…"`, key `a11y.chip.loading`). Loading chips are not buttons — omit `.accessibilityRole(.button)` and `accessibilityHint`; they are status announcements.

  Verification: run with VoiceOver enabled, swipe through the chip row. Confirm settled chips announce role + label, double-tap fires `handleRemoveTap`. Confirm loading chips announce status only.
  *Depends on: T-6102, T-6002.*

### VoiceOver alternate path for join (cross-references US-80 alternate)

- [ ] **T-6106** Per spec TR-9, on the session card root add `.accessibilityAction(named: "Add speaker") { sessionVM.presentAddSpeakerSheet = true }` and present a `.confirmationDialog("Add speaker", isPresented: $sessionVM.presentAddSpeakerSheet, titleVisibility: .visible) { … }` listing every eligible draggable speaker (same eligibility rules as T-5903). Selecting a row invokes `sessionVM.handleJoinDrop(source: selectedSpeaker, target: sessionVM.group.hostSpeaker)` — identical to the drag drop. Add string key `grouping.a11yAddAction.en` = `"Add speaker"` / `.da` = `"Tilføj højttaler"` per design-spec Appendix B.

  This task technically belongs to E-59 (US-80 alternate path) but is grouped under E-61 because it shares the chip-row VoiceOver pass and benefits from the same testing session. Document the cross-reference inline.
  *Depends on: T-5902, T-6001, T-5903.*

### Verification

- [ ] **T-6107** Manual interaction test on device with a multi-member group:
  1. Form a group of 3 (host + 2 members) via voice command or via E-59/E-60 drag.
  2. Tap the first member chip. Confirm: chip fades immediately, leave call runs, success haptic fires, VoiceOver announces removal, bottom-bar pill regains full opacity and is draggable.
  3. Tap the second (now last) member chip. Confirm: chip fades, leave call runs, chip row disappears, card becomes a solo session.
  4. Force a failure: airplane-mode the member's IP, tap its chip. Confirm: chip fades optimistically, after the leave call fails, the chip reappears, error toast appears, error haptic fires.
  5. Enable VoiceOver. Swipe through a member chip — confirm role + label announce correctly. Double-tap — confirm remove action runs.
  6. Enable VoiceOver. Swipe to the session card root, find the "Add speaker" custom action, invoke it. Confirm the action sheet lists every eligible speaker. Select one. Confirm join completes identically to a drag.

  Document each step with screenshots and `os_log` excerpts. Update `Specification/Voxio 1.4/test-notes-multiroom-grouping.md`.
  *Depends on: T-6101–T-6106, F3 / E-53.*

---

## Recommended Implementation Order

1. **T-5901 (Transferable conformance)** lands first — tiny, isolated, unblocks everything downstream.

2. **T-5902 (SessionViewModel)** lands next — defines the per-card state shape consumed by both E-59 (drop destination) and E-60 (handleJoinDrop) and E-61 (handleRemoveTap).

3. **E-59 drag-and-drop scaffolding (T-5903–T-5908)** in sequence: pill drag source (T-5903, T-5904) before card drop destination (T-5905, T-5906); ghost cancel (T-5908) is non-blocking polish. T-5907 (multi-card support) lands once F3 / E-54 has shipped the strip — can be deferred.

4. **T-5909 (coach mark)** can ship in parallel with T-5905–T-5908; depends only on T-5903 (eligibility helper) and T-5902 (notification hook from T-6001).

5. **T-5910 (E-59 verification)** at the end of E-59 — gates the start of E-60 verification.

6. **E-60 join handler and loading chip (T-6001–T-6004)** in sequence: handler (T-6001) before chip variant (T-6002) before pulse (T-6003) before source-pill plumbing (T-6004). T-6004 is small and can land alongside T-5903 if the union-set plumbing is added defensively early.

7. **T-6005 (E-60 verification)** at the end of E-60 — requires real Mozart speakers on a LAN.

8. **E-61 tap-to-remove (T-6101–T-6106)** in any order after T-6101; T-6102 and T-6105 land together (chip view changes); T-6106 can land standalone with the VoiceOver pass.

9. **T-6107 (E-61 verification)** at the end of E-61. Final F2 acceptance gate.

A reasonable single-engineer sequence (assuming F3 / E-53 has merged):

```
Day 1:    T-5901 (Transferable)
          T-5902 (SessionViewModel scaffolding)
          T-5903 (eligibility helper + opacity rendering)

Day 2:    T-5904 (.draggable + ghost preview + lift haptic)
          T-5905 (.dropDestination + isTargeted)
          T-5906 (gold border visual)

Day 3:    T-5907 (multi-card verification — if F3 / E-54 shipped)
          T-5908 (cancel haptic — non-blocking)
          T-5909 (coach mark)

Day 4:    T-5910 (E-59 manual test)
          T-6001 (handleJoinDrop)
          T-6002 (loading chip variant)

Day 5:    T-6003 (pulse animation)
          T-6004 (joinsInFlight aggregation)
          T-6005 (E-60 manual test on LAN)

Day 6:    T-6101 (handleRemoveTap)
          T-6102 (chip tap target)
          T-6103 (collapse-to-solo verification)
          T-6104 (rollback unit tests)

Day 7:    T-6105 (VoiceOver labels)
          T-6106 (VoiceOver join alternate action)
          T-6107 (E-61 manual test + final F2 acceptance)
```

---

## Task Summary

| Epic | Tasks | Notes |
|---|---|---|
| E-59 Drag-to-join infrastructure | 10 | T-5901–T-5910. `SpeakerIdentifier` Transferable, `SessionViewModel` scaffolding, bottom-bar pill drag source with eligibility gate, session card drop destination + gold border, ghost cancel, coach mark, manual test. |
| E-60 Join chip loading state | 5 | T-6001–T-6005. `handleJoinDrop` with detached `Task`, loading chip variant in row, pulse on success, `joinsInFlight` aggregation for source-pill lockout, manual LAN test. |
| E-61 Tap-to-remove | 7 | T-6101–T-6107. `handleRemoveTap` with optimistic remove + rollback, chip tap target, collapse-to-solo, failure-path rollback unit tests, VoiceOver labels + alternate join action, manual test. |
| **Total** | **22** | All-iOS feature; no backend or design tokens added. |

---

## Cross-Feature Dependencies

| F2 Task | Depends on F3 Task | Why |
|---|---|---|
| T-5905 (drop destination) | E-52 (session card root) | The drop destination attaches to the session card root view |
| T-5907 (multi-card support) | E-54 (session strip) | Verifies independent isTargeted callbacks across multiple visible cards |
| T-6002 (loading chip variant) | E-53 (chip row) | Adds a variant to the existing chip view; requires chip-row container and chip-view file |
| T-6102 (tap target) | E-53 (chip row) | Adds `.onTapGesture` to the existing chip view |
| T-6103 (collapse-to-solo) | E-53 (chip row) | Verifies the row's empty-state guard |
| T-6107 (final manual test) | E-53, E-54 | Requires the real chip row and session strip to be present |

E-59 / E-60 / E-61 implementation can begin against stub F3 components (a placeholder chip row and a placeholder session card root), but verification tasks (T-5910, T-6005, T-6107) require the real F3 components to be merged into the working branch.

---

## Amendment History

| Date | Source | Change |
|---|---|---|
| 2026-05-09 | Initial draft | First version of the F2 epics and tasks (E-59–E-61, T-5901–T-6107). Derived from `spec-multiroom-grouping.md` v1.0 and `design-spec-multiroom-grouping.md` v1.1 (all UQs resolved). |
| 2026-05-11 | architect-review-v1.4.md | Fixed stack banner (Swift 6 / iOS 26). Renamed haptics in T-5904 (`dragInitiated` → `dragLifted`) and T-5905 (`dropZoneEntered` → `dragEnteredDropZone`) to match design-spec §6.2 and ADR REVISE 1; added prereq notes that those `HapticEngine` methods must be added before T-5904/T-5905. Rewrote T-6001 to include the 10 s `withThrowingTaskGroup` timeout wrapper required by ADR D5 and design-spec §4.1; replaced the `NotificationCenter` coach-mark dismiss with a `@Published lastDropCompletedAt: Date?` observer. |
