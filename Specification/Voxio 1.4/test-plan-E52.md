# Test Plan — E-52 Session Card Strip

**Status:** Draft
**Date:** 2026-05-11
**Refs:** ADR-E52-session-card-strip.md, spec-home-screen-redesign.md US-60/US-61/US-62, design-spec-home-screen-redesign.md §3/§3.3, epics-and-tasks-home-screen-redesign.md E-52

---

## 1. Scope

This plan covers the testable interface contract introduced by E-52: the `SessionStripView` two-way binding with `selectedSpeaker`, the `SessionPageDots` rendering rules, the `HomeView.cardArea` three-branch routing, the single-session no-regression requirement, the parallax forwarding rule, the card insertion/removal scroll-position policy, and the re-entrancy guard that prevents the two `onChange` observers from looping.

The plan tests against the public interface contract defined in ADR-E52-session-card-strip.md §7. Every ADR §7 behavioural assertion (1–10) and every relevant AC from US-60, US-61, and US-62 is covered by at least one TC.

What is out of scope:

- E-53 group chip row internals (separate epic, tested separately once E-53 lands).
- E-54 `SpeakerSelectorPill` pill rendering (tested in `test-plan-E54.md`).
- E-55 discovery and offline state machine (separate epic).
- F1 touch playback controls and F2 multiroom drag-and-drop destination wiring.
- Backend, telemetry, CI/CD.
- The E-54 tasks blocked on T-5202 (TC-E54-A08/A09/A10 remain in `test-plan-E54.md` §10 and are unblocked when T-5202 merges, not within this plan).

---

## 2. Test Environment

| Item | Value |
|---|---|
| Platform | iOS 26, iPhone (portrait) |
| Framework | SwiftUI, `@Observable @MainActor` |
| Test harness | XCTest (unit) + XCUITest (UI/acceptance) — no separate test target exists in the repo at plan-authoring time. Tests are written as specifications; an engineer creating the test target should place unit tests in a new `VoxioTests` target and UI tests in `VoxioUITests`. |
| Accessibility testing | Xcode Accessibility Inspector + VoiceOver on device/simulator |
| Reduce Motion | iOS Settings → Accessibility → Motion → Reduce Motion |
| Speaker doubles | `SpeakerStub` and `SpeakerGroupStub` value types sufficient for all unit/integration TCs; real `SpeakerGroup` and `Speaker` models used where `@testable import Voxio` grants access. |
| Source files under test | `iOS/Voxio/Features/Home/SessionStripView.swift`, `iOS/Voxio/Features/Home/SessionPageDots.swift`, `iOS/Voxio/Features/Home/HomeView.swift` |
| Screen-width stub | For unit TCs that must compute `cardWidth`, inject the screen width via a test hook or verify the formula indirectly through layout assertions. |

---

## 3. Unit-Level Test Cases (SessionPageDots)

These cases test the `SessionPageDots` struct in isolation. They are host-app tests using ViewInspector or equivalent snapshot infrastructure, or plain XCTest assertions where view-modifier values can be inspected via `@testable import Voxio`.

---

### TC-E52-U01

**ID:** TC-E52-U01
**Target:** `SessionPageDots`
**Setup:** Instantiate `SessionPageDots(count: 0, selectedIndex: 0)`.
**Action:** Inspect the rendered view type.
**Expected:** The view returns `EmptyView()` — not an empty `HStack`, not a zero-height `VStack`. No dot shapes are present in the hierarchy. No crash. The count-zero path is the same type as count-one (both return `EmptyView()`).
**Covers ADR contract assertion:** §7 SessionPageDots behavioural contract #6 (returns `EmptyView()` when `count <= 1`)
**Covers spec AC:** US-60 AC-7 (single-session: no page dots)

---

### TC-E52-U02

**ID:** TC-E52-U02
**Target:** `SessionPageDots`
**Setup:** Instantiate `SessionPageDots(count: 1, selectedIndex: 0)`.
**Action:** Inspect the rendered view type.
**Expected:** The view returns `EmptyView()`. Identical to the count-zero case. A single-session strip shows no page dots per spec §3.3 and US-60 AC-7.
**Covers ADR contract assertion:** §7 SessionPageDots behavioural contract #6
**Covers spec AC:** US-60 AC-7; design-spec §3.6 (single-session fallback)

---

### TC-E52-U03

**ID:** TC-E52-U03
**Target:** `SessionPageDots`
**Setup:** Instantiate `SessionPageDots(count: 2, selectedIndex: 0)`.
**Action:** Inspect the view hierarchy for `Circle` shapes, their sizes, and fill colours.
**Expected:** Exactly 2 `Circle` shapes are present. The circle at index 0 (active) has a diameter of 8 pt and a fill of `BeoColor.accent`. The circle at index 1 (inactive) has a diameter of 6 pt and a fill of `BeoColor.muted` at 0.4 opacity. Spacing between dots is `Spacing.s8`. No extra dot shapes are present.
**Covers ADR contract assertion:** §7 SessionPageDots behavioural contracts #1 (active dot: 8 pt, `BeoColor.accent`), #2 (inactive: 6 pt, `BeoColor.muted` at 0.4 opacity), #3 (spacing `Spacing.s8`)
**Covers spec AC:** US-60 AC-4 (page dots: active and inactive styling); design-spec §3.3

---

### TC-E52-U04

**ID:** TC-E52-U04
**Target:** `SessionPageDots`
**Setup:** Instantiate `SessionPageDots(count: 3, selectedIndex: 1)`.
**Action:** Inspect the fill colours and sizes of all three dots in order.
**Expected:** Dot at index 0: 6 pt, `BeoColor.muted` at 0.4 opacity (inactive). Dot at index 1: 8 pt, `BeoColor.accent` (active). Dot at index 2: 6 pt, `BeoColor.muted` at 0.4 opacity (inactive). Exactly 3 dots present. The `selectedIndex` correctly drives the active position — not always index 0.
**Covers ADR contract assertion:** §7 SessionPageDots behavioural contract #1, #2 (active index is parameter-driven)
**Covers spec AC:** US-60 AC-4

---

### TC-E52-U05

**ID:** TC-E52-U05
**Target:** `SessionPageDots` — many sessions (boundary: 8)
**Setup:** Instantiate `SessionPageDots(count: 8, selectedIndex: 7)`.
**Action:** Count the rendered dot shapes. Inspect the last dot (index 7) for active styling and all others for inactive styling.
**Expected:** Exactly 8 dots present. Dot at index 7 is active (8 pt, `BeoColor.accent`). All other 7 dots are inactive (6 pt, `BeoColor.muted` at 0.4 opacity). No crash. Layout does not overflow the HStack bounds — the dot row is compact enough to fit within `screenWidth - Spacing.s16 * 2`.
**Covers ADR contract assertion:** §7 SessionPageDots behavioural contracts #1, #2; spec NFR ("up to 8 concurrent sessions render without dropped frames")
**Covers spec AC:** US-60 AC-4; NFR boundary

---

### TC-E52-U06

**ID:** TC-E52-U06
**Target:** `SessionPageDots` — `.accessibilityHidden(true)`
**Setup:** Instantiate `SessionPageDots(count: 3, selectedIndex: 0)`.
**Action:** Inspect the `.accessibilityHidden` modifier on the outermost container of the returned view.
**Expected:** `.accessibilityHidden(true)` is applied to the root view. The dots do not appear in the accessibility element tree. VoiceOver does not focus any dot shape. This applies regardless of `count` or `selectedIndex`.
**Covers ADR contract assertion:** §7 SessionPageDots behavioural contract #5 (`.accessibilityHidden(true)`)
**Covers spec AC:** US-60 AC-5 (page dots not interactive); design-spec §3.7 ("Page dots: `accessibilityHidden(true)`")

---

### TC-E52-U07

**ID:** TC-E52-U07
**Target:** `SessionPageDots` — Reduce Motion (no scale change)
**Setup:** Instantiate `SessionPageDots(count: 3, selectedIndex: 0)`. Set `@Environment(\.accessibilityReduceMotion) = false`. Trigger `selectedIndex` change from 0 to 1.
**Action:** Inspect the animation descriptor applied to the active-index transition.
**Expected:** Active-index changes animate with `BeoAnimation.toast` (200 ms). The animation involves an opacity cross-fade between old and new active dot.

**Setup (Reduce Motion variant):** Set `@Environment(\.accessibilityReduceMotion) = true`. Repeat the `selectedIndex` change.
**Expected (Reduce Motion):** Only an opacity transition is applied — no scale change (the dot does not grow/shrink as it activates). The 200 ms timing may still apply; what is absent is any `scaleEffect` modifier transition. No crash.
**Covers ADR contract assertion:** §7 SessionPageDots behavioural contract #4 (animate with `BeoAnimation.toast`; Reduce Motion: opacity-only, no scale)
**Covers spec AC:** US-60 AC-4; design-spec §Motion ("Page indicator: dot scale + opacity cross-fade on `BeoAnimation.toast`. Reduce Motion: opacity only, no scale")

---

## 4. Unit-Level Test Cases (SessionStripView Binding Helpers)

These cases test the observable outcomes of the internal `scrollHostId` logic and the two `onChange` handlers by driving the `selectedSpeaker` binding externally and observing the resulting `scrollHostId` state, or by asserting the absence of an infinite loop. Where `scrollHostId` is `private`, assertions are made via observable side-effects (which card appears selected in the rendered hierarchy, or which speaker becomes `selectedSpeaker` after a simulated swipe).

---

### TC-E52-U08

**ID:** TC-E52-U08
**Target:** `SessionStripView` — `onChange(of: selectedSpeaker?.id)` sets `scrollHostId` to group host when `selectedSpeaker` is a host
**Setup:** Create two `SpeakerGroup` stubs: group A (host `H_A`, one member `H_A`) and group B (host `H_B`, one member `H_B`). Both hosts `isPlaying = true`. Render `SessionStripView(groups: [A, B], selectedSpeaker: $sel, roll: 0, pitch: 0, isCommandActive: false)` with `sel = H_A` (so strip starts showing card A). 
**Action:** Set `sel = H_B` externally (simulating a pill tap in `SpeakerSelectorPill`). Allow one SwiftUI update cycle.
**Expected:** `scrollHostId` becomes `H_B.id`. The card for group B is now the visible card. The animation used is `BeoAnimation.spring`. No crash.
**Covers ADR contract assertion:** §7 behavioural contract #2 (setting `selectedSpeaker` to a host scrolls the strip)
**Covers spec AC:** US-62 AC-7 (tapping a host-speaker pill scrolls the strip to its card)

---

### TC-E52-U09

**ID:** TC-E52-U09
**Target:** `SessionStripView` — `onChange(of: selectedSpeaker?.id)` finds group by member (non-host)
**Setup:** Create group G with host `H` and two members `M1`, `M2`. `H.isPlaying = true`. Render strip with `groups: [G]`, `selectedSpeaker = H`.
**Action:** Set `selectedSpeaker = M1` (a non-host member of G). Allow one update cycle.
**Expected:** `scrollHostId` becomes `H.id` (the group host, not `M1.id`). The strip scrolls to (or remains showing) the card for group G. The non-host member resolves to the group host — there is no attempt to find a card for `M1` directly.
**Covers ADR contract assertion:** §7 behavioural contract #3 (setting `selectedSpeaker` to a non-host member scrolls to the group's host card)
**Covers spec AC:** US-62 AC-7 (non-host group member: strip scrolls to the group's session card)

---

### TC-E52-U10

**ID:** TC-E52-U10
**Target:** `SessionStripView` — idle-speaker tap: `scrollHostId` unchanged
**Setup:** Create one playing group G (host `H`, `isPlaying = true`) and one idle speaker `I` not in any playing group. Render strip with `groups: [G]`, `selectedSpeaker = H`.
**Action:** Set `selectedSpeaker = I` externally. Allow one update cycle.
**Expected:** `scrollHostId` does NOT change — it remains `H.id`. The strip continues to show card for G. The idle speaker belongs to no playing group, so the `onChange(of: selectedSpeaker?.id)` handler skips the scroll animation entirely. No crash.
**Covers ADR contract assertion:** §7 behavioural contract #4 (idle-speaker tap: `scrollHostId` unchanged)
**Covers spec AC:** US-62 AC-7 (idle pill tap does not scroll the strip)

---

### TC-E52-U11

**ID:** TC-E52-U11
**Target:** `SessionStripView` — re-entrancy guard prevents `onChange` loop
**Setup:** Create two groups A (host `H_A`) and B (host `H_B`). Both playing. Render strip with `groups: [A, B]`, `selectedSpeaker = H_A`, so `scrollHostId = H_A.id`.
**Action:** Set `selectedSpeaker = H_A` again (same value — simulating the strip's own `onChange(of: scrollHostId)` writing back the same speaker). Allow multiple update cycles.
**Expected:** `scrollHostId` is NOT rewritten. The `onChange(of: selectedSpeaker?.id)` handler's guard `group.hostSpeaker.id != scrollHostId` evaluates to `false` and exits without calling `withAnimation`. No animation fires. No observable loop (the binding update count is bounded — at most one change per direction per interaction). The view renders stably without repeated re-renders.
**Covers ADR contract assertion:** §7 behavioural contract — re-entrancy guard (ADR §5 Consequences: "Implementer must include this guard")
**Covers spec AC:** N/A (architectural invariant, not a user-facing AC)

---

### TC-E52-U12

**ID:** TC-E52-U12
**Target:** `SessionStripView` — `onChange(of: scrollHostId)` writes `selectedSpeaker`
**Setup:** Create two groups A (host `H_A`) and B (host `H_B`). Both playing. Render strip with `groups: [A, B]`, `selectedSpeaker = H_A`.
**Action:** Simulate the user swiping the strip from card A to card B (trigger `scrollHostId = H_B.id` as the `ScrollView` position settles). Allow one update cycle.
**Expected:** `selectedSpeaker` becomes `H_B`. The bottom bar's selected pill changes to `H_B`'s pill within one SwiftUI update cycle. The `onChange(of: scrollHostId)` handler finds the group whose `hostSpeaker.id == H_B.id` and assigns that host speaker.
**Covers ADR contract assertion:** §7 behavioural contract #1 (swiping strip causes `selectedSpeaker` to become the new card's host)
**Covers spec AC:** US-60 AC-6 (visible card change → selected speaker in bottom bar); US-62 AC-8

---

### TC-E52-U13

**ID:** TC-E52-U13
**Target:** `SessionStripView` — `onChange(of: scrollHostId)` with nil (empty strip edge case)
**Setup:** Render `SessionStripView(groups: [], selectedSpeaker: $sel, roll: 0, pitch: 0, isCommandActive: false)`. `scrollHostId` resolves to `nil` because no cards exist.
**Action:** Allow the view to render and the `scrollHostId` onChange to fire.
**Expected:** `selectedSpeaker` is NOT changed (it is left in whatever state the caller passed). No crash. The `onChange(of: scrollHostId)` nil guard exits without writing to `selectedSpeaker`. The view body renders the empty-group branch (in practice, `HomeView.cardArea` routing should prevent this call when no playing groups exist — but the component itself is defensive).
**Covers ADR contract assertion:** §7 behavioural contract #1 (if `scrollHostId` resolves to nil, do not change `selectedSpeaker`)
**Covers spec AC:** N/A (defensive edge case; `HomeView` routing prevents this in normal operation)

---

## 5. Integration Test Cases (SessionStripView View)

These cases render `SessionStripView` in a host view and assert on visible output or layout properties. They require `SpeakerGroup` stubs and a `@State var selectedSpeaker: Speaker?` binding in a host view wrapper.

---

### TC-E52-I01

**ID:** TC-E52-I01
**Target:** `SessionStripView` — card width formula (multi-session)
**Setup:** Create two playing groups A and B. Determine `screenWidth` via `UIApplication.shared.connectedScenes` (or stub the value). Render `SessionStripView(groups: [A, B], ...)`.
**Action:** Inspect the `.frame(width:)` modifier on each `SpeakerCard` wrapper inside the `LazyHStack`.
**Expected:** Each card's frame width equals `screenWidth - (Spacing.s16 * 2)`. The 8 pt trailing peek is created by natural overflow — no additional trailing-clip magic needed. The card width does NOT include an extra 8 pt subtraction; the peek emerges from the `ScrollView`'s content overflowing the available width.
**Covers ADR contract assertion:** §7 behavioural contract #4 (card sizing: `screenWidth - (Spacing.s16 * 2)` when `groups.count > 1`)
**Covers spec AC:** US-60 AC-2 (each card occupies `screenWidth - Spacing.s16` on each side; next card peeks at 8 pt); design-spec §3.3

---

### TC-E52-I02

**ID:** TC-E52-I02
**Target:** `SessionStripView` — single-session card width equals multi-session card width; scroll disabled
**Setup:** Create exactly one playing group G. Render `SessionStripView(groups: [G], ...)`.
**Action:** Inspect the card's `.frame(width:)` and check for `.scrollDisabled(true)` on the `ScrollView`. Also check for absence of any trailing peek (no adjacent card visible).
**Expected:** Card frame width equals `screenWidth - (Spacing.s16 * 2)` — the same formula as multi-session (the peek disappears naturally because there is no adjacent card, not because the width is different). `.scrollDisabled(true)` is present OR the card layout produces identical visual output to the v1.3 single-card layout. `SessionPageDots` is absent (verified by TC-E52-U02). No horizontal scroll bounce on swipe attempt.
**Covers ADR contract assertion:** §7 behavioural contract #4 (single-session: `effectiveCardWidth = screenWidth - (Spacing.s16 * 2)`, `.scrollDisabled(true)`, no page dots)
**Covers spec AC:** US-60 AC-7 (single-session: no peek, no page dots, no scroll affordance); design-spec §3.6 (single-session fallback)

---

### TC-E52-I03

**ID:** TC-E52-I03
**Target:** `SessionStripView` — screen-width workaround (UIKit path)
**Setup:** Render `SessionStripView` on a device or simulator where the iOS 26 ZStack inflation issue affects `GeometryReader` width. Check the implementation's screen-width acquisition method.
**Action:** Inspect whether `SessionStripView` reads screen width via `UIApplication.shared.connectedScenes` (the UIKit workaround) rather than via a SwiftUI `GeometryReader` or `.frame(maxWidth: .infinity)` approach.
**Expected:** Screen width is read from the UIKit scene, matching the workaround documented in `SpeakerSelectorPill.swift` (ADR §2 "Screen-width workaround"). Cards are correctly sized on iPhone 14 Pro — no oversizing due to ZStack inflation. This is a code-review assertion; the reviewer must verify the implementation does not use `GeometryReader` for the card-width computation.
**Covers ADR contract assertion:** §7 behavioural contract #5 (screen width from `UIApplication.shared.connectedScenes`, not SwiftUI geometry)
**Covers spec AC:** N/A (architectural invariant — ADR §5 Consequences: "code review must verify the workaround is present")

---

### TC-E52-I04

**ID:** TC-E52-I04
**Target:** `SessionStripView` — parallax: only visible card receives non-zero roll/pitch
**Setup:** Create three playing groups A, B, C. Render strip with `roll: 5.0, pitch: 3.0`. The strip starts with `scrollHostId = H_A.id` (group A's host is visible).
**Action:** Inspect the `roll` and `pitch` arguments passed to each `SpeakerCard` in the `ForEach`.
**Expected:** The card for group A receives `roll: 5.0, pitch: 3.0`. The cards for groups B and C receive `roll: 0, pitch: 0`. When the user swipes to group B (scrollHostId becomes `H_B.id`), group B's card receives the live roll/pitch and groups A and C receive 0/0.
**Covers ADR contract assertion:** §7 behavioural contract #10 (only `scrollHostId` card receives non-zero roll/pitch; all others receive 0/0)
**Covers spec AC:** design-spec §7 Resolved Decision UQ-7 ("Parallax highlight applies to the front-most visible session card only. Offscreen cards are frozen.")

---

### TC-E52-I05

**ID:** TC-E52-I05
**Target:** `SessionStripView` — page dots rendered below strip when `groups.count > 1`
**Setup:** Create two playing groups A and B. Render strip.
**Action:** Inspect the view hierarchy below the `ScrollView`. Check for `SessionPageDots` presence, its count parameter, and its active index parameter.
**Expected:** `SessionPageDots(count: 2, selectedIndex: ...)` is rendered below the `ScrollView`, separated by `Spacing.s8` vertical padding. The `activeIndex` matches the index of the currently visible group in the `groups` array. The two components (strip + dots) are wrapped in a `VStack(spacing: 0)` so they move together in `HomeView`.
**Covers ADR contract assertion:** §7 behavioural contract #6 (when `groups.count > 1`, `SessionPageDots(count: groups.count, selectedIndex: activeIndex)` is rendered below the strip, separated by `Spacing.s8`)
**Covers spec AC:** US-60 AC-4 (page dots appear below the strip when more than one session exists); design-spec §3.3

---

### TC-E52-I06

**ID:** TC-E52-I06
**Target:** `SessionStripView` — page dots active index tracks swipe
**Setup:** Create three playing groups A, B, C. Render strip. Active index starts at 0.
**Action:** Simulate swipe to group B (scrollHostId becomes H_B.id). Read the `selectedIndex` passed to `SessionPageDots`.
**Expected:** `selectedIndex` is 1 (the index of group B in the `groups` array). The active dot in `SessionPageDots` moves to position 1. The computation is `groups.firstIndex(where: { $0.hostSpeaker.id == scrollHostId }) ?? 0` per T-5205.
**Covers ADR contract assertion:** §7 (active index derivation drives `SessionPageDots`)
**Covers spec AC:** US-60 AC-3 (visible card change → page dot indicator updates); design-spec §3.3

---

### TC-E52-I07

**ID:** TC-E52-I07
**Target:** `SessionStripView` — card insertion: currently visible card stays visible
**Setup:** Create one playing group A. Render strip with `groups: [A]`, `selectedSpeaker = H_A`. The single card for A is visible.
**Action:** Add a new playing group B to the `groups` array (simulate a speaker starting playback). Allow one update cycle.
**Expected:** The scroll position does NOT jump to group B. `scrollHostId` remains `H_A.id`. The currently visible card (group A) stays in view. Group B's card is inserted into the strip (visible if user swipes right) but does not displace the current view. `SessionPageDots` updates to `count: 2`.
**Covers ADR contract assertion:** §7 behavioural contract #8 (group added: currently-visible card remains visible, `scrollHostId` unchanged)
**Covers spec AC:** US-60 AC-10 (speaker transitions idle → playing: new card inserted without losing current scroll position)

---

### TC-E52-I08

**ID:** TC-E52-I08
**Target:** `SessionStripView` — card removal: visible card removed → `scrollHostId` moves to first remaining
**Setup:** Create two playing groups A and B. Render strip. Swipe to group B (scrollHostId = H_B.id). B's card is visible.
**Action:** Remove group B from the `groups` array (simulate speaker stopping). Allow one update cycle.
**Expected:** `scrollHostId` moves to `groups.first?.hostSpeaker.id` — which is now H_A.id (the first remaining group). The strip animates to show group A's card. `SessionPageDots` updates to `count: 1` (and thus returns `EmptyView()` per TC-E52-U02).
**Covers ADR contract assertion:** §7 behavioural contract #7 (group removed while visible: `scrollHostId` moves to `groups.first?.hostSpeaker.id`)
**Covers spec AC:** US-60 AC-11 (speaker transitions playing → idle: visible card removed → strip animates to nearest remaining session card)

---

### TC-E52-I09

**ID:** TC-E52-I09
**Target:** `SessionStripView` — card removal: non-visible card removed, current position preserved
**Setup:** Create three playing groups A, B, C. Render strip with A visible (scrollHostId = H_A.id).
**Action:** Remove group C (non-visible) from the `groups` array. Allow one update cycle.
**Expected:** `scrollHostId` remains H_A.id. The strip continues to show group A's card. Group C's card disappears from the trailing end of the strip without disrupting the current view. `SessionPageDots` updates to `count: 2`. The `onChange(of: groups.map(\.id))` guard correctly identifies that the currently-visible host (H_A) is still in the new set and does NOT reset `scrollHostId`.
**Covers ADR contract assertion:** §7 behavioural contract #8 (variant: removing a non-visible card should not displace the current view)
**Covers spec AC:** US-60 AC-11 (stopping a non-visible session removes its card without animation jank)

---

### TC-E52-I10

**ID:** TC-E52-I10
**Target:** `SessionStripView` — `LazyHStack` uses `.id(group.id)` per card for stable diffing
**Setup:** Create three playing groups A, B, C. Render strip. Note the initial rendering order.
**Action:** Remove group A from `groups`. Allow one update cycle. Inspect the rendered card identities.
**Expected:** SwiftUI correctly removes only group A's card. Groups B and C remain in the hierarchy with their existing SwiftUI node identities — no full re-render of the remaining cards. This confirms the `.id(group.id)` modifier is present on each card in the `ForEach`. (Code-review assertion: the `ForEach` uses `ForEach(groups, id: \.id)` or per-element `.id(group.id)`.)
**Covers ADR contract assertion:** §7 behavioural contract #6 (LazyHStack with `.id(group.id)` per card for SwiftUI diffing); ADR §4 (LazyHStack diffing for card insertion/removal)
**Covers spec AC:** US-60 AC-10, AC-11 (card insertion/removal without reordering or jank)

---

## 6. Acceptance Test Cases (HomeView cardArea Routing)

These cases test the three-branch routing in `HomeView.cardArea` introduced by T-5206, plus the `playingGroups` computed property. They are integration/acceptance-level and may be implemented as XCUITest or snapshot tests against a stubbed `SpeakerDiscoveryService`.

---

### TC-E52-A01

**ID:** TC-E52-A01
**Target:** `HomeView.cardArea` — branch 1: `playingGroups` non-empty → `SessionStripView`
**Setup:** Stub `SpeakerDiscoveryService.groups` to return two groups, both with `hostSpeaker.isPlaying = true`. `displayedSpeaker` may be either host. Render `HomeView`.
**Action:** Inspect which component is rendered in the `cardArea` region.
**Expected:** `SessionStripView` is rendered (not `SpeakerCard` directly, not `emptyState`). `SessionStripView` receives `groups: playingGroups` (the two playing groups), `selectedSpeaker: $selectedSpeaker`, `roll:`, `pitch:`, and `isCommandActive:` from `HomeView`'s own motion/state. The existing `SpeakerCard` direct render path is absent.
**Covers ADR contract assertion:** §7 HomeView `cardArea` routing shape (`!playingGroups.isEmpty` → `SessionStripView`)
**Covers spec AC:** US-60 AC-1 (when two or more groups are playing, home screen shows the session strip)

---

### TC-E52-A02

**ID:** TC-E52-A02
**Target:** `HomeView.cardArea` — branch 2: `playingGroups` empty but `displayedSpeaker` non-nil → existing `SpeakerCard`
**Setup:** Stub discovery to return one group whose `hostSpeaker.isPlaying = false`. `displayedSpeaker` is non-nil (the idle speaker). Render `HomeView`.
**Action:** Inspect the `cardArea` region.
**Expected:** `SpeakerCard(speaker: displayedSpeaker, isExpanded: isCommandActive, roll: motionManager.roll, pitch: motionManager.pitch)` is rendered directly (the v1.3 single-idle-card path). The card has `.opacity(hasAppeared ? 1 : 0)` and `.scaleEffect(hasAppeared ? 1 : 0.96)` modifiers. `SessionStripView` is NOT rendered.
**Covers ADR contract assertion:** §7 HomeView `cardArea` routing shape (`playingGroups.isEmpty && displayedSpeaker != nil` → existing `SpeakerCard`)
**Covers spec AC:** US-60 AC-8 (idle speakers never appear as session cards); design-spec §3.2 ("An idle speaker → no session card; only visible in the bottom bar")

---

### TC-E52-A03

**ID:** TC-E52-A03
**Target:** `HomeView.cardArea` — branch 3: `playingGroups` empty and `displayedSpeaker` nil → `emptyState`
**Setup:** Stub discovery to return an empty groups array. `displayedSpeaker` resolves to nil. Render `HomeView`.
**Action:** Inspect the `cardArea` region.
**Expected:** The existing `emptyState` view is rendered. `SessionStripView` is NOT rendered. `SpeakerCard` is NOT rendered. This is the zero-speakers empty state, unchanged from v1.3 (E-55 will later wrap this path with the state-machine routing; for E-52 alone, the empty path remains the existing `emptyState`).
**Covers ADR contract assertion:** §7 HomeView `cardArea` routing shape (`playingGroups.isEmpty && displayedSpeaker == nil` → `emptyState`)
**Covers spec AC:** US-60 AC-8 (zero playing groups: empty/idle card area shown)

---

### TC-E52-A04

**ID:** TC-E52-A04
**Target:** `HomeView` — `playingGroups` computed property filters by `hostSpeaker.isPlaying`
**Setup:** Stub three groups: group A (`hostSpeaker.isPlaying = true`), group B (`hostSpeaker.isPlaying = false`), group C (`hostSpeaker.isPlaying = true`). Render `HomeView`.
**Action:** Read `playingGroups` directly (via `@testable import`) or observe which groups appear as cards in the `SessionStripView`.
**Expected:** `playingGroups` contains exactly groups A and C. Group B (idle host) is excluded. `SessionStripView` renders exactly two cards (one per playing group). The filter is `discovery.groups.filter { $0.hostSpeaker.isPlaying }` — no other predicate is applied.
**Covers ADR contract assertion:** §7 HomeView `playingGroups` property definition
**Covers spec AC:** US-60 AC-9 (idle/stopped speakers never appear as session cards)

---

### TC-E52-A05

**ID:** TC-E52-A05
**Target:** `HomeView` — speaker transitions idle → playing inserts new session card
**Setup:** Stub one playing group A and one idle speaker B (not yet in any playing group). `HomeView` renders `SessionStripView` with one card for A.
**Action:** Mutate `B.isPlaying = true` (and ensure B's `SpeakerGroup` host is B). Allow `HomeView` to re-evaluate `playingGroups`.
**Expected:** `SessionStripView` now receives two groups (A and B's group). A second card for B is inserted into the strip. The currently visible card (A's) remains visible. `SessionPageDots` appears with `count: 2`. No crash or full re-layout of the card area.
**Covers ADR contract assertion:** §7 behavioural contract #8 (card added: currently-visible unchanged)
**Covers spec AC:** US-60 AC-10

---

### TC-E52-A06

**ID:** TC-E52-A06
**Target:** `HomeView` — speaker transitions playing → idle removes session card; fallback if last session
**Setup:** Stub one playing group A. `HomeView` renders `SessionStripView` with one card for A.
**Action:** Mutate `H_A.isPlaying = false`. Allow `HomeView` to re-evaluate `playingGroups`.
**Expected:** `playingGroups` becomes empty. `HomeView.cardArea` switches to branch 2 (existing `SpeakerCard`) if `displayedSpeaker != nil`, or branch 3 (`emptyState`) if `displayedSpeaker == nil`. `SessionStripView` is unmounted. No crash. The transition uses the existing `.opacity` and `.scaleEffect` entry animation if entering the idle card path.
**Covers ADR contract assertion:** §7 HomeView routing — falls back to non-strip branch when `playingGroups` empties
**Covers spec AC:** US-60 AC-11 (playing → idle while it was the visible card → strip transitions to empty/idle card)

---

### TC-E52-A07

**ID:** TC-E52-A07
**Target:** `HomeView` — `SessionStripView` call-site parameter shape
**Setup:** Read the `HomeView.cardArea` source (code review) or inspect the rendered call through `@testable import`.
**Action:** Confirm that `SessionStripView` is initialised with exactly the five parameters specified in ADR §7: `groups: playingGroups`, `selectedSpeaker: $selectedSpeaker`, `roll: motionManager.roll`, `pitch: motionManager.pitch`, `isCommandActive: isCommandActive`. No additional parameters are present; no E-52 parameters are missing.
**Expected:** The call site compiles with the ADR §7 signature. `selectedSpeaker` is the same `@State` variable passed to `SpeakerSelectorPill` — they share the same binding source (no separate `@State` was added for the strip). The shared binding is the mechanism that creates two-way sync between the strip and the pill.
**Covers ADR contract assertion:** §7 HomeView call-site shape
**Covers spec AC:** US-62 AC-8 (visible card's host is selected pill — requires the shared binding)

---

### TC-E52-A08

**ID:** TC-E52-A08
**Target:** `HomeView` + `SessionStripView` — end-to-end: swipe strip → pill changes selection
**Setup:** Stub two playing speakers H_A and H_B (each in their own group). Render full `HomeView`. `selectedSpeaker` starts as `H_A`. Strip shows card A. Pill for H_A is selected in `SpeakerSelectorPill`.
**Action:** Simulate swiping the strip from card A to card B (XCUITest gesture on the strip, or programmatically settle `scrollHostId` to H_B.id). Allow the `onChange(of: scrollHostId)` handler to fire.
**Expected:** `selectedSpeaker` becomes `H_B`. The pill for `H_B` in `SpeakerSelectorPill` transitions to the selected visual state within one SwiftUI update cycle. This verifies the full loop: swipe → `scrollHostId` change → `selectedSpeaker` update → pill re-render.
**Covers ADR contract assertion:** §7 behavioural contract #1 (swiping strip causes `selectedSpeaker` to become the session host)
**Covers spec AC:** US-62 AC-8; US-60 AC-6

---

### TC-E52-A09

**ID:** TC-E52-A09
**Target:** `HomeView` + `SessionStripView` — end-to-end: pill tap → strip scrolls
**Setup:** Stub two playing speakers H_A and H_B. `selectedSpeaker = H_A`. Strip shows card A.
**Action:** Tap the pill for H_B in `SpeakerSelectorPill` (sets `selectedSpeaker = H_B`). Allow the `onChange(of: selectedSpeaker?.id)` handler to fire.
**Expected:** The strip scrolls to show card B. `scrollHostId` becomes `H_B.id`. The scroll animation uses `BeoAnimation.spring`. This verifies the E-52 half of the cross-epic dependency that was blocking E-54 T-5407/T-5409/T-5410.
**Covers ADR contract assertion:** §7 behavioural contract #2
**Covers spec AC:** US-62 AC-7 (tapping a host pill scrolls the strip); this TC also unblocks TC-E54-A08 in `test-plan-E54.md`

---

## 7. Error States and Boundary Values

---

### TC-E52-E01

**ID:** TC-E52-E01
**Target:** `SessionStripView` — boundary: 0 playing groups
**Setup:** Pass `groups: []` directly to `SessionStripView` (defensive test for the component in isolation; `HomeView` routing normally prevents this call).
**Action:** Render and inspect.
**Expected:** No crash. `scrollHostId` remains nil. `selectedSpeaker` is not changed. `SessionPageDots` is not rendered (count 0 → `EmptyView()`). The view renders nothing visible or a minimal empty container. The component is defensive against this edge case even though the expected caller (`HomeView`) will not reach this path in normal operation.
**Covers ADR contract assertion:** §7 behavioural contract #1 (nil scrollHostId does not change selectedSpeaker)
**Covers spec AC:** Boundary: 0 playing groups

---

### TC-E52-E02

**ID:** TC-E52-E02
**Target:** `SessionStripView` — boundary: 1 playing group, 1 member (solo speaker)
**Setup:** One group G with host H and no additional members. H.isPlaying = true.
**Action:** Render `SessionStripView(groups: [G], ...)`. Inspect layout.
**Expected:** One card rendered. No page dots (TC-E52-U02 confirms count-1 → EmptyView). Card width = `screenWidth - (Spacing.s16 * 2)`. No trailing peek visible. Scroll disabled. `scrollHostId` initialises to `H.id`. `selectedSpeaker` is set to H via the initial `onChange` fire. No crash.
**Covers ADR contract assertion:** §7 behavioural contract #4 (single session: full width, disabled scroll, no dots)
**Covers spec AC:** US-60 AC-7; design-spec §3.6

---

### TC-E52-E03

**ID:** TC-E52-E03
**Target:** `SessionStripView` — boundary: many groups (8 playing sessions)
**Setup:** Create 8 playing groups, each with one member. Render strip.
**Action:** Inspect card count, page dot count, layout stability.
**Expected:** 8 cards render without dropped frames (NFR). `SessionPageDots` renders with `count: 8`. Swiping through all 8 cards works. `selectedSpeaker` updates correctly for each card. No crash or layout overflow. The page dot row for 8 dots (each 6–8 pt + `Spacing.s8` spacing) fits within `screenWidth - (Spacing.s16 * 2)` without clipping.
**Covers ADR contract assertion:** §7 (general robustness at scale)
**Covers spec AC:** NFR: "Up to 8 concurrent sessions render without dropped frames at 60 fps"

---

### TC-E52-E04

**ID:** TC-E52-E04
**Target:** `SessionStripView` — boundary: 1 playing group with many members (6 members)
**Setup:** One group G with host H and 5 additional members. H.isPlaying = true. Render strip.
**Action:** Render `SessionStripView(groups: [G], ...)`. Inspect the card rendered for G.
**Expected:** One card for G. No page dots. Card width correct. `selectedSpeaker` initialises to H. No crash. (The group member chip row is handled by E-53 T-5306 and is out of E-52 scope — the card renders without chips at this stage unless E-53 has also landed.)
**Covers ADR contract assertion:** §7 (general — large group membership does not affect strip logic)
**Covers spec AC:** Boundary: group with many members

---

### TC-E52-E05

**ID:** TC-E52-E05
**Target:** `SessionStripView` — card removal while last remaining card is visible → `groups` becomes empty
**Setup:** One playing group A. Strip shows A (scrollHostId = H_A.id).
**Action:** Remove group A from `groups` (simulates the only playing speaker stopping). Allow one update cycle.
**Expected:** `groups` is now empty. The `onChange(of: groups.map(\.id))` fires. `scrollHostId` is set to `groups.first?.hostSpeaker.id` which is nil. `selectedSpeaker` update from `onChange(of: scrollHostId)` with nil: `selectedSpeaker` is NOT changed (per behavioural contract #1). In practice `HomeView` re-routes to the idle card or empty state in the same update cycle. No crash.
**Covers ADR contract assertion:** §7 behavioural contract #7 (scrollHostId moves to groups.first?.hostSpeaker.id when visible card removed); #1 (nil scrollHostId does not change selectedSpeaker)
**Covers spec AC:** US-60 AC-11 (playing → idle: strip transitions)

---

### TC-E52-E06

**ID:** TC-E52-E06
**Target:** `SessionStripView` — `selectedSpeaker` set to host of non-playing group (group was playing, now stopped, but selectedSpeaker still points to it)
**Setup:** Two groups A (playing) and B (was playing, now stopped). `groups` receives only [A] (B has been filtered out). `selectedSpeaker = H_B` (stale from before B stopped).
**Action:** Render `SessionStripView(groups: [A], ...)` with `selectedSpeaker = H_B`. Allow onChange handlers to fire.
**Expected:** The `onChange(of: selectedSpeaker?.id)` handler looks for a group where H_B is host or member. H_B is not in `groups` (B was filtered out). Handler exits without changing `scrollHostId`. The strip remains on group A's card (or initialises to A's card). No crash. `selectedSpeaker` may be left as H_B — the strip does not forcibly reset it (that is HomeView's concern).
**Covers ADR contract assertion:** §7 behavioural contract #4 (speaker not in any playing group → scrollHostId unchanged); similar logic to idle-speaker tap
**Covers spec AC:** Error state: stale `selectedSpeaker` after group stops

---

### TC-E52-E07

**ID:** TC-E52-E07
**Target:** `SessionStripView` — VoiceOver: swipe gesture does not override VoiceOver swipe
**Setup:** Enable VoiceOver. Render `SessionStripView` with three groups. Navigate to the session card region using VoiceOver.
**Action:** Perform the standard VoiceOver horizontal swipe gesture (one-finger swipe right to advance focus).
**Expected:** VoiceOver focus advances to the next accessibility element (next session card or next focusable element) rather than triggering the native `ScrollView` paging gesture. The two gesture systems do not conflict. This is consistent with the spec requirement that "Swipe gesture does not override VoiceOver swipe" (US-60 last AC).
**Covers ADR contract assertion:** N/A (VoiceOver conformance — spec requirement)
**Covers spec AC:** US-60 last AC (VoiceOver users navigate session cards in standard element-focus order; swipe gesture does not interfere)

---

### TC-E52-E08

**ID:** TC-E52-E08
**Target:** `HomeView` — all speakers transition from playing → idle; routing falls back gracefully
**Setup:** Two playing groups A and B. `HomeView` shows `SessionStripView`. `selectedSpeaker = H_A`.
**Action:** Set both H_A.isPlaying and H_B.isPlaying to false in the same update. Allow `HomeView` to re-evaluate.
**Expected:** `playingGroups` becomes empty. `HomeView.cardArea` switches to the idle-speaker or empty-state branch. `SessionStripView` is unmounted. No crash. `selectedSpeaker` is either retained or set to nil by `HomeView`'s existing logic (E-52 does not specify a `selectedSpeaker` reset policy here — the existing `HomeView` policy is the regression baseline).
**Covers ADR contract assertion:** §7 HomeView routing — fallback when all groups become idle
**Covers spec AC:** Error state: "All speakers disappear (e.g. all powered off) post-discovery"; US-60 AC-8

---

### TC-E52-E09

**ID:** TC-E52-E09
**Target:** `HomeView` — user swipes strip during card insertion animation
**Setup:** Two playing groups A and B. Strip shows A. Simultaneously: group C is inserted (starts playing) and the user initiates a swipe gesture toward B.
**Action:** Let both the animation and the swipe compete. Allow SwiftUI to resolve.
**Expected:** The native `ScrollView` paging handles the gesture. The swipe wins (or completes after the animation); no crash or corrupt `scrollHostId` state. The final visible card is deterministic — either B (if the swipe completed) or the result of the insertion diffing. The key assertion is no crash and no stale `scrollHostId` pointing to a group not in `groups`.
**Covers ADR contract assertion:** §7 (robustness — spec error state: "User swipes the session strip during a card insertion/removal animation")
**Covers spec AC:** Error state: spec-home-screen-redesign.md error states table row "User swipes the session strip during a card insertion/removal animation"

---

## 8. Coverage Matrix (AC/ER → TC IDs)

| AC / Contract Assertion | TC IDs | Status |
|---|---|---|
| **ADR §7 behavioural contract #1** — swipe → `selectedSpeaker` = group host | TC-E52-U12, TC-E52-A08 | Covered |
| **ADR §7 behavioural contract #2** — setting `selectedSpeaker` to a host scrolls strip | TC-E52-U08, TC-E52-A09 | Covered |
| **ADR §7 behavioural contract #3** — setting `selectedSpeaker` to a non-host member scrolls to group host card | TC-E52-U09 | Covered |
| **ADR §7 behavioural contract #4** — setting `selectedSpeaker` to idle speaker: `scrollHostId` unchanged | TC-E52-U10, TC-E52-A09 (idle sub-case via TC-E54-A05) | Covered |
| **ADR §7 behavioural contract #5** — `groups.count == 1`: scroll-disabled, no peek, no dots | TC-E52-U02, TC-E52-I02, TC-E52-E02 | Covered |
| **ADR §7 behavioural contract #6** — `groups.count > 1`: `SessionPageDots` rendered below strip with `Spacing.s8` | TC-E52-I05, TC-E52-I06 | Covered |
| **ADR §7 behavioural contract #7** — visible card removed: `scrollHostId` → `groups.first?.hostSpeaker.id` | TC-E52-I08, TC-E52-E05 | Covered |
| **ADR §7 behavioural contract #8** — card added: currently-visible unchanged | TC-E52-I07, TC-E52-A05 | Covered |
| **ADR §7 behavioural contract #9** — `SessionPageDots` `.accessibilityHidden(true)` | TC-E52-U06 | Covered |
| **ADR §7 behavioural contract #10** — only visible card receives non-zero roll/pitch | TC-E52-I04 | Covered |
| **Re-entrancy guard** — `onChange` loop prevented by `hostSpeaker.id != scrollHostId` check | TC-E52-U11 | Covered |
| **Screen-width workaround** — UIKit `connectedScenes` path (not GeometryReader) | TC-E52-I03 | Covered (code review) |
| **US-60 AC-1** — two or more playing groups → horizontal session strip | TC-E52-A01 | Covered |
| **US-60 AC-2** — card width = `screenWidth - Spacing.s16 * 2`; 8 pt trailing peek | TC-E52-I01 | Covered |
| **US-60 AC-3** — swipe snaps to alignment; no half-page positions | TC-E52-A08 (manual verification); T-5209 is the formal sign-off | Covered (manual) |
| **US-60 AC-4** — page dots: active 8 pt `BeoColor.accent`; inactive 6 pt `BeoColor.muted` 0.4 opacity; one per session | TC-E52-U03, TC-E52-U04, TC-E52-I05 | Covered |
| **US-60 AC-5** — page dots not interactive; `accessibilityHidden(true)` | TC-E52-U06 | Covered |
| **US-60 AC-6** — visible card change → session host becomes selected in bottom bar | TC-E52-U12, TC-E52-A08 | Covered |
| **US-60 AC-7** — single session: no peek, no dots, no scroll affordance | TC-E52-U02, TC-E52-I02, TC-E52-E02 | Covered |
| **US-60 AC-8** — zero sessions: existing empty/idle card area shown | TC-E52-A03, TC-E52-A06 | Covered |
| **US-60 AC-9** — idle/stopped speakers never appear as session cards | TC-E52-A02, TC-E52-A04 | Covered |
| **US-60 AC-10** — idle → playing: new card inserted, current position preserved | TC-E52-I07, TC-E52-A05 | Covered |
| **US-60 AC-11** — playing → idle: visible card removed → nearest remaining; VoiceOver no conflict | TC-E52-I08, TC-E52-A06, TC-E52-E05, TC-E52-E07 | Covered |
| **US-62 AC-7** — tapping pill scrolls strip (host case) | TC-E52-A09 | Covered |
| **US-62 AC-7** — tapping pill scrolls strip (non-host member case) | TC-E52-U09 | Covered |
| **US-62 AC-7** — idle-speaker tap: strip does NOT scroll | TC-E52-U10 | Covered |
| **US-62 AC-8** — visible card's host is selected pill | TC-E52-U12, TC-E52-A08 | Covered |
| **Error state: all speakers stop** | TC-E52-E08, TC-E52-A06 | Covered |
| **Error state: swipe during insertion animation** | TC-E52-E09 | Covered |
| **Error state: stale selectedSpeaker after group stops** | TC-E52-E06 | Covered |
| **Boundary: 0 playing groups** | TC-E52-E01, TC-E52-A03 | Covered |
| **Boundary: 1 playing group** | TC-E52-E02, TC-E52-I02 | Covered |
| **Boundary: 8 playing groups** | TC-E52-E03, TC-E52-U05 | Covered |
| **Boundary: 1-member group (solo speaker)** | TC-E52-E02 | Covered |
| **Boundary: many-member group (6 members)** | TC-E52-E04 | Covered |
| **SessionPageDots: count 0 → EmptyView** | TC-E52-U01 | Covered |
| **SessionPageDots: count 1 → EmptyView** | TC-E52-U02 | Covered |
| **SessionPageDots: count > 1 → dots rendered** | TC-E52-U03, TC-E52-U04, TC-E52-U05 | Covered |
| **SessionPageDots: Reduce Motion → opacity-only, no scale** | TC-E52-U07 | Covered |
| **US-61 (group chip row)** | Out of scope for E-52 | **Deferred to E-53 test plan** |

---

## 9. Spec Gaps Discovered

The following ambiguities or omissions were identified during test-plan authoring. None are implementation blockers; each is flagged for the Spec Author and Architect to resolve before QA sign-off.

**Gap 1 — `scrollHostId` initialisation not specified**

ADR §7 lists `scrollHostId` as a `@State private var scrollHostId: Speaker.ID?` but does not specify the initial value or when it first gets populated. The most natural implementation sets it in `onAppear` or via the initial render of `.scrollPosition(id: $scrollHostId, anchor: .center)`. However, there is no explicit contract that says "on first render, `scrollHostId` = `selectedSpeaker`'s group host, or `groups.first?.hostSpeaker.id` if `selectedSpeaker` is not in any playing group." TC-E52-E02 assumes this is handled but the Implementer must decide the tie-breaking rule. The spec should state: "Initial `scrollHostId` is derived from `selectedSpeaker` if it belongs to a playing group; otherwise `groups.first?.hostSpeaker.id`."

**Gap 2 — `selectedSpeaker` update policy when `scrollHostId` becomes nil**

ADR §7 behavioural contract #1 says: "If `scrollHostId` resolves to nil (edge case: strip empty), do not change `selectedSpeaker`." This is clear, but when `HomeView` removes `SessionStripView` from the hierarchy (because `playingGroups` becomes empty), the existing `selectedSpeaker` binding is left in whatever state it was. The spec does not define what `HomeView` should do with `selectedSpeaker` when transitioning from the strip branch back to the idle-card or empty-state branch. TC-E52-E05 and TC-E52-A06 expose this gap as "existing HomeView logic is the regression baseline." A spec note should be added to `spec-home-screen-redesign.md` or the ADR to make the reset policy explicit.

**Gap 3 — Animation for `scrollHostId` initialisation vs. subsequent changes**

ADR §7 contract #2 specifies `withAnimation(BeoAnimation.spring)` when the `onChange(of: selectedSpeaker?.id)` handler sets `scrollHostId`. It is unclear whether this animation should also apply on the first render (when `scrollHostId` is nil and the strip is just mounting). Animating from nil to the initial position could produce a spurious slide-in animation on first appearance. The spec should clarify that `withAnimation` applies only to changes after the initial mount, or that the animation is suppressed for the `nil → initial` transition.

**Gap 4 — Page dot row width overflow on small iPhones with 8 sessions**

TC-E52-E03 notes that 8 dots (each 6–8 pt + `Spacing.s8` gaps) must fit within `screenWidth - (Spacing.s16 * 2)`. On an iPhone SE (375 pt screen), the strip width is 343 pt. 8 inactive dots (6 pt) + 7 gaps (`Spacing.s8` = 8 pt each) = 48 + 56 = 104 pt — this fits. But with an active dot at 8 pt the total is 106 pt — still fine. However, the spec does not confirm whether `Spacing.s8 = 8 pt` (which appears correct from the token naming convention). If `Spacing.s8` is a different value, the overflow assertion in TC-E52-E03 may be wrong. The spec should confirm the numeric value of `Spacing.s8` in the `DesignTokens.swift` table reference, or the test value should be updated once confirmed.

**Gap 5 — `onChange(of: groups.map(\.id))` — order sensitivity**

ADR §7 contract #6 specifies `onChange(of: groups.map(\.id))` for the insertion/removal guard. This compares arrays by identity sequence, not by set equality. If `groups` is ever re-sorted (e.g. a new playing group is inserted at the front rather than the back), `groups.map(\.id)` will produce a changed value even if the visible host is still in the array — potentially causing a spurious `scrollHostId` reset. The ADR confirms that `SpeakerGroup.id` is stable and sorted (per `makeId(for:)` in `Group.swift`), but the spec should explicitly state whether the `groups` array passed to `SessionStripView` is guaranteed to be stable-sorted, and if so, by what key.

**Gap 6 — VoiceOver order for `SessionPageDots` region**

Design-spec §Accessibility states: "VoiceOver order: session card → page dots region (labelled 'Session n of m') → voice feedback → bottom bar pills." However, `SessionPageDots` is `accessibilityHidden(true)` per ADR §7 contract #9 and design-spec §3.7. These two statements are contradictory: the label "Session n of m" implies a VoiceOver-visible element, but `accessibilityHidden(true)` removes it entirely from the tree. TC-E52-U06 asserts `accessibilityHidden(true)` per the ADR. The design-spec §Accessibility "page dots region" label must be clarified — is it a separate invisible container with an `accessibilityLabel` but no children, or is the label absent and the dots are truly silent? If silent, the design-spec §Accessibility VoiceOver order description must be updated to remove the "page dots region" entry.

---

## 10. Tests Deferred to Manual Device Verification

The following items cannot be fully automated at the unit or XCUITest level and are deferred to the manual verification tasks T-5209 and T-5210 defined in the epics document.

| Item | Reason for deferral | Epic task |
|---|---|---|
| Swipe momentum and snap feel | Native `ScrollView` paging kinetics are not reproducible in XCUITest; requires physical device evaluation | T-5209 item (a) |
| 8 pt trailing-card peek visual confirmation | Pixel-level measurement of the peek requires a snapshot or device screenshot review | T-5209 item (b) |
| Performance: 8 sessions at 60 fps on iPhone 14 | Requires Instruments / MetricKit profiling; no XCTest mechanism for frame-drop detection | T-5209 / NFR |
| No horizontal scroll bounce (single session) | Bounce behaviour is a UIKit-level property; XCUITest cannot directly assert `.scrollDisabled` effect | T-5207 / TC-E52-I02 note |
| VoiceOver navigation between session cards (gesture non-conflict) | Requires VoiceOver enabled and manual interaction; not reproducible in XCUITest `accessibilityActivate` flow | T-5210 item (c) |
| VoiceOver announcement order (session card → dots → feedback → bar) | Requires screen reader focus traversal on device | T-5210 item (d) |
| `BeoAnimation.spring` snap duration (≈ 450 ms) | Animation timing assertions in XCUITest are unreliable; NFR requires visual confirmation | NFR Latency |
| Parallax specular highlight (visual quality) | `roll`/`pitch` correctness is tested by TC-E52-I04; the specular rendering quality requires visual inspection | T-5209 / T-5208 |
