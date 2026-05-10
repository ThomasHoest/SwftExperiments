# Functional Specification: Multiroom Grouping
**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-09
**Platform:** iOS 26 (iPhone, portrait) — SwiftUI
**References:** `design-spec-multiroom-grouping.md` v1.1 (visual + interaction source of truth, all UQs resolved), `VoxioSpecification-1.4.md` Feature 2, `spec-home-screen-redesign.md` (F3 — produces the display-only group chip row consumed by F2), CLAUDE.md (`SpeakerClient`, `SpeakerDiscoveryService`, `Speaker`, `BeoColor`, `Spacing`, `Radius`, `BeoAnimation`)

---

## Introduction

Voxio v1.4 Feature 2 (F2) makes multiroom grouping a touch-first interaction. Until v1.3, the only path into a multiroom group was the voice command `"join Stue"`. F2 adds two new touch surfaces on the home screen:

1. **Drag-to-join** — bottom-bar speaker pills become draggable. Dragging a pill onto a session card calls `SpeakerClient.join(peer:)` against the dropped speaker's client and merges the model via `SpeakerDiscoveryService.mergeIntoSpeakerGroup(source:target:)`.
2. **Tap-to-remove** — group member chips on the session card (introduced in F3 as display-only) become tappable. A tap calls `SpeakerClient.leave()` on the chip's speaker and updates the local model via `SpeakerDiscoveryService.removeMember(_:)`.

Both surfaces sit on top of the existing grouping API — the underlying `join(peer:)` / `leave()` protocol methods, the Mozart `beolinkExpand` / `beolinkLeave` REST calls, and the `SpeakerGroup` model are unchanged. The voice command path `joinSpeaker` / `leaveSpeaker` (HomeView dispatch lines ~569–592) continues to work and shares the same API and model mutations.

F2 depends on **F3 / E-53** to ship the display-only chip row first. F2's E-61 transforms that row's chips from labels into tap targets.

This spec covers WHAT the user sees and does, the WHEN/WHY of state transitions, and the HOW of API calls and model updates. Visual treatment (colours, opacities, spacing, haptics, ghost geometry, drop-zone border) is specified verbatim in `design-spec-multiroom-grouping.md` and not duplicated here.

### What is in scope

- Conformance of `Speaker` to `Transferable` for SwiftUI drag-and-drop
- A `.draggable()` modifier on bottom-bar pills, gated by speaker eligibility
- A `.dropDestination(for: Speaker.self)` on session cards
- Drop-handler wiring to `client.join(peer:)` and `discovery.mergeIntoSpeakerGroup`
- A new chip-row entry in **loading** state during the in-flight join `Task`
- Chip resolution to **success** (full opacity + pulse) or **failure** (fade out + error toast)
- Source-pill lockout (0.5 opacity, non-draggable) for the duration of an in-flight join
- Tap targets on F3's group member chips, calling `client.leave()` and `discovery.removeMember(_:)` optimistically
- A one-time coach mark `"Drag to join this session"` displayed when a draggable speaker first becomes available
- VoiceOver-accessible alternate paths for both join and remove

### What is NOT in scope

- Named group presets or saved group configurations
- Broadcast controls (apply action to all members) — voice-only in v1.4
- `beolinkJoin()` without a peer (the physical Join button scenario)
- Per-member volume — touch controls apply to the host speaker only
- Drag-scroll: automatically scrolling the card strip while holding a drag near the edge
- Drag from within the chip row to reorder or move members between groups
- Auto-move when dragging an already-grouped speaker — already-grouped pills are non-draggable
- Confirmation dialog on remove (UQ-1 resolved: no confirmation)

---

## Technical Context

| Decision | Choice | Rationale |
|---|---|---|
| Drag framework | SwiftUI `.draggable(_:)` + `Transferable` (iOS 16+) | Matches v1.4 deployment target (iOS 26); UIKit drag interactions are not needed |
| Transferable payload | `Speaker.identifier` (`SpeakerIdentifier`) encoded as JSON via `CodableRepresentation` | `Speaker` itself is a reference type and `@MainActor` — the drop handler resolves the identifier back to the live `Speaker` via `discovery.allSpeakers` |
| Drop destination | `.dropDestination(for: SpeakerIdentifier.self)` on the session card root | Single drop target per visible card; activates independently when ghost enters its bounds |
| Join semantics | Not optimistic — chip appears in loading state, resolves on API completion | UQ-3 resolved: `beolinkExpand` latency can reach 10 seconds; showing a confirmed chip pre-completion would mislead the user |
| Leave semantics | Optimistic — chip fades immediately, reappears on failure | Leave latency is short and rollback is visually simple (re-insert chip + toast) |
| In-flight tracking | A `Set<String>` of in-flight join identifiers (keyed by source `SpeakerIdentifier.id`) on the session view model; per-speaker `Task` handles cancellation on view teardown | Allows the source pill to render at 0.5 opacity and the loading chip to render until the task completes |
| Coach mark persistence | `@AppStorage("hasSeenGroupingCoachMark")` Bool, default false | UQ-4 resolved: once per app lifetime; flipped to true on first drag completion or on the first screen-tap after the mark appears |
| Already-grouped detection | `discovery.groups.first(where: { $0.members.count > 1 && $0.members.contains(speaker) }) != nil` | UQ-2 resolved: such pills render at 0.5 opacity and skip `.draggable(_:)` entirely |
| Playing-host detection | `discovery.groups.contains(where: { $0.hostSpeaker.id == speaker.id && $0.playbackState == .playing })` | Playing-host pills are also non-draggable (they are the destination, not the source) |
| API surface used | `SpeakerClient.join(peer: SpeakerIdentifier)`, `SpeakerClient.leave()` | Already implemented for Mozart (`MozartClient+SpeakerClient.swift`); BNR conformance tracked separately |
| Model mutations | `SpeakerDiscoveryService.mergeIntoSpeakerGroup(source:target:)` after successful join; `SpeakerDiscoveryService.removeMember(_:)` after successful leave (or before, optimistically, with rollback on failure) | Existing methods, already used by voice command dispatch |
| VoiceOver alternate join | `.accessibilityAction(named: "Add speaker")` on the session card; system action sheet listing eligible speakers | Drag-and-drop is not VoiceOver-accessible; design-spec §8 |

---

## User Stories

The user stories below describe the touch interactions. The voice paths (`joinSpeaker` / `leaveSpeaker`) are unchanged and not restated here.

---

**US-80 — Join a speaker to a session by dragging**
> As a user with a playing speaker (the host) and one or more idle speakers, I want to drag an idle speaker pill from the bottom bar onto the session card so that the idle speaker joins the group and starts playing the same audio.

**Acceptance criteria:**
- A long-press on an eligible bottom-bar pill (idle or stopped, not already in a group) initiates a drag after the system long-press threshold; the long-press haptic fires and the ghost pill appears at the finger position.
- A long-press on an **ineligible** pill (the playing host, or a speaker already in any multi-member group) does not initiate a drag; the pill remains rendered at 0.5 opacity per design-spec §1.2.
- While the drag ghost is over a session card's bounds, that card enters the drop-zone-active state (gold border per design-spec §3); when the ghost leaves the card's bounds, the card returns to its idle state.
- Releasing the ghost over a session card triggers the join: `speakerToJoin.client.join(peer: hostSpeaker.identifier)` is called on a new detached `Task` owned by the session view model.
- Releasing the ghost outside any session card cancels the drag with no state change; the warning haptic fires per design-spec §6.2.
- During the in-flight join, the source bottom-bar pill renders at 0.5 opacity and is non-draggable per design-spec §1.1 row "Source dimmed".
- The drag-and-drop interaction is reachable by VoiceOver via the session card's `.accessibilityAction(named: "Add speaker")`, which presents a system action sheet of eligible speakers; selecting one performs the same join action.

---

**US-81 — See a join-in-progress indicator**
> As a user who has just dropped a speaker onto a session card, I want immediate visual confirmation that the join is being processed, so that I know the app received my action even when the API call takes several seconds.

**Acceptance criteria:**
- Within one animation frame of the drop, a new chip appears in the session card's group chip row, in **loading** state (dimmed label + inline spinner per design-spec §4.1 step 3).
- The loading chip remains visible for the full duration of the `client.join(peer:)` call (up to 10 seconds per UQ-3).
- On API success: the chip transitions to full-opacity and plays the brief pulse defined in design-spec §4.1 step 7; the source pill regains full opacity and renders the group connector defined in F3 §2.3.
- On API failure (timeout, unreachable, 4xx/5xx): the chip fades out via `.transition(.opacity)`; the source pill regains full opacity and is draggable again; an `.error` toast appears with the speaker name and reason; `HapticEngine.shared.errorOccurred()` fires per design-spec §6.2.
- The loading chip is not interactive — tapping it does nothing, and it cannot be dragged.
- If the user backgrounds the app or the session card scrolls out of view during the in-flight call, the `Task` continues to completion; the resulting model mutation (success or failure) is applied when control returns.
- The `SpeakerDiscoveryService.mergeIntoSpeakerGroup(source:target:)` call is made **only after** the API call succeeds (not before), so the speaker is not visible in the chip row in its post-join solid form until the join is confirmed by the speaker.

---

**US-82 — See the current group members**
> As a user with a multiroom group active, I want the session card to show every speaker currently in the group, so that I always know which speakers are playing together.

**Acceptance criteria:**
- The session card's chip row (introduced in F3 / E-53 as display-only) lists every member of `SpeakerGroup.members` except the host speaker, in the order returned by the model.
- When `SpeakerDiscoveryService.groups` changes (a new member joins via any path — drag-drop, voice command, or peer event from another controller), the chip row reflects the new membership within one animation frame.
- When a member leaves (any path), the chip is removed from the row.
- F2 makes no visual change to the chip presentation defined in F3 — only adds tap behaviour (US-83) and the loading-state variant (US-81).

---

**US-83 — Remove a speaker from a group by tapping its chip**
> As a user looking at the group chip row, I want to tap a chip to remove that speaker from the group, with no confirmation step.

**Acceptance criteria:**
- Tapping a member chip immediately fades the chip out (`.transition(.opacity)`).
- The remove action calls `memberSpeaker.client.leave()` on a new detached `Task`.
- `SpeakerDiscoveryService.removeMember(memberSpeaker)` is called optimistically (before the API call resolves) so the chip-row model and bottom-bar pill state update immediately.
- On API success: `HapticEngine.shared.commandRecognised()` fires; no further visual change is needed (the optimistic update already completed); the bottom-bar pill regains its idle (draggable) state.
- On API failure: `discovery.mergeIntoSpeakerGroup(source: memberSpeaker, target: hostSpeaker)` is called to re-insert the chip; an `.error` toast appears; `HapticEngine.shared.errorOccurred()` fires.
- No confirmation dialog is shown (UQ-1 resolved).
- When the last member chip is removed (group collapses to solo), the chip row disappears per design-spec §5.4; the host card becomes a solo session.
- The chip is reachable by VoiceOver with `.accessibilityLabel = "[Name], in group. Tap to remove."` and `.accessibilityRole(.button)`; double-tap performs the remove. On success, the system posts `"[Name] removed from group"` via `UIAccessibility.post(notification: .announcement, …)`.

---

**US-84 — Discover the drag-to-join gesture**
> As a first-time user with at least one playing speaker and at least one idle speaker, I want a one-time hint that explains I can drag a pill onto the card, so that I don't miss the join feature.

**Acceptance criteria:**
- The first time the home screen renders with at least one **eligible draggable** pill in the bottom bar (any session in the device's lifetime), a coach mark appears above the first eligible pill with the text `"Drag to join this session"` (DA: `"Træk for at tilslutte"`) per design-spec Appendix B.
- The coach mark fades out automatically after 3 seconds.
- The coach mark is dismissed permanently if the user (a) completes a successful drop, or (b) taps anywhere on the screen, whichever happens first.
- The "seen" state persists in `@AppStorage("hasSeenGroupingCoachMark")`. Once true, the coach mark never appears again on this device (UQ-4 resolved: once per app lifetime).
- The coach mark does not appear if the user has only ineligible pills available (e.g. all speakers already in groups, or only the host visible).
- The coach mark does not block any other interaction — the pill underneath remains draggable while the mark is showing.

---

## Technical Requirements

### TR-1 — `Speaker` Transferable conformance

Add an extension making `Speaker` (or a small struct wrapping `SpeakerIdentifier`) conform to `Transferable`. The dropped payload must round-trip cleanly:

```swift
extension SpeakerIdentifier: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}
```

`Speaker` itself is a `@MainActor` `@Observable` reference type and cannot be copied across the drag boundary. The `Transferable` payload is `SpeakerIdentifier` (the value-type identity already used by `join(peer:)`); the drop handler resolves the live `Speaker` reference via the session view model's `discovery` snapshot.

### TR-2 — Bottom-bar pill drag source

The `SpeakerSelectorPill` (or its replacement in F3 / E-53) attaches `.draggable(speaker.identifier) { /* drag-preview view */ }` per pill, gated by an `isDraggable(speaker)` check. `isDraggable` returns `false` when:
- The speaker is the playing host of any group, OR
- The speaker is a member of any multi-member group, OR
- The speaker has an in-flight join `Task` originating from this pill.

Non-draggable pills omit `.draggable(_:)` entirely (do not pass an empty payload — this disables the gesture cleanly) and render at 0.5 opacity per design-spec §1.2.

### TR-3 — Session-card drop destination

The session card root (or its drop-target subview) attaches:

```swift
.dropDestination(for: SpeakerIdentifier.self) { items, _ in
    guard let droppedId = items.first,
          let sourceSpeaker = sessionViewModel.resolveSpeaker(droppedId),
          sourceSpeaker.id != hostSpeaker.id else { return false }
    sessionViewModel.handleJoinDrop(source: sourceSpeaker, target: hostSpeaker)
    return true
} isTargeted: { isOver in
    sessionViewModel.dropZoneActive = isOver
}
```

`dropZoneActive` drives the gold-border + inner-glow visual treatment defined in design-spec §3. `handleJoinDrop` is defined in TR-4.

### TR-4 — Join task lifecycle

The session view model owns a per-card `joinsInFlight: Set<String>` (keyed by `SpeakerIdentifier.id`) and a `[String: Task<Void, Never>]` map for cancellation. `handleJoinDrop(source:target:)` is `@MainActor`:

1. Insert `source.identifier.id` into `joinsInFlight`. The chip row reads this set to render a loading chip for `source` (label dimmed, inline `ProgressView`).
2. Start a detached `Task`. Inside: `try await source.client.join(peer: target.identifier)`.
3. On success (return without throw):
   - `discovery.mergeIntoSpeakerGroup(source: source, target: target)`.
   - Remove `source.identifier.id` from `joinsInFlight`.
   - Trigger the chip-pulse animation (a per-chip `@State var pulse` toggled then reset).
4. On failure (caught `Error`):
   - Remove `source.identifier.id` from `joinsInFlight`.
   - `HapticEngine.shared.errorOccurred()`.
   - Append a `.error` toast `"Couldn't add [source.name] — [reason]"` (reason mapped from `SpeakerError`).
5. On view teardown (e.g. discovery removes the host speaker mid-flight): the task is **not** cancelled — let the API call complete to keep the speaker state consistent. The model mutation in step 3 is a no-op if the host group no longer exists.

### TR-5 — Source-pill in-flight lockout

The bottom-bar pill renderer reads `sessionViewModel.joinsInFlight` (or the parent home view's union across all sessions). A pill whose identifier is in any `joinsInFlight` set:
- Renders at 0.5 opacity (matching the already-grouped state per design-spec §1.2 and §4.1 step 6).
- Has `.draggable(_:)` omitted.
- Cannot be re-dropped onto a different card (consistent with non-draggable state).

### TR-6 — Tap-to-remove on member chips

The F3 chip-row chip view gains `.onTapGesture { sessionViewModel.handleRemoveTap(chipSpeaker) }`. `handleRemoveTap` is `@MainActor`:

1. Capture `originalGroup = discovery.groups.first { $0.members.contains { $0.id == speaker.id } }` (for rollback).
2. `discovery.removeMember(speaker)` — optimistic; the chip fades out via the row's `.transition(.opacity)` driven by the `members` diff.
3. Start a detached `Task`. Inside: `try await speaker.client.leave()`.
4. On success: `HapticEngine.shared.commandRecognised()`; post VoiceOver announcement `"[Name] removed from group"`.
5. On failure:
   - Re-insert via `discovery.mergeIntoSpeakerGroup(source: speaker, target: originalGroup.hostSpeaker)` if `originalGroup` still has at least one remaining member; otherwise reconstruct the group from `originalGroup` snapshot.
   - `HapticEngine.shared.errorOccurred()`.
   - Toast `"Couldn't remove [speaker.name] — [reason]"`.

### TR-7 — Coach mark trigger

A small `@MainActor` view modifier on the bottom bar:

```swift
.onChange(of: hasEligibleDraggablePill) { _, eligible in
    guard eligible, !hasSeenGroupingCoachMark else { return }
    coachMarkVisible = true
    Task {
        try? await Task.sleep(for: .seconds(3))
        coachMarkVisible = false
    }
}
```

On any of (a) successful drop, (b) screen tap (via `simultaneousGesture`), (c) 3-second timeout: set `hasSeenGroupingCoachMark = true` and `coachMarkVisible = false`. The "seen" flag is stored in `@AppStorage("hasSeenGroupingCoachMark")`.

### TR-8 — Multiple visible cards

When the F3 session strip exposes multiple cards in the visible viewport (including a peeking card at the edge), each card attaches its own `.dropDestination` independently. The `isTargeted` callback fires per card; only the card whose bounds currently contain the drag location enters drop-zone-active state. Releasing the ghost over a peeking-but-partially-visible card is valid — the drop handler runs identically.

### TR-9 — VoiceOver alternate paths

- **Join (US-80 alternate)**: each session card declares `.accessibilityAction(named: "Add speaker")`. The action presents a `confirmationDialog` (or an `.actionSheet` on iOS 16) listing every eligible draggable speaker (same eligibility rules as TR-2). Selecting a speaker invokes `sessionViewModel.handleJoinDrop(source: selectedSpeaker, target: hostSpeaker)`.
- **Remove (US-83 alternate)**: each chip's `.accessibilityRole(.button)` and `.accessibilityLabel("[Name], in group. Tap to remove.")` enables a direct VoiceOver double-tap.
- **Announcements**:
  - On successful join: `UIAccessibility.post(notification: .announcement, argument: "[source.name] joined [host.name]")`.
  - On successful remove: `UIAccessibility.post(notification: .announcement, argument: "[speaker.name] removed from group")`.

---

## Error States

| Scenario | Expected Behaviour |
|---|---|
| Drop succeeds; `client.join(peer:)` returns without throw | Chip transitions from loading to full-opacity + pulse; `mergeIntoSpeakerGroup` updates the model; success haptic fires per design-spec §6.2 |
| Drop succeeds; `client.join(peer:)` throws `SpeakerError.timeout` | Loading chip fades out; source pill regains full opacity; `.error` toast `"Couldn't add [name] — connection timed out"`; error haptic fires |
| Drop succeeds; `client.join(peer:)` throws `SpeakerError.unreachable` | Loading chip fades out; toast `"Couldn't add [name] — speaker unreachable"`; error haptic fires |
| Drop succeeds; `client.join(peer:)` throws other error | Loading chip fades out; toast `"Couldn't add [name]"`; error haptic fires |
| Drop occurs on the same speaker's own card (drop ID == host ID) | Drop handler returns `false`; no API call; no visual change; no haptic |
| Drop occurs while another join from the same source is in flight | Drop handler returns `false` (source pill is non-draggable per TR-5; this branch is defensive) |
| Drag released outside any drop destination | No API call; ghost animates back to source per design-spec §2.1; warning haptic per design-spec §6.2 |
| Tap chip; `client.leave()` returns without throw | Optimistic remove already applied; success haptic fires; VoiceOver announcement posted |
| Tap chip; `client.leave()` throws | Re-insert chip via `mergeIntoSpeakerGroup`; `.error` toast `"Couldn't remove [name]"`; error haptic fires |
| Tap chip whose speaker has been removed by another path between view render and tap | `discovery.removeMember(_:)` is a no-op (no matching member); the leave call still runs (defensive); on success, no further action; on failure, no re-insert is needed |
| Coach mark visible; user taps anywhere | Coach mark fades; `hasSeenGroupingCoachMark = true`; pill underneath still receives the long-press if continued |
| Coach mark visible; user completes a successful drop within the 3-s window | Coach mark fades immediately on drop completion; `hasSeenGroupingCoachMark = true` |
| Host speaker disappears from discovery during in-flight join | Join `Task` is not cancelled; on completion, `mergeIntoSpeakerGroup` is a no-op if the target group no longer exists; loading chip is removed when the host card unmounts |
| Source speaker disappears from discovery during in-flight join | Join `Task` is not cancelled; on completion, `mergeIntoSpeakerGroup` is a no-op if `source` is not in `discovery.allSpeakers` (the merge searches for the source by id) |
| User drags a pill while a join from a different source is already in flight on the same card | Allowed — multiple in-flight joins per card are tracked independently in `joinsInFlight` |

---

## Non-Functional Requirements

**Latency budgets**

- Drag initiation (long-press to ghost-visible): ≤ 100 ms after the system long-press threshold fires.
- Drop-zone-active visual transition: ≤ 1 frame after `isTargeted` callback fires (animated with `BeoAnimation.spring`).
- Loading chip appearance: within 1 frame of the drop release.
- Loading chip resolution (success or failure): bounded by the `client.join(peer:)` call — up to 10 seconds for `beolinkExpand` per UQ-3.
- Optimistic remove visual: within 1 frame of the tap.
- Coach mark appearance: within 1 frame of the eligible-pill condition becoming true.

**Concurrency**

- All drop handlers and tap handlers run on `@MainActor` for model mutations.
- `client.join(peer:)` and `client.leave()` are awaited inside detached `Task` blocks so the UI thread never blocks on the network call.
- `joinsInFlight` mutations are `@MainActor`-isolated; the set is read by both bottom-bar pill renderers and the chip row, so atomic update is required (assignment to a `@State` `Set<String>` is sufficient).

**Accessibility**

- Drag-and-drop is supplemented by an `.accessibilityAction(named: "Add speaker")` per TR-9 — VoiceOver users have full join coverage.
- Member chips are direct VoiceOver targets per TR-9 — VoiceOver users have full remove coverage.
- All success and failure transitions post `UIAccessibility` announcements per TR-9.
- Reduce Motion: the chip pulse and ghost spring animations respect `@Environment(\.accessibilityReduceMotion)` — when reduced, the pulse is replaced by a single opacity flash and the ghost return is instantaneous.

**Telemetry**

- F2 introduces no new telemetry events. Voice-path joins and leaves are already captured under existing intents `joinSpeaker` / `leaveSpeaker`. Touch-path joins and leaves are out of scope for v1.4 telemetry per VoxioSpecification-1.4.md "What is NOT changing".

**Platform**

- Requires iOS 16+ for `.draggable()` / `.dropDestination()` / `Transferable`. v1.4 deployment target is iOS 26 — fully supported.

---

## Out of Scope (this version)

Mirrors design-spec §9, repeated here for the implementation team's audit trail:

- Named group presets or saved group configurations
- Broadcast controls (apply action to all members) — voice-only in v1.4
- `beolinkJoin()` without a peer (the physical Join button scenario)
- Per-member volume — touch controls apply to the host speaker only
- Drag-scroll: automatically scrolling the card strip while holding a drag near the edge
- Drag from within the chip row to reorder or move members between groups
- Auto-move when dragging an already-grouped speaker (UQ-2 resolved: not draggable instead)
- Confirmation dialog on remove (UQ-1 resolved: no confirmation)
- New telemetry events for touch-path joins/leaves

---

## Open Questions

*None.* All UQs in design-spec §7 are resolved (UQ-1 through UQ-4). No new questions were raised during functional spec drafting.

---

## Resolved Decisions

| Question | Decision | Source |
|---|---|---|
| Should remove require confirmation? | No — direct tap | design-spec UQ-1 |
| Already-grouped speaker dragged to another card — auto-move or prevent? | Prevent — already-grouped pills are non-draggable (0.5 opacity, gesture omitted) | design-spec UQ-2 |
| What is the expected latency of `beolinkExpand`? Spinner? | Up to 10 seconds; loading chip with spinner for full duration; not optimistic | design-spec UQ-3 |
| Coach mark frequency? | Once per app lifetime, persisted via `@AppStorage` | design-spec UQ-4 |
| Transferable payload type? | `SpeakerIdentifier` (Codable value type) — `Speaker` is `@MainActor` reference, can't cross drag boundary | TR-1 |
| Where does the in-flight set live? | On the per-card session view model, with the home view aggregating across cards for bottom-bar pill state | TR-4, TR-5 |
| Cancel join task on view teardown? | No — let the API call complete; model mutation is a no-op if the target no longer exists | TR-4 step 5 |
| Optimistic vs deferred for leave? | Optimistic — chip fades immediately, `mergeIntoSpeakerGroup` rolls back on failure | TR-6 |

---

## Amendment History

| Date | Source | Change |
|---|---|---|
| 2026-05-09 | Initial draft | First version of the F2 functional spec. Derived from `design-spec-multiroom-grouping.md` v1.1 (all UQs resolved), VoxioSpecification-1.4.md F2, and the existing iOS code (`SpeakerDiscoveryService.mergeIntoSpeakerGroup`, `MozartClient+SpeakerClient.join/leave`, HomeView voice dispatch lines ~569–592). |
