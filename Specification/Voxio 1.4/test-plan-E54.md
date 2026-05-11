# Test Plan — E-54 Bottom Bar Redesign

**Status:** Draft
**Date:** 2026-05-11
**Refs:** ADR-E54-bottom-bar-redesign.md, spec-home-screen-redesign.md US-62, design-spec-home-screen-redesign.md §2.2–§2.5, epics-and-tasks-home-screen-redesign.md E-54

---

## 1. Scope

This plan covers the testable interface contract introduced by E-54: the extraction of `PlaybackBars` into a shared component, the refactoring of `SpeakerSelectorPill` to accept `Speaker` references and `groups:` input, the group connector line logic (`sameGroup(_:_:)`), the accessibility label rules for all pill states, and the correction of the bottom-bar visibility condition from `> 1` to `>= 1`.

Tests that cover the `pillButton(speaker:isActive:isPlaying:)` signature, pill styling tokens, and accessibility surfaces are included because those items form part of the E-54 public interface contract that F1 (Touch Playback Controls) will consume (per ADR-002 Consequences §2). These test cases therefore also serve as the regression suite for F1: they verify that the styling and accessibility surfaces F1 inherits remain stable. What is out of scope is F1's own implementation — specifically, the touch playback controls wired inside `SpeakerCard.cardContent`. Multiroom grouping (F2) is also out of scope.

The plan does not cover:

- E-52 `SessionStripView` internals (separate epic, separate plan).
- E-53 group chip row.
- E-55 discovery/offline state machine.
- F1 touch playback controls implementation (i.e. `SpeakerCard.cardContent` changes) and F2 multiroom grouping.
- Backend, telemetry, or CI pipeline.

The tap-to-scroll behaviour (T-5407/T-5409) requires E-52 T-5202 (`SessionStripView.onChange(of: selectedSpeaker?.id)`). TCs that test the end-to-end scroll path are listed in §10 as blocked; the pill-tap-to-selection-set path is independently testable and is covered in §6.

---

## 2. Test Environment

| Item | Value |
|---|---|
| Platform | iOS 26, iPhone (portrait) |
| Framework | SwiftUI, `@Observable @MainActor` |
| Test harness | XCTest (unit) + XCUITest (UI/acceptance) — no separate test target exists in the repo at plan-authoring time. Tests are written as specifications; an engineer creating the test target should place unit tests in a new `VoxioTests` target and UI tests in `VoxioUITests`. |
| Accessibility testing | Xcode Accessibility Inspector + VoiceOver on device/simulator |
| Reduce Motion | iOS Settings → Accessibility → Motion → Reduce Motion |
| Speaker doubles | Protocol-backed `SpeakerStub` and `SpeakerGroupStub` value types sufficient for all unit TCs. No real network required for §§3–4. |
| Source files under test | `iOS/Voxio/Features/Home/Components/PlaybackBars.swift`, `iOS/Voxio/Features/Home/SpeakerSelectorPill.swift`, `iOS/Voxio/Features/Home/HomeView.swift` |

---

## 3. Unit-Level Test Cases (PlaybackBars)

These cases test the `PlaybackBars` struct's parameter contract and accessibility attributes. They are host-app tests using `ViewInspector` or equivalent snapshot infrastructure, or plain XCTest assertions on view-modifier values where `ViewInspector` is not available.

---

### TC-E54-U01

**ID:** TC-E54-U01
**Target:** `PlaybackBars`
**Setup:** Instantiate `PlaybackBars()` (no arguments).
**Action:** Read the `.frame` modifier applied to the outermost container.
**Expected:** Frame height equals `20` (the default parameter value). Bars are not clipped — they are scaled to fill the 20 pt height proportionally.
**Covers ADR contract assertion:** §7 assertion 1 — `PlaybackBars(height: 10)` uses `frame(height:, alignment: .bottom)`; default is 20 pt.
**Covers spec AC:** US-62 AC-1 (pill shows `PlaybackBars` animation)

---

### TC-E54-U02

**ID:** TC-E54-U02
**Target:** `PlaybackBars`
**Setup:** Instantiate `PlaybackBars(height: 10)`.
**Action:** Read the `.frame` modifier applied to the outermost container.
**Expected:** Frame height equals `10`. `alignment` is `.bottom` (bars grow upward from a fixed baseline, not downward from the top edge). Bars are rendered proportionally smaller — none of the three bar rectangles exceeds the 10 pt frame height.
**Covers ADR contract assertion:** §7 assertion 1
**Covers spec AC:** US-62 AC-1

---

### TC-E54-U03

**ID:** TC-E54-U03
**Target:** `PlaybackBars`
**Setup:** Instantiate `PlaybackBars(height: 10)`. Set `@Environment(\.accessibilityReduceMotion)` to `false`.
**Action:** Inspect the view hierarchy for `.accessibilityHidden(_:)` modifier.
**Expected:** `.accessibilityHidden(true)` is present on the `PlaybackBars` root view, regardless of the `height` value and regardless of the `reduceMotion` environment value.
**Covers ADR contract assertion:** §7 assertion 2
**Covers spec AC:** US-62 AC-11 (VoiceOver labels — bars must be hidden so only the pill label is read)

---

### TC-E54-U04

**ID:** TC-E54-U04
**Target:** `PlaybackBars`
**Setup:** Instantiate `PlaybackBars(height: 20)`. Set `@Environment(\.accessibilityReduceMotion)` to `true`.
**Action:** Inspect the rendered bar shapes (three `RoundedRectangle` or equivalent).
**Expected:** Each bar is rendered as a static shape at its midpoint height: `(lo + hi) / 2` per the three spec pairs `(lo: 6, hi: 14)`, `(lo: 14, hi: 6)`, `(lo: 10, hi: 16)`. Midpoints are `10`, `10`, `13` (rounded or truncated to whatever the implementation uses — assert the value matches `(lo + hi) / 2` for each pair). No `withAnimation` / `repeatForever` modifier is active.
**Covers ADR contract assertion:** §7 assertion 3
**Covers spec AC:** US-62 AC-1 (Reduce Motion variant of the bar)

---

### TC-E54-U05

**ID:** TC-E54-U05
**Target:** `PlaybackBars`
**Setup:** Instantiate `PlaybackBars(height: 10)`. Set `@Environment(\.accessibilityReduceMotion)` to `true`.
**Action:** Inspect bar heights at the 10 pt scale.
**Expected:** Static bar heights are the same midpoint fractions as TC-E54-U04 scaled proportionally to the 10 pt frame (i.e. the proportional positions are identical; only the absolute pixel values differ). No animation descriptors present.
**Covers ADR contract assertion:** §7 assertion 3
**Covers spec AC:** US-62 AC-1

---

### TC-E54-U06

**ID:** TC-E54-U06
**Target:** `PlaybackBars`
**Setup:** Inspect the bar fill colour in the default (non-reduce-motion) render.
**Action:** Read the foreground or fill colour of the bar shapes.
**Expected:** Fill colour is `Color(hex: "#C8A97E")` — matching `BeoColor.accent`. No new tokens are introduced.
**Covers ADR contract assertion:** §7 (no new design tokens — ADR-002 constraint preserved)
**Covers spec AC:** US-62 AC-2 (pill style matches design spec §2.2 — gold bars on playing pill)

---

## 4. Unit-Level Test Cases (SpeakerSelectorPill.sameGroup)

`sameGroup(_:_:)` is a `private` function. These cases are white-box tests that test the observable outcomes of the function by asserting connector-line presence/absence in the rendered view, or — if the test target grants internal access via `@testable import Voxio` — by calling the helper directly.

---

### TC-E54-U07

**ID:** TC-E54-U07
**Target:** `SpeakerSelectorPill.sameGroup(_:_:)` (via `@testable import` or observable connector rendering)
**Setup:** Create two `Speaker` stubs `A` and `B`. Create one `SpeakerGroup` whose `members` array contains both `A` and `B`. Pass `groups: [group]` to the pill view.
**Action:** Call `sameGroup(A, B)` (or verify connector line is visible between adjacent pills for A and B).
**Expected:** Returns `true`. The connector `Rectangle` rendered between the A-pill and the B-pill has a non-clear fill (`BeoColor.muted.opacity(0.3)`).
**Covers ADR contract assertion:** §7 assertion 4
**Covers spec AC:** US-62 AC-3 (connector line drawn between adjacent grouped pills)

---

### TC-E54-U08

**ID:** TC-E54-U08
**Target:** `SpeakerSelectorPill.sameGroup(_:_:)`
**Setup:** Create two `Speaker` stubs `A` and `B`. Create two separate `SpeakerGroup`s — group 1 contains only `A`, group 2 contains only `B`. Pass both groups as `groups:`.
**Action:** Call `sameGroup(A, B)`.
**Expected:** Returns `false`. The connector `Rectangle` between the A-pill and B-pill has a clear/transparent fill.
**Covers ADR contract assertion:** §7 assertion 4 (false when speakers are absent from the same group)
**Covers spec AC:** US-62 AC-4 (no connector when speakers not in same group)

---

### TC-E54-U09

**ID:** TC-E54-U09
**Target:** `SpeakerSelectorPill.sameGroup(_:_:)`
**Setup:** Create two `Speaker` stubs `A` and `B`. Pass `groups: []` (empty array).
**Action:** Call `sameGroup(A, B)`.
**Expected:** Returns `false`. No connector visible. No crash. The function handles an empty groups array gracefully.
**Covers ADR contract assertion:** §7 assertion 4 (returns false when either speaker is absent from all groups)
**Covers spec AC:** US-62 AC-4; boundary: 0-group edge case

---

### TC-E54-U10

**ID:** TC-E54-U10
**Target:** `SpeakerSelectorPill.sameGroup(_:_:)`
**Setup:** Create `Speaker` stub `A` and a second stub `B` whose `.id` does not appear in any group's `members` array. Create a group containing only `A`.
**Action:** Call `sameGroup(A, B)`.
**Expected:** Returns `false`. The function does not crash or throw when one speaker is present in a group and the other is absent from all groups.
**Covers ADR contract assertion:** §7 assertion 4
**Covers spec AC:** Boundary — speaker disappearing or never having joined a group

---

### TC-E54-U11

**ID:** TC-E54-U11
**Target:** `SpeakerSelectorPill.sameGroup(_:_:)` — actor isolation
**Setup:** (Conceptual/code-review assertion) Confirm in the implementation that `sameGroup(_:_:)` is callable synchronously on `@MainActor` without an `await` expression.
**Action:** Inspect the function signature and its call site inside the `body` property (which is `@MainActor`).
**Expected:** The function is not `async`. It reads `SpeakerGroup.members` synchronously. No off-actor access is performed. Compiler accepts the call without `await`.
**Covers ADR contract assertion:** §7 SpeakerSelectorPill internal helpers note ("Must be called on @MainActor. Pure sync query — no async.")
**Covers spec AC:** N/A (architectural invariant)

---

## 5. Integration Test Cases (SpeakerSelectorPill View)

These cases render `SpeakerSelectorPill` in a host view and assert on the visible output or view hierarchy. They require at least one or two `Speaker` and `SpeakerGroup` stubs and a `@State var selectedSpeaker: Speaker?` binding.

---

### TC-E54-I01

**ID:** TC-E54-I01
**Target:** `SpeakerSelectorPill` rendered layout — connector placeholder stability
**Setup:** Create three speakers `A`, `B`, `C`. No group relationships. Pass `groups: []`. Render `SpeakerSelectorPill(speakers: [A, B, C], selectedSpeaker: $sel, groups: [])`.
**Action:** Inspect the view hierarchy between adjacent pills.
**Expected:** Between each adjacent pair (A–B, B–C) there is exactly one connector segment element with `frame(width: 8, height: 1)` and a transparent/clear fill. Total pill spacing is stable: the clear placeholder occupies the same 8 pt as a visible connector would. Three pills are present; two connector placeholders are present.
**Covers ADR contract assertion:** §7 assertion 5 — spacing is stable regardless of group membership
**Covers spec AC:** US-62 AC-3/AC-4

---

### TC-E54-I02

**ID:** TC-E54-I02
**Target:** `SpeakerSelectorPill` — connector visible between two grouped adjacent pills
**Setup:** Speakers `A` (index 0) and `B` (index 1) in the same group `G`. Speaker `C` (index 2) in no group. `groups: [G]`.
**Action:** Render pill with `speakers: [A, B, C]`. Inspect connector elements.
**Expected:** Connector between positions 0–1 (A and B) has fill `BeoColor.muted.opacity(0.3)` and is visible. Connector between positions 1–2 (B and C) has clear fill and is invisible. Total connector element count is 2.
**Covers ADR contract assertion:** §7 assertion 5
**Covers spec AC:** US-62 AC-3, AC-4

---

### TC-E54-I03

**ID:** TC-E54-I03
**Target:** `SpeakerSelectorPill` — no connector drawn for non-adjacent grouped speakers
**Setup:** Speakers `A` (index 0), `B` (index 1), `C` (index 2). `A` and `C` are in the same group `G`. `B` is in no group. `groups: [G]`. `speakers: [A, B, C]`.
**Action:** Render and inspect all connector elements.
**Expected:** Neither connector (A–B at positions 0–1, nor B–C at positions 1–2) has a visible fill. Both are transparent placeholders. Non-adjacent grouping is not indicated in the bottom bar per spec resolved-UQ-3.
**Covers ADR contract assertion:** §7 assertion 5; design spec §2.3
**Covers spec AC:** US-62 AC-4 (non-adjacent grouped speakers have no connector)

---

### TC-E54-I04

**ID:** TC-E54-I04
**Target:** `SpeakerSelectorPill` — playing pill includes `PlaybackBars`
**Setup:** Speaker `A` with `isPlaying = true`. Speaker `B` with `isPlaying = false`. `selectedSpeaker = nil`. `groups: []`.
**Action:** Render `SpeakerSelectorPill(speakers: [A, B], selectedSpeaker: $sel, groups: [])`. Inspect pill button labels.
**Expected:** Pill for `A` contains a `PlaybackBars(height: 10)` child view. Pill for `B` does not contain a `PlaybackBars` child view. Both pills are present in the hierarchy.
**Covers ADR contract assertion:** §7 assertion 1 (PlaybackBars(height: 10) in pill)
**Covers spec AC:** US-62 AC-1

---

### TC-E54-I05

**ID:** TC-E54-I05
**Target:** `SpeakerSelectorPill` — playing pill visual styling
**Setup:** Speaker `A` with `isPlaying = true`. Render with no selection.
**Action:** Inspect the pill button's foreground colour, border colour, and border width.
**Expected:** Foreground is `BeoColor.accent`. Border is 1 pt at `BeoColor.accent` with 0.55 opacity. Glass effect background is present (same background as existing pill — no change to glass styling).
**Covers ADR contract assertion:** §7 (no new tokens; existing tokens applied correctly)
**Covers spec AC:** US-62 AC-2 (pill style for playing state matches design spec §2.2)

---

### TC-E54-I06

**ID:** TC-E54-I06
**Target:** `SpeakerSelectorPill` — idle pill visual styling
**Setup:** Speaker `A` with `isPlaying = false`. Not selected. Render.
**Action:** Inspect foreground colour and border.
**Expected:** Foreground is `BeoColor.text` (primary label). No border stroke is visible (or border is at zero opacity). No `PlaybackBars` in hierarchy. Glass effect background is present.
**Covers ADR contract assertion:** §7 (default pill style)
**Covers spec AC:** US-62 AC-6 (idle speakers shown in bar with no PlaybackBars, default style)

---

### TC-E54-I07

**ID:** TC-E54-I07
**Target:** `SpeakerSelectorPill` — selected non-playing pill visual styling
**Setup:** Speaker `A` with `isPlaying = false`. `selectedSpeaker = A`.
**Action:** Render and inspect pill for `A`.
**Expected:** Border is 1 pt at `.white.opacity(0.4)`. No gold accent on border or foreground. No `PlaybackBars`. Glass effect background and existing selection highlight present.
**Covers ADR contract assertion:** §7 (pillButton signature — isActive/isPlaying parameters drive styling independently)
**Covers spec AC:** US-62 AC-8 (currently visible card's host rendered as selected pill)

---

### TC-E54-I08

**ID:** TC-E54-I08
**Target:** `SpeakerSelectorPill` — `PlaybackBars` transition from playing to idle
**Setup:** Speaker `A` starting as `isPlaying = true`. Render pill.
**Action:** Mutate `A.isPlaying = false` and trigger a view update.
**Expected:** The `PlaybackBars` view disappears with an opacity cross-fade (`.transition(.opacity.animation(BeoAnimation.toast))`). The pill remains in its position in the bar — no reordering or layout shift occurs.
**Covers ADR contract assertion:** §7 assertion 1
**Covers spec AC:** US-62 AC-9 (PlaybackBars disappear with standard fade; pill remains in place)

---

### TC-E54-I09

**ID:** TC-E54-I09
**Target:** `SpeakerSelectorPill` — `PlaybackBars` transition from idle to playing
**Setup:** Speaker `A` starting as `isPlaying = false`. Render pill.
**Action:** Mutate `A.isPlaying = true` and trigger a view update.
**Expected:** The `PlaybackBars(height: 10)` view appears with an opacity cross-fade. Pill remains in its position — no layout shift.
**Covers ADR contract assertion:** §7 assertion 1
**Covers spec AC:** US-62 AC-10 (PlaybackBars appear with standard fade; pill remains in place)

---

### TC-E54-I10

**ID:** TC-E54-I10
**Target:** `SpeakerSelectorPill` — accessibility labels (all four states)
**Setup:** Four speakers: `P` (playing, not selected), `PS` (playing, selected), `S` (idle, selected), `N` (idle, not selected). Render pill with `selectedSpeaker = PS`, all four speakers in `speakers:`.
**Action:** Read the `.accessibilityLabel` of each pill button.
**Expected:**
- Pill for `P`: `"\(P.name), playing"`
- Pill for `PS`: `"\(PS.name), playing, selected"`
- Pill for `S`: `"\(S.name), selected"`
- Pill for `N`: `"\(N.name)"`

No extra tokens, no trailing commas, order is name → playing → selected.
**Covers ADR contract assertion:** §7 assertion 6
**Covers spec AC:** US-62 AC-11 (VoiceOver labels per design spec §2.5)

---

### TC-E54-I11

**ID:** TC-E54-I11
**Target:** `SpeakerSelectorPill` — accessibility hint
**Setup:** Speaker `A`, not selected. Speaker `B`, selected.
**Action:** Read `accessibilityHint` on each pill.
**Expected:** Unselected pill `A` has hint `"Show this speaker"`. Selected pill `B` has an empty hint string (or no hint). The old v1.3 hint `"Select this speaker"` is absent.
**Covers ADR contract assertion:** §7 assertion 6 (accessibility label spec; design spec §2.5)
**Covers spec AC:** US-62 AC-11

---

### TC-E54-I12

**ID:** TC-E54-I12
**Target:** `SpeakerSelectorPill` — connector `Rectangle` is not an accessibility element
**Setup:** Two speakers in a shared group. Render pill.
**Action:** Inspect the connector `Rectangle` view between the two pills using the accessibility hierarchy.
**Expected:** The connector has no accessibility element traits (it is a decorative `Rectangle` with no `.accessibilityElement()` modifier). VoiceOver does not focus the connector. The connector view does not appear in the accessibility tree.
**Covers ADR contract assertion:** §7 (connector is decorative per epics-and-tasks T-5410)
**Covers spec AC:** US-62 AC-11

---

## 6. Acceptance Test Cases (HomeView Wiring)

These cases test the corrected visibility condition and the call-site shape of `SpeakerSelectorPill` inside `HomeView`. They are integration/acceptance-level and may be implemented as XCUITest or snapshot tests against a stubbed `SpeakerDiscoveryService`.

---

### TC-E54-A01

**ID:** TC-E54-A01
**Target:** `HomeView` — bottom bar visibility with exactly one speaker
**Setup:** Stub `SpeakerDiscoveryService` to return exactly one `SpeakerGroup` containing one idle (non-playing) `Speaker`. `network.isOnWifi = true` (not in offline state).
**Action:** Render `HomeView`. Inspect whether `SpeakerSelectorPill` is present in the view hierarchy.
**Expected:** `SpeakerSelectorPill` is rendered. The bottom bar is visible. Condition `discovery.groups.flatMap(\.members).count >= 1` evaluates to `true` with one speaker.
**Covers ADR contract assertion:** §7 assertion 7
**Covers spec AC:** US-62 AC-6 (idle/stopped speakers shown in bottom bar)

---

### TC-E54-A02

**ID:** TC-E54-A02
**Target:** `HomeView` — bottom bar not shown with zero speakers (pre-existing behaviour, regression guard)
**Setup:** Stub discovery to return zero groups (no speakers). `network.isOnWifi = true`, `didSettle = false`.
**Action:** Render `HomeView`. Inspect for `SpeakerSelectorPill`.
**Expected:** `SpeakerSelectorPill` is not rendered. The bottom bar is hidden. Condition `>= 1` evaluates to `false` for zero speakers.
**Covers ADR contract assertion:** §7 assertion 7 (boundary: 0 speakers)
**Covers spec AC:** US-63 AC-2 (bottom bar not shown until at least one speaker is discovered)

---

### TC-E54-A03

**ID:** TC-E54-A03
**Target:** `HomeView` — `SpeakerSelectorPill` call-site includes `groups:` parameter
**Setup:** Stub discovery with two groups, each containing one speaker.
**Action:** Inspect the `SpeakerSelectorPill` initialiser call in `HomeView`'s rendered output (or via code review / compiler-enforced call-site shape).
**Expected:** `SpeakerSelectorPill` is called with:
- `speakers: discovery.groups.flatMap(\.members)` — all discovered speakers in discovery order
- `selectedSpeaker: $selectedSpeaker` — existing binding
- `groups: discovery.groups` — newly added parameter

The old call-site shape (no `groups:` argument) does not compile once T-5406 lands. This TC confirms that `HomeView` was updated to match the ADR §7 call-site shape.
**Covers ADR contract assertion:** §7 HomeView call-site shape
**Covers spec AC:** US-62 (entire bar wiring)

---

### TC-E54-A04

**ID:** TC-E54-A04
**Target:** `HomeView` — tapping a pill sets `selectedSpeaker`
**Setup:** Stub two playing speakers `A` and `B`. `selectedSpeaker = A`. Render `HomeView`.
**Action:** Tap the pill for speaker `B` via XCUITest or simulated button action.
**Expected:** `selectedSpeaker` is set to `B`. The pill for `B` transitions to the selected visual state. (Whether the strip scrolls to `B`'s session card depends on E-52 T-5202 — see §10.)
**Covers ADR contract assertion:** §7 (SpeakerSelectorPill produces selection changes via the `selectedSpeaker` binding)
**Covers spec AC:** US-62 AC-7 (tapping a pill scrolls to that speaker's session — this TC covers only the selection half; scroll is blocked by E-52)

---

### TC-E54-A05

**ID:** TC-E54-A05
**Target:** `HomeView` — tapping an idle speaker pill does not crash and does not scroll the strip
**Setup:** Stub one playing speaker `A` and one idle speaker `B`. `selectedSpeaker = A`. Render `HomeView` (with E-52 T-5202 available, or confirm no-scroll via binding state inspection only).
**Action:** Tap the pill for idle speaker `B`.
**Expected:** `selectedSpeaker` becomes `B`. No strip scroll animation is triggered (there is no session for `B` to scroll to). No crash. The empty/idle card area remains visible if no other session exists.
**Covers ADR contract assertion:** §7 assertion 7 (idle-speaker pill tap does not scroll the strip per spec)
**Covers spec AC:** US-62 AC-7 (idle speaker — tap selects but does not scroll)

---

### TC-E54-A06

**ID:** TC-E54-A06
**Target:** `HomeView` — many speakers (boundary: 8 speakers)
**Setup:** Stub 8 speakers across 3 groups. All playing. Render `HomeView`.
**Action:** Inspect the bottom bar and confirm all 8 pills render without dropped frames or layout overflow.
**Expected:** All 8 pills are present in the horizontally scrollable `SpeakerSelectorPill`. 7 connector elements are rendered between adjacent pills (some visible, some placeholder). No layout overflow or clipping of pill text. This tests the NFR: "up to 8 concurrent sessions render without dropped frames."
**Covers ADR contract assertion:** §7 (general wiring correctness at scale)
**Covers spec AC:** US-62 (bottom bar overflows to scroll — existing scroll behaviour preserved); spec NFR (8 sessions)

---

### TC-E54-A07

**ID:** TC-E54-A07
**Target:** `HomeView` — speaker disappears mid-render
**Setup:** Stub 3 speakers `A`, `B`, `C`. All in `SpeakerSelectorPill`. `selectedSpeaker = B`.
**Action:** Remove speaker `B` from the discovery list and trigger a view update.
**Expected:** The pill for `B` disappears from the bar. `selectedSpeaker` is updated (to `nil` or the nearest valid speaker — per the existing `HomeView` logic; E-54 does not specify a new policy here so the existing behaviour is the regression baseline). The remaining pills for `A` and `C` rerender without layout jank. No crash.
**Covers ADR contract assertion:** §7 (general robustness)
**Covers spec AC:** Error state: "All speakers disappear (e.g. all powered off) post-discovery" (error states table); boundary: speaker disappearing mid-render

---

## 7. Error States and Boundary Values

---

### TC-E54-E01

**ID:** TC-E54-E01
**Target:** `SpeakerSelectorPill` + `HomeView` — 0 speakers
**Setup:** `discovery.groups = []`. Render `HomeView` with `network.isOnWifi = true`, `didSettle = false`.
**Action:** Inspect bottom bar visibility.
**Expected:** `SpeakerSelectorPill` is not rendered. No crash when `flatMap(\.members).count == 0`. Condition `>= 1` correctly evaluates to `false`.
**Covers ADR contract assertion:** §7 assertion 7 (boundary)
**Covers spec AC:** US-63 AC-2

---

### TC-E54-E02

**ID:** TC-E54-E02
**Target:** `SpeakerSelectorPill` — 1 speaker, no groups
**Setup:** One speaker `A`, `isPlaying = false`. `groups: []`. Render pill with `speakers: [A]`.
**Action:** Inspect rendered view.
**Expected:** One pill rendered. No connector elements visible (no adjacent pair exists). No `PlaybackBars`. No crash. Pill is accessible with label `"\(A.name)"`.
**Covers ADR contract assertion:** §7 assertion 4 (false when speakers absent from all groups); assertion 5 (stable spacing — zero connectors is the zero-pair case)
**Covers spec AC:** US-62 AC-6; boundary: 1 speaker

---

### TC-E54-E03

**ID:** TC-E54-E03
**Target:** `SpeakerSelectorPill` — all speakers in same group, all playing
**Setup:** Speakers `A`, `B`, `C` all in group `G`. All `isPlaying = true`. `groups: [G]`. `speakers: [A, B, C]`.
**Action:** Render and inspect all pills and connectors.
**Expected:** Three pills, all with `PlaybackBars(height: 10)`. Two connector elements, both with `BeoColor.muted.opacity(0.3)` fill. No transparent placeholders between adjacent pills. No crash.
**Covers ADR contract assertion:** §7 assertions 1, 4, 5
**Covers spec AC:** US-62 AC-1, AC-3

---

### TC-E54-E04

**ID:** TC-E54-E04
**Target:** `SpeakerSelectorPill` — mixed group membership (some grouped, some solo)
**Setup:** `A` and `B` in group `G1`. `C` solo (no group). `D` and `E` in group `G2`. Discovery order: `[A, B, C, D, E]`. `groups: [G1, G2]`.
**Action:** Render and inspect connector elements.
**Expected:**
- Connector at 0–1 (A–B): visible (`G1`)
- Connector at 1–2 (B–C): transparent (B in `G1`, C in no group — different groups)
- Connector at 2–3 (C–D): transparent (C in no group, D in `G2`)
- Connector at 3–4 (D–E): visible (`G2`)

Pill count = 5. Connector count = 4 (2 visible, 2 placeholder). Spacing identical for all connectors.
**Covers ADR contract assertion:** §7 assertions 4, 5
**Covers spec AC:** US-62 AC-3, AC-4, AC-5 (pill order is discovery order; bar not re-sorted by group)

---

### TC-E54-E05

**ID:** TC-E54-E05
**Target:** `SpeakerSelectorPill` — speaker transitions from playing to idle while pill is mounted
**Setup:** Speaker `A` with `isPlaying = true`. Render pill. `A` is in `speakers[0]`.
**Action:** Mutate `A.isPlaying = false`. Allow SwiftUI to re-render.
**Expected:** `PlaybackBars` disappears with `.opacity` transition. Pill position unchanged (no reorder). Pill border changes from gold 1 pt to no-border (idle style). `accessibilityLabel` updates from `"\(A.name), playing"` to `"\(A.name)"` (if not selected) within one render cycle.
**Covers ADR contract assertion:** §7 assertion 6 (a11y label reflects real-time state)
**Covers spec AC:** US-62 AC-9

---

### TC-E54-E06

**ID:** TC-E54-E06
**Target:** `SpeakerSelectorPill` — `PlaybackBars` Reduce Motion in pill context
**Setup:** Speaker `A` with `isPlaying = true`. Set `@Environment(\.accessibilityReduceMotion) = true`. Render `SpeakerSelectorPill(speakers: [A], selectedSpeaker: $sel, groups: [])`.
**Action:** Inspect the `PlaybackBars(height: 10)` inside the pill.
**Expected:** Static bars at midpoint heights (per TC-E54-U04 logic, scaled to 10 pt). No repeating animations active. `accessibilityHidden(true)` still applied. No crash.
**Covers ADR contract assertion:** §7 assertion 3
**Covers spec AC:** US-62 AC-1; spec NFR Accessibility (Reduce Motion — all PlaybackBars suspend)

---

### TC-E54-E07

**ID:** TC-E54-E07
**Target:** `HomeView` — bottom bar remains visible when all speakers become idle (but remain discovered)
**Setup:** Two speakers, both initially `isPlaying = true`. Bar is visible. Mutate both to `isPlaying = false`.
**Action:** Allow HomeView to re-render. Inspect bottom bar.
**Expected:** `SpeakerSelectorPill` remains rendered (speakers are still discovered — `flatMap(\.members).count >= 1`). Both pills show no `PlaybackBars`. No connectors if not grouped.
**Covers ADR contract assertion:** §7 assertion 7 (bar shown whenever `>= 1` speaker is discovered, regardless of playing state)
**Covers spec AC:** US-62 AC-6 (idle speakers shown in bar)

---

### TC-E54-E08

**ID:** TC-E54-E08
**Target:** `SpeakerSelectorPill` — connector line uses `.opacity(0.3)` at fill level, not on the `Rectangle` view modifier
**Setup:** Render two adjacent grouped speakers. Inspect the fill of the connector `Rectangle`.
**Action:** Check whether `BeoColor.muted.opacity(0.3)` is applied to `.fill(BeoColor.muted.opacity(0.3))` versus `.fill(BeoColor.muted).opacity(0.3)` on the view.
**Expected:** Opacity is applied inside the fill argument (`.fill(BeoColor.muted.opacity(0.3))`), not as a separate `.opacity(0.3)` modifier on the `Rectangle` view. This prevents double-compositing with any parent opacity modifier per ADR §8 minor spec ambiguity note.
**Covers ADR contract assertion:** ADR §8 minor spec ambiguity — "implementation must apply `.opacity(0.3)` at the fill level"
**Covers spec AC:** US-62 AC-3 (connector visual correctness)

---

## 8. Coverage Matrix

| AC / Contract Assertion | TC IDs | Status |
|---|---|---|
| ADR §7 assertion 1 — `PlaybackBars` height + bottom alignment | TC-E54-U01, TC-E54-U02, TC-E54-I04, TC-E54-I08, TC-E54-I09 | Covered |
| ADR §7 assertion 2 — `PlaybackBars` always `.accessibilityHidden(true)` | TC-E54-U03 | Covered |
| ADR §7 assertion 3 — Reduce Motion: static bars at midpoint | TC-E54-U04, TC-E54-U05, TC-E54-E06 | Covered |
| ADR §7 assertion 4 — `sameGroup` true/false contract | TC-E54-U07, TC-E54-U08, TC-E54-U09, TC-E54-U10 | Covered |
| ADR §7 assertion 5 — connector placeholder stable spacing | TC-E54-I01, TC-E54-I02, TC-E54-I03, TC-E54-E03, TC-E54-E04 | Covered |
| ADR §7 assertion 6 — accessibility label format (all 4 states) | TC-E54-I10, TC-E54-I11, TC-E54-E05 | Covered |
| ADR §7 assertion 7 — bar visible when `count >= 1` | TC-E54-A01, TC-E54-A02, TC-E54-E01, TC-E54-E07 | Covered |
| ADR §7 call-site shape (HomeView must pass `groups:`) | TC-E54-A03 | Covered |
| ADR §8 fill-level opacity (no double-compositing) | TC-E54-E08 | Covered |
| US-62 AC-1 — pill shows PlaybackBars when playing | TC-E54-U01, TC-E54-U02, TC-E54-I04, TC-E54-E03, TC-E54-E06 | Covered |
| US-62 AC-2 — pill style matches design spec §2.2 | TC-E54-I05, TC-E54-I06, TC-E54-I07, TC-E54-U06 | Covered |
| US-62 AC-3 — connector line between adjacent grouped pills | TC-E54-I02, TC-E54-E03, TC-E54-E04 | Covered |
| US-62 AC-4 — no connector for non-adjacent or non-grouped pills | TC-E54-I01, TC-E54-I03, TC-E54-U08, TC-E54-U09, TC-E54-E04 | Covered |
| US-62 AC-5 — pill order is discovery order; bar not re-sorted | TC-E54-E04 | Covered |
| US-62 AC-6 — idle speakers shown in bar (no PlaybackBars) | TC-E54-I06, TC-E54-A01, TC-E54-E02, TC-E54-E07 | Covered |
| US-62 AC-7 — tapping pill scrolls strip (host/member/idle cases) | TC-E54-A04 (selection only), TC-E54-A05 (idle) | **Partially blocked by E-52 T-5202** — scroll assertion blocked; selection assertion covered |
| US-62 AC-8 — visible session card's host is selected pill | TC-E54-I07 (selection visual), TC-E54-A04 | **Partially blocked by E-52 T-5202** — two-way binding from strip to pill blocked; pill-to-selection covered |
| US-62 AC-9 — PlaybackBars disappear with fade on idle transition | TC-E54-I08, TC-E54-E05 | Covered |
| US-62 AC-10 — PlaybackBars appear with fade on playing transition | TC-E54-I09 | Covered |
| US-62 AC-11 — VoiceOver labels per design spec §2.5 | TC-E54-I10, TC-E54-I11, TC-E54-I12 | Covered |
| Error state: all speakers disappear mid-render | TC-E54-A07 | Covered |
| Error state: bottom bar overflows (many speakers) | TC-E54-A06 | Covered |
| Boundary: 0 speakers | TC-E54-E01 | Covered |
| Boundary: 1 speaker | TC-E54-E02 | Covered |
| Boundary: many speakers (8) | TC-E54-A06 | Covered |
| Boundary: mixed groups | TC-E54-E04 | Covered |
| Boundary: speaker disappearing mid-render | TC-E54-A07 | Covered |
| Architectural: `sameGroup` is synchronous @MainActor | TC-E54-U11 | Covered (code review) |

---

## 9. Spec Gaps Discovered

The following ambiguities or omissions were identified during test-plan authoring. None are blockers for implementation; each is flagged for the Spec Author to resolve if clarity is needed before QA sign-off.

**Gap 1 — Accessibility label ordering when playing AND selected**

ADR §7 assertion 6 specifies `"\(speaker.name), playing, selected"` for a playing-and-selected pill. Design spec §2.5 says `"\(name)\(isPlaying ? ", playing" : "")\(isSelected ? ", selected" : "")"` which implies the same order, but does not spell out the combined case explicitly. TC-E54-I10 assumes name → playing → selected. If the implementation reverses to name → selected → playing, TC-E54-I10 will fail. The ADR should be treated as canonical; the design spec §2.5 formula should be made explicit for the combined case.

**Gap 2 — `SpeakerSelectorPill` scroll position when a playing speaker's pill is off-screen**

US-62 specifies that the bottom bar scrolls to show the selected speaker when the session strip card changes. Neither the ADR nor the epics doc specifies whether `SpeakerSelectorPill` itself performs a scroll-to-selected action when `selectedSpeaker` changes. E-52 T-5202 handles scrolling the card strip; it is unclear whether the pill bar also auto-scrolls to reveal the newly selected pill. If the bar does not auto-scroll and the selected pill is off-screen to the right, the user may not see the gold border change. TC-E54-A04 and TC-E54-A05 do not cover this case. A clarification is needed in `spec-home-screen-redesign.md` or ADR-E54.

**Gap 3 — Behaviour when `discovery.groups` changes but `selectedSpeaker` is still a valid speaker**

ADR §7 assertion 7 only defines bar visibility based on `count >= 1`. The spec does not define what happens to `selectedSpeaker` if the speaker it points to is removed from `discovery.groups` while the bar is visible (e.g. speaker powered off mid-session). TC-E54-A07 covers the crash-free assertion but leaves the `selectedSpeaker` update policy as "existing `HomeView` logic" — which may itself be unspecified. The spec should add an explicit rule (e.g. "reset to `nil` or to the first remaining speaker") to prevent divergent implementations.

**Gap 4 — `PlaybackBars` animation spec values vs. design-spec wording**

The epics doc (T-5401) specifies bar specs as `[(6, 14), (14, 6), (10, 16)]` with 20 pt frame height. TC-E54-U04 and TC-E54-U05 derive midpoints from these pairs. However, the design spec §Motion says "static bars at mid-height" without defining the pairs. If the implementation uses different lo/hi values, the midpoint assertions in those TCs will fail without clear authority to resolve the discrepancy. The ADR §7 contract should specify the exact `(lo, hi)` pairs or reference the epics doc as the canonical source.

**Gap 5 — Connector line and Reduce Motion**

Design spec §2.2 references Reduce Motion for `PlaybackBars` but does not address whether the connector line itself should change under Reduce Motion. The connector is a static `Rectangle` (no animation), so this is likely a non-issue in practice. However, no TC can formally confirm "the connector is unaffected by Reduce Motion" without an explicit spec statement that it is intentionally static. Recommend adding a one-line note to design spec §2.3 confirming the connector has no motion variant.

---

## 10. Tests Blocked by Cross-Epic Dependency (E-52 T-5202)

The following acceptance criteria and test cases require `SessionStripView.onChange(of: selectedSpeaker?.id)` introduced by E-52 T-5202. Until that task lands, these behaviours are untestable end-to-end.

| Blocked AC | Description | Unblocked sub-assertion | Blocked sub-assertion |
|---|---|---|---|
| US-62 AC-7 (host speaker) | Tapping a playing-speaker pill scrolls the strip to its session card | Pill tap sets `selectedSpeaker` (TC-E54-A04 covers this) | Strip scroll response to `selectedSpeaker` change |
| US-62 AC-7 (group member) | Tapping a non-host group-member pill scrolls to the group's session card | Pill tap sets `selectedSpeaker` | Strip identifies group membership and scrolls to host card |
| US-62 AC-7 (idle speaker) | Tapping an idle pill does not scroll the strip | Pill tap sets `selectedSpeaker` (TC-E54-A05 covers this); strip does not scroll (trivially true until T-5202 exists, but cannot be verified as an intentional no-op) | Confirming no-scroll is intentional when T-5202's logic explicitly skips idle speakers |
| US-62 AC-8 | Visible session card's host is rendered as selected pill | Selection visual state on pill (TC-E54-A04, TC-E54-I07 cover this) | Two-way binding: swipe the strip → the pill for the new session's host becomes selected |
| T-5409 manual verification (spec task) | Full end-to-end bottom bar verification including strip scroll | All pill rendering items | Items (d) and (e) of T-5409's verification list |
| T-5410 VoiceOver verification (spec task) | VoiceOver for scroll-related assertions | Pill label assertions (TC-E54-I10, TC-E54-I11 cover these) | Scroll-related VoiceOver confirmation |

**Action for Test Reviewer:** When E-52 T-5202 is merged, unblock these assertions by adding the following test cases to this plan:

- **TC-E54-A08** (to be written): Tap a playing-speaker pill → assert `SessionStripView` scrolls to display that speaker's session card (XCUITest).
- **TC-E54-A09** (to be written): Tap a non-host group-member pill → assert strip scrolls to the group's session card (XCUITest).
- **TC-E54-A10** (to be written): Swipe the session strip to a different card → assert the newly visible card's host speaker becomes the selected pill in `SpeakerSelectorPill` (XCUITest).
