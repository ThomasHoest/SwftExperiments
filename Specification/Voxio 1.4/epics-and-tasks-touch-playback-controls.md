# Epics & Tasks: Touch Playback Controls (Voxio 1.4 — Feature 1)
**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-09
**References:** spec-touch-playback-controls.md (v1.0), design-spec-touch-playback-controls.md (v1.2), VoxioSpecification-1.4.md (Feature 1), epics-and-tasks-telemetry-backend.md (format reference), CLAUDE.md
**Stack:** Swift 6, SwiftUI, iOS 26, `@Observable @MainActor` view models, `withTaskGroup` for concurrent group volume broadcast, `HapticEngine`

---

## Overview

This document breaks Feature 1 of Voxio 1.4 — Touch Playback Controls — into epics and constituent tasks. The deliverable is three additions to `SpeakerCard` (`iOS/Voxio/Features/Home/SpeakerCard.swift`): a play/pause toggle button, an interactive volume slider, and a horizontally-scrolling favorites row, plus a stopped-state card variant. Wiring is to existing `Speaker` methods (`play`, `pause`, `setVolume`, `getFavorites`, `playFavorite`) and the existing `HapticEngine`. No backend, REST, or voice pipeline changes.

This is a **pure iOS** feature in the existing `iOS/Voxio.xcodeproj`. All paths in tasks below are relative to the repo root unless otherwise noted. The `PBXFileSystemSynchronizedRootGroup` setup means new `.swift` files dropped into `iOS/Voxio/` are auto-compiled — no `pbxproj` edits required.

Epic numbering begins at **E-56**, continuing from earlier Voxio epics. Task numbering begins at **T-5601**.

---

## Epic Index

| # | Epic | User Stories | Feature Area |
|---|---|---|---|
| E-56 | Play/pause toggle button | US-70 | `SpeakerCard` transport row, `DarkGlassIconButton` wiring, stopped-state Play pill, haptics, accessibility |
| E-57 | Interactive volume slider | US-71, US-73 | Slider promotion, custom slider style, `onEditingChanged` API timing, group member broadcast via `withTaskGroup`, limit haptic |
| E-58 | Favorites row | US-72 | `getFavorites()` async load, `DarkGlassButton` row, `playFavorite(presetIndex:)` wiring, empty-state absence, accessibility |

---

## E-56 — Play/pause toggle button

Add a single play/pause toggle button to `SpeakerCard` below the volume bar in the playing/paused/buffering states. In the stopped/idle state, replace the empty card body with a header plus a full-width Play pill. Wire taps to `Speaker.play()` / `Speaker.pause()` on the lead (host) speaker. Fire `HapticEngine.shared.commandRecognised()` synchronously on tap. No confirmation countdown.

**Depends on:** none — this epic operates entirely within existing `SpeakerCard` and `Speaker` surfaces. `DarkGlassIconButton` and `DarkGlassButton` already exist (`iOS/Voxio/DesignSystem/DarkGlassButton.swift`).
**Unlocks:** E-57 (slider replaces the existing volumeTrack and lives directly above the transport row), E-58 (favorites row is placed below the transport row in playing/paused/buffering and below the Play pill in stopped).

---

### Card structure refactor

- [x] **T-5601** Refactor `SpeakerCard.cardContent` in `iOS/Voxio/Features/Home/SpeakerCard.swift` to switch on `speaker.playbackState` (`.playing` / `.paused` / `.buffering` / `.stopped`) rather than the current `speaker.isPlaying` boolean. The current `isPlaying` branch becomes the playing/paused/buffering branch (rendering header + nowPlayingPanel + volumeTrack + transport row + favorites row). The else branch becomes the stopped branch (header + Play pill + favorites row). Verify that the existing `nowPlayingPanel` continues to render in `.paused` state (the design spec §2.1 keeps the panel visible so the track title is readable; bars become static — handled later in T-5604).

  Do not yet add the slider, transport row, or favorites row in this task — they are added in T-5602 (transport), E-57, and E-58 respectively. This task is a pure scaffolding refactor.
  *No dependencies. Prerequisite for T-5602, T-5605, T-5701, T-5801.*

### Transport button — playing/paused/buffering states

- [x] **T-5602** Add a private `transportRow` view to `SpeakerCard` that renders a single centred `DarkGlassIconButton` (52 pt visual / 64 pt hit area) wrapped in an `HStack` with `.frame(maxWidth: .infinity)`. Switch on `speaker.playbackState`:
  - `.playing` or `.buffering` → `DarkGlassIconButton(systemImage: "pause.fill", role: .default, accessibilityLabel: "Pause", action: onPauseTapped)`
  - `.paused` → `DarkGlassIconButton(systemImage: "play.fill", role: .confirm, accessibilityLabel: "Play", action: onPlayTapped)`

  The `DarkGlassIconButton` component currently sizes to 36 pt (`DarkGlassButtonTokens.iconOnlySize`). Add a new initializer parameter `var size: CGFloat = DarkGlassButtonTokens.iconOnlySize` to `DarkGlassIconButton` (file `iOS/Voxio/DesignSystem/DarkGlassButton.swift`) so callers can pass `52`. Update the `Image` frame and the `.frame(minWidth:minHeight:)` so the hit area scales (52 pt visual → 64 pt hit area, i.e. `minWidth: max(44, size + 12)`). Keep the default `36` for existing call sites.

  Apply horizontal padding `Spacing.s24` and vertical padding `Spacing.s16` top, `Spacing.s20` bottom to the `transportRow` per design-spec §1.2. Insert the row into the playing/paused/buffering branch of `cardContent` directly below the volume bar.
  *Depends on: T-5601.*

- [x] **T-5603** Implement `onPlayTapped()` and `onPauseTapped()` as private methods on `SpeakerCard`. Each method:
  1. Fires `HapticEngine.shared.commandRecognised()` synchronously.
  2. Dispatches `Task { @MainActor in ... }` calling `speaker.play()` or `speaker.pause()` (on the lead speaker — see T-5605 for the group-aware variant).
  3. Wraps the call in `do/try/catch`. On error, calls a private `showErrorToast(_ message: String)` helper (see T-5606) and fires `HapticEngine.shared.errorOccurred()`.

  Do not optimistically update `speaker.state` — the visual button state continues to be driven by the speaker's actual state via the `@Observable` re-render. This means the button may appear unresponsive for up to ~1 second on a slow speaker; that is acceptable per the design philosophy (design-spec §5.3) and matches the existing voice-command behaviour.
  *Depends on: T-5602.*

- [x] **T-5604** Update `PlaybackBars` in `SpeakerCard.swift` so the bar animation pauses (bars become static at their `lo` height) when `speaker.playbackState == .paused`. Pass the playback state into `PlaybackBars` as a parameter, and gate the `animate` `@State` toggle on `state == .playing || state == .buffering`. Per design-spec §2.1, the panel stays visible in paused state so the track title remains readable, but the bars stop moving.
  *Depends on: T-5601.*

### Group-aware transport dispatch

- [x] **T-5605** Modify `SpeakerCard`'s init to accept an optional `SpeakerGroup` (`iOS/Voxio/Core/Models/Group.swift`) in addition to the current `Speaker` parameter. If only a `Speaker` is provided, internally wrap it via `SpeakerGroup.single(speaker)`. Replace direct `speaker.play()` / `speaker.pause()` calls in `onPlayTapped()` / `onPauseTapped()` (T-5603) with `group.hostSpeaker.play()` / `group.hostSpeaker.pause()`. Per design-spec UQ-3 resolved: transport actions target the lead speaker only — followers mirror automatically.

  Update all `SpeakerCard(speaker: ...)` call sites in `iOS/Voxio/Features/Home/ContentView.swift` (and any other files that instantiate `SpeakerCard`). Where a single speaker is passed, the wrapping is automatic; where the call site already has a `SpeakerGroup`, pass it directly.
  *Depends on: T-5603.*

### Stopped-state card variant

- [x] **T-5606** Implement the stopped-state branch of `SpeakerCard.cardContent` (added in T-5601). Renders:
  - The existing `headerSection` (which already shows "Idle" via `speaker.stateDisplay` for non-playing states; design-spec §3 calls this "Stopped" — leave the existing string unless localisation work is opened separately).
  - A full-width `DarkGlassButton(label: "Play", systemImage: "play.fill", role: .confirm, action: onPlayTapped)` with `Spacing.s24` horizontal padding and `Spacing.s20` top and bottom padding.
  - The favorites row (added in E-58) below the Play pill — wired by T-5803.

  In the stopped state, do **not** render `nowPlayingPanel`, `volumeTrack`, or `transportRow`.

  Add a private `showErrorToast(_ message: String)` helper to `SpeakerCard` that hooks into the existing toast mechanism in `ContentView`. If no shared toast surface exists yet, route through a `@Binding var errorMessage: String?` passed in from `ContentView` (or via an `EnvironmentObject` if one is already in use). Document the chosen route in the PR description so E-57 and E-58 can reuse it.
  *Depends on: T-5601, T-5605.*

### Accessibility

- [x] **T-5607** Loosen the existing `.accessibilityElement(children: .ignore)` on the outer `SpeakerCard` to `.accessibilityElement(children: .contain)` so the new transport button (and later, the slider and favorites) are reachable individually by VoiceOver. Move the existing card-level summary (`accessibilityDescription` computed property) onto the `headerSection` only — it should describe the speaker name and state, not the controls. Confirm VoiceOver navigation order matches visual top-to-bottom: header → now-playing panel → volume → transport → favorites.

  Verify on a physical device with VoiceOver enabled that:
  - The pause button reads "Pause" when playing.
  - The play button reads "Play" when paused or stopped.
  - The header summary reads the speaker name and state.
  *Depends on: T-5602, T-5606.*

### Verification

- [ ] **T-5608** (deferred: manual verification on device) Manual test pass on a real Mozart speaker. Test matrix:
  1. Speaker playing → tap pause button → speaker pauses within ~1 s; button flips to gold play icon.
  2. Speaker paused → tap play button → speaker resumes; button flips to white pause icon.
  3. Speaker stopped → card collapses to header + full-width Play pill → tap Play → speaker starts last source.
  4. Speaker buffering → button shows pause.fill (white); tap pauses correctly.
  5. Disconnect speaker from network → tap pause → error toast appears; haptic pattern matches `errorOccurred`.
  6. Tap pause/play 5 times in quick succession → no crash; final speaker state matches final tap.
  7. VoiceOver: navigate the card; confirm header reads first, transport button last (before favorites land).

  Document timings (touch-up to visible state change) in the PR description.
  *Depends on: T-5603, T-5605, T-5606, T-5607.*

- [x] **T-5609** SwiftUI preview in `SpeakerCard.swift` covering all four playback states with mocked `Speaker` instances: playing, paused, buffering, stopped. Verify the transport row renders the correct icon and role in each. The previews should compile against `MockSpeaker` or use the existing speaker init with a stub `SpeakerClient` and `SpeakerEventSource`.
  *Depends on: T-5602, T-5606.*

---

## E-57 — Interactive volume slider

Replace the existing static gold `volumeTrack` view in `SpeakerCard` with an interactive `Slider` (custom style, invisible thumb, gold fill is the affordance) bound to `speaker.volume`. Range `0...100`, step `5`. Fire `setVolume(_:)` on drag end (`.onEditingChanged: false`), never on intermediate drag points. For grouped speakers, broadcast the new volume to all `group.members` concurrently via `withTaskGroup`. Fire `HapticEngine.shared.limitReached()` once when the dragged value crosses 0 or 100.

**Depends on:** E-56 (T-5605 — `SpeakerGroup` parameter on `SpeakerCard`; T-5606 — `showErrorToast` helper).
**Unlocks:** E-58 (favorites row sits below transport which sits below slider).

---

### Slider component

- [x] **T-5701** Create a new file `iOS/Voxio/DesignSystem/InteractiveVolumeBar.swift` defining a private SwiftUI view `InteractiveVolumeBar`:
  ```swift
  struct InteractiveVolumeBar: View {
      @Binding var value: Int
      let onEditingChanged: (Bool) -> Void
      // body: Slider(value:in:step:) with custom track + invisible thumb
  }
  ```

  Implementation: SwiftUI on iOS 26 does not expose a public `SliderStyle` protocol. Implement the bar as a `GeometryReader` containing a `ZStack` of two `Capsule`s (track at `.white.opacity(0.12)`, gold fill at `Color(hex: "#C8A97E")` width = `geo.size.width * CGFloat(value) / 100`, height 4 pt) wrapped in a `.gesture(DragGesture(minimumDistance: 0))`. The drag gesture updates `value` (snapped to nearest 5) and calls `onEditingChanged(true)` on `onChanged` first call; calls `onEditingChanged(false)` on `onEnded`.

  The view is non-private (file-internal) so `SpeakerCard` can use it. Visual fidelity must match the current `volumeTrack(level:)` exactly — same gold colour, same 4 pt height, same gold-fill animation on external value changes (`.animation(.easeOut(duration: 0.3), value: value)`).

  Trailing volume number (12 pt medium, `.secondary`, 28 pt fixed width) is rendered to the right of the bar inside the same `HStack`, identical to the current `volumeTrack` layout.
  *Depends on: T-5601.*

- [x] **T-5702** Replace `SpeakerCard.volumeTrack(level:)` (current static implementation, lines ~127–150 of `SpeakerCard.swift`) with `InteractiveVolumeBar` from T-5701. Wire the binding:
  ```swift
  InteractiveVolumeBar(
      value: Binding<Int>(
          get: { dragVolume ?? speaker.volume ?? 0 },
          set: { dragVolume = $0; handleLimitHaptic($0) }),
      onEditingChanged: { editing in
          if editing == false {
              let final = dragVolume ?? speaker.volume ?? 0
              Task { await broadcastVolume(final) }
              dragVolume = nil
              lastLimitHaptic = nil
          }
      })
  ```

  Add the supporting `@State` properties to `SpeakerCard`:
  - `@State private var dragVolume: Int? = nil`
  - `@State private var lastLimitHaptic: Int? = nil`

  Apply horizontal padding `Spacing.s24` and vertical padding `Spacing.s12` top and bottom (per design-spec §1.3 — increased from the static bar's previous padding to enlarge the drag target).

  Conditionally render the slider only in `.playing`, `.paused`, and `.buffering` states. Do NOT render in `.stopped` (per design-spec §3).
  *Depends on: T-5701, T-5601.*

### Limit haptic

- [x] **T-5703** Implement the private `handleLimitHaptic(_ value: Int)` method on `SpeakerCard`:
  - If `value == 0` and `lastLimitHaptic != 0`: fire `HapticEngine.shared.limitReached()`, post `AccessibilityNotification.Announcement("Volume at minimum").post()`, set `lastLimitHaptic = 0`.
  - If `value == 100` and `lastLimitHaptic != 100`: fire `HapticEngine.shared.limitReached()`, post `AccessibilityNotification.Announcement("Volume at maximum").post()`, set `lastLimitHaptic = 100`.
  - If `value > 0 && value < 100`: set `lastLimitHaptic = nil` (re-arms the haptic so a return to the limit fires again).

  This guarantees the limit haptic fires at most once per boundary crossing within a single drag, never on every step at the boundary.
  *Depends on: T-5702.*

### Group volume broadcast

- [x] **T-5704** Add `func setVolumeOnAllMembers(_ level: Int) async -> [(speaker: Speaker, result: Result<Void, Error>)]` to `SpeakerGroup` (`iOS/Voxio/Core/Models/Group.swift`). Implementation uses `withTaskGroup`:
  ```swift
  await withTaskGroup(of: (Speaker, Result<Void, Error>).self) { taskGroup in
      for member in members {
          taskGroup.addTask {
              do {
                  try await member.setVolume(level)
                  return (member, .success(()))
              } catch {
                  return (member, .failure(error))
              }
          }
      }
      var results: [(Speaker, Result<Void, Error>)] = []
      for await result in taskGroup { results.append(result) }
      return results
  }
  ```

  Per spec UQ-3 resolved: volume is broadcast to all members concurrently. Failures on individual members do not block other members.
  *Depends on: T-5701 (file infrastructure not strictly required, but tasks are sequenced for review clarity).*

- [x] **T-5705** Implement the `broadcastVolume(_ level: Int) async` private method on `SpeakerCard`:
  ```swift
  private func broadcastVolume(_ level: Int) async {
      let results = await group.setVolumeOnAllMembers(level)
      let failed = results.filter { if case .failure = $0.result { return true } else { return false } }
      guard failed.isEmpty == false else { return }
      for (speaker, result) in failed {
          if case .failure(let error) = result {
              Log.error("[\(speaker.name)] setVolume failed: \(error)")
          }
      }
      let suffix = failed.count == 1 ? "speaker" : "speakers"
      showErrorToast("Volume failed on \(failed.count) \(suffix)")
      HapticEngine.shared.errorOccurred()
  }
  ```

  Note: the current `Speaker.setVolume(_:)` already updates `speaker.volume` locally on success. After a partial failure, the slider's visible position will reflect whichever member values are received via WS events; this is acceptable — the lead speaker's WS event drives the displayed value via `speaker.volume`.
  *Depends on: T-5702, T-5704, T-5606 (showErrorToast helper).*

### Accessibility

- [x] **T-5706** Add a `.accessibilityValue("\(value) percent")` and `.accessibilityLabel("Volume")` to the `InteractiveVolumeBar`. VoiceOver users adjust via the rotor's "Adjust value" gesture — implement `.accessibilityAdjustableAction { direction in ... }` so VoiceOver up/down adjusts in steps of 5 and dispatches the same `setVolume` call as the visual drag. Limit announcements from T-5703 fire identically for VoiceOver-driven adjustments.
  *Depends on: T-5702, T-5703.*

### Verification

- [ ] **T-5707** (deferred: manual verification on device) Manual test pass on a real Mozart speaker (single speaker, no group). Test matrix:
  1. Drag slider from 20 to 60 → volume number updates live; `setVolume(60)` fires once on release; speaker volume changes to 60.
  2. Drag slider to 0 → `limitReached` haptic fires; VoiceOver announces "Volume at minimum"; `setVolume(0)` fires on release.
  3. Drag slider to 100 → `limitReached` haptic fires; "Volume at maximum" announced; `setVolume(100)` fires on release.
  4. Drag slider, releasing at 5-step boundaries (e.g. 35, 70) → exactly one `setVolume` per release.
  5. Tap-and-release at the slider midpoint without dragging → `setVolume` fires for the tapped value (drag gesture with `minimumDistance: 0` treats taps as zero-distance drags).
  6. Disconnect speaker → drag slider and release → error toast "Volume failed on 1 speaker"; `errorOccurred` haptic.
  7. WS event arrives mid-drag (e.g. another app on the network changes volume) → slider position remains at the dragged value during drag (`dragVolume` overrides `speaker.volume`); on release, `dragVolume` clears and slider snaps to the WS-updated value if no further `setVolume` is in flight.
  *Depends on: T-5702, T-5703, T-5705.*

- [ ] **T-5708** (deferred: manual verification on device) Manual test pass on a multi-speaker group. Two Mozart speakers joined into a group:
  1. Drag the lead speaker's card slider to 50 → both speakers' volumes change to 50 within ~1 s.
  2. Disconnect one follower mid-drag → release at 30 → error toast "Volume failed on 1 speaker"; the still-connected speaker reaches 30; the disconnected speaker remains at its prior level.
  3. Disconnect both speakers → drag and release → error toast "Volume failed on 2 speakers".
  4. Verify with the speakers' physical knobs / B&O app that all members reached the broadcast value.
  *Depends on: T-5705.*

- [ ] **T-5709** (deferred: no XCTest target in this repo; covered in test plan) Unit test in `iOS/VoxioTests/SpeakerGroupTests.swift` (create file if absent) covering `setVolumeOnAllMembers(_:)`. Use mock `Speaker` instances (or test doubles) with stub `SpeakerClient` implementations that record calls. Assert:
  - All members' `setVolume` are called with the same level.
  - All calls are dispatched concurrently (assert via timestamps inside the mocks — first-call-time differs by < 50 ms).
  - One member throwing returns a `.failure` for that member and `.success` for others.
  - All members throwing returns all-failures.
  - Empty-members precondition triggers (already enforced by `SpeakerGroup` init's `precondition(!members.isEmpty)`).
  *Depends on: T-5704.*

---

## E-58 — Favorites row

Add a horizontally-scrolling row of `DarkGlassButton` pills below the transport row (in playing/paused/buffering states) and below the Play pill (in stopped state). Load favorites async on card appear via `speaker.getFavorites()`. Tapping a favorite calls `speaker.playFavorite(presetIndex:)` with the array index. No active-favorite highlight (per UQ-1). Empty favorites → row absent.

**Depends on:** E-56 (T-5601 — card structure refactor; T-5606 — `showErrorToast` helper). E-57 is independent but is sequenced after for clean diffs in `SpeakerCard.swift`.
**Unlocks:** future Feature 3 (home screen redesign) reuses the same favorites pill component.

---

### Favorites loading

- [x] **T-5801** Add `@State private var favorites: [Favorite] = []` to `SpeakerCard`. Add a `.task` modifier on the outer card view (or on the favorites row container) that calls:
  ```swift
  .task {
      do {
          favorites = try await speaker.getFavorites()
      } catch {
          Log.warn("[\(speaker.name)] getFavorites failed: \(error)")
          favorites = []
      }
  }
  ```

  `Speaker.getFavorites()` is already implemented (`iOS/Voxio/Features/Home/Speaker.swift` line 227) and returns `[Favorite]` via `client.getSources()`. The `.task` modifier ensures the call runs once on appear and is cancelled if the card disappears before completion.

  Failures are silent (logged at WARN, no toast) — this is a passive load, not a user-initiated action.
  *Depends on: T-5601.*

### Favorites row view

- [x] **T-5802** Add a private `favoritesRow` view to `SpeakerCard`. Implementation:
  ```swift
  @ViewBuilder
  private var favoritesRow: some View {
      if favorites.isEmpty == false {
          ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: Spacing.s8) {
                  ForEach(Array(favorites.enumerated()), id: \.offset) { index, fav in
                      DarkGlassButton(label: fav.displayName, role: .default) {
                          onFavoriteTapped(index: index)
                      }
                      .fixedSize()
                  }
              }
              .padding(.horizontal, Spacing.s24)
          }
          .mask(trailingFadeGradient)
          .padding(.top, Spacing.s8)
          .padding(.bottom, Spacing.s20)
      }
  }
  ```

  `trailingFadeGradient` is a `LinearGradient` (`.white` from leading to ~90% width, fading to `.clear` at trailing) that signals scrollability per design-spec §4.2.

  All favorites use `role: .default` per UQ-1 resolved (no active-favorite highlight). `fav.displayName` is the favorite's user-visible name from the `Favorite` model (`iOS/Voxio/Core/Models/`); confirm the property name and adjust if the model uses `name` or another field.

  Insert the `favoritesRow` view in the `cardContent`:
  - In playing/paused/buffering: directly below the `transportRow` (T-5602).
  - In stopped state: directly below the full-width Play pill (T-5606).
  *Depends on: T-5801, T-5602, T-5606.*

### Tap handler

- [x] **T-5803** Implement the private `onFavoriteTapped(index: Int)` method on `SpeakerCard`:
  ```swift
  private func onFavoriteTapped(index: Int) {
      HapticEngine.shared.commandRecognised()
      Task {
          do {
              try await speaker.playFavorite(presetIndex: index)
          } catch {
              Log.error("[\(speaker.name)] playFavorite(\(index)) failed: \(error)")
              showErrorToast("Could not start favorite")
              HapticEngine.shared.errorOccurred()
          }
      }
  }
  ```

  Per the spec, the `presetIndex` is the array position from `speaker.getFavorites()`. `Speaker.playFavorite(presetIndex:)` (line 231 of `Speaker.swift`) already routes Mozart vs BNR appropriately.

  Use `speaker` directly (not `group.hostSpeaker`) because the favorite is being started on the speaker the card represents — which for grouped cards is also the host. If a future iteration wants to start a favorite across all members, that is a separate decision (currently out of scope; per design-spec §8 broadcast touch is voice-only in v1.4).
  *Depends on: T-5802.*

### Accessibility

- [x] **T-5804** Confirm each `DarkGlassButton` in the favorites row exposes the favorite's display name as its `accessibilityLabel` — `DarkGlassButton` already passes `label` to `.accessibilityLabel(label)` so this should be automatic. Per UQ-1 resolved, do NOT append "currently playing" or any active-state suffix to the label.

  Wrap the `ScrollView` in `.accessibilityElement(children: .contain)` so VoiceOver navigates each pill individually rather than treating the scroll view as a single element.

  Verify on a physical device with VoiceOver enabled:
  - Each pill reads its favorite's name.
  - VoiceOver swipes between pills horizontally; the scroll view scrolls to keep the focused pill visible.
  *Depends on: T-5802.*

### Verification

- [ ] **T-5805** (deferred: manual verification on device) Manual test pass on a real Mozart speaker that has at least 3 configured presets. Test matrix:
  1. Card appears → favorites row populates within ~500 ms with 3+ pills.
  2. Tap a favorite → `commandRecognised` haptic fires; speaker switches source; card re-renders to show the new now-playing track within ~2 s.
  3. Tap another favorite → switches without issue.
  4. Tap a favorite while the card is in the stopped state → speaker starts; card transitions from stopped layout (header + Play pill + favorites) to playing layout (header + now-playing panel + slider + transport + favorites).
  5. Disconnect speaker → tap a favorite → error toast "Could not start favorite"; `errorOccurred` haptic.
  6. Test against a speaker with zero presets configured → favorites row is absent (no empty space, no placeholder).
  7. Test against a speaker that returns an error from `getSources()` → favorites row is absent; WARN logged.
  8. VoiceOver: navigate the row; each pill reads its favorite name.
  *Depends on: T-5803, T-5804.*

- [x] **T-5806** SwiftUI preview in `SpeakerCard.swift` (or a new `SpeakerCard+Previews.swift`) covering the favorites row in three configurations:
  - Playing state with 5 favorites.
  - Stopped state with 3 favorites.
  - Playing state with 0 favorites (row absent).

  Use a stub `SpeakerClient.getSources()` that returns the configured array. Confirm visual matches design-spec §4.2 layout.
  *Depends on: T-5802.*

---

## Recommended Implementation Order

1. **E-56 first.** T-5601 (card structure refactor) is the structural prerequisite for both other epics. T-5602 → T-5603 → T-5604 → T-5605 → T-5606 → T-5607 → T-5608 → T-5609 in sequence; the manual and preview verification tasks (T-5608, T-5609) can run in parallel at the end.

2. **E-57 second.** T-5701 (component file) and T-5704 (group helper on `SpeakerGroup`) can begin in parallel since they touch different files. T-5702 (slider integration) requires T-5701. T-5703 (limit haptic) and T-5705 (broadcast wiring) follow T-5702. T-5706 (accessibility) after T-5703. Verification T-5707, T-5708, T-5709 run last; T-5709 (unit test) can land in parallel with T-5707 (single-speaker manual test) since it tests the helper in isolation.

3. **E-58 last** so the favorites row diff lands cleanly on top of the transport + slider work. T-5801 (loading) → T-5802 (view) → T-5803 (tap handler) → T-5804 (accessibility) → T-5805 (manual test), T-5806 (preview).

4. **Parallel option:** if two engineers are available, E-58 can start in parallel with E-57 because they touch independent regions of `SpeakerCard.cardContent`. Resolve any merge conflicts in the cardContent body when both land.

A reasonable single-engineer sequence (one full-stack iOS engineer):

```
Day 1:    T-5601 (refactor) → T-5602 (transport row) → T-5603 (tap handlers) → T-5604 (paused bars)
Day 2:    T-5605 (group plumbing) → T-5606 (stopped state) → T-5607 (a11y) → T-5608, T-5609 (verify)
Day 3:    T-5701 (slider component) → T-5702 (slider integration) → T-5703 (limit haptic) → T-5704 (group helper)
Day 4:    T-5705 (broadcast wiring) → T-5706 (slider a11y) → T-5707, T-5708, T-5709 (verify)
Day 5:    T-5801 (favorites load) → T-5802 (favorites row) → T-5803 (tap handler) → T-5804 (a11y) → T-5805, T-5806 (verify)
```

---

## Task Summary

| Epic | Tasks | Notes |
|---|---|---|
| E-56 Play/pause toggle button | 9 | T-5601–T-5609. Card structure refactor, transport row, group-aware dispatch, stopped-state Play pill, paused-state bars freeze, accessibility, manual + preview verification. |
| E-57 Interactive volume slider | 9 | T-5701–T-5709. Custom interactive volume bar component, slider integration, limit haptic, group volume helper on `SpeakerGroup`, broadcast wiring, accessibility, manual (single + group) + unit verification. |
| E-58 Favorites row | 6 | T-5801–T-5806. Async favorites load, scrollable pill row, tap handler, accessibility, manual + preview verification. |
| **Total** | **24** | All tasks are new work (unchecked). No backend, REST, or voice pipeline changes. |

---

## Amendment History

| Date | Source | Change |
|---|---|---|
| 2026-05-09 | Initial draft | First version of the Touch Playback Controls epics and tasks (E-56–E-58, T-5601–T-5806). Derived from approved design-spec v1.2 and functional spec v1.0. |
