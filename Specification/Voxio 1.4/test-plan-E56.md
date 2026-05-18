# Test Plan — E-56 Play/Pause Toggle Button

**Status:** Draft
**Date:** 2026-05-12
**Refs:** ADR-E56-play-pause-toggle.md, spec-touch-playback-controls.md US-70/US-73, design-spec-touch-playback-controls.md §1.2/§2.1/§3.1/§5, epics-and-tasks-touch-playback-controls.md E-56

---

## 1. Scope

This plan covers the testable interface contract introduced by E-56: the `SpeakerCard.cardContent` four-way switch on `SpeakerPlaybackState`; the private `transportRow` computed view and its icon/role mapping; the `DarkGlassIconButton` size parameter and the resulting hit-area formula; `PlaybackBars` animation gating on playback state; the group-aware `resolvedGroup` computed property and the `SpeakerGroup.single(_:)` fallback; the `onPlayTapped()` / `onPauseTapped()` handlers, including synchronous haptic ordering, Task dispatch, and absence of optimistic state mutation; the `showErrorToast` / `@Binding errorMessage:` pathway through `HomeView`; the stopped-state card branch (Play pill present; volumeTrack + nowPlayingPanel + transportRow absent); and the accessibility loosening to `.accessibilityElement(children: .contain)` with header-relocated summary.

Every ADR §7 behavioural assertion (1–13) and every AC under US-70 and US-73 that falls within E-56 scope is covered by at least one TC.

What is out of scope:

- E-57 interactive volume slider (separate test plan).
- E-58 favorites row (separate test plan).
- US-71 and US-72 acceptance criteria (E-57 and E-58 scope respectively).
- Group volume broadcast (`setVolumeOnAllMembers`) — E-57 T-5704/T-5705.
- SwiftUI preview correctness (T-5609 is a developer verification step, not a regression test case).
- Backend, telemetry, voice pipeline.

---

## 2. Test Environment

| Item | Value |
|---|---|
| Platform | iOS 26, iPhone (portrait) |
| Framework | SwiftUI, `@Observable @MainActor` |
| Test harness | XCTest (unit) + XCUITest (UI/acceptance) — no separate test target exists in the repo at plan-authoring time. Unit tests belong in a new `VoxioTests` target; UI tests in `VoxioUITests`. |
| Accessibility testing | Xcode Accessibility Inspector + VoiceOver on device/simulator |
| Reduce Motion | iOS Settings → Accessibility → Motion → Reduce Motion |
| Speaker doubles | `SpeakerStub: @Observable @MainActor` — exposes writable `playbackState: SpeakerPlaybackState` and a `playCallCount: Int` / `pauseCallCount: Int` counter; records errors thrown via `playError: Error?` / `pauseError: Error?` injected before the call. `SpeakerGroup.single(stub)` wraps it for solo-card tests. |
| Group doubles | `SpeakerGroupStub` — wraps one or more `SpeakerStub` instances; exposes `hostSpeaker` property so transport assertions can verify which stub received the call. |
| Source files under test | `iOS/Voxio/Features/Home/SpeakerCard.swift`, `iOS/Voxio/DesignSystem/DarkGlassButton.swift`, `iOS/Voxio/Features/Home/Components/PlaybackBars.swift`, `iOS/Voxio/Features/Home/HomeView.swift`, `iOS/Voxio/Features/Home/SessionStripView.swift`, `iOS/Voxio/Core/Strings/UIStrings.swift` |
| `HapticEngine` double | Replace `HapticEngine.shared` with a test-injectable `HapticEngineSpy` that records `commandRecognised()` and `errorOccurred()` call counts and the order they were called relative to the async task dispatch. |

---

## 3. Unit-Level Test Cases (cardContent Branch Routing, resolvedGroup, PlaybackBars Freeze)

These cases test `SpeakerCard.cardContent`'s switch routing and the `resolvedGroup` computed property in isolation. They are host-app tests using ViewInspector or equivalent, or plain XCTest assertions on models via `@testable import Voxio`.

---

### TC-E56-U01

**ID:** TC-E56-U01
**Target:** `SpeakerCard.cardContent` — `.playing` branch routing
**Setup:** Instantiate `SpeakerCard` with a `SpeakerStub` whose `playbackState = .playing`. Pass `isExpanded: false`, `roll: 0`, `pitch: 0`, `errorMessage: .constant(nil)`.
**Action:** Inspect `cardContent` for the presence of `transportRow` (or a `DarkGlassIconButton` with symbol `pause.fill`), the presence of `nowPlayingPanel`, and the absence of a full-width Play pill (`DarkGlassButton` with label "Play").
**Expected:** `transportRow` is present. `nowPlayingPanel` is present. No full-width Play `DarkGlassButton` pill in the hierarchy. `volumeTrack` / slider region is present. This confirms the playing/paused/buffering branch is active, not the stopped branch.
**Covers ADR contract assertion:** §7 assertion #1 (`.playing` → transportRow with `pause.fill`)
**Covers spec AC:** US-70 AC-1 (playing state: card shows pause button)

---

### TC-E56-U02

**ID:** TC-E56-U02
**Target:** `SpeakerCard.cardContent` — `.paused` branch routing
**Setup:** `SpeakerStub` with `playbackState = .paused`. Same other parameters as TC-E56-U01.
**Action:** Inspect `cardContent` for a `DarkGlassIconButton` with symbol `play.fill`, role `.confirm`, and label matching `UIStrings.forLanguage(...).play`. Confirm `nowPlayingPanel` is present. Confirm full-width Play pill is absent.
**Expected:** `transportRow` renders a `play.fill` icon with `.confirm` (gold) role. `nowPlayingPanel` remains visible (track title readable — design-spec §2.1). No stopped-state Play pill. The playing/paused/buffering branch is active.
**Covers ADR contract assertion:** §7 assertion #2 (`.paused` → transportRow with `play.fill` + `.confirm`)
**Covers spec AC:** US-70 AC-2 (paused state: card shows play button in gold); design-spec §2.1 (panel stays visible)

---

### TC-E56-U03

**ID:** TC-E56-U03
**Target:** `SpeakerCard.cardContent` — `.buffering` branch routing
**Setup:** `SpeakerStub` with `playbackState = .buffering`. Same other parameters.
**Action:** Inspect `cardContent` for a `DarkGlassIconButton` with symbol `pause.fill` and role `.default`.
**Expected:** Buffering renders identically to playing: `pause.fill` icon, `.default` (white) role. `nowPlayingPanel` present. No stopped-state Play pill. The spec explicitly groups `.buffering` with `.playing` for the transport icon (ADR §7 assertion #3; epics T-5602).
**Covers ADR contract assertion:** §7 assertion #3 (`.buffering` → transportRow with `pause.fill` + `.default`, same as playing)
**Covers spec AC:** US-70 AC-2 (buffering treated like playing for the transport toggle)

---

### TC-E56-U04

**ID:** TC-E56-U04
**Target:** `SpeakerCard.cardContent` — `.stopped` branch routing
**Setup:** `SpeakerStub` with `playbackState = .stopped`. Same other parameters.
**Action:** Inspect `cardContent` for: (a) a full-width `DarkGlassButton` with label matching `controls.play` ("Play"), symbol `play.fill`, role `.confirm`; (b) absence of `nowPlayingPanel`; (c) absence of `volumeTrack`; (d) absence of `transportRow` (the icon-only button).
**Expected:** Exactly the stopped-state layout: header + Play pill. `nowPlayingPanel`, `volumeTrack`/slider, and `transportRow` are all absent. This validates the entire stopped-state branch per ADR §7 assertion #4 and spec §3.1.
**Covers ADR contract assertion:** §7 assertion #4 (`.stopped` → Play pill; transportRow + nowPlayingPanel + volumeTrack absent)
**Covers spec AC:** US-70 AC-3 (stopped state: card collapses to header + Play pill only)

---

### TC-E56-U05

**ID:** TC-E56-U05
**Target:** `SpeakerCard.cardContent` — switch driven by `speaker.playbackState`, not `speaker.isPlaying`
**Setup:** Create a `SpeakerStub` whose `isPlaying == false` but `playbackState == .paused`. (Pre-E-56, `isPlaying == false` would route to the else/stopped branch.)
**Action:** Inspect `cardContent` to confirm the playing/paused/buffering branch is active (transportRow present), not the stopped branch.
**Expected:** The `.paused` case is handled by the playing/paused/buffering branch. The refactor in T-5601 is confirmed to use `playbackState`, not `isPlaying`. This is the key regression guard for the T-5601 refactor.
**Covers ADR contract assertion:** §7 assertion #1 (cardContent switches on `speaker.playbackState`, not `speaker.isPlaying`); ADR §1 Decision (pure scaffolding refactor)
**Covers spec AC:** US-70 ACs that depend on correct four-way state routing

---

### TC-E56-U06

**ID:** TC-E56-U06
**Target:** `resolvedGroup` — `group == nil` wraps speaker in `SpeakerGroup.single`
**Setup:** Instantiate `SpeakerCard` with a `SpeakerStub` and no `group:` argument (defaults to `nil`).
**Action:** Read `resolvedGroup` via `@testable import` or inspect via the transport tap side-effect: trigger `onPauseTapped()` and observe which stub's `pause()` is called.
**Expected:** `resolvedGroup.hostSpeaker` is the same instance as `speaker`. Calling `onPauseTapped()` invokes `pause()` on the stub directly — confirming `SpeakerGroup.single(speaker)` wrapping. No separate group object is created externally; the wrapping is internal to `SpeakerCard`.
**Covers ADR contract assertion:** §7 assertion #7 (`group == nil` → `resolvedGroup.hostSpeaker === speaker`)
**Covers spec AC:** US-70 AC-4 (solo card: tap pause calls `speaker.pause()` exactly once)

---

### TC-E56-U07

**ID:** TC-E56-U07
**Target:** `resolvedGroup` — real group routes transport to `hostSpeaker`
**Setup:** Create a `SpeakerGroupStub` with two stubs: `hostStub` (host) and `memberStub` (follower). Pass the group to `SpeakerCard(speaker: hostStub, group: groupStub, ...)`. Set `playbackState = .playing`.
**Action:** Trigger `onPauseTapped()`. Observe `hostStub.pauseCallCount` and `memberStub.pauseCallCount`.
**Expected:** `hostStub.pauseCallCount == 1`. `memberStub.pauseCallCount == 0`. Transport is targeted at the host only; followers mirror via B&O Mozart protocol (design-spec UQ-3 resolved). This validates ADR §7 assertion #8 and US-73 AC-7.
**Covers ADR contract assertion:** §7 assertion #8 (multi-member group → transport hits host only)
**Covers spec AC:** US-73 AC-7 (transport not broadcast to group members)

---

### TC-E56-U08

**ID:** TC-E56-U08
**Target:** `PlaybackBars` — static bars when paused
**Setup:** Instantiate `PlaybackBars(playbackState: .paused)`. Inspect the animation state after one render cycle.
**Action:** Read the animation/`animate` state property (via `@testable import` or by asserting bar heights remain at the `lo` constant). Compare to a `PlaybackBars(playbackState: .playing)` instance.
**Expected:** With `.paused`, bars are static at `lo` height — the animation toggle is `false` and no `withAnimation` block repeats. With `.playing`, bars animate (toggle is `true`). This confirms T-5604 gating.
**Covers ADR contract assertion:** §7 assertion #11 (`PlaybackBars(playbackState: .paused)` → static bars)
**Covers spec AC:** US-70 (paused state: bars freeze; design-spec §2.1)

---

### TC-E56-U09

**ID:** TC-E56-U09
**Target:** `PlaybackBars` — animation active for `.playing` and `.buffering`; static for `.stopped`
**Setup:** Three separate instantiations: `PlaybackBars(playbackState: .playing)`, `PlaybackBars(playbackState: .buffering)`, `PlaybackBars(playbackState: .stopped)`.
**Action:** For each, read the animation state. `.stopped` is a boundary case — bars should be static even though stopped cards do not render the panel (regression guard in case the panel is accidentally shown).
**Expected:** `.playing` → animated. `.buffering` → animated. `.stopped` → static. Default parameter `.playing` preserves existing call sites that omit the parameter.
**Covers ADR contract assertion:** §7 assertion #11 (bars animate for playing/buffering; static for paused/stopped)
**Covers spec AC:** T-5604 requirement; design-spec §2.1 (paused bars static)

---

### TC-E56-U10

**ID:** TC-E56-U10
**Target:** `PlaybackBars` — default parameter preserves existing call sites
**Setup:** Instantiate `PlaybackBars()` with no arguments (uses default `playbackState: .playing`).
**Action:** Confirm the instance compiles and the bars animate (same behaviour as `PlaybackBars(playbackState: .playing)`).
**Expected:** No compile error. Animation is active. The additive parameter does not break any E-54 call sites that omit it.
**Covers ADR contract assertion:** §7 assertion #11 (ADR §5 Consequences: "Default `.playing` preserves existing call sites")
**Covers spec AC:** No-regression: E-54 `PlaybackBars` extraction remains intact

---

## 4. Unit-Level Test Cases (DarkGlassIconButton Size)

These cases test the `DarkGlassIconButton` size parameter introduced in T-5602 against both the 36 pt default and the 52 pt transport size.

---

### TC-E56-U11

**ID:** TC-E56-U11
**Target:** `DarkGlassIconButton` — default size (36 pt): image frame and hit area unchanged
**Setup:** Instantiate `DarkGlassIconButton(systemImage: "heart.fill", role: .default, accessibilityLabel: "Test", action: {})` with no `size:` argument.
**Action:** Inspect the `.frame(width:height:)` on the `Image` view inside the button. Inspect the outer `.frame(minWidth:minHeight:)` on the hit area container.
**Expected:** Image frame: 36 × 36 pt (equals `DarkGlassButtonTokens.iconOnlySize`). Hit area: `minWidth: 44, minHeight: 44` (the original pre-E-56 values; `max(44, 36 + 12) = 44`). No visual regression for any existing call site.
**Covers ADR contract assertion:** §7 assertion #10 (`DarkGlassIconButton(size: 36)` default → identical to pre-E-56)
**Covers spec AC:** US-70 (hit area ≥ 44 × 44 pt); no-regression for existing icon buttons

---

### TC-E56-U12

**ID:** TC-E56-U12
**Target:** `DarkGlassIconButton` — 52 pt transport size: image frame and hit area
**Setup:** Instantiate `DarkGlassIconButton(systemImage: "pause.fill", role: .default, accessibilityLabel: "Pause", size: 52, action: {})`.
**Action:** Inspect `.frame(width:height:)` on the `Image`. Inspect the outer `.frame(minWidth:minHeight:)`.
**Expected:** Image frame: 52 × 52 pt. Hit area: `minWidth: 64, minHeight: 64` (`max(44, 52 + 12) = 64`). Both the visual frame and the touch target meet the ADR §7 assertion #9 contract.
**Covers ADR contract assertion:** §7 assertion #9 (`DarkGlassIconButton(size: 52)` → 52 pt image, 64 pt hit area)
**Covers spec AC:** US-70 AC-9 (hit area ≥ 44 × 44 pt; transport button is 64 × 64 pt); design-spec §1.2

---

### TC-E56-U13

**ID:** TC-E56-U13
**Target:** `DarkGlassIconButton` — hit area formula at intermediate size (48 pt)
**Setup:** Instantiate `DarkGlassIconButton(systemImage: "star.fill", role: .confirm, accessibilityLabel: "Star", size: 48, action: {})`.
**Action:** Inspect `minWidth` and `minHeight`.
**Expected:** `max(44, 48 + 12) = 60`. minWidth and minHeight both equal 60 pt. This confirms the formula generalises correctly beyond just the two sizes specified in the ADR.
**Covers ADR contract assertion:** §7 assertion #9 (hit area formula: `max(44, size + 12)`)
**Covers spec AC:** US-70 AC-9 (minimum hit area 44 × 44 pt guaranteed at any size)

---

### TC-E56-U14

**ID:** TC-E56-U14
**Target:** `DarkGlassIconButton` — existing call sites compile with no `size:` argument
**Setup:** Code-review assertion: search `iOS/Voxio/` for all call sites of `DarkGlassIconButton(`. Confirm every call site that does not explicitly pass `size:` continues to compile and produces a 36 pt icon.
**Action:** Build the Xcode project without modifying any existing call site.
**Expected:** Zero compile errors at existing call sites. The `var size: CGFloat = DarkGlassButtonTokens.iconOnlySize` default ensures backward compatibility. Specifically verify: any call sites in `SpeakerCardView.swift`, `ContentView.swift`, or elsewhere that were present before E-56 pass the build.
**Covers ADR contract assertion:** §7 assertion #10; ADR §2 ("`DarkGlassIconButton` current size — four current call sites use the 36 pt default")
**Covers spec AC:** No-regression requirement for pre-E-56 call sites

---

## 5. Integration Test Cases (Transport Tap Handlers and Error Toast)

These cases render `SpeakerCard` in a host view with a binding and a `SpeakerStub`, then assert on observable side-effects of tap actions: haptic ordering, async dispatch, absence of optimistic state mutation, and `errorMessage` binding writes.

---

### TC-E56-I01

**ID:** TC-E56-I01
**Target:** `onPauseTapped()` — haptic fires synchronously before async dispatch
**Setup:** `SpeakerStub` with `playbackState = .playing`. Inject `HapticEngineSpy`. Wrap `SpeakerStub.pause()` to record call order relative to the spy's `commandRecognised` call. Render card.
**Action:** Tap the `pause.fill` button. Allow one run loop iteration (not a full async resolution).
**Expected:** `HapticEngineSpy.commandRecognisedCallCount == 1` is observable immediately after tap, before the `Task` created by `onPauseTapped()` completes. The async `pause()` call has not yet resolved. This confirms that step 1 (haptic) is synchronous on main actor and step 2 (async Task) is dispatched afterward.
**Covers ADR contract assertion:** §7 assertion #5 (tapping pause fires `HapticEngine.shared.commandRecognised()` synchronously before async dispatch)
**Covers spec AC:** US-70 AC-4 (haptic fires synchronously on tap); design-spec §5.2

---

### TC-E56-I02

**ID:** TC-E56-I02
**Target:** `onPlayTapped()` — haptic fires synchronously before async dispatch
**Setup:** `SpeakerStub` with `playbackState = .paused`. Inject `HapticEngineSpy`. Render card.
**Action:** Tap the `play.fill` button. Allow one run loop iteration before async resolution.
**Expected:** `HapticEngineSpy.commandRecognisedCallCount == 1` before `stub.playCallCount > 0`. Mirrors TC-E56-I01 for the play path.
**Covers ADR contract assertion:** §7 assertion #5 (synchronous haptic on any transport tap)
**Covers spec AC:** US-70 AC-4 (haptic fires on tap)

---

### TC-E56-I03

**ID:** TC-E56-I03
**Target:** `onPauseTapped()` — successful pause: `speaker.playbackState` not mutated optimistically
**Setup:** `SpeakerStub` with `playbackState = .playing`. The stub's `pause()` succeeds asynchronously (no error). The stub's `playbackState` remains `.playing` until the stub explicitly changes it (simulating the speaker's WS event arriving later). Render card.
**Action:** Tap the pause button. Wait for the `Task` in `onPauseTapped()` to complete. Observe `stub.playbackState` immediately after the tap and after the Task completes.
**Expected:** At no point does `SpeakerCard` mutate `stub.playbackState` — not to `.paused` optimistically, not to any intermediate state. `stub.playbackState` remains whatever the stub object holds, driven externally. The transport button icon is driven solely by `@Observable` re-render from the stub, not by any local `SpeakerCard` state.
**Covers ADR contract assertion:** §7 assertion #6 (failed or successful play/pause does NOT change speaker.playbackState)
**Covers spec AC:** US-70 AC-7 (button state driven by `speaker.state` via @Observable); error states table ("button visual state remains driven by speaker.state")

---

### TC-E56-I04

**ID:** TC-E56-I04
**Target:** `onPlayTapped()` — failed play: `errorMessage` binding set to non-nil; state not mutated
**Setup:** `SpeakerStub` with `playbackState = .paused`. Set `stub.playError = MozartError.unreachable`. Render `SpeakerCard` with `@State var errorMsg: String? = nil`, passing `$errorMsg` as `errorMessage:`. Inject `HapticEngineSpy`.
**Action:** Tap the play button. Await the `Task` completion.
**Expected:**
- `errorMsg != nil` — the `showErrorToast` helper set the binding to a non-empty error string.
- `stub.playbackState` is unchanged (still `.paused`).
- `HapticEngineSpy.errorOccurredCallCount == 1`.
- `HapticEngineSpy.commandRecognisedCallCount == 1` (fired before the async error).
**Covers ADR contract assertion:** §7 assertion #6 (failed play sets `errorMessage` to non-nil; does NOT change `speaker.playbackState`)
**Covers spec AC:** US-70 AC-10 (failed play: toast shown, button visual unchanged); error states table (network unreachable)

---

### TC-E56-I05

**ID:** TC-E56-I05
**Target:** `onPauseTapped()` — failed pause: `errorMessage` binding set to non-nil; state not mutated
**Setup:** `SpeakerStub` with `playbackState = .playing`. Set `stub.pauseError = MozartError.timeout`. Render card with `$errorMsg`. Inject spy.
**Action:** Tap pause. Await Task completion.
**Expected:**
- `errorMsg != nil`.
- `stub.playbackState` is unchanged (still `.playing`).
- `HapticEngineSpy.errorOccurredCallCount == 1`.
- `HapticEngineSpy.commandRecognisedCallCount == 1`.
**Covers ADR contract assertion:** §7 assertion #6
**Covers spec AC:** US-70 AC-10 (failed pause: toast + haptic; state unchanged); error states (timeout)

---

### TC-E56-I06

**ID:** TC-E56-I06
**Target:** `onPlayTapped()` from stopped state — Play pill tap
**Setup:** `SpeakerStub` with `playbackState = .stopped`. Render card. Inject spy. Set `stub.playError = nil` (success).
**Action:** Tap the full-width Play `DarkGlassButton` pill. Await Task.
**Expected:** `stub.playCallCount == 1`. `HapticEngineSpy.commandRecognisedCallCount == 1`. `errorMsg == nil`. The stopped-state Play pill uses the same `onPlayTapped()` handler as the transport row (no separate handler per ADR §1 Decision and T-5606). `stub.playbackState` is not mutated by the card.
**Covers ADR contract assertion:** §7 assertion #4 (stopped Play pill triggers same onPlayTapped as transport row); §7 assertion #6
**Covers spec AC:** US-70 AC-3 (tapping Play in stopped state calls `speaker.play()` once); AC-4 (haptic fires)

---

### TC-E56-I07

**ID:** TC-E56-I07
**Target:** `onPlayTapped()` from stopped state — failed play
**Setup:** `SpeakerStub` with `playbackState = .stopped`. `stub.playError = MozartError.httpError(503)`. Render card with `$errorMsg`. Inject spy.
**Action:** Tap Play pill. Await Task.
**Expected:** `errorMsg != nil`. `stub.playbackState` unchanged (`.stopped`). `HapticEngineSpy.errorOccurredCallCount == 1`. Error states table: "User taps Play in stopped state but API rejects → standard error toast."
**Covers ADR contract assertion:** §7 assertion #6
**Covers spec AC:** US-70 AC-10; error states table (no source configured → error toast)

---

### TC-E56-I08

**ID:** TC-E56-I08
**Target:** `showErrorToast` → `errorMessage` binding → `HomeView` `onChange` → Toast → reset to nil
**Setup:** Render a `HomeView` stub (or the `cardArea` section) with `@State private var cardErrorMessage: String? = nil`. Wire `$cardErrorMessage` to a `SpeakerCard`. Confirm `HomeView` has an `.onChange(of: cardErrorMessage)` that creates a `Toast` and then resets `cardErrorMessage = nil`.
**Action:** Trigger `showErrorToast("Test error")` by forcing a failed play via the stub. Observe `cardErrorMessage` lifecycle.
**Expected:**
- After toast creation: `cardErrorMessage == nil` (reset by `HomeView.onChange`).
- The toast surface (whatever `HomeView` uses, e.g. `ToastView`) receives a `.error` toast with the error message.
- Triggering a second error after the first one is handled causes a fresh `cardErrorMessage` write — the nil reset allows the `onChange` to fire again.
**Covers ADR contract assertion:** §7 assertion #6; ADR §6 (`showErrorToast` / `HomeView.onChange` / reset to nil)
**Covers spec AC:** US-70 AC-10 (failed call surfaces through the existing toast mechanism)

---

### TC-E56-I09

**ID:** TC-E56-I09
**Target:** Rapid taps — no optimistic disable between tap and state update
**Setup:** `SpeakerStub` with `playbackState = .playing`. `stub.pauseError = nil`. Configure the stub so `pause()` takes 300 ms to complete. Render card.
**Action:** Tap the pause button 5 times in rapid succession (simulating impatient user).
**Expected:** `stub.pauseCallCount == 5` (button does not disable between taps; final state wins on rapid taps per ADR §7 assertion). No crash. The card does not enter any undefined state. After all Tasks complete, `stub.playbackState` reflects whatever the stub's final state is.
**Covers ADR contract assertion:** §7 assertion (ADR §1 "Button does not disable between tap and state update")
**Covers spec AC:** T-5608 manual test matrix item 6 (5 rapid taps; no crash; final state correct)

---

## 6. Acceptance Test Cases (Stopped-State Card; HomeView errorMessage Wiring)

These cases test `HomeView.cardArea` routing to the stopped-state idle card slot and the full `errorMessage` wiring path. They may be implemented as XCUITest or snapshot tests.

---

### TC-E56-A01

**ID:** TC-E56-A01
**Target:** Stopped-state card: correct elements present and absent
**Setup:** Stub discovery so `displayedSpeaker.playbackState == .stopped` and `playingGroups.isEmpty` (routes to the idle-card branch per E-55). Render `HomeView`.
**Action:** Inspect the card area for: (a) `headerSection` presence, (b) Play pill presence (`DarkGlassButton` with "Play" label), (c) `nowPlayingPanel` absence, (d) `volumeTrack`/slider absence, (e) `transportRow` (icon-only button) absence.
**Expected:** All five assertions hold simultaneously. The stopped-state layout is exactly: header + Play pill (and later, favorites row from E-58, which is absent in E-56 alone). This is the acceptance-level confirmation of the T-5606 implementation.
**Covers ADR contract assertion:** §7 assertion #4 (`.stopped` → Play pill rendered; transportRow + nowPlayingPanel + volumeTrack absent)
**Covers spec AC:** US-70 AC-3 (stopped/idle: header + Play pill only); design-spec §3.1

---

### TC-E56-A02

**ID:** TC-E56-A02
**Target:** `HomeView.cardArea` — `cardErrorMessage` state variable is present and wired to both `SpeakerCard` call sites
**Setup:** Code-review assertion: read `HomeView.cardArea` source. Confirm `@State private var cardErrorMessage: String?` is declared and passed as `errorMessage: $cardErrorMessage` to:
1. The idle-card `SpeakerCard` in the `else if let speaker = displayedSpeaker` branch.
2. The `SessionStripView` (which threads it to each `SpeakerCard` in the strip).
**Action:** Build the project. Confirm it compiles with no binding errors.
**Expected:** No compile errors. `cardErrorMessage` is the single shared binding source for all `SpeakerCard` error outputs in `HomeView`. The architectural choice (one binding, last-write-wins) is confirmed per ADR §7 `SessionStripView` comment.
**Covers ADR contract assertion:** §7 assertion (ADR §5 Consequences: "`@Binding var errorMessage: String?` — same binding shared across E-56/E-57/E-58")
**Covers spec AC:** US-70 AC-10; CF-1 resolved (all call sites updated)

---

### TC-E56-A03

**ID:** TC-E56-A03
**Target:** `SessionStripView` — `@Binding var errorMessage: String?` pass-through to each card
**Setup:** Render `SessionStripView` with two groups. Pass a `@State var testError: String? = nil` binding as `errorMessage: $testError`.
**Action:** From the second card's stub, trigger a failed pause. Observe `testError`.
**Expected:** `testError` becomes non-nil (the error message from the second card propagates through `SessionStripView`'s binding pass-through to the shared `HomeView` state). The first card's stub is unaffected. "Last write wins" when two cards error simultaneously.
**Covers ADR contract assertion:** §7 `SessionStripView` (NEW `@Binding var errorMessage: String?` pass-through); ADR §6 `SessionStripView` modifications
**Covers spec AC:** US-70 AC-10 (error surfaces to toast regardless of which card triggered it)

---

### TC-E56-A04

**ID:** TC-E56-A04
**Target:** SwiftUI `#Preview` blocks compile with `.constant(nil)` for `errorMessage:`
**Setup:** Code-review / build assertion: confirm that all `#Preview` blocks in `SpeakerCard.swift` (and `SessionStripView.swift` if it has previews) pass `errorMessage: .constant(nil)`.
**Action:** Build the Xcode project. Run any preview that renders `SpeakerCard`.
**Expected:** All previews compile. No "missing argument" error for `errorMessage:`. ADR §8 CF-1 documents that `@Binding` has no default — previews must explicitly provide `.constant(nil)`.
**Covers ADR contract assertion:** §7 assertion #13 (`SpeakerCard` calls without `errorMessage:` produce compile errors — expected migration signal; previews must be updated)
**Covers spec AC:** CF-1 mitigation (all call sites updated, including preview blocks)

---

### TC-E56-A05

**ID:** TC-E56-A05
**Target:** Full path: speaker transitions playing → stopped → card collapses without crash
**Setup:** Render `HomeView` with a `SpeakerStub` initially in `.playing` state. Card shows the playing layout (transport row, now-playing panel, volume bar).
**Action:** Mutate `stub.playbackState = .stopped`. Allow one SwiftUI update cycle.
**Expected:** `SpeakerCard.cardContent` switches to the stopped branch. The card now shows: header + Play pill. No now-playing panel, no transport row, no volume bar. No crash. No layout artefact. The transition happens within one SwiftUI re-render frame.
**Covers ADR contract assertion:** §7 assertion #4 (state-driven branch switching)
**Covers spec AC:** Error states table ("Speaker transitions to stopped while pause/play tap is in flight — button updates to stopped-state Play pill on next frame")

---

### TC-E56-A06

**ID:** TC-E56-A06
**Target:** Full path: speaker transitions stopped → playing → card expands without crash
**Setup:** Render `HomeView` with a `SpeakerStub` initially in `.stopped` state. Card shows the stopped layout.
**Action:** Mutate `stub.playbackState = .playing`. Allow one SwiftUI update cycle.
**Expected:** `cardContent` switches to the playing branch. Now-playing panel, volume bar, and transport row (with `pause.fill`) appear. Play pill is gone. No crash or duplicate views. Transition is driven purely by `@Observable` re-render.
**Covers ADR contract assertion:** §7 assertion #1 (`.playing` → playing branch); ADR §2 (`@Observable @MainActor` invariant)
**Covers spec AC:** US-70 AC-6 (icon/layout updates within one frame of `speaker.state` changing)

---

## 7. Error States and Boundary Values

---

### TC-E56-E01

**ID:** TC-E56-E01
**Target:** Network unreachable — play tap in stopped state
**Setup:** `SpeakerStub` with `playbackState = .stopped`. `stub.playError = MozartError.unreachable`. Render card with `$errorMsg`. Inject `HapticEngineSpy`.
**Action:** Tap Play pill. Await Task.
**Expected:** `errorMsg != nil` (error message references "unreachable" or generic network error). `stub.playbackState` unchanged. `HapticEngineSpy.errorOccurredCallCount == 1`. Card remains in stopped layout (no optimistic switch to playing branch).
**Covers ADR contract assertion:** §7 assertion #6
**Covers spec AC:** US-70 AC-10; error states table (network unreachable)

---

### TC-E56-E02

**ID:** TC-E56-E02
**Target:** HTTP 5xx — pause tap while playing
**Setup:** `SpeakerStub` with `playbackState = .playing`. `stub.pauseError = MozartError.httpError(500)`. Render with `$errorMsg`. Inject spy.
**Action:** Tap pause. Await Task.
**Expected:** `errorMsg != nil`. `stub.playbackState` unchanged (`.playing`). `HapticEngineSpy.errorOccurredCallCount == 1`. The error toast message reflects the HTTP 5xx code.
**Covers ADR contract assertion:** §7 assertion #6
**Covers spec AC:** US-70 AC-10; error states table (HTTP 5xx)

---

### TC-E56-E03

**ID:** TC-E56-E03
**Target:** Request timeout — play tap while paused
**Setup:** `SpeakerStub` with `playbackState = .paused`. `stub.playError = MozartError.timeout`. Render with `$errorMsg`. Inject spy.
**Action:** Tap play. Await Task.
**Expected:** `errorMsg != nil`. `stub.playbackState` unchanged. `HapticEngineSpy.errorOccurredCallCount == 1`. Timeout error surfaced via toast per `MozartClient` 5 s contract.
**Covers ADR contract assertion:** §7 assertion #6
**Covers spec AC:** US-70 AC-10; error states table (5 s timeout)

---

### TC-E56-E04

**ID:** TC-E56-E04
**Target:** Boundary — `onPlayTapped()` called in `.playing` state (stale tap race)
**Setup:** `SpeakerStub` with `playbackState = .playing`. Render card. Between the `@Observable` update and the card re-render, programmatically call `onPlayTapped()` (simulating a stale tap from the prior state). `stub.playError = nil`.
**Action:** Complete the Task.
**Expected:** `stub.playCallCount == 1`. No crash. The speaker receives a `play()` call even though it was already playing — the card does not guard against this. The speaker's own state machine handles idempotent play. `errorMsg == nil` (no error; speaker accepts the call).
**Covers ADR contract assertion:** No specific contract — boundary robustness
**Covers spec AC:** T-5608 item 6 (no crash on rapid taps); general robustness

---

### TC-E56-E05

**ID:** TC-E56-E05
**Target:** Boundary — `group` set to a single-member `SpeakerGroup` vs. `nil`
**Setup 1:** Pass `group: nil`. Tap pause.
**Setup 2:** Pass `group: SpeakerGroup.single(stub)` explicitly. Tap pause.
**Action:** Compare `stub.pauseCallCount` in each case.
**Expected:** Both setups result in `stub.pauseCallCount == 1`. `resolvedGroup` with `group: nil` uses `SpeakerGroup.single(speaker)` internally; passing it explicitly is equivalent. No duplicated calls.
**Covers ADR contract assertion:** §7 assertion #7 (with `group == nil`, `resolvedGroup.hostSpeaker === speaker`)
**Covers spec AC:** US-73 AC-6 (single-speaker card behaves identically to a single `speaker.pause()` call)

---

### TC-E56-E06

**ID:** TC-E56-E06
**Target:** Error toast concurrent writes — two rapid errors write `errorMessage` twice
**Setup:** Render `HomeView` with two `SpeakerStub` instances in a strip. Both stubs have `pauseError = MozartError.unreachable`. `cardErrorMessage` starts as `nil`.
**Action:** Trigger tap-pause on both cards in the same run loop. Await both Tasks.
**Expected:** `cardErrorMessage` is non-nil after the first write, reset to nil by `HomeView.onChange`, then potentially set non-nil again by the second write (last-write-wins). No crash. No deadlock. The toast surface shows at least one error. The exact ordering is non-deterministic; the assertion is that `HomeView` does not enter a loop or corrupt state.
**Covers ADR contract assertion:** ADR §7 `SessionStripView` ("last write wins")
**Covers spec AC:** US-70 AC-10 (error surfaces; no crash from concurrent errors)

---

## 8. Coverage Matrix (AC/ER → TC IDs)

| AC / Contract Assertion | TC IDs | Status |
|---|---|---|
| **ADR §7 assertion #1** — `.playing` → transportRow with `pause.fill` + `.default` | TC-E56-U01, TC-E56-A06 | Covered |
| **ADR §7 assertion #2** — `.paused` → transportRow with `play.fill` + `.confirm` | TC-E56-U02 | Covered |
| **ADR §7 assertion #3** — `.buffering` → transportRow with `pause.fill` + `.default` | TC-E56-U03 | Covered |
| **ADR §7 assertion #4** — `.stopped` → Play pill rendered; transportRow + nowPlayingPanel + volumeTrack absent | TC-E56-U04, TC-E56-A01, TC-E56-A05, TC-E56-I06 | Covered |
| **ADR §7 assertion #5** — Tapping pause fires `commandRecognised()` synchronously before async dispatch | TC-E56-I01, TC-E56-I02 | Covered |
| **ADR §7 assertion #6** — Failed play/pause sets `errorMessage` to non-nil; does NOT change `speaker.playbackState` | TC-E56-I03, TC-E56-I04, TC-E56-I05, TC-E56-I07, TC-E56-E01, TC-E56-E02, TC-E56-E03 | Covered |
| **ADR §7 assertion #7** — `group == nil` → `resolvedGroup.hostSpeaker === speaker` | TC-E56-U06, TC-E56-E05 | Covered |
| **ADR §7 assertion #8** — Multi-member group → transport hits host only | TC-E56-U07 | Covered |
| **ADR §7 assertion #9** — `DarkGlassIconButton(size: 52)` → 52 pt image, 64 pt hit area | TC-E56-U12 | Covered |
| **ADR §7 assertion #10** — `DarkGlassIconButton(size: 36)` default → identical to pre-E-56 | TC-E56-U11, TC-E56-U14 | Covered |
| **ADR §7 assertion #11** — `PlaybackBars(playbackState: .paused)` → static bars | TC-E56-U08, TC-E56-U09, TC-E56-U10 | Covered |
| **ADR §7 assertion #12** — `.accessibilityElement(children: .contain)` after T-5607 — header summary + reachable transport | TC-E56-A07 (§10 deferred to manual) | Deferred (manual) |
| **ADR §7 assertion #13** — `SpeakerCard` calls without `errorMessage:` produce compile errors | TC-E56-A04 | Covered |
| **US-70 AC-1** — Playing state: `pause.fill` button shown | TC-E56-U01 | Covered |
| **US-70 AC-2** — Paused/buffering state: `play.fill` gold button shown | TC-E56-U02, TC-E56-U03 | Covered |
| **US-70 AC-3** — Stopped state: full-width Play pill; no volume bar or now-playing panel | TC-E56-U04, TC-E56-A01, TC-E56-I06 | Covered |
| **US-70 AC-4** — Tap pause calls `speaker.pause()` once; haptic fires synchronously | TC-E56-I01, TC-E56-U06 | Covered |
| **US-70 AC-4** — Tap play calls `speaker.play()` once; haptic fires synchronously | TC-E56-I02, TC-E56-I06 | Covered |
| **US-70 AC-5** — No confirmation countdown | TC-E56-I01, TC-E56-I02 (tap is immediate) | Covered |
| **US-70 AC-6** — Icon, role, and card layout update within one frame of `speaker.state` changing | TC-E56-A05, TC-E56-A06 | Covered |
| **US-70 AC-7** — Button state driven by `speaker.state` via @Observable (no optimistic mutation) | TC-E56-I03, TC-E56-I04 | Covered |
| **US-70 AC-8** — VoiceOver reads "Pause" when playing; "Play" when paused/stopped | TC-E56-A08 (§10 deferred to manual) | Deferred (manual) |
| **US-70 AC-9** — Hit area ≥ 44 × 44 pt | TC-E56-U11, TC-E56-U12 | Covered |
| **US-70 AC-10** — Failed call: toast shown; `errorOccurred` haptic; button visual unchanged | TC-E56-I04, TC-E56-I05, TC-E56-I07, TC-E56-I08, TC-E56-E01, TC-E56-E02, TC-E56-E03 | Covered |
| **US-73 AC-7** — Transport not broadcast: only host receives play/pause | TC-E56-U07 | Covered |
| **US-73 AC-6** — Single-speaker card behaves identically to direct `speaker.pause()` | TC-E56-U06, TC-E56-E05 | Covered |
| **cardContent switches on `playbackState`, not `isPlaying`** | TC-E56-U05 | Covered |
| **Design-spec §2.1** — nowPlayingPanel visible in paused state; bars static | TC-E56-U02, TC-E56-U08 | Covered |
| **Design-spec §1.2** — transport row padding `Spacing.s24 / s16 / s20`; centred button | TC-E56-A09 (§10 deferred to manual snapshot) | Deferred (snapshot) |
| **Design-spec §3.1** — stopped Play pill: `Spacing.s24` padding; `Spacing.s20` above and below | TC-E56-A09 (§10 deferred to manual snapshot) | Deferred (snapshot) |
| **CF-1 — @Binding breaks all call sites** | TC-E56-A02, TC-E56-A04 | Covered |
| **Error: network unreachable on tap** | TC-E56-E01 | Covered |
| **Error: HTTP 5xx on pause** | TC-E56-E02 | Covered |
| **Error: timeout on play** | TC-E56-E03 | Covered |
| **Error: rapid taps (5×); no crash** | TC-E56-I09 | Covered |
| **Boundary: `nil` group vs. explicit `SpeakerGroup.single`** | TC-E56-E05 | Covered |
| **Boundary: concurrent error writes to `errorMessage`** | TC-E56-E06 | Covered |
| **Boundary: `DarkGlassIconButton` hit area formula at non-standard size** | TC-E56-U13 | Covered |

---

## 9. Spec Gaps Discovered

The following ambiguities or omissions were identified during test-plan authoring. None are implementation blockers; each is flagged for the Spec Author and Architect to resolve before QA sign-off.

**Gap 1 — `onPlayTapped()` / `onPauseTapped()` use `try?` or `do/catch` — spec is inconsistent**

`epics-and-tasks-touch-playback-controls.md` T-5603 specifies `do/try/catch` with explicit `showErrorToast` and `errorOccurred`. ADR §7 (transport tap handlers code block) shows `do { try await ... } catch { showErrorToast(...); HapticEngine.shared.errorOccurred() }`. However, a different snippet in the same ADR shows `Task { try? await group.hostSpeaker.pause() }` with "with error handling". The `try?` form silently discards errors. The authoritative contract must confirm which form is used. TC-E56-I04 and TC-E56-I05 assume `do/catch` (error surfaces). If `try?` is chosen instead, US-70 AC-10 cannot be satisfied. The Implementer must confirm and the ADR should be updated to remove the `try?` variant.

**Gap 2 — `SpeakerCard` `@Binding errorMessage:` vs. closure alternative — CF-1 does not settle the choice**

ADR §8 CF-1 documents both `@Binding var errorMessage: String?` and `var onError: (String) -> Void = { _ in }` as equivalent options and says "the Implementer may switch to the closure approach." TC-E56-I08 and TC-E56-A02 are written assuming `@Binding`. If the closure approach is chosen instead, TC-E56-I08 must be rewritten to assert the closure is invoked rather than a binding write. The spec should settle this before implementation begins to avoid test rework.

**Gap 3 — Stopped-state header: no source badge vs. existing `headerSection`**

Design-spec §3.1 shows the stopped-state header with "no source badge when idle." The existing `headerSection` in `SpeakerCard` may render a source badge (e.g. `beolink` label from the design-spec §1.1 anatomy). The spec does not explicitly state whether T-5606 suppresses the badge in the stopped branch or leaves the existing `headerSection` unchanged. If `headerSection` is reused without modification, the source badge may appear in the stopped layout, contradicting design-spec §3.1. TC-E56-A01 currently only asserts absence of `nowPlayingPanel`/volumeTrack/transportRow — it should also assert the badge behaviour once the spec clarifies this.

**Gap 4 — `SessionStripView` `errorMessage:` parameter: when does it land?**

ADR §6 lists `SessionStripView.swift` as a modified file for T-5606, gaining `@Binding var errorMessage: String?`. ADR §8 CF-3 warns that F2 E-59 T-5905 also modifies `SessionStripView.body`. TC-E56-A03 tests the pass-through, but the test cannot be authored until T-5606 lands. The spec does not specify how `SessionStripView.body`'s `ForEach` passes the binding to each `SpeakerCard` — each card needs its own reference to the same binding, but Swift `@Binding` structs are value-type copies. The Implementer must confirm that all card taps write to the same parent `@State` (they do, because `@Binding` in a `ForEach` via `@State` in the host propagates writes back — but this should be explicitly tested). TC-E56-A03 provides the test case; the gap is that the spec assumes this works without documenting the mechanism.

**Gap 5 — `UIStrings.forLanguage(...)` locale selection not specified for transport labels**

T-5607 adds `play` and `pause` accessibility labels to `UIStrings.swift`. ADR §7 transport button code snippets reference `UIStrings.forLanguage(...).pause` / `.play` but do not specify how the language is determined: `Locale.current.language.languageCode?.identifier`, `Bundle.main.preferredLocalizations.first`, or a stored user preference. TC-E56-A08 (deferred to manual, §10) tests VoiceOver reads "Pause" / "Play" in English, but if the locale selection logic is wrong, Danish users would hear "Pause"/"Play" anyway (they happen to be identical — see design-spec Appendix B `a11y.pause = "Pause"` in both locales). This gap matters more for other strings; it is flagged here because T-5607 establishes the pattern that E-57 and E-58 will follow.

---

## 10. Tests Deferred to Manual Device Verification

The following items cannot be fully automated at the unit or XCUITest level and are deferred to the manual verification tasks T-5608 defined in the epics document.

| Item | Reason for deferral | Epic task |
|---|---|---|
| VoiceOver reads "Pause" when playing, "Play" when paused/stopped | Requires VoiceOver enabled on device; XCUITest `accessibilityLabel` assertions can verify the label value but not the screen-reader pronunciation in context | T-5608 item 7 |
| `.accessibilityElement(children: .contain)` on `SpeakerCard` — transport button individually reachable by VoiceOver | VoiceOver focus order cannot be fully asserted in XCUITest without screen reader running; requires Accessibility Inspector inspection on device | T-5608 item 7; T-5607 |
| Header summary (`accessibilityLabel`) relocated to `headerSection` — VoiceOver reads it first | Same reason as above; focus traversal order requires VoiceOver on device | T-5607 |
| Transport row padding pixel-accuracy (`Spacing.s24` / `Spacing.s16` / `Spacing.s20`) | Precise padding values require snapshot comparison or manual measurement in Xcode canvas; no XCTest API exposes SwiftUI padding values directly | T-5608; design-spec §1.2 |
| Stopped-state Play pill padding (`Spacing.s24` horizontal / `Spacing.s20` vertical) | Same as above | T-5608; design-spec §3.1 |
| Touch-up to API dispatch latency (≤ 50 ms) | Timing assertions in XCUITest are unreliable at sub-100 ms granularity; requires Instruments / MetricKit profiling or a custom timing log | spec-touch-playback-controls.md NFR (Latency) |
| `speaker.play()` called within ~1 s of tap on a real Mozart speaker; card updates | Requires a real Mozart speaker on the local network; mock stubs cannot validate the full WS-event round-trip | T-5608 items 1–4 |
| Disconnect network mid-session → error toast appears; haptic pattern matches `errorOccurred` | Requires physical network disconnection or network link conditioner; XCUITest cannot reliably intercept URLSession connections | T-5608 item 5 |
| Buffering state: pause button shown; tap pauses correctly | Buffering is a transient real-speaker state; mock stubs can cover the rendering (TC-E56-U03) but the full interaction requires a speaker actually buffering | T-5608 item 4 |
