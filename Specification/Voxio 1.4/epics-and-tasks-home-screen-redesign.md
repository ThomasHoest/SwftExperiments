# Epics & Tasks: Home Screen Redesign (Voxio 1.4)
**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-09
**References:** spec-home-screen-redesign.md (v1.0), design-spec-home-screen-redesign.md (v1.2), VoxioSpecification-1.4.md (Feature 3, US-60–US-66), epics-and-tasks-telemetry-backend.md (format reference), CLAUDE.md
**Stack:** SwiftUI, iOS 26, `@Observable @MainActor`, `Network.framework` (`NWPathMonitor`), `PBXFileSystemSynchronizedRootGroup` (no pbxproj edits required for any new `.swift` file)

---

## Overview

This document breaks Feature 3 (Home Screen Redesign) of `VoxioSpecification-1.4.md` into epics and constituent tasks. The deliverable is a refresh of the iOS home screen surface in the existing `Voxio` Xcode target — no new repositories, no new modules, no new build settings. All new files drop into `iOS/Voxio/Features/Home/` (or a `Components/` subfolder) and are picked up automatically by `PBXFileSystemSynchronizedRootGroup`.

The work is partitioned into four epics that map 1:1 with the four areas described in the spec: (E-52) the swipeable session card strip, (E-53) the new group chip row inside each session card, (E-54) the bottom bar redesign with `PlaybackBars` and the group connector, and (E-55) the discovery + offline state machine driven by a new `NetworkMonitor`. Epics may be implemented in parallel by separate engineers — the only cross-epic seam is the shared extraction of `PlaybackBars` (used by both the existing `SpeakerCard` and the new `SpeakerSelectorPill`), which is owned by E-54 T-5402.

Epic numbering begins at **E-52**, continuing from `epics-and-tasks-multiroom-grouping.md` (which is expected to end at E-51 once written). Task numbering follows the per-epic four-digit pattern: T-5201+, T-5301+, T-5401+, T-5501+.

No tasks in this document are marked complete — all are new work for v1.4.

---

## Epic Index

| # | Epic | User Stories | Feature Area |
|---|---|---|---|
| E-52 | Session card strip | US-60, US-62 | Horizontal swipeable strip, page dots, single-session fallback, two-way binding with bottom bar |
| E-53 | Session card group chip row | US-61 | Display-only chip row at the bottom of `SpeakerCardView`; "+N more" overflow |
| E-54 | Bottom bar redesign | US-62 | `PlaybackBars` per playing pill, group connector line, `SpeakerSelectorPill` refactor |
| E-55 | Discovery and offline states | US-63, US-64, US-65, US-66 | Pre-settle pulse rings, no-speakers-found state, offline state, `NetworkMonitor`, `ConnectionStatusChip` rewrite |

---

## E-52 — Session card strip

Replace the single `SpeakerCard` rendered by `HomeView.cardArea` with a horizontally swipeable `ScrollView(.horizontal)` strip — one card per active `SpeakerGroup` whose host speaker is playing. Provide page dots below the strip when more than one session exists. Maintain a two-way binding between the visible card and the bottom bar's selected speaker: swiping the strip selects the session host in the bottom bar; tapping a bottom-bar pill scrolls the strip to that speaker's session card.

This epic touches `HomeView.swift` (rewires `cardArea`), introduces three new files under `iOS/Voxio/Features/Home/` (`SessionStripView.swift`, `SessionPageDots.swift`, and a small `SessionsModel` helper if needed), and depends on the existing `SpeakerCard` view body unchanged.

**Depends on:** none. The session-strip work can begin first.
**Unlocks:** E-53 (group chip row goes inside each session card), E-54 (bottom bar selection two-way binding), E-55 (discovery state-machine routing wraps the strip).

---

### Session strip view

- [x] **T-5201** Create `iOS/Voxio/Features/Home/SessionStripView.swift`. Defines `struct SessionStripView: View` that takes `let groups: [SpeakerGroup]` (already filtered to playing-host groups by the parent), `@Binding var selectedSpeaker: Speaker?`, `let roll: Double`, `let pitch: Double`, and `let isCommandActive: Bool`. Renders a `ScrollView(.horizontal, showsIndicators: false)` with `.scrollTargetBehavior(.viewAligned)` and `.scrollTargetLayout()` on the inner `LazyHStack(spacing: Spacing.s8)`. Each card is a `SpeakerCard` wrapped in a fixed frame: `.frame(width: cardWidth)` where `cardWidth = screenWidth - (Spacing.s16 * 2)`. The trailing 8 pt peek is created by the trailing card's natural overflow plus `.scrollTargetBehavior(.viewAligned)` snap. Use `UIApplication.shared.connectedScenes` to read the true screen width (matching the `SpeakerSelectorPill` workaround for the iOS 26 ZStack inflation issue documented inline in `SpeakerSelectorPill.swift`). When `groups.count == 1`, render the single card without horizontal scroll affordance — frame to full available width minus `Spacing.s16` each side, no peek (use a computed `effectiveCardWidth` that omits the 8 pt peek when single-session).
  *Depends on: nothing.*

- [x] **T-5202** In `SessionStripView` (T-5201), use `ScrollPosition(id: $scrollHostId)` (`@State private var scrollHostId: Speaker.ID?`) bound to `.scrollPosition(id: $scrollHostId, anchor: .center)`. On `onChange(of: scrollHostId)`, set `selectedSpeaker = groups.first(where: { $0.hostSpeaker.id == scrollHostId })?.hostSpeaker`. On `onChange(of: selectedSpeaker?.id)`, if the selected speaker belongs to a group in `groups` (as host or member), animate `scrollHostId = matchingGroup.hostSpeaker.id` using `withAnimation(BeoAnimation.spring)`. This implements the two-way binding required by US-60 and US-62. If the selected speaker is idle (not the host of any session), do not change `scrollHostId` — the strip stays where it was per US-62 acceptance criterion.
  *Depends on: T-5201.*

- [x] **T-5203** In `SessionStripView` (T-5201), handle the insertion/removal animation case from US-60: when a group joins or leaves the playing set, do not lose the user's current scroll position. Use `LazyHStack` with `.id(group.id)` per card so SwiftUI's diffing inserts/removes the right card in place. If the currently-visible card is removed, after the animation lands set `scrollHostId = groups.first?.hostSpeaker.id` (the nearest remaining session) — wrap in `.onChange(of: groups.map(\.id))` with a guard that fires only when the previously-visible host is no longer in the new set.
  *Depends on: T-5202.*

### Page dots

- [x] **T-5204** Create `iOS/Voxio/Features/Home/SessionPageDots.swift`. Defines `struct SessionPageDots: View` that takes `let count: Int` and `let activeIndex: Int`. Renders an `HStack(spacing: Spacing.s8)` of `Circle()` shapes per design spec §3.3: active dot 8 pt diameter in `BeoColor.accent`; inactive dots 6 pt diameter in `BeoColor.muted` at 0.4 opacity. Returns `EmptyView()` when `count <= 1`. Apply `.accessibilityHidden(true)` (the cards themselves carry the navigation information per design spec §3.7). Animate active-index changes with `BeoAnimation.toast` (200 ms cross-fade); on Reduce Motion, opacity-only without scale per design spec §Motion.
  *Depends on: nothing.*

- [x] **T-5205** In `SessionStripView`, derive the active page index from `scrollHostId` (`groups.firstIndex(where: { $0.hostSpeaker.id == scrollHostId }) ?? 0`). Render `SessionPageDots` below the `ScrollView` separated by `Spacing.s8` vertical padding. Wrap the strip + dots in a `VStack(spacing: 0)` so they move together inside `HomeView`.
  *Depends on: T-5201, T-5204.*

### HomeView integration

- [x] **T-5206** In `iOS/Voxio/Features/Home/HomeView.swift`, replace `private var cardArea: some View` to delegate to a new computed property `playingGroups: [SpeakerGroup]` = `discovery.groups.filter { $0.hostSpeaker.isPlaying }`. Routing logic:
  - If `playingGroups.isEmpty && displayedSpeaker != nil` → render the existing `SpeakerCard(speaker: displayedSpeaker, …)` unchanged (covers the "speakers discovered but none playing" idle case).
  - If `playingGroups.isEmpty && displayedSpeaker == nil` → render the existing `emptyState` view (unchanged in F3 — replaced wholesale by E-55).
  - If `!playingGroups.isEmpty` → render `SessionStripView(groups: playingGroups, selectedSpeaker: $selectedSpeaker, roll: motionManager.roll, pitch: motionManager.pitch, isCommandActive: isCommandActive)`.

  Note: the discovery state-machine routing (Discovering / Offline / NoSpeakersFound) wraps this entire block in E-55 T-5505 — for now, this routing replaces only the existing `cardArea` body and does not yet handle network state.
  *Depends on: T-5205.*

### Single-session fallback (no-regression)

- [x] **T-5207** Verify the single-session case in `SessionStripView`: when `groups.count == 1`, the layout must be visually indistinguishable from the v1.3 single-card layout. Specifically: no 8 pt peek on the trailing edge (the card occupies the full `screenWidth - Spacing.s16 * 2`), no page dots (handled by T-5204's `count <= 1` guard), no horizontal scroll bounce. Confirm by snapshot test or by manual inspection on a one-speaker network. If the `ScrollView` adds visible bounce even with one child, set `.scrollDisabled(groups.count == 1)`.
  *Depends on: T-5205.*

### Front-most parallax (resolved UQ-7)

- [x] **T-5208** In `SessionStripView` (T-5201), pass `roll` and `pitch` only to the front-most visible card. Track the visible card via `scrollHostId`; pass `0` for `roll`/`pitch` to all other cards in the `ForEach`. This preserves the existing `SpeakerCard.specularHighlight` parallax on the visible card while freezing offscreen cards per resolved UQ-7. Reduce Motion is already handled inside `SpeakerCard` (`if !reduceMotion { specularHighlight }`).
  *Depends on: T-5202.*

### Verification

- [ ] **T-5209** Manual verification on device or simulator with three concurrent sessions: confirm (a) cards swipe with momentum and snap to alignment, (b) trailing card peeks at 8 pt, (c) page dots reflect the visible card, (d) swiping updates `selectedSpeaker` (visible by the bottom bar's selected pill changing), (e) tapping a different bottom-bar pill scrolls the strip to that speaker's session card, (f) idle-speaker pill tap does not scroll the strip, (g) starting playback on an idle speaker inserts a new card without disturbing the visible card, (h) stopping playback on a non-visible session removes its card without animation jank. Document the test setup in a temporary `docs/manual-test-session-strip.md` (delete on merge).
  *Depends on: T-5206, T-5208.* (deferred: manual verification on device)

- [ ] **T-5210** VoiceOver verification: turn on VoiceOver and confirm (a) each session card is announced as a single accessibility element with the speaker name, state, track, and group members appended per design spec §3.7, (b) page dots are not announced (`.accessibilityHidden(true)` from T-5204), (c) swiping with the standard VoiceOver gesture moves between cards in element-focus order without invoking the native paging gesture, (d) the announced order on the home screen is status bar → session card → page dots region (silent) → voice feedback → bottom bar pills.
  *Depends on: T-5206.* (deferred: manual verification on device)

---

## E-53 — Session card group chip row

Add a new region at the bottom of `SpeakerCardView` that lists the non-host members of the speaker's `SpeakerGroup` as `+ <name>` chips. The row is display-only in F3 (interactivity is added in F2). When the group has more than 3 members, show 2 chips followed by a `+N more` chip. When the group has only one member (the host), the row is absent — no empty space below the volume track.

This epic adds one new view file (`GroupChipRow.swift`) and a small change to `SpeakerCard.swift` to mount the row when applicable.

**Depends on:** none. Can be built in parallel with E-52, E-54, E-55.
**Unlocks:** F2 multiroom UI consumes the same chip row and adds tap interactivity later.

---

### Group chip row view

- [x] **T-5301** Create `iOS/Voxio/Features/Home/GroupChipRow.swift`. Defines `struct GroupChipRow: View` taking `let members: [Speaker]` (already filtered to exclude the host). Renders an `HStack(spacing: Spacing.s8)` of `Capsule()` chips. Each chip displays `"+ \(speaker.name)"` in `BeoType.caption` with `BeoColor.muted` foreground, `.white.opacity(0.07)` background, padding `Spacing.s8` horizontal and `Spacing.s4` vertical. Returns `EmptyView()` when `members.isEmpty`. Frame the row with leading alignment; do not constrain trailing edge — chips lay out naturally and never overflow because the parent enforces the card width.
  *Depends on: nothing.*

- [x] **T-5302** In `GroupChipRow` (T-5301), implement the "+N more" overflow per resolved UQ-6: when `members.count > 3`, render the first 2 chips followed by a third chip with label `"+\(members.count - 2) more"` (English) / `"+\(members.count - 2) flere"` (Danish — verify via `LanguageService.shared.activeLanguage`). The `+N more` chip is visually identical to a member chip but its `accessibilityLabel` is `"\(members.count - 2) more speakers in this group"` / Danish equivalent. Tap is a no-op in F3 — do not attach a `Button` wrapper or `.onTapGesture` modifier.
  *Depends on: T-5301.*

- [x] **T-5303** In `GroupChipRow`, accessibility: each chip carries an `.accessibilityLabel("Also playing: \(speaker.name)")` / Danish equivalent. The row itself does not group children — VoiceOver reads chips individually. Combined with the parent `SpeakerCard.accessibilityElement(children: .ignore)` and its own `accessibilityLabel`, the chip labels are appended to the card label by `SpeakerCard` (handled in T-5305 below) — the chips themselves are decorative within the card's accessibility surface.
  *Depends on: T-5301.*

### Mount in SpeakerCard

- [x] **T-5304** In `iOS/Voxio/Features/Home/SpeakerCard.swift`, add a new optional input `var groupMembers: [Speaker] = []` (default empty for backwards compatibility with non-strip callers). In `cardContent`, after the volume track block, render `if !groupMembers.isEmpty { GroupChipRow(members: groupMembers).padding(.horizontal, Spacing.s24).padding(.bottom, Spacing.s16) }`. Confirm the existing `nowPlayingPanel` and `volumeTrack` regions retain their current padding values (per design spec §3.4: chip row padding is added below the volume track at `Spacing.s16` to the card edge).
  *Depends on: T-5301.*

- [x] **T-5305** In `SpeakerCard.accessibilityDescription` (T-5304), append the group members to the description string when non-empty: `if !groupMembers.isEmpty { parts.append("Also playing: " + groupMembers.map(\.name).joined(separator: ", ")) }`. Use the localised "Also playing" string from design spec Appendix B (`a11y.alsoPlaying`).
  *Depends on: T-5304.*

### Wire from SessionStripView

- [x] **T-5306** In `SessionStripView` (T-5201), pass `groupMembers: group.members.filter { $0.id != group.hostSpeaker.id }` to each `SpeakerCard`. Confirm the host is correctly excluded — per design spec §3.4, the primary speaker (card title) is never repeated in the chip row.
  *Depends on: T-5301, T-5304, T-5201.*

### Layout reflow on group composition change

- [x] **T-5307** Verify that when `group.members` changes (a member joins or leaves), the chip row updates in place without re-rendering the rest of the card. SwiftUI's diffing handles this automatically given the `members` parameter is a value type. Confirm by manually triggering a join during testing — the card content above the chip row must remain visually stable. If reflow jank is observed, wrap `GroupChipRow` in `.transition(.opacity)` to soften individual chip insertions.
  *Depends on: T-5306.*

### Localisation

- [x] **T-5308** Add the new localised strings from design spec Appendix B to the existing English and Danish localisation catalogues (`en.lproj/Localizable.strings` and `da.lproj/Localizable.strings` or whatever pattern the project uses — verify against `LanguageService.shared` consumers). Keys: `groupChip.prefix`, `a11y.alsoPlaying`. Do not duplicate keys that already exist for `Speaker.stateDisplay`.
  *Depends on: T-5301.*

### Verification

- [ ] **T-5309** Manual verification with a 4-speaker group: confirm the chip row shows `+ Member1`, `+ Member2`, and `+2 more`. With a 2-speaker group: confirm one chip is shown. With a 1-speaker group (solo session): confirm the chip row is absent and there is no empty space below the volume track. With Dynamic Type at AX1 and AX5: confirm the row remains legible and either wraps gracefully or truncates at the trailing edge without breaking the card layout.
  *Depends on: T-5306.* (deferred: manual verification on device)

- [ ] **T-5310** VoiceOver verification: with a 3-speaker group active, confirm the visible session card's accessibility label includes the appended "Also playing: <name>, <name>" string per T-5305. Confirm the chips themselves are not separately focusable (covered by `SpeakerCard.accessibilityElement(children: .ignore)`).
  *Depends on: T-5305.* (deferred: manual verification on device)

---

## E-54 — Bottom bar redesign

Refresh `SpeakerSelectorPill` so that each pill shows a `PlaybackBars` indicator when its speaker is playing, and so that adjacent grouped pills are visually linked by a thin connector line. Pill order is preserved as discovery order — the bar is not re-sorted by group (per resolved UQ-3). Idle speakers continue to appear in the bar (per resolved UQ-4). The bottom bar is shown whenever at least one speaker is discovered, regardless of session count.

This epic extracts the existing private `PlaybackBars` struct from `SpeakerCard.swift` to a shared component file, then adds rendering logic to `SpeakerSelectorPill` for the bars and connector line.

**Depends on:** E-52 only at the integration point (the strip-to-pill two-way binding in T-5202 must exist before the bottom bar's tap-to-scroll behaviour is testable end-to-end). Pill rendering work can start in parallel.
**Unlocks:** F1 touch playback controls (the new pill anatomy is referenced by F1's volume pill).

---

### Extract PlaybackBars

- [x] **T-5401** Create `iOS/Voxio/Features/Home/Components/PlaybackBars.swift`. Move the private `struct PlaybackBars` from `SpeakerCard.swift` into this new file as `internal struct PlaybackBars: View`. Behaviour and animation specs unchanged from the original (specs `[(6, 14), (14, 6), (10, 16)]`, `Color(hex: "#C8A97E")`, staggered easeInOut with `repeatForever(autoreverses: true)`, 20 pt frame height). Add an optional `var height: CGFloat = 20` parameter to support the 10 pt height required for the bottom-bar pill per design spec §2.2 — the bars are drawn proportionally smaller. Add a Reduce Motion variant: when `@Environment(\.accessibilityReduceMotion) reduceMotion` is true, render static bars at the midpoint values per design spec §Motion. Add `.accessibilityHidden(true)`.
  *Depends on: nothing.*

- [x] **T-5402** Update `iOS/Voxio/Features/Home/SpeakerCard.swift` to import the now-shared `PlaybackBars` (no import statement needed inside the same target — confirm the type resolves). Remove the duplicate private struct. Verify the `nowPlayingPanel` continues to render the bars at the previous 20 pt height (default parameter value). No visual regression.
  *Depends on: T-5401.*

### Pill rendering with playback bars

- [x] **T-5403** In `iOS/Voxio/Features/Home/SpeakerSelectorPill.swift`, modify `pillButton(name:isActive:)` to accept the speaker itself (`pillButton(speaker: Speaker, isActive: Bool, isPlaying: Bool)`). Inside the label, change from `Text(name)` to a `HStack(spacing: Spacing.s8)` of `Text(speaker.name)` and (when `isPlaying`) `PlaybackBars(height: 10)`. Pill colour rules per design spec §2.2:
  - Playing pill: foreground `BeoColor.accent` (`#C8A97E`), `Capsule()` border 1 pt at `BeoColor.accent` with 0.55 opacity, glass effect background.
  - Selected and not playing: foreground `BeoColor.text` (primary), `Capsule()` border 1 pt at `.white.opacity(0.4)`, glass effect background.
  - Inactive (neither playing nor selected): foreground `.primary`, no border, glass effect background.
  Padding values: per design spec §2.4 — `Spacing.s16` left, `Spacing.s8` between text and bars (only when bars present), `Spacing.s12` right; `Spacing.s12` vertical top and bottom; `min-width: 44 pt`; `border-radius: Radius.pill` (100).
  *Depends on: T-5401.*

- [x] **T-5404** In `SpeakerSelectorPill`, update the `ForEach(speakers)` body to pass `isPlaying: speaker.isPlaying` to `pillButton`. When the speaker's `isPlaying` flips while the pill is mounted, the bars appear/disappear via SwiftUI's standard view-update cycle. Wrap the bars insertion/removal in `.transition(.opacity.animation(BeoAnimation.toast))` so the change cross-fades rather than popping.
  *Depends on: T-5403.*

- [x] **T-5405** Update accessibility per design spec §2.5: `accessibilityLabel = "\(speaker.name)" + (speaker.isPlaying ? ", playing" : "") + (isActive ? ", selected" : "")`. `accessibilityHint = isActive ? "" : "Show this speaker"`. Replace the existing v1.3 `"Select this speaker"` hint with `"Show this speaker"` to reflect the F3 behaviour change (tapping a pill in F3 scrolls the strip rather than just selecting).
  *Depends on: T-5403.*

### Group connector line

- [x] **T-5406** In `SpeakerSelectorPill`, add a new input `var groups: [SpeakerGroup]` so the pill view knows which speakers share a group. Inside the `HStack(spacing: 10)`, insert a connector segment between adjacent pills when both speakers belong to the same `SpeakerGroup`. Implementation: replace the simple `ForEach` with `ForEach(speakers.indices, id: \.self) { i in ... }` and after each pill (except the last), insert `connectorLine(currentSpeaker: speakers[i], nextSpeaker: speakers[i+1])`. The `connectorLine` view is a `Rectangle().fill(BeoColor.muted.opacity(0.3)).frame(width: 8, height: 1)` when both speakers share a group, otherwise `Rectangle().fill(.clear).frame(width: 8, height: 1)` (transparent placeholder preserves spacing). Helper: `func sameGroup(_ a: Speaker, _ b: Speaker) -> Bool` consults `groups.first { $0.members.contains { $0.id == a.id } }?.members.contains { $0.id == b.id } ?? false`. Per design spec §2.3, when grouped speakers are not adjacent, no connector is drawn — the helper returns `false` for non-adjacent pairs by construction.
  *Depends on: T-5404.*

### Tap-to-scroll wiring

- [x] **T-5407** In `HomeView.swift`, the existing `selectedSpeaker` binding flows to both `SessionStripView` (via E-52 T-5202) and `SpeakerSelectorPill`. Confirm that tapping a pill (which sets `selectedSpeaker = speaker`) triggers `SessionStripView.onChange(of: selectedSpeaker?.id)` to scroll the strip — per E-52 T-5202 — to the host of the group containing that speaker. For idle speakers (no playing group), the strip does not scroll (T-5202 acceptance criterion). No new code required here beyond ensuring the bindings are correctly wired.
  *Depends on: T-5202.*

### Bottom bar always-visible logic

- [x] **T-5408** In `HomeView.swift`, change the existing condition `if discovery.groups.flatMap(\.members).count > 1` to `if discovery.groups.flatMap(\.members).count >= 1` so the bottom bar appears as soon as one speaker is discovered (per US-62 acceptance criterion: idle speakers are shown in the bar). Pass `groups: discovery.groups` into `SpeakerSelectorPill` per T-5406. The bottom bar continues to be hidden in the Discovering state (no speakers yet) and the Offline state (gated by E-55 T-5505 routing).
  *Depends on: T-5406.*

### Verification

- [ ] **T-5409** Manual verification on a network with three speakers, two in a group and one solo (all playing): confirm (a) all three pills show `PlaybackBars` in gold, (b) the two grouped speakers have a connector line drawn between them in the bar (assuming they appear adjacent in discovery order), (c) the third pill has no connector, (d) tapping the solo pill scrolls the session strip to its card, (e) tapping a grouped pill scrolls the strip to the group's session card. With one of the three speakers paused: confirm its bars disappear with a fade and the pill remains in place. With three speakers none of which is grouped: confirm no connector lines are drawn.
  *Depends on: T-5407, T-5408.* (deferred: manual verification on device)

- [ ] **T-5410** VoiceOver verification: confirm a playing pill announces `"<name>, playing"`, the selected pill announces `"<name>, selected"`, and a playing-and-selected pill announces `"<name>, playing, selected"`. Confirm the connector line is not announced (it is a decorative `Rectangle` with no accessibility traits — inherits `.isAccessibilityElement = false` by default, but verify with VoiceOver).
  *Depends on: T-5405, T-5406.* (deferred: manual verification on device)

---

## E-55 — Discovery and offline states

Replace the current ambiguous "Looking for speakers…" / "Offline" UI with a three-state state machine driven by `(network.isOnWifi, discovery.didSettle, discoveredSpeakerCount)`. Introduce a new `NetworkMonitor` (`@Observable @MainActor`) wrapping `NWPathMonitor` from `Network.framework`. Rewrite `ConnectionStatusChip` to display three distinct copy states ("Searching…" / "No Wi-Fi" / "n speakers"). Build the pre-settle scanning UI with concentric pulse rings, the post-settle "no speakers found" UI with a "Search again" button, and the dedicated offline UI with auto-recovery messaging.

This epic introduces the largest set of new files: `NetworkMonitor.swift`, `DiscoveryStateView.swift`, `PulseRingsView.swift`, plus a rewrite of `ConnectionStatusChip.swift`. It also adds an auto-retry timer to `SpeakerDiscoveryService`.

**Depends on:** E-52 T-5206 (the `cardArea` routing must already accept the playingGroups branch — E-55 wraps the entire body with state-machine routing).
**Unlocks:** none — this is the final piece of F3.

---

### Network monitor

- [x] **T-5501** Create `iOS/Voxio/Core/Discovery/NetworkMonitor.swift`. Defines `@Observable @MainActor final class NetworkMonitor`. Properties: `var isOnWifi: Bool = true` (defaults to `true` per ADR-002 D2 revision — avoids offline-state flash during the brief window between view mount and the first `pathUpdateHandler` callback; the first callback corrects this within tens of milliseconds), `var isAvailable: Bool = true` (same default rationale). The properties are set to their true values from `NWPathMonitor`'s first callback: `isOnWifi` becomes true when `path.status == .satisfied && path.usesInterfaceType(.wifi)`; `isAvailable` becomes true when `path.status == .satisfied` regardless of interface (informational only, not consumed by F3 UI). Internal: `private let monitor = NWPathMonitor()`, `private let queue = DispatchQueue(label: "com.voxio.networkmonitor")`. Method: `func start()` calls `monitor.pathUpdateHandler = { [weak self] path in Task { @MainActor in self?.update(from: path) } }` and `monitor.start(queue: queue)`. Method: `func stop()` calls `monitor.cancel()`. Method: `private func update(from path: NWPath)` sets `isOnWifi` and `isAvailable` based on the path. On state change, log via `Log.info("[NetworkMonitor] isOnWifi=\(isOnWifi)")`.
  *Depends on: nothing.*

- [x] **T-5502** In `iOS/Voxio/Features/Home/HomeView.swift`, add `@State private var network = NetworkMonitor()`. In `onAppear`, call `network.start()`. Add `.onDisappear { network.stop() }` to the view body. The `NetworkMonitor` lives for the lifetime of the `HomeView` — this is the only home-screen surface and the monitor does not need to outlive it.
  *Depends on: T-5501.*

### ConnectionStatusChip rewrite

- [x] **T-5503** Rewrite `iOS/Voxio/Features/Home/ConnectionStatusChip.swift`. New signature: `struct ConnectionStatusChip: View { var isOnWifi: Bool; var didSettle: Bool; var speakerCount: Int }`. Computed property `private var state: ChipState` returns one of `.searching` (when `isOnWifi && !didSettle`), `.offline` (when `!isOnWifi`), or `.connected(speakerCount)` (when `isOnWifi && didSettle`). Render per state per US-66:
  - `.searching` — `wifi` symbol in `BeoColor.muted`, label "Searching…" / "Søger…" in primary; existing chip styling.
  - `.offline` — `wifi.slash` symbol in `BeoColor.muted`, label "No Wi-Fi" / "Ingen Wi-Fi" in secondary.
  - `.connected(n)` — `wifi` symbol in green (existing), label `"\(n)"` in primary.
  Existing styling (padding, glass capsule, font sizes) unchanged from v1.3. `accessibilityLabel` per state: searching → "Searching for speakers"; offline → "No Wi-Fi connection"; connected → existing "n speaker(s) connected" string.
  *Depends on: T-5501.*

- [x] **T-5504** In `HomeView.statusBar`, update the `ConnectionStatusChip` call to pass the three new inputs: `ConnectionStatusChip(isOnWifi: network.isOnWifi, didSettle: discovery.didSettle, speakerCount: discovery.groups.flatMap(\.members).count)`. Remove the old `speakerCount` shorthand from `ConnectionStatusChip` callers.
  *Depends on: T-5502, T-5503.*

### Home-screen state machine

- [x] **T-5505** In `iOS/Voxio/Features/Home/HomeView.swift`, refactor the `cardArea` computed property (after E-52 T-5206) to add the four-state routing per design spec §5.2. New top-level switch:
  - If `!network.isOnWifi` → render `DiscoveryStateView(state: .offline, onSearchAgain: {})` (button absent).
  - Else if `!discovery.didSettle && discoveredSpeakerCount == 0` → render `DiscoveryStateView(state: .searching, onSearchAgain: {})`.
  - Else if `discovery.didSettle && discoveredSpeakerCount == 0` → render `DiscoveryStateView(state: .noSpeakersFound, onSearchAgain: { discovery.restart() })`.
  - Else → existing E-52 T-5206 routing (session strip or idle card).
  Where `discoveredSpeakerCount = discovery.groups.flatMap(\.members).count`. Wrap the bottom bar conditional from E-54 T-5408 in the same logic: bottom bar is shown only in the fourth branch (and in the third branch's "Search again" intermediate, which falls back to the second branch immediately).
  *Depends on: T-5206, T-5408, T-5503.*

### DiscoveryStateView and pulse rings

- [x] **T-5506** Create `iOS/Voxio/Features/Home/PulseRingsView.swift`. Defines `struct PulseRingsView: View`. Renders three `Circle().stroke(BeoColor.accent, lineWidth: 1)` shapes layered behind the orb, each with its own `@State private var phase: CGFloat = 0` for the expand-and-fade animation. Per design spec §4.2: each ring expands from 96 pt diameter to 200 pt over 2.0 s with `.easeOut`, then resets. Opacity animates from 0.15 → 0 over the same 2.0 s. Ring 2 starts 0.6 s after ring 1; ring 3 starts 0.6 s after ring 2. Use `.onAppear { withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false).delay(stagger)) { phase = 1 } }` per ring. Reduce Motion variant: render a single static `Circle().stroke(BeoColor.accent.opacity(0.1), lineWidth: 1).frame(width: 200, height: 200)`. Apply `.accessibilityHidden(true)`.
  *Depends on: nothing.*

- [x] **T-5507** Create `iOS/Voxio/Features/Home/DiscoveryStateView.swift`. Defines `struct DiscoveryStateView: View` taking `let state: DiscoveryState` (enum: `searching`, `noSpeakersFound`, `offline`) and `let onSearchAgain: () -> Void`. Renders one of three layouts:
  - `.searching` — full-width centred `ZStack` of `PulseRingsView` (T-5506) behind the existing orb component (reuse the home screen's existing orb view; if it's an inline view in `HomeView`, extract into a small `OrbView` shared component as part of this task) at full opacity with idle pulse. Below: centred `Text("Searching for speakers…")` in `BeoType.body`, `BeoColor.muted`. After 10 s without state change, show a sub-label `Text("Still looking…")` in `BeoType.caption`, `BeoColor.muted` at 0.6 opacity. Use `@State private var stillLookingShown = false` driven by a `Task` with `try? await Task.sleep(for: .seconds(10))`.
  - `.noSpeakersFound` — orb at 0.4 opacity, no pulse animation. Below: `Text("No speakers found")` in `BeoType.nowPlaying`, primary text. Then a centred body paragraph in `BeoType.body`, `BeoColor.muted`. Then a `DarkGlassButton` with label "Search again" — calls `onSearchAgain()` when tapped. While the action is in flight (use `@State private var isSearching = false`), show an inline `ProgressView()` in the button.
  - `.offline` — orb at 0.2 opacity, no animation. Below: `Text("No Wi-Fi")` in `BeoType.nowPlaying`, primary text. Then a centred body paragraph in `BeoType.body`, `BeoColor.muted`. Then a sub-label "Recovers automatically when Wi-Fi reconnects" in `BeoType.caption`, `BeoColor.muted` at 0.6 opacity. No button.
  All copy strings come from design spec Appendix B (`discovery.searching`, `discovery.noSpeakers.title`, `discovery.noSpeakers.body`, `discovery.searchAgain`, `offline.title`, `offline.body`).
  *Depends on: T-5506.*

- [x] **T-5508** In `DiscoveryStateView` (T-5507), add accessibility announcements per design spec §4.5 and §5.5:
  - On `.searching` first render: `.accessibilityAnnouncement(Text("Searching for speakers"))` once.
  - On `.offline` first render: `.accessibilityAnnouncement(Text("No Wi-Fi connection"))` once.
  - On transition from `.offline` to `.searching`: `.accessibilityAnnouncement(Text("Wi-Fi connected, searching for speakers"))` once.
  Use `@State private var lastAnnouncedState: DiscoveryState? = nil` to suppress repeated announcements when the state remains unchanged across re-renders.
  *Depends on: T-5507.*

### State transitions and animations

- [x] **T-5509** In `HomeView`, add `.animation(BeoAnimation.toast, value: cardLayoutKey)` modifier to the `cardArea` body, where `cardLayoutKey` is a derived `String` summarising the current state-machine branch (e.g. `"offline"`, `"searching"`, `"noSpeakers"`, `"normal-N"` where N is the session count). This drives the cross-fade between Offline ↔ Discovering ↔ NoSpeakersFound ↔ Normal per design spec §4.4 and §5.4. Within `DiscoveryStateView`, the orb opacity changes (0.2 → 0.4 → 1.0) animate via a separate `.animation(BeoAnimation.spring, value: state)` to give the orb-restore springiness specified in §5.4.
  *Depends on: T-5505, T-5507.*

### Auto-retry in SpeakerDiscoveryService

- [x] **T-5510** In `iOS/Voxio/Core/Discovery/SpeakerDiscoveryService.swift`, add `func restart()` that calls `stop()`, resets `didSettle = false` (this requires `didSettle` to be assignable from within the class — already true since the property is `private(set)`), then calls `start()`. Used by `DiscoveryStateView`'s "Search again" button (E-55 T-5505).
  *Depends on: nothing.*

- [x] **T-5511** In `SpeakerDiscoveryService`, add a 30-second auto-retry timer per resolved UQ-9. When `didSettle == true && allSpeakers.isEmpty`, schedule a `Task` that sleeps 30 s, then calls `restart()` if the same condition still holds. Cancel the task whenever a speaker is added or `restart()` is called manually. Implementation: add `private var autoRetryTask: Task<Void, Never>?`. In `scheduleInitialSettle` (or a new `scheduleAutoRetry` called from `addSpeaker` and the `didSettle` setter), if entering the empty-post-settle state, kick off `autoRetryTask = Task { try? await Task.sleep(nanoseconds: 30_000_000_000); guard !Task.isCancelled, await self.allSpeakers.isEmpty else { return }; await self.restart() }`. Cancel from `addSpeaker` and `restart`. Stop from `stop()`.
  *Depends on: T-5510.*

### Hide voice and bottom bar in offline state

- [x] **T-5512** In `HomeView`, hide the `voiceFeedback` view and the `SpeakerSelectorPill` when `!network.isOnWifi`. Wrap both in `if network.isOnWifi { ... }` (or use `.hidden()` with a layout-preserving alternative if hiding causes the orb to reposition awkwardly — prefer the conditional render). Per US-65 acceptance criteria, the mic indicator and bottom bar are hidden in the offline state.
  *Depends on: T-5505.*

- [x] **T-5513** In `HomeView.startListening` (or the existing voice-pipeline entry point), gate the call by `network.isOnWifi`. If the user opens the app while offline, do not start the speech recognizer, the discovery service, or the motion manager. When `NWPathMonitor` reports Wi-Fi restored (via `.onChange(of: network.isOnWifi)` in the view body), call `startListening()` once if the user has completed onboarding and chosen a language. This prevents speech-recognition errors that would otherwise fire continuously while offline.
  *Depends on: T-5512.*

### Localisation

- [x] **T-5514** Add the new localised strings from design spec Appendix B to the localisation catalogues (English and Danish). Keys: `discovery.searching`, `discovery.noSpeakers.title`, `discovery.noSpeakers.body`, `discovery.searchAgain`, `offline.title`, `offline.body`, `chip.searching`, `chip.noWifi`, `a11y.offline`, `a11y.wifiRestored`, `a11y.pillPlaying`, `a11y.pillSelected`, `a11y.sessionCard`. Confirm that `state.playing`, `state.paused`, `state.stopped`, `state.connecting` already exist under `Speaker.stateDisplay` before adding duplicates per design spec Appendix B note.
  *Depends on: T-5503, T-5507.*

### Verification

- [ ] **T-5515** (deferred: manual verification on device) Manual verification of the full state machine: (a) open the app on Wi-Fi with no speakers powered on — confirm pre-settle pulse rings + "Searching for speakers…" label; after 10 s confirm "Still looking…" appears; after 30 s confirm a silent restart (visible by the orb pulse continuing without UI flicker). (b) Power on a speaker — confirm cross-fade to normal home screen with bottom bar appearing. (c) Power off the speaker — confirm transition to "No speakers found" state with dim orb + body copy + "Search again" button. (d) Tap "Search again" — confirm immediate transition back to pre-settle. (e) Disable Wi-Fi on the device — confirm transition to "No Wi-Fi" state with very-dim orb, hidden bottom bar, hidden voice feedback. (f) Re-enable Wi-Fi — confirm automatic transition back to pre-settle without any user action. (g) Quickly toggle Wi-Fi off and on — confirm both transitions render (acknowledged that flicker may be visible; debouncing not added in F3).
  *Depends on: T-5505, T-5511, T-5513.*

- [ ] **T-5516** (deferred: manual verification on device) VoiceOver verification of state transitions: with VoiceOver on, (a) entering pre-settle state announces "Searching for speakers" once, (b) entering offline state announces "No Wi-Fi connection" once, (c) Wi-Fi restoration announces "Wi-Fi connected, searching for speakers" once, (d) the "Search again" button announces "Search again for speakers", (e) the `ConnectionStatusChip` announces the appropriate per-state label per T-5503.
  *Depends on: T-5508.*

- [ ] **T-5517** (deferred: manual verification on device) Reduce Motion verification: enable Reduce Motion in iOS Settings and confirm (a) pre-settle pulse rings reduce to a single static ring at 0.1 opacity, (b) orb idle pulse suspends in pre-settle state, (c) `PlaybackBars` in both the session card and the bottom bar render statically at midpoint values, (d) state transition cross-fades use opacity only (no scale), (e) the in-place feedback pulse from F1 is omitted entirely (covered by F1's spec — no F3 tasks required).
  *Depends on: T-5506, T-5507.*

---

## Recommended Implementation Order

1. **E-54 T-5401** (extract `PlaybackBars`) — lifts first because it is a pure refactor that unblocks both the bottom bar work and avoids merge conflicts when E-54 and E-52 land in parallel.

2. **E-52 in full (T-5201–T-5210)** — the session strip is the largest visual change and the most likely to surface layout issues that need iteration. Land it first so the rest can build against the new `cardArea` shape.

3. **E-53 in full (T-5301–T-5310)** — depends only on `SpeakerCard.swift` accepting a new optional input; can land in parallel with E-52 once T-5201 (the `SessionStripView` skeleton) exists, because E-53 T-5306 wires the chip row through `SessionStripView`.

4. **E-54 T-5402–T-5410** — depends on E-52 T-5202 (the two-way binding) being in place for end-to-end verification, but the pill rendering work (T-5403 / T-5404) and the connector line (T-5406) can land beforehand.

5. **E-55 in full (T-5501–T-5517)** — wraps the entire `cardArea` with the state-machine routing. T-5505 must land last among E-55's HomeView edits because it consolidates all branches. T-5511 (auto-retry) and T-5513 (offline-aware voice gating) round out the behavioural surface.

A reasonable team sequence (one full-stack iOS engineer, three working weeks):

```
Week 1:   T-5401 (extract PlaybackBars)
          T-5201–T-5208 (SessionStripView + page dots + parallax)
          T-5209, T-5210 (manual + VoiceOver verification of strip)

Week 2:   T-5301–T-5308 (group chip row + SpeakerCard mount + localisation)
          T-5309, T-5310 (chip row verification)
          T-5402–T-5408 (PlaybackBars in pill, group connector, always-visible bar)
          T-5409, T-5410 (bottom bar verification)

Week 3:   T-5501, T-5502 (NetworkMonitor + HomeView wiring)
          T-5503, T-5504 (ConnectionStatusChip rewrite)
          T-5506, T-5507, T-5508 (PulseRingsView + DiscoveryStateView + a11y announcements)
          T-5505 (HomeView state-machine routing)
          T-5509 (transition animations)
          T-5510, T-5511 (restart() + 30 s auto-retry)
          T-5512, T-5513 (hide voice/bar offline; gate startListening)
          T-5514 (localisation top-up)
          T-5515, T-5516, T-5517 (full-state-machine verification, VoiceOver, Reduce Motion)
```

---

## Task Summary

| Epic | Tasks | Notes |
|---|---|---|
| E-52 Session card strip | 10 | T-5201–T-5210. New `SessionStripView` + `SessionPageDots`, two-way binding with bottom bar, single-session fallback, front-most parallax, manual + VoiceOver verification. |
| E-53 Session card group chip row | 10 | T-5301–T-5310. New `GroupChipRow`, "+N more" overflow, `SpeakerCard` mount, localisation, manual + VoiceOver verification. |
| E-54 Bottom bar redesign | 10 | T-5401–T-5410. Extract `PlaybackBars`, refactor `SpeakerSelectorPill` to render bars + connector line, always-visible bar, manual + VoiceOver verification. |
| E-55 Discovery and offline states | 17 | T-5501–T-5517. New `NetworkMonitor`, `ConnectionStatusChip` rewrite, `PulseRingsView` + `DiscoveryStateView`, home-screen state machine, 30 s auto-retry, offline voice gating, manual + VoiceOver + Reduce Motion verification. |
| **Total** | **47** | All work in the existing iOS Xcode target. No new repositories, no new build settings, no pbxproj edits (`PBXFileSystemSynchronizedRootGroup` auto-includes new `.swift` files). |

---

## Amendment History

| Date | Source | Change |
|---|---|---|
| 2026-05-09 | Initial draft | First version of the home screen redesign epics and tasks (E-52–E-55, T-5201–T-5517). Derived from approved spec `spec-home-screen-redesign.md` v1.0 and design spec `design-spec-home-screen-redesign.md` v1.2. |
| 2026-05-11 | architect-review-v1.4.md | T-5501: `NetworkMonitor.isOnWifi` and `isAvailable` default to `true` (was `false`) per ADR D2 revision — avoids offline-state flash during the brief window between view mount and the first `pathUpdateHandler` callback. |
| 2026-05-11 | E-54 implementation | T-5401, T-5402, T-5403, T-5404, T-5405, T-5406, T-5408 marked complete. T-5407, T-5409, T-5410 marked blocked on E-52 T-5202. |
