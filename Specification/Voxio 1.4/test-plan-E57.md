# Test Plan — E-57 Interactive Volume Slider

**Status:** Draft
**Date:** 2026-05-12
**Refs:** ADR-E57-volume-slider.md, spec-touch-playback-controls.md US-71/US-73, design-spec-touch-playback-controls.md §3/§5.2/§5.4, epics-and-tasks-touch-playback-controls.md E-57 (T-5701–T-5709)

---

## 1. Scope

This plan covers the testable interface contract introduced by E-57: the `InteractiveVolumeBar` custom SwiftUI component (geometry-reader track, dual `Capsule` visual, `DragGesture(minimumDistance: 0)` overlay, snap-to-5 logic, `isEditing` first-call gate, VoiceOver adjustable action); the `@State dragVolume: Int?` and `@State lastLimitHaptic: Int?` properties on `SpeakerCard`; the `handleLimitHaptic(_:)` limit-haptic gate and accessibility announcement logic; the `SpeakerGroup.setVolumeOnAllMembers(_:)` `withTaskGroup` fan-out helper (T-5704); the `broadcastVolume(_:)` partial-failure toast and haptic logic (T-5705); the WS-event mid-drag suppression via `dragVolume` dominance; and the VoiceOver `.accessibilityAdjustableAction` on `InteractiveVolumeBar` (T-5706).

All 14 ADR §7 behavioural assertions are mapped to at least one TC. All US-71 and US-73 acceptance criteria are covered. The plan also covers snap-to-5 boundary values, the tap-as-zero-distance-drag behaviour, the limit-haptic gate, partial/total group broadcast failure, and the "1 speaker" vs "2 speakers" toast pluralisation.

What is out of scope:

- E-56 play/pause toggle (covered in test-plan-E56.md).
- E-58 favorites row (separate test plan).
- US-70 and US-72 acceptance criteria.
- WS event handling upstream of `SpeakerCard` (network layer, `MozartEvents`, `Speaker.initialize()`).
- Backend, telemetry, voice pipeline.
- `HapticEngine.limitReached()` internal implementation (already shipped; only call-count is asserted here).
- SwiftUI preview correctness (T-5709 is overridden to test-plan coverage per ADR §8 CF-6; no XCTest file is produced).

---

## 2. Test Environment

| Item | Value |
|---|---|
| Platform | iOS 26, iPhone (portrait) |
| Framework | SwiftUI, `@Observable @MainActor`, `withTaskGroup` |
| Test harness | No XCTest target exists in this repo (ADR §8 CF-6). All TCs are manual verification procedures or static/code-review assertions unless a future XCTest target is created. Where XCTest is noted, it is conditional on the target being added. |
| Accessibility testing | Xcode Accessibility Inspector + VoiceOver on device/simulator |
| Reduce Motion | iOS Settings → Accessibility → Motion → Reduce Motion |
| Speaker doubles | `SpeakerStub: @Observable @MainActor` — writable `volume: Int?`, records `setVolumeCallCount: Int` and `lastSetVolumeLevel: Int?`; injectable `setVolumeError: Error?` to simulate per-call failure. Extended from E-56 stub (adds volume recording). |
| Group doubles | `SpeakerGroupStub` wrapping one or more `SpeakerStub` instances; exposes `members: [SpeakerStub]` and `hostSpeaker`. Passed to `SpeakerCard` in group-broadcast tests. |
| HapticEngine double | `HapticEngineSpy` recording `limitReachedCallCount: Int`, `errorOccurredCallCount: Int`, and the call sequence relative to async task events. Same spy defined in test-plan-E56. |
| AccessibilityNotification double | `AccessibilityAnnouncementSpy` recording each posted announcement string in order. Required to assert "Volume at minimum" / "Volume at maximum" without running VoiceOver. |
| Source files under test | `iOS/Voxio/DesignSystem/InteractiveVolumeBar.swift` (new), `iOS/Voxio/Features/Home/SpeakerCard.swift` (modified), `iOS/Voxio/Core/Models/Group.swift` (modified) |
| Files NOT modified by E-57 | `HapticEngine.swift`, `DesignTokens.swift`, `BeoColor.swift`, all networking files, all backend files |

---

## 3. Unit-Level Test Cases — InteractiveVolumeBar Rendering and Gesture

These cases target `InteractiveVolumeBar` in isolation: its visual layout, drag-to-value mapping, snap-to-5 arithmetic, `onEditingChanged` lifecycle, and VoiceOver adjustable action. Where XCTest ViewInspector is unavailable, these become manual canvas/device verification steps.

---

### TC-E57-U01

**ID:** TC-E57-U01
**Target:** `InteractiveVolumeBar` — gold fill width proportional to `value`
**ADR assertion:** §7 assertion #1 — "With `value = 50`, renders gold fill at exactly 50% of track width."
**Setup:** Instantiate `InteractiveVolumeBar` with `@State var vol = 50` and a no-op `onEditingChanged`. Render inside a `GeometryReader` of known width W (e.g. 300 pt).
**Action:** Inspect the gold `Capsule` view's computed frame width. Inspect the track (background) `Capsule` frame width.
**Expected:** Gold fill width = `W * 50 / 100 = 150 pt`. Track width = W. Both capsules share height 4 pt. The gold fill uses `Color(hex: "#C8A97E")`. The track uses `.white.opacity(0.12)`. The trailing volume number reads "50".
**Covers spec AC:** US-71 AC-4 (numeric readout reflects value); design-spec §1.3 (4 pt height, gold fill, dark track).

---

### TC-E57-U02

**ID:** TC-E57-U02
**Target:** `InteractiveVolumeBar` — gold fill width at boundary value 0
**Setup:** `value = 0`. Same geometry as TC-E57-U01 (W = 300 pt).
**Action:** Inspect gold fill width.
**Expected:** Gold fill width = 0 pt (or `Capsule` is effectively invisible at zero width). Trailing number reads "0". Track remains full width. No crash or negative-width layout error.
**Covers spec AC:** US-71 AC-4 (readout live during drag); boundary: snap-to-5 at 0.

---

### TC-E57-U03

**ID:** TC-E57-U03
**Target:** `InteractiveVolumeBar` — gold fill width at boundary value 100
**Setup:** `value = 100`. W = 300 pt.
**Action:** Inspect gold fill width.
**Expected:** Gold fill width = 300 pt (fills the full track). Trailing number reads "100". No overflow or clipping beyond track.
**Covers spec AC:** US-71 AC-4; boundary: snap-to-5 at 100.

---

### TC-E57-U04

**ID:** TC-E57-U04
**Target:** `InteractiveVolumeBar` — gold fill width at non-boundary multiples of 5
**Setup:** Three instantiations: `value = 5`, `value = 50`, `value = 95`. W = 200 pt.
**Action:** Inspect gold fill width for each.
**Expected:**
- `value = 5` → fill width = 10 pt.
- `value = 50` → fill width = 100 pt.
- `value = 95` → fill width = 190 pt.
All produce exact proportional widths (no rounding beyond integer pt).
**Covers spec AC:** Snap-to-5 boundary values (0, 5, 50, 95, 100) per coverage requirement.

---

### TC-E57-U05

**ID:** TC-E57-U05
**Target:** `InteractiveVolumeBar` — drag-to-value mapping, `onEditingChanged(true)` on first `onChanged`
**ADR assertion:** §7 assertion #2 — "Drag from 20 → 60 → binding receives 60; `onEditingChanged(true)` fires on first `onChanged`."
**Setup:** `@State var vol = 20`. `onEditingChanged` closure records calls in an array: `[(Bool, Int)]` (editing flag + current `vol` at call time). W = 200 pt. A `DragGesture` starting at x = 40 pt (20% = value 20) and moving to x = 120 pt (60% = value 60).
**Action:** Simulate `DragGesture.onChanged` events at intermediate x positions (e.g. 60 pt, 90 pt, 120 pt). Then simulate `DragGesture.onEnded` at x = 120 pt.
**Expected:**
- After first `onChanged` at x = 60 pt: `vol` = snapped nearest-5 of `60/200*100 = 30`. `onEditingChanged` called with `true` exactly once.
- After second `onChanged` at x = 90 pt: `vol` = 45. `onEditingChanged(true)` NOT called again (gate is set after first call).
- After `onChanged` at x = 120 pt: `vol` = 60.
- After `onEnded` at x = 120 pt: `vol` = 60 (final write). `onEditingChanged(false)` called exactly once. `isEditing` state reset.
**Covers spec AC:** US-71 AC-5 (setVolume called once on drag end, not per intermediate point via `onEditingChanged(false)` dispatch); ADR §7 assertions #2 and #3.

---

### TC-E57-U06

**ID:** TC-E57-U06
**Target:** `InteractiveVolumeBar` — `onEditingChanged(false)` fires exactly once at drag end; intermediate positions do not fire `false`
**ADR assertion:** §7 assertion #3 — "Drag end → `onEditingChanged(false)` fires exactly once; intermediate positions don't fire `false`."
**Setup:** Same as TC-E57-U05 but record each call to `onEditingChanged`. Simulate 10 `onChanged` events followed by one `onEnded`.
**Action:** Count calls to `onEditingChanged(false)` throughout.
**Expected:** `onEditingChanged(false)` call count = exactly 1 (on `onEnded`). `onEditingChanged(true)` call count = exactly 1 (on first `onChanged`). No `false` fire during any `onChanged` event.
**Covers spec AC:** US-71 AC-5 (setVolume fires once per drag, not per point); ADR §7 assertion #3.

---

### TC-E57-U07

**ID:** TC-E57-U07
**Target:** `InteractiveVolumeBar` — tap-as-zero-distance-drag (minimumDistance: 0)
**ADR assertion:** §7 assertion #4 — "Tap at 75% with no drag → value snaps to 75."
**Setup:** `@State var vol = 20`. W = 200 pt. Simulate a `DragGesture(minimumDistance: 0)` with `startLocation.x = 150 pt` (75%) and zero movement (start == end location).
**Action:** Fire `onChanged` once at x = 150 pt, then `onEnded` at x = 150 pt.
**Expected:** `vol` = 75 (nearest-5 of `150/200*100 = 75.0`). `onEditingChanged(true)` fires on the single `onChanged`. `onEditingChanged(false)` fires on `onEnded`. A tap-in-place is treated as a zero-distance drag that snaps to value — `DragGesture(minimumDistance: 0)` enables this.
**Covers spec AC:** US-71 AC-2 (slider has invisible thumb; gold fill is touch affordance — tap anywhere snaps to value); ADR §7 assertion #4; epics T-5701 (minimumDistance: 0 treats taps as zero-distance drags).

---

### TC-E57-U08

**ID:** TC-E57-U08
**Target:** `InteractiveVolumeBar` — snap-to-5 rounding at midpoints
**Setup:** W = 200 pt. Test the following drag x positions and expected snapped values:

| x (pt) | Raw % | Expected snap |
|---|---|---|
| 2 | 1% | 0 |
| 6 | 3% | 5 |
| 13 | 6.5% | 5 |
| 17 | 8.5% | 10 |
| 102 | 51% | 50 |
| 108 | 54% | 55 |
| 194 | 97% | 95 |
| 198 | 99% | 100 |

**Action:** For each x position, simulate a single `onChanged` event. Read the resulting `vol` binding value.
**Expected:** Each row's "Expected snap" matches the actual `vol` after the `onChanged`. The snap formula is `round(rawPercent / 5) * 5` clamped to `[0, 100]`.
**Covers spec AC:** US-71 AC-1 (step: 5, range 0–100); design-spec §1.3 (step 5); ADR §7 §1 Decision (snapped to nearest 5).

---

### TC-E57-U09

**ID:** TC-E57-U09
**Target:** `InteractiveVolumeBar` — external value change animates with `.easeOut(duration: 0.3)`; drag update does not animate
**Setup:** `@State var vol = 20`. Instantiate `InteractiveVolumeBar`. Render in preview/canvas.
**Action (A):** Externally set `vol = 80` without any drag gesture in flight.
**Action (B):** Simulate a drag gesture update setting `vol = 80` via `onChanged`.
**Expected (A):** The gold fill animates from 20% width to 80% width over ~0.3 s using `.easeOut`. This is the `.animation(.easeOut(duration: 0.3), value: value)` modifier applied only to external value changes.
**Expected (B):** The gold fill jumps immediately to 80% width (no spring animation on the drag itself — "Reduce Motion: gold fill follows touch directly" per ADR §7 contract #9).
**Covers spec AC:** US-71 AC-4 (readout updates live during drag); design-spec §5.4 (drag-end dispatch lags visual); ADR §7 binding contract item 3 (`.animation` for external only).

---

### TC-E57-U10

**ID:** TC-E57-U10
**Target:** `InteractiveVolumeBar` — VoiceOver `.accessibilityLabel` and `.accessibilityValue`
**Setup:** Instantiate `InteractiveVolumeBar` with `value = 35`. Read accessibility properties via Accessibility Inspector or XCUITest `.accessibilityLabel` / `.accessibilityValue`.
**Action:** Inspect the element's `accessibilityLabel` and `accessibilityValue`.
**Expected:** `accessibilityLabel = "Volume"`. `accessibilityValue = "35 percent"`. These match ADR §7 contract item 7 (`accessibilityLabel("Volume")`, `accessibilityValue("\(value) percent")`).
**Covers spec AC:** US-71 AC-7 (VoiceOver announces limit); design-spec §7 (all controls expose `accessibilityLabel`); T-5706.

---

### TC-E57-U11

**ID:** TC-E57-U11
**Target:** `InteractiveVolumeBar` — VoiceOver `.accessibilityAdjustableAction` increment by 5
**ADR assertion:** coverage requirement — "VoiceOver adjustable action increments/decrements by 5, fires broadcast immediately."
**Setup:** `@State var vol = 50`. `onEditingChanged` records calls. Inject `HapticEngineSpy` (to verify limit haptic if boundary reached).
**Action:** Trigger `.accessibilityAdjustableAction(.increment)`.
**Expected:** `vol` = 55. `onEditingChanged(true)` fires. `onEditingChanged(false)` fires immediately after (same call as per ADR §7 contract item 7: `onEditingChanged(true); onEditingChanged(false)`). This simulates an instant drag+end, causing a `broadcastVolume(55)` dispatch.
**Covers spec AC:** US-71 AC-7 (VoiceOver announces limit reached — not triggered here since value is mid-range); T-5706; ADR §7 contract item 7.

---

### TC-E57-U12

**ID:** TC-E57-U12
**Target:** `InteractiveVolumeBar` — VoiceOver `.accessibilityAdjustableAction` decrement by 5
**Setup:** `@State var vol = 50`. Same spy setup as TC-E57-U11.
**Action:** Trigger `.accessibilityAdjustableAction(.decrement)`.
**Expected:** `vol` = 45. `onEditingChanged(true)` then `onEditingChanged(false)` both fire. Mirrors TC-E57-U11.
**Covers spec AC:** T-5706; ADR §7 contract item 7.

---

### TC-E57-U13

**ID:** TC-E57-U13
**Target:** `InteractiveVolumeBar` — VoiceOver adjustable action at upper boundary (value = 100)
**Setup:** `@State var vol = 100`. Inject `HapticEngineSpy`.
**Action:** Trigger `.accessibilityAdjustableAction(.increment)`.
**Expected:** `vol` remains 100 (clamped by `min(100, value + 5)`). `onEditingChanged(true)` and `onEditingChanged(false)` still fire (allowing `handleLimitHaptic` to be called by `SpeakerCard`). No crash. The caller (`SpeakerCard.handleLimitHaptic`) fires `limitReached()` if `lastLimitHaptic != 100`.
**Covers spec AC:** US-71 AC-6 (limit haptic fires once per boundary crossing); ADR §7 contract item 7 (`.increment` at max: `min(100, 100 + 5) = 100`).

---

### TC-E57-U14

**ID:** TC-E57-U14
**Target:** `InteractiveVolumeBar` — VoiceOver adjustable action at lower boundary (value = 0)
**Setup:** `@State var vol = 0`. Same spy.
**Action:** Trigger `.accessibilityAdjustableAction(.decrement)`.
**Expected:** `vol` remains 0 (clamped by `max(0, value - 5)`). `onEditingChanged(true)` and `onEditingChanged(false)` fire. No crash.
**Covers spec AC:** US-71 AC-6 (limit haptic at minimum); ADR §7 contract item 7 (`.decrement` at min: `max(0, 0 - 5) = 0`).

---

### TC-E57-U15

**ID:** TC-E57-U15
**Target:** `InteractiveVolumeBar` — visual fidelity matches pre-E-57 `volumeTrack(level:)` appearance
**Setup:** Render `InteractiveVolumeBar(value: .constant(40), onEditingChanged: { _ in })` alongside the pre-E-57 static `volumeTrack(level: 40)` view in a SwiftUI canvas (if available in preview history) or compare via design-spec §1.3 token checklist.
**Action:** Visually compare: track colour, fill colour, height, trailing number font/size/weight/colour, HStack layout, horizontal padding.
**Expected:** Gold fill = `Color(hex: "#C8A97E")`. Track = `.white.opacity(0.12)`. Height = 4 pt. Trailing number: `Text("\(value)")`, `.system(size: 12, weight: .medium)`, `.secondary`, `.frame(width: 28, alignment: .trailing)`. Horizontal padding `Spacing.s24`; vertical padding `Spacing.s12` top and bottom (increased from static bar). Layout matches design-spec §1.3 exactly.
**Covers spec AC:** US-71 AC-2 (invisible thumb; gold fill is affordance); design-spec §1.3; ADR §7 contract items 2–4 (visual fidelity must match `volumeTrack(level:)` exactly).

---

## 4. Unit-Level Test Cases — SpeakerGroup.setVolumeOnAllMembers (Partial Failure)

These cases target the `SpeakerGroup.setVolumeOnAllMembers(_ level: Int) async` method in isolation. All calls use stub `Speaker` doubles with injectable failure. Where XCTest is unavailable, these are manual async-verification steps.

---

### TC-E57-U16

**ID:** TC-E57-U16
**Target:** `SpeakerGroup.setVolumeOnAllMembers` — all-success, two members
**ADR assertion:** §7 assertion #9 — "With two members, both `setVolume(50)` called concurrently."
**Setup:** Two `SpeakerStub` instances: `stubA` (volume = 20, no error), `stubB` (volume = 30, no error). Create `SpeakerGroup(members: [stubA, stubB])`.
**Action:** `await group.setVolumeOnAllMembers(50)`.
**Expected:** Return value has count = 2. Both results are `.success(())`. `stubA.lastSetVolumeLevel == 50`. `stubB.lastSetVolumeLevel == 50`. Both `setVolumeCallCount == 1`.
**Covers spec AC:** US-73 AC-1 (drag-end fires `setVolume` on every member); ADR §7 assertion #9; epics T-5704.

---

### TC-E57-U17

**ID:** TC-E57-U17
**Target:** `SpeakerGroup.setVolumeOnAllMembers` — concurrent dispatch (not serial)
**ADR assertion:** §7 assertion #9 — "Both calls dispatched concurrently."
**Setup:** Two stubs each taking 200 ms to complete (via `Task.sleep`). Both stubs succeed. Measure wall-clock elapsed time.
**Action:** `await group.setVolumeOnAllMembers(50)` and measure total duration.
**Expected:** Total duration ≈ 200 ms (concurrent), not ≈ 400 ms (serial). Confirm `withTaskGroup` fan-out by asserting total elapsed time < 300 ms. Also assert that both `setVolume` start timestamps (recorded by each stub) differ by < 50 ms, confirming near-simultaneous dispatch per US-73 AC-2.
**Covers spec AC:** US-73 AC-2 (all member calls dispatched concurrently; slider drag not blocked); ADR §7 assertion #9; spec NFR (all member requests dispatched concurrently within 50 ms of drag-end).

---

### TC-E57-U18

**ID:** TC-E57-U18
**Target:** `SpeakerGroup.setVolumeOnAllMembers` — one member failure, one success
**ADR assertion:** §7 assertion #10 — "One member failure → `[(ok, .success), (err, .failure)]`."
**Setup:** `stubA`: no error. `stubB`: `setVolumeError = MozartError.unreachable`.
**Action:** `await group.setVolumeOnAllMembers(30)`.
**Expected:** Return array contains exactly one `.success(())` (for stubA) and one `.failure(MozartError.unreachable)` (for stubB). `stubA.lastSetVolumeLevel == 30`. `stubB.setVolumeCallCount == 1` (the call is made; it fails). The failure of stubB does not prevent stubA's call (concurrent, independent per US-73 AC-3).
**Covers spec AC:** US-73 AC-3 (failure on one member logged; success/failure of one does not block others); ADR §7 assertion #10.

---

### TC-E57-U19

**ID:** TC-E57-U19
**Target:** `SpeakerGroup.setVolumeOnAllMembers` — all members fail
**Setup:** Both `stubA` and `stubB` have `setVolumeError = MozartError.timeout`.
**Action:** `await group.setVolumeOnAllMembers(70)`.
**Expected:** Return array contains two `.failure` results. Both stubs' `setVolumeCallCount == 1` (both are still called). No crash. All-failure result is collected correctly.
**Covers spec AC:** US-73 AC-5 (all fail: error toast for all N speakers); ADR §7 assertion #10 (by extension to all-failure case).

---

### TC-E57-U20

**ID:** TC-E57-U20
**Target:** `SpeakerGroup.setVolumeOnAllMembers` — single-member group behaves identically to direct call
**ADR assertion:** Coverage requirement — "Single-member-group."
**Setup:** `SpeakerGroup(members: [stubA])`. `stubA` succeeds.
**Action:** `await group.setVolumeOnAllMembers(50)`.
**Expected:** Return array has count = 1. Result is `.success(())`. `stubA.lastSetVolumeLevel == 50`. `stubA.setVolumeCallCount == 1`. Behaviour is identical to a direct `stubA.setVolume(50)` call (US-73 AC-6).
**Covers spec AC:** US-73 AC-6 (single-speaker card: identical to single `setVolume` call).

---

### TC-E57-U21

**ID:** TC-E57-U21
**Target:** `SpeakerGroup.setVolumeOnAllMembers` — large group (5 members) all succeed
**ADR assertion:** Coverage requirement — "Large group."
**Setup:** Five stubs, all succeeding, each with a 100 ms artificial delay.
**Action:** `await group.setVolumeOnAllMembers(60)`. Measure duration.
**Expected:** All 5 results are `.success(())`. All `lastSetVolumeLevel == 60`. Total elapsed time ≈ 100 ms (concurrent), not 500 ms (serial). Confirms `withTaskGroup` scales beyond 2 members.
**Covers spec AC:** US-73 AC-2 (concurrency); ADR §3 Option A rationale (concurrent fan-out).

---

## 5. Integration Test Cases — SpeakerCard Binding, handleLimitHaptic, and broadcastVolume

These cases test the `SpeakerCard` layer: the `dragVolume` / `lastLimitHaptic` state wiring, the limit-haptic gate, the `broadcastVolume` error-surface logic, and the `WS-event-mid-drag` suppression. They require rendering `SpeakerCard` with injected stubs.

---

### TC-E57-I01

**ID:** TC-E57-I01
**Target:** `handleLimitHaptic(0)` — fires `limitReached()` and "Volume at minimum" announcement
**ADR assertion:** §7 assertion #5 — "`handleLimitHaptic(0)` → `HapticEngine.shared.limitReached()` + 'Volume at minimum' announcement."
**Setup:** `SpeakerCard` with `stubA` (volume = 30, `playbackState = .playing`). Inject `HapticEngineSpy` and `AccessibilityAnnouncementSpy`. `lastLimitHaptic` starts as `nil`.
**Action:** Simulate a drag reaching value 0 (trigger the `InteractiveVolumeBar` binding `set:` path that calls `handleLimitHaptic(0)`).
**Expected:** `HapticEngineSpy.limitReachedCallCount == 1`. `AccessibilityAnnouncementSpy.postedAnnouncements` contains "Volume at minimum". `lastLimitHaptic` is set to 0.
**Covers spec AC:** US-71 AC-6 (limitReached fires when dragged value reaches 0 mid-drag); US-71 AC-7 (VoiceOver announces "Volume at minimum"); ADR §7 assertion #5.

---

### TC-E57-I02

**ID:** TC-E57-I02
**Target:** `handleLimitHaptic(100)` — fires `limitReached()` and "Volume at maximum" announcement
**ADR assertion:** §7 assertion #6 — "`handleLimitHaptic(100)` → `HapticEngine.shared.limitReached()` + 'Volume at maximum' announcement."
**Setup:** Same as TC-E57-I01. `lastLimitHaptic` starts as `nil`.
**Action:** Simulate drag reaching value 100.
**Expected:** `HapticEngineSpy.limitReachedCallCount == 1`. Announcement = "Volume at maximum". `lastLimitHaptic` = 100.
**Covers spec AC:** US-71 AC-6/AC-7; ADR §7 assertion #6; error states table (limit mid-drag).

---

### TC-E57-I03

**ID:** TC-E57-I03
**Target:** `handleLimitHaptic(0)` called twice — fires only on first call (gate blocks second)
**ADR assertion:** §7 assertion #7 — "`handleLimitHaptic(0)` twice → fires only on the first call."
**Setup:** `lastLimitHaptic = nil`. Inject spy.
**Action:** Call `handleLimitHaptic(0)` twice in succession (simulating the user dragging and holding at 0, triggering multiple `onChanged` events at value 0).
**Expected:** `HapticEngineSpy.limitReachedCallCount == 1`. Announcement posted exactly once. `lastLimitHaptic` = 0 after both calls. The gate `if value == 0 && lastLimitHaptic != 0` prevents the second call from firing.
**Covers spec AC:** US-71 AC-6 (haptic fires once per limit boundary crossing); ADR §7 assertion #7; spec error states (re-fires only after leaving and returning to limit).

---

### TC-E57-I04

**ID:** TC-E57-I04
**Target:** `handleLimitHaptic(0)` called twice but with `handleLimitHaptic(50)` in between — gate re-arms
**ADR assertion:** §7 assertion #8 — "`handleLimitHaptic(50)` after `handleLimitHaptic(0)` → resets gate; subsequent `(0)` fires again."
**Setup:** `lastLimitHaptic = nil`. Inject spy.
**Action (sequence):**
1. `handleLimitHaptic(0)` → fires haptic (count = 1). `lastLimitHaptic = 0`.
2. `handleLimitHaptic(50)` → no haptic. `lastLimitHaptic = nil` (gate cleared).
3. `handleLimitHaptic(0)` → fires haptic again (count = 2). `lastLimitHaptic = 0`.
**Expected:** `HapticEngineSpy.limitReachedCallCount == 2`. "Volume at minimum" announced twice. `lastLimitHaptic = 0` after step 3.
**Covers spec AC:** US-71 AC-6 (re-fires after leaving the limit); ADR §7 assertion #8; spec §"Limit haptic" (mid-value clears `lastLimitHaptic`).

---

### TC-E57-I05

**ID:** TC-E57-I05
**Target:** `handleLimitHaptic(100)` gate — same re-arm behaviour at upper limit
**Setup:** `lastLimitHaptic = nil`. Inject spy.
**Action (sequence):**
1. `handleLimitHaptic(100)` → fires (count = 1). `lastLimitHaptic = 100`.
2. `handleLimitHaptic(95)` → no haptic. `lastLimitHaptic = nil` (any value in 1–99 re-arms).
3. `handleLimitHaptic(100)` → fires (count = 2). `lastLimitHaptic = 100`.
**Expected:** `HapticEngineSpy.limitReachedCallCount == 2`. "Volume at maximum" announced twice.
**Covers spec AC:** US-71 AC-6; ADR §7 assertion #8 (symmetric for max limit).

---

### TC-E57-I06

**ID:** TC-E57-I06
**Target:** `SpeakerCard` drag state — `dragVolume` dominates `speaker.volume` during drag
**ADR assertion:** §7 assertion #13 — "WS event arriving mid-drag — slider visual unaffected (`dragVolume != nil` dominates)."
**Setup:** `stubA` with `volume = 40` and `playbackState = .playing`. Render `SpeakerCard`. Begin a drag gesture (simulate `onEditingChanged(true)` fired by `InteractiveVolumeBar`) setting `dragVolume = 60`.
**Action:** While `dragVolume == 60`, externally set `stubA.volume = 20` (simulating a WS event from another app or speaker state update). Read the `InteractiveVolumeBar` binding's current value.
**Expected:** The binding's `get: { dragVolume ?? speaker.volume ?? 0 }` returns 60 (not 20). The slider visual position remains at 60%. The WS event (`stubA.volume = 20`) is dominated by `dragVolume`. The trailing volume number also reads "60".
**Covers spec AC:** US-71 (failure leaves volume reading at last-known `speaker.volume` after drag end — complementary: during drag, `dragVolume` wins); ADR §7 assertion #13; ADR §5 Consequences ("WS events during drag are dominated by `dragVolume`").

---

### TC-E57-I07

**ID:** TC-E57-I07
**Target:** `SpeakerCard` drag end — `dragVolume` clears to `nil`; `lastLimitHaptic` clears to `nil`
**Setup:** `stubA` with `volume = 40`, `playbackState = .playing`. `dragVolume = 70`. `lastLimitHaptic = nil`.
**Action:** Fire `onEditingChanged(false)` (drag end). Allow the resulting `Task { await broadcastVolume(70) }` to complete asynchronously.
**Expected:** Immediately after `onEditingChanged(false)` (before async Task completes): `dragVolume = nil`. `lastLimitHaptic = nil`. The slider binding `get` now falls back to `stubA.volume` (optimistic update from `Speaker.setVolume` on success, or last-known WS value on failure).
**Covers spec AC:** US-71 AC-5 (setVolume called once on drag end); ADR §5 Consequences ("`dragVolume = nil` after onEditingChanged(false)").

---

### TC-E57-I08

**ID:** TC-E57-I08
**Target:** `broadcastVolume` — all success → no toast, no `errorOccurred` haptic
**ADR assertion:** §7 assertion #12 — "`broadcastVolume(50)` all success → no toast; no haptic."
**Setup:** `SpeakerGroupStub` with two stubs, both succeeding. `SpeakerCard` with `$errorMsg`. Inject `HapticEngineSpy`.
**Action:** Trigger drag end with `dragVolume = 50`. Await `broadcastVolume(50)` to complete.
**Expected:** `errorMsg == nil` (no toast written). `HapticEngineSpy.errorOccurredCallCount == 0`. Both stubs received `setVolume(50)`.
**Covers spec AC:** US-73 AC-1 (setVolume on every member); ADR §7 assertion #12.

---

### TC-E57-I09

**ID:** TC-E57-I09
**Target:** `broadcastVolume` — one failure → "Volume failed on 1 speaker" toast; `errorOccurred` haptic; `Log.error`
**ADR assertion:** §7 assertion #11 — "`broadcastVolume(50)` with one failure → 'Volume failed on 1 speaker'; errorOccurred haptic; Log.error."
**Setup:** `SpeakerGroupStub`: `stubA` succeeds, `stubB` fails with `MozartError.unreachable`. `$errorMsg` binding. Inject `HapticEngineSpy`.
**Action:** `await broadcastVolume(50)`.
**Expected:**
- `errorMsg == "Volume failed on 1 speaker"` (singular "speaker").
- `HapticEngineSpy.errorOccurredCallCount == 1`.
- `stubA.setVolumeCallCount == 1`, `stubB.setVolumeCallCount == 1` (both called; one failed).
- Log at ERROR contains `stubB.name` and level 50. (Verify via log spy or console assertion.)
**Covers spec AC:** US-73 AC-4 (partial failure: error toast with failed count); ADR §7 assertion #11; spec error states ("Volume failed on 1 speaker").

---

### TC-E57-I10

**ID:** TC-E57-I10
**Target:** `broadcastVolume` — all failure → "Volume failed on 2 speakers" toast (plural)
**ADR assertion:** Coverage requirement — "All-failure: plural toast text."
**Setup:** `SpeakerGroupStub`: both stubs fail with `MozartError.timeout`. `$errorMsg`. Inject spy.
**Action:** `await broadcastVolume(30)`.
**Expected:**
- `errorMsg == "Volume failed on 2 speakers"` (plural "speakers", not singular).
- `HapticEngineSpy.errorOccurredCallCount == 1` (fires once regardless of failure count).
**Covers spec AC:** US-73 AC-5 (all fail: toast + `errorOccurred` haptic); ADR §7 assertion #11 (plural suffix: `failed.count == 1 ? "speaker" : "speakers"`); spec error states.

---

### TC-E57-I11

**ID:** TC-E57-I11
**Target:** `broadcastVolume` — "1 speaker" vs "2 speakers" pluralisation boundary
**ADR assertion:** Coverage requirement — "broadcastVolume toast text: singular vs plural."
**Setup A:** 1 failure → expected suffix "speaker" (no 's').
**Setup B:** 2 failures → expected suffix "speakers".
**Setup C:** 5 failures → expected suffix "speakers".
**Action:** Run `broadcastVolume` for each setup.
**Expected:** Suffix is "speaker" only when `failed.count == 1`; "speakers" for all other counts. This guards the ternary `failed.count == 1 ? "speaker" : "speakers"` in `broadcastVolume`.
**Covers spec AC:** ADR §7 assertion #11; CF-3 (inline literal acceptable for v1.4); spec error states.

---

### TC-E57-I12

**ID:** TC-E57-I12
**Target:** `SpeakerCard` — slider not rendered in `.stopped` state
**ADR assertion:** §7 assertion #14 — "Drag end on stopped speaker — no crash (slider not rendered in `.stopped` state)."
**Setup:** `stubA` with `playbackState = .stopped`. Render `SpeakerCard`.
**Action:** Inspect `cardContent` for the presence of `InteractiveVolumeBar`.
**Expected:** `InteractiveVolumeBar` is NOT present in the view hierarchy when `playbackState == .stopped`. The stopped branch renders only header + Play pill (per E-56 T-5606). No `dragVolume` state can be set (no drag target exists). No crash can occur from a gesture on a non-rendered view.
**Covers spec AC:** US-71 AC-3 (slider shown only in playing/paused/buffering); design-spec §3 (no volume track in stopped); ADR §7 assertion #14; epics T-5702 ("conditionally render the slider only in `.playing`, `.paused`, and `.buffering` states").

---

### TC-E57-I13

**ID:** TC-E57-I13
**Target:** `SpeakerCard` — `broadcastVolume` dispatched as a `Task` (non-blocking on main actor)
**Setup:** `SpeakerGroupStub` with two stubs, each taking 300 ms. `SpeakerCard` renders with `playbackState = .playing`.
**Action:** Simulate drag end. Observe whether the UI (main thread) is blocked during the 300 ms `broadcastVolume` call.
**Expected:** The UI is not blocked. The drag gesture completes immediately (`dragVolume = nil` is set synchronously). The `Task { await broadcastVolume(final) }` runs concurrently. No UI jank. VoiceOver and other gestures remain responsive during broadcast.
**Covers spec AC:** US-73 AC-2 (slider drag not blocked waiting for completion); spec NFR — latency (setVolume dispatched within 50 ms of drag-end).

---

### TC-E57-I14

**ID:** TC-E57-I14
**Target:** `SpeakerCard` — VoiceOver adjustable action fires `broadcastVolume` immediately
**ADR assertion:** Coverage requirement — "VoiceOver adjustable action increments/decrements by 5, fires broadcast immediately."
**Setup:** `SpeakerGroupStub` with one stub (volume = 50, `playbackState = .playing`). Inject `HapticEngineSpy`.
**Action:** Trigger `.accessibilityAdjustableAction(.increment)` on the `InteractiveVolumeBar` element within the rendered `SpeakerCard`.
**Expected:** `vol` becomes 55. `onEditingChanged(true)` fires, then `onEditingChanged(false)` fires immediately in the same call (per ADR §7 contract item 7). The `onEditingChanged(false)` handler in `SpeakerCard` dispatches `broadcastVolume(55)` as a `Task`. `stub.setVolumeCallCount == 1` after Task completes. No intermediate `dragVolume` state lingers.
**Covers spec AC:** T-5706 (VoiceOver adjustable action shares same `onEditingChanged` path); ADR §7 contract item 7.

---

## 6. Acceptance Test Cases — Full Drag + Group Broadcast End-to-End

These cases test the complete user flow from gesture start through API dispatch and response, including multi-speaker group scenarios.

---

### TC-E57-A01

**ID:** TC-E57-A01
**Target:** Single-speaker full drag: value 20 → 60 → one `setVolume(60)` call on release
**Setup:** `SpeakerCard` with `stubA` (volume = 20, `playbackState = .playing`, no group). Inject spy.
**Action (sequence):**
1. Simulate drag start at x = 40% (value 20). `onEditingChanged(true)` fires.
2. Drag through x = 50% (value 50), x = 55% (value 55).
3. Drag end at x = 60% (value 60). `onEditingChanged(false)` fires.
4. `Task { await broadcastVolume(60) }` completes.
**Expected:**
- `dragVolume` transitions: nil → 50 → 55 → 60 → nil (cleared on drag end).
- `stubA.setVolumeCallCount == 1`. `stubA.lastSetVolumeLevel == 60`.
- `errorMsg == nil` (success).
- `HapticEngineSpy.limitReachedCallCount == 0` (no limit crossed).
**Covers spec AC:** US-71 AC-5 (setVolume called exactly once per drag on drag end); ADR §7 assertion #2 (drag binding flow); epics T-5707 item 1.

---

### TC-E57-A02

**ID:** TC-E57-A02
**Target:** Single-speaker full drag to 0 — limit haptic, announcement, then `setVolume(0)` on release
**Setup:** `SpeakerCard` with `stubA` (volume = 50, `playbackState = .playing`). Inject `HapticEngineSpy` and `AccessibilityAnnouncementSpy`.
**Action:** Drag from x = 50% down to x = 0% (value 0). Release.
**Expected:**
- During drag: `HapticEngineSpy.limitReachedCallCount == 1` (fires when value first reaches 0). "Volume at minimum" announced once.
- Holding at 0 and receiving additional `onChanged` at x = 0: `limitReachedCallCount` stays 1 (gate blocks re-fire).
- On release: `stubA.setVolumeCallCount == 1`. `stubA.lastSetVolumeLevel == 0`. `dragVolume = nil`. `lastLimitHaptic = nil`.
**Covers spec AC:** US-71 AC-6 (limitReached fires once per limit crossing); US-71 AC-7 (VoiceOver "Volume at minimum"); ADR §7 assertions #5, #7; epics T-5707 items 2, 4.

---

### TC-E57-A03

**ID:** TC-E57-A03
**Target:** Single-speaker full drag to 100 — limit haptic, announcement, then `setVolume(100)` on release
**Setup:** `stubA` (volume = 30, `playbackState = .playing`). Same spies.
**Action:** Drag from x = 30% up to x = 100% (value 100). Release.
**Expected:**
- `HapticEngineSpy.limitReachedCallCount == 1` (fires once at 100). "Volume at maximum" announced.
- On release: `stubA.lastSetVolumeLevel == 100`. `dragVolume = nil`.
**Covers spec AC:** US-71 AC-6/AC-7; ADR §7 assertions #6, #7; epics T-5707 item 3.

---

### TC-E57-A04

**ID:** TC-E57-A04
**Target:** Tap-in-place at midpoint — `setVolume` fires for the tapped value
**Setup:** `stubA` (volume = 20, `playbackState = .paused`). W = 200 pt. Tap at x = 100 pt (exactly 50%). Release immediately (zero drag distance).
**Action:** `DragGesture(minimumDistance: 0)` fires `onChanged` then `onEnded` at same location.
**Expected:** `vol` snaps to 50. `stubA.setVolumeCallCount == 1`. `stubA.lastSetVolumeLevel == 50`. No crash. Tap is treated as a zero-distance drag per `minimumDistance: 0`.
**Covers spec AC:** US-71 AC-2 (gold fill is touch affordance; tap anywhere sets value); ADR §7 assertion #4; epics T-5707 item 5.

---

### TC-E57-A05

**ID:** TC-E57-A05
**Target:** Group broadcast end-to-end: 2 speakers both receive volume 50 concurrently
**Setup:** `SpeakerCard` with `SpeakerGroupStub(members: [stubA, stubB])`. Both stubs succeed. `stubA.volume = 30`, `stubB.volume = 40`.
**Action:** Drag slider to 50%, release. Await `broadcastVolume(50)`.
**Expected:** `stubA.lastSetVolumeLevel == 50`. `stubB.lastSetVolumeLevel == 50`. `stubA.setVolumeCallCount == 1`. `stubB.setVolumeCallCount == 1`. `errorMsg == nil`. Both calls dispatched within ~50 ms of each other (concurrent).
**Covers spec AC:** US-73 AC-1 (setVolume on every member concurrently on drag-end); ADR §7 assertion #9; epics T-5708 item 1.

---

### TC-E57-A06

**ID:** TC-E57-A06
**Target:** Group broadcast: one follower disconnected — error toast "Volume failed on 1 speaker"; connected speaker reaches target
**Setup:** `SpeakerGroupStub(members: [stubA, stubB])`. `stubA` succeeds. `stubB.setVolumeError = MozartError.unreachable`. `$errorMsg`. Inject `HapticEngineSpy`.
**Action:** Drag to 30%, release. Await `broadcastVolume(30)`.
**Expected:** `stubA.lastSetVolumeLevel == 30` (connected speaker reaches target). `errorMsg == "Volume failed on 1 speaker"`. `HapticEngineSpy.errorOccurredCallCount == 1`.
**Covers spec AC:** US-73 AC-3 (failure on one member logged; others succeed); US-73 AC-4 (partial failure: toast with count); epics T-5708 item 2.

---

### TC-E57-A07

**ID:** TC-E57-A07
**Target:** Group broadcast: both speakers disconnected — error toast "Volume failed on 2 speakers"
**Setup:** Both stubs fail. `$errorMsg`. Inject spy.
**Action:** Drag to 30%, release. Await.
**Expected:** `errorMsg == "Volume failed on 2 speakers"`. `HapticEngineSpy.errorOccurredCallCount == 1`. Both stubs' `setVolumeCallCount == 1` (both called, both failed).
**Covers spec AC:** US-73 AC-5 (all fail: toast + `errorOccurred`); epics T-5708 item 3; ADR §7 assertion #12 (by negation — failure path).

---

### TC-E57-A08

**ID:** TC-E57-A08
**Target:** `dragVolume` dominates WS event during active drag — full end-to-end
**ADR assertion:** §7 assertion #13 — full path from drag start through WS update to drag end.
**Setup:** `stubA` (volume = 40, `playbackState = .playing`). Begin drag; `dragVolume = 70`.
**Action:** While drag is in progress, set `stubA.volume = 10` (simulating WS event). Read slider binding value. Continue drag to 80. Release.
**Expected:**
- During drag (after WS update): slider binding `get` returns `dragVolume` = 70, not 10.
- On further drag to 80: `dragVolume = 80`.
- On release: `stubA.setVolumeCallCount == 1`. `stubA.lastSetVolumeLevel == 80`. `dragVolume = nil`. Slider now reads `stubA.volume` (which may be 10 until the `setVolume(80)` call's optimistic update or WS event updates it).
**Covers spec AC:** US-71 AC-8 (failed setVolume: volume reading at last-known `speaker.volume` after failure — complementary: during drag `dragVolume` wins); ADR §7 assertion #13; epics T-5707 item 7.

---

## 7. Error States and Boundary Values

---

### TC-E57-E01

**ID:** TC-E57-E01
**Target:** `setVolume` fails on single speaker — toast appears; slider visual driven by WS event after drag
**Setup:** `stubA.setVolumeError = MozartError.unreachable`. `playbackState = .playing`. `stubA.volume = 40` (starts at 40; WS event will leave it at 40 after failure). `$errorMsg`. Inject spy.
**Action:** Drag to 80, release. Await `broadcastVolume(80)`.
**Expected:** `errorMsg == "Volume failed on 1 speaker"`. `HapticEngineSpy.errorOccurredCallCount == 1`. After `dragVolume = nil`, slider binding reads `stubA.volume` = 40 (unchanged because `setVolume` failed and no WS update fires to change it). Slider visually returns to 40.
**Covers spec AC:** US-71 AC-8 (failed setVolume: volume reading at last-known `speaker.volume`); spec error states ("Slider drag end and setVolume fails on a single speaker").

---

### TC-E57-E02

**ID:** TC-E57-E02
**Target:** `setVolume` HTTP 5xx — toast; `errorOccurred` haptic
**Setup:** `stubA.setVolumeError = MozartError.httpError(500)`. Inject spy. `$errorMsg`.
**Action:** Drag to 60, release. Await.
**Expected:** `errorMsg == "Volume failed on 1 speaker"`. `HapticEngineSpy.errorOccurredCallCount == 1`. Matches MozartError HTTP error path.
**Covers spec AC:** spec error states ("Slider drag end and setVolume fails on single speaker"); US-73 ACs (error surface).

---

### TC-E57-E03

**ID:** TC-E57-E03
**Target:** `setVolume` timeout — toast; `errorOccurred` haptic
**Setup:** `stubA.setVolumeError = MozartError.timeout`. Inject spy. `$errorMsg`.
**Action:** Drag to 50, release. Await.
**Expected:** `errorMsg == "Volume failed on 1 speaker"`. `HapticEngineSpy.errorOccurredCallCount == 1`. 5 s `MozartClient` timeout is the underlying error.
**Covers spec AC:** spec error states; spec NFR — network (Mozart 5 s timeout applies).

---

### TC-E57-E04

**ID:** TC-E57-E04
**Target:** Speaker transitions playing → stopped while user is dragging — drag continues, then slider disappears
**ADR assertion:** §7 assertion #14 (partial) — drag end on stopped speaker results in no crash.
**Setup:** `stubA` starts `playbackState = .playing`. Drag begins; `dragVolume = 60`.
**Action:** While dragging, set `stubA.playbackState = .stopped` (simulating WS state change). Release the drag (fire `onEditingChanged(false)`).
**Expected:**
- During drag: `dragVolume` continues to drive the visual position (slider still visible until the SwiftUI re-render cycle catches up).
- On `onEditingChanged(false)`: `broadcastVolume(60)` is dispatched as a `Task`. `dragVolume = nil`. `lastLimitHaptic = nil`.
- After the re-render triggered by `playbackState = .stopped`: `InteractiveVolumeBar` is no longer rendered (stopped branch has no slider).
- `broadcastVolume(60)` Task completes — if `stubA` is now unreachable, error toast appears. No crash regardless.
**Covers spec AC:** ADR §7 assertion #14; spec error states ("Speaker transitions from playing → stopped while user is dragging slider").

---

### TC-E57-E05

**ID:** TC-E57-E05
**Target:** Boundary — drag x position clamped to [0, 1] before snap: negative x and x > W
**Setup:** W = 200 pt. Simulate drag events at x = -20 pt (off left edge) and x = 250 pt (off right edge).
**Action:** Apply `onChanged` at each extreme.
**Expected:**
- x = -20 pt: `rawPercent = -20/200 = -10%`. Clamped to 0. Snapped to 0. `vol = 0`.
- x = 250 pt: `rawPercent = 250/200 = 125%`. Clamped to 100. Snapped to 100. `vol = 100`.
No crash, no negative fill width, no overflow.
**Covers spec AC:** US-71 AC-1 (range 0–100, step 5); ADR §7 contract #5 ("clamped 0–100 → snapped to nearest 5").

---

### TC-E57-E06

**ID:** TC-E57-E06
**Target:** Boundary — `speaker.volume` is `nil` (speaker volume not yet fetched)
**Setup:** `stubA.volume = nil` (simulating a speaker where volume has not yet been populated from REST init). `dragVolume = nil`.
**Action:** Read the `InteractiveVolumeBar` binding `get` value.
**Expected:** Binding returns `dragVolume ?? speaker.volume ?? 0` = `nil ?? nil ?? 0` = 0. Slider renders at 0% fill. No crash. Trailing number reads "0".
**Covers spec AC:** ADR §7 `SpeakerCard` binding contract (`get: { dragVolume ?? speaker.volume ?? 0 }`).

---

### TC-E57-E07

**ID:** TC-E57-E07
**Target:** Limit haptic — no repeat at boundary value 0 while `lastLimitHaptic == 0`
**Setup:** `lastLimitHaptic = 0` (set by a prior `handleLimitHaptic(0)` call). Inject spy.
**Action:** Call `handleLimitHaptic(0)` again (simulating multiple `onChanged` events while drag is held at 0).
**Expected:** `HapticEngineSpy.limitReachedCallCount == 0` (this second call does NOT fire — gate is `lastLimitHaptic != 0`). "Volume at minimum" NOT announced a second time.
**Covers spec AC:** US-71 AC-6; ADR §7 assertion #7; spec error states ("Re-fires only after the value leaves the limit and returns").

---

### TC-E57-E08

**ID:** TC-E57-E08
**Target:** Limit haptic — no repeat at boundary value 100 while `lastLimitHaptic == 100`
**Setup:** `lastLimitHaptic = 100`. Inject spy.
**Action:** `handleLimitHaptic(100)` again.
**Expected:** `HapticEngineSpy.limitReachedCallCount == 0`. "Volume at maximum" NOT re-announced.
**Covers spec AC:** US-71 AC-6; ADR §7 assertion #7.

---

### TC-E57-E09

**ID:** TC-E57-E09
**Target:** `setVolumeOnAllMembers` — speaker removed from group between drag start and drag end
**Setup:** `SpeakerGroupStub(members: [stubA, stubB])`. Between drag start and `onEditingChanged(false)`, remove `stubB` from the group (simulating a speaker going offline mid-drag). The `broadcastVolume` call takes a snapshot of `group.members` at drag-end.
**Action:** Release drag. Await `broadcastVolume`.
**Expected:** The `withTaskGroup` iteration uses whichever snapshot `setVolumeOnAllMembers` receives at call time. If `stubB` is removed from `members` before `broadcastVolume` calls `setVolumeOnAllMembers`, `stubB` does NOT receive the call. If `stubB` is still in `members` at call time but unreachable, it receives the call and fails (surfaces as a per-speaker failure per TC-E57-A06). Spec error states: "The `withTaskGroup` iteration uses the snapshot of `group.members` taken at drag-end." No crash.
**Covers spec AC:** spec error states ("Speaker is removed from `SpeakerGroup.members` mid-drag").

---

## 8. Coverage Matrix (AC/ER → TC IDs)

| AC / Contract Assertion | TC IDs | Status |
|---|---|---|
| **ADR §7 assertion #1** — `value = 50` → gold fill at 50% of track width | TC-E57-U01 | Covered |
| **ADR §7 assertion #2** — Drag from 20 → 60 → binding receives 60; `onEditingChanged(true)` on first `onChanged` | TC-E57-U05, TC-E57-A01 | Covered |
| **ADR §7 assertion #3** — Drag end → `onEditingChanged(false)` exactly once; no `false` mid-drag | TC-E57-U06, TC-E57-A01 | Covered |
| **ADR §7 assertion #4** — Tap at 75%; value snaps to 75 (minimumDistance: 0) | TC-E57-U07, TC-E57-A04 | Covered |
| **ADR §7 assertion #5** — `handleLimitHaptic(0)` → `limitReached()` + "Volume at minimum" | TC-E57-I01, TC-E57-A02 | Covered |
| **ADR §7 assertion #6** — `handleLimitHaptic(100)` → `limitReached()` + "Volume at maximum" | TC-E57-I02, TC-E57-A03 | Covered |
| **ADR §7 assertion #7** — `handleLimitHaptic(0)` twice → fires only on first call | TC-E57-I03, TC-E57-E07 | Covered |
| **ADR §7 assertion #8** — `handleLimitHaptic(50)` after `(0)` resets gate; subsequent `(0)` fires again | TC-E57-I04, TC-E57-I05 | Covered |
| **ADR §7 assertion #9** — `setVolumeOnAllMembers(50)` two members: both called concurrently | TC-E57-U16, TC-E57-U17, TC-E57-A05 | Covered |
| **ADR §7 assertion #10** — One member failure → `[(ok, .success), (err, .failure)]` | TC-E57-U18, TC-E57-A06 | Covered |
| **ADR §7 assertion #11** — `broadcastVolume(50)` one failure → "Volume failed on 1 speaker"; `errorOccurred`; Log.error | TC-E57-I09, TC-E57-A06 | Covered |
| **ADR §7 assertion #12** — `broadcastVolume(50)` all success → no toast; no haptic | TC-E57-I08, TC-E57-A05 | Covered |
| **ADR §7 assertion #13** — WS event mid-drag → slider unaffected (`dragVolume` dominates) | TC-E57-I06, TC-E57-A08 | Covered |
| **ADR §7 assertion #14** — Drag end on stopped speaker → no crash (slider not rendered) | TC-E57-I12, TC-E57-E04 | Covered |
| **US-71 AC-1** — Slider range 0–100, step 5 (interactive; replaces static bar) | TC-E57-U08, TC-E57-U04 | Covered |
| **US-71 AC-2** — Invisible thumb; gold fill is touch affordance | TC-E57-U07, TC-E57-U15, TC-E57-A04 | Covered |
| **US-71 AC-3** — Slider shown only in playing/paused/buffering (not stopped) | TC-E57-I12 | Covered |
| **US-71 AC-4** — Numeric readout updates live during drag | TC-E57-U01, TC-E57-U02, TC-E57-U03, TC-E57-U05 | Covered |
| **US-71 AC-5** — `setVolume` called exactly once per drag, on drag end | TC-E57-U06, TC-E57-A01, TC-E57-A04 | Covered |
| **US-71 AC-6** — `limitReached()` fires once per limit boundary crossing mid-drag | TC-E57-I01, TC-E57-I02, TC-E57-I03, TC-E57-A02, TC-E57-A03, TC-E57-E07, TC-E57-E08 | Covered |
| **US-71 AC-7** — VoiceOver announces "Volume at maximum"/"minimum" at limit | TC-E57-I01, TC-E57-I02, TC-E57-A02, TC-E57-A03 | Covered |
| **US-71 AC-8** — Failed `setVolume`: volume reading driven by `speaker.volume` (last WS value) | TC-E57-E01, TC-E57-I07 | Covered |
| **US-73 AC-1** — Drag-end fires `setVolume` on every group member concurrently | TC-E57-U16, TC-E57-U17, TC-E57-A05 | Covered |
| **US-73 AC-2** — All member calls dispatched concurrently; drag not blocked | TC-E57-U17, TC-E57-U21, TC-E57-I13, TC-E57-A05 | Covered |
| **US-73 AC-3** — One member failure logged; others unaffected | TC-E57-U18, TC-E57-A06 | Covered |
| **US-73 AC-4** — Partial failure: toast "Volume failed on N speakers" | TC-E57-I09, TC-E57-I10, TC-E57-I11, TC-E57-A06 | Covered |
| **US-73 AC-5** — All fail: toast + `errorOccurred` once | TC-E57-U19, TC-E57-I10, TC-E57-A07 | Covered |
| **US-73 AC-6** — Single-speaker card: identical to direct `setVolume` | TC-E57-U20, TC-E57-A01 | Covered |
| **US-73 AC-7** — Transport NOT broadcast; volume IS broadcast | TC-E57-I08 (volume; E-56 covers transport) | Covered |
| **Snap-to-5 at boundary: 0** | TC-E57-U02, TC-E57-U08, TC-E57-A02 | Covered |
| **Snap-to-5 at boundary: 5** | TC-E57-U04, TC-E57-U08 | Covered |
| **Snap-to-5 at boundary: 50** | TC-E57-U01, TC-E57-U08 | Covered |
| **Snap-to-5 at boundary: 95** | TC-E57-U04, TC-E57-U08 | Covered |
| **Snap-to-5 at boundary: 100** | TC-E57-U03, TC-E57-U08, TC-E57-A03 | Covered |
| **Tap-as-zero-distance-drag (minimumDistance: 0)** | TC-E57-U07, TC-E57-A04 | Covered |
| **Limit haptic gated by `lastLimitHaptic` (no repeat at 0)** | TC-E57-I03, TC-E57-E07 | Covered |
| **Limit haptic gated by `lastLimitHaptic` (no repeat at 100)** | TC-E57-E08 | Covered |
| **`setVolumeOnAllMembers`: all-success** | TC-E57-U16, TC-E57-A05 | Covered |
| **`setVolumeOnAllMembers`: one-failure** | TC-E57-U18, TC-E57-A06 | Covered |
| **`setVolumeOnAllMembers`: all-failure** | TC-E57-U19, TC-E57-A07 | Covered |
| **`setVolumeOnAllMembers`: single-member-group** | TC-E57-U20 | Covered |
| **`setVolumeOnAllMembers`: large group (5 members)** | TC-E57-U21 | Covered |
| **broadcastVolume toast: singular "1 speaker"** | TC-E57-I09, TC-E57-I11 | Covered |
| **broadcastVolume toast: plural "2 speakers"** | TC-E57-I10, TC-E57-I11, TC-E57-A07 | Covered |
| **WS event mid-drag: slider visual unaffected** | TC-E57-I06, TC-E57-A08 | Covered |
| **Drag end on stopped speaker: no crash** | TC-E57-I12, TC-E57-E04 | Covered |
| **VoiceOver adjustable action: increment/decrement by 5** | TC-E57-U11, TC-E57-U12, TC-E57-I14 | Covered |
| **VoiceOver adjustable action fires broadcast immediately** | TC-E57-U11, TC-E57-I14 | Covered |
| **VoiceOver adjustable action at upper boundary (no overshoot)** | TC-E57-U13 | Covered |
| **VoiceOver adjustable action at lower boundary (no undershoot)** | TC-E57-U14 | Covered |
| **`speaker.volume = nil` → binding defaults to 0** | TC-E57-E06 | Covered |
| **Drag x clamped at negative / beyond track width** | TC-E57-E05 | Covered |
| **Error: MozartError.unreachable on setVolume** | TC-E57-E01, TC-E57-A06 | Covered |
| **Error: MozartError.httpError(5xx) on setVolume** | TC-E57-E02 | Covered |
| **Error: MozartError.timeout on setVolume** | TC-E57-E03 | Covered |
| **Error: speaker removed from group mid-drag** | TC-E57-E09 | Covered |
| **Error: speaker transitions playing → stopped mid-drag** | TC-E57-E04 | Covered |
| **`Speaker.setVolume` optimistically updates `speaker.volume` on success** | TC-E57-I07, TC-E57-A08 (noted; full WS round-trip deferred to manual) | Partial (manual) |
| **Visual fidelity: matches pre-E-57 `volumeTrack(level:)` appearance** | TC-E57-U15 | Covered (manual) |
| **Design-spec §1.3 padding: `Spacing.s24` horizontal, `Spacing.s12` vertical** | TC-E57-A09 (§10 deferred to manual snapshot) | Deferred (manual) |

---

## 9. Spec Gaps Discovered

The following ambiguities or omissions were identified during test-plan authoring. None are implementation blockers; each is flagged for the Spec Author and Architect to resolve before QA sign-off.

**Gap 1 — Snap formula: "nearest 5" is ambiguous at exact midpoints**

The ADR specifies "clamped 0–100 → snapped to nearest 5" but does not specify tie-breaking behaviour at exact midpoints (e.g. 2.5% → 0 or 5? 7.5% → 5 or 10?). Swift's `Int(x.rounded())` uses "round half to even" (banker's rounding), while `(Int(x / 5 + 0.5)) * 5` rounds half up. TC-E57-U08 tests known non-midpoint values only. The implementation should document which rounding rule is used; this matters at drag positions where `rawPercent % 5 == 2.5`. Recommendation: specify `round half up` for user-visible snapping to avoid unexpected stalls at midpoint values.

**Gap 2 — `InteractiveVolumeBar.isEditing` not exposed for external inspection**

The `@State private var isEditing: Bool` that gates `onEditingChanged(true)` to the first `onChanged` call is private to `InteractiveVolumeBar`. TC-E57-U05 must infer its behaviour indirectly through `onEditingChanged` call counts. If a future XCTest target is created, `@testable import Voxio` does not expose `@State` properties. The spec (and ADR §7 contract item 5) should clarify that the gate is observable only through side effects. This is a test-harness gap, not an implementation gap.

**Gap 3 — `Log.error` in `broadcastVolume`: log spy not specified in test infrastructure**

TC-E57-I09 asserts that `Log.error` is called with the failing speaker's name and level. `Logger.swift` (VERBOSE/INFO/ERROR) has no documented test-spy mechanism in the existing codebase. TC-E57-I09 currently marks this assertion as "verify via console" for manual runs. If a `LogSpy` is added to the test infrastructure (analogous to `HapticEngineSpy`), TC-E57-I09 should be updated to assert on logged entries programmatically. This is a test-infrastructure gap; the functional requirement (Log.error is called) stands.

**Gap 4 — `broadcastVolume` calls `resolvedGroup.setVolumeOnAllMembers` but spec refers to both `group.setVolumeOnAllMembers` and `resolvedGroup.setVolumeOnAllMembers`**

The epics doc T-5705 shows `group.setVolumeOnAllMembers(level)` (bare `group`), while the ADR §7 binding code shows `resolvedGroup.setVolumeOnAllMembers(level)` (via the computed property from E-56). These are functionally equivalent because `resolvedGroup` always returns a valid `SpeakerGroup` (wrapping single-speaker cards in `SpeakerGroup.single`). However, TC-E57-A01 (single-speaker, no group) would crash if the bare `group` variable (which is `Optional<SpeakerGroup>`) is used without nil-checking. The Implementer must confirm `broadcastVolume` calls `resolvedGroup` (non-optional) and the epics doc wording is updated. This is a documentation inconsistency, not a functional gap.

**Gap 5 — Reduce Motion: spec states "no spring on drag" but does not specify the external-value animation behaviour under Reduce Motion**

ADR §7 contract item 9 states "Reduce Motion: gold fill follows touch directly; no spring on drag." This covers the drag path. The `.animation(.easeOut(duration: 0.3), value: value)` for external value changes is not addressed under Reduce Motion. Best practice (matching Voxio's existing `BeoAnimation` approach) would be to suppress or shorten this animation when `accessibilityReduceMotion` is true. TC-E57-U09 does not test the Reduce Motion path for external value changes. The spec should clarify whether the `.easeOut` animation is suppressed under Reduce Motion (as it is for card-level animations in `design-spec-home-screen-redesign.md`). Deferred to a future accessibility audit if not resolved pre-implementation.

**Gap 6 — `AccessibilityNotification.Announcement` vs. `UIAccessibility.post` — test spy not specified**

TC-E57-I01 / TC-E57-I02 rely on an `AccessibilityAnnouncementSpy` to capture posted announcements. The codebase uses `AccessibilityNotification.Announcement(_:).post()` (iOS 17+ API confirmed safe per ADR §9). There is no existing spy mechanism documented in test-plan-E56 for this API. The test infrastructure will need to either swizzle the `post()` method or use a dependency-injectable announcement closure. The spec does not describe how this is to be mocked. Recommendation: add an `AnnouncementPoster` protocol injectable into `SpeakerCard` (or `handleLimitHaptic`), with a live implementation calling `AccessibilityNotification.Announcement` and a spy implementation recording strings. This unblocks TC-E57-I01, TC-E57-I02, TC-E57-I04, TC-E57-I05, TC-E57-A02, TC-E57-A03.

---

## 10. Tests Deferred to Manual Device Verification

The following items require a real Mozart speaker, a physical device with VoiceOver, or platform-level tooling and cannot be fully automated without a dedicated XCTest target.

| Item | Reason for Deferral | Epic Task |
|---|---|---|
| Drag slider from 20 to 60 on real speaker: `setVolume(60)` fires; speaker changes volume within ~1 s | Requires real Mozart speaker for full WS-event round-trip; mock stubs cover the API-call path (TC-E57-A01) | T-5707 item 1 |
| Drag to 0: `limitReached` haptic felt physically; "Volume at minimum" announced by VoiceOver | Haptic cannot be asserted programmatically without device; VoiceOver announcement requires screen reader active | T-5707 items 2, 3 |
| Drag to 100: `limitReached` haptic felt; "Volume at maximum" announced | Same as above | T-5707 item 3 |
| Tap-and-release at midpoint on real slider: `setVolume` fires for tapped value | Real gesture recogniser required; stub simulation covers the logic (TC-E57-A04) | T-5707 item 5 |
| Disconnect speaker → drag and release → error toast appears; `errorOccurred` haptic felt | Physical network disconnection required; MozartError.unreachable covered in TC-E57-E01 | T-5707 item 6 |
| WS event mid-drag from another source changes `speaker.volume` live on device | Real WS event from B&O Mozart speaker required; logic covered in TC-E57-A08 | T-5707 item 7 |
| Multi-speaker group: both speakers' physical volumes change to broadcast value | Two real Mozart speakers required; stub covers concurrent call dispatch (TC-E57-A05, TC-E57-U17) | T-5708 items 1–4 |
| VoiceOver reads "Volume" label and "N percent" value; adjustable rotor increments/decrements by 5 | Requires VoiceOver active; accessibilityLabel/Value logic covered by TC-E57-U10–U14 | T-5706; T-5707 |
| VoiceOver "Volume at minimum"/"maximum" announcement heard through speaker; no double-announcement on hold | Screen reader must be running for audio announcement verification | T-5707 items 2, 3 |
| Slider padding pixel accuracy: `Spacing.s24` horizontal, `Spacing.s12` vertical | SwiftUI padding values not introspectable via XCTest; requires Xcode canvas ruler or snapshot comparison | T-5701/T-5702; design-spec §1.3 |
| Reduce Motion: gold fill tracks touch directly; `.easeOut(duration: 0.3)` suppressed for external updates | Requires Reduce Motion enabled on device; visual verification in canvas | ADR §7 contract #9; spec NFR Accessibility |
| `Speaker.setVolume` optimistic update: `speaker.volume` updates before WS event arrives | Requires real speaker WS event sequencing; optimism is documented in ADR §2 CF-2 | T-5707 (full round-trip) |
| Touch-up to API dispatch latency ≤ 50 ms | Sub-100 ms timing assertions unreliable in XCUITest; Instruments/MetricKit required | spec NFR Latency |
