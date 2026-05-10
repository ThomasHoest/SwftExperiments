# Touch Playback Controls Specification — Voxio 1.4
**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-09
**Platform:** iOS 26 (iPhone, portrait) — SwiftUI
**References:** design-spec-touch-playback-controls.md (v1.2 — primary source for visual design and resolved UQs), VoxioSpecification-1.4.md (Feature 1), CLAUDE.md (`Speaker`, `SpeakerGroup`, `MozartClient`, `DarkGlassIconButton`, `DarkGlassButton`, `HapticEngine`, `Spacing`, `Radius`, `BeoAnimation`)

**Amendment history**

| Version | Date | Summary |
|---|---|---|
| 1.0 | 2026-05-09 | Initial draft. Functional specification for Feature 1 of Voxio 1.4 — touch play/pause, interactive volume slider, and favorites row added to `SpeakerCard`. |

---

## Introduction

Voxio v1.4 Feature 1 adds direct touch control of playback to the existing now-playing card (`SpeakerCard`). Until v1.3, the card was a read-only surface — the user could see what was playing and at what volume, but every command (play, pause, volume, favorite) had to go through the voice pipeline. v1.4 makes those four actions available as touch controls **on the card itself**, without removing or altering any voice behaviour.

All visual design decisions — sizes, colours, layouts, paddings, SF Symbols — are specified in `design-spec-touch-playback-controls.md` and are not duplicated here. This document specifies **what the user can do, what the system must do in response, how the components wire to the existing data layer, and how failures are handled.** Visual polish lives in the design spec; behaviour and contracts live here.

The feature consists of three additions placed below the existing volume bar inside `SpeakerCard`:

1. A play/pause toggle button (single `DarkGlassIconButton`).
2. An interactive volume slider (replaces the current static gold bar).
3. A horizontally scrolling favorites row (`DarkGlassButton` pills).

In the stopped/idle state the card collapses to a header plus a single full-width Play pill plus the favorites row.

Touch controls do **not** go through the voice confirmation countdown — a deliberate tap is unambiguous. Touch controls do **not** introduce new voice intents, do not change the voice parsing pipeline, and do not change any backend or telemetry behaviour.

### What is in scope

- Three new touch controls on `SpeakerCard`: play/pause toggle, interactive volume slider, favorites row.
- Stopped-state card variant: header + full-width Play pill + favorites row.
- Group-aware volume: a volume drag on a card whose speaker is part of a `SpeakerGroup` broadcasts the new level to **all** group members concurrently.
- Haptic feedback on tap (`commandRecognised`) and at volume limits (`limitReached`).
- Accessibility labels and announcements for all new controls.
- Async load of favorites on card appear; empty state (no favorites → row absent).

### What is NOT in scope

See design-spec-touch-playback-controls.md §8 for the full out-of-scope list. In summary: no separate stop control, no seek/scrub, no skip next/previous, no mute touch control, no broadcast-to-all-speakers touch, no group join/leave UI (covered in `design-spec-multiroom-grouping.md`).

---

## Technical Context

| Decision | Choice | Rationale |
|---|---|---|
| Where touch controls live | Inside `SpeakerCard` (`iOS/Voxio/Features/Home/SpeakerCard.swift`) | Keeps controls contextual; no separate control surface or panel |
| Play/pause toggle component | Single `DarkGlassIconButton` (52 pt visual / 64 pt hit area) | Matches design-spec §1.2; one tap = one action |
| Stopped-state Play affordance | Full-width `DarkGlassButton` pill with "Play" label | Matches design-spec §3.1; pill (not icon-only) signals primary CTA when card is otherwise empty |
| Volume control | `Slider(value:in:step:)` with `step: 5`, range 0–100, custom `SliderStyle` (invisible thumb — fill is the affordance) | Promotes the existing static gold bar to interactive without introducing a new visual component |
| Volume API call timing | `setVolume(_:)` on drag end (`.onEditingChanged`), not on every drag point | Avoids flooding the speaker REST API; design-spec §1.3 |
| Volume in groups | Broadcast to all `SpeakerGroup.members` concurrently via `withTaskGroup` | Design-spec UQ-3 resolved: B&O grouping is leader/follower for transport but volume is per-speaker |
| Transport actions in groups | Targeted at the lead (host) speaker only | Design-spec UQ-3 resolved: followers mirror leader's play state automatically |
| Favorite component | `DarkGlassButton` pill with favorite name as label, no icon, `.default` role always | Design-spec UQ-1 resolved: no active-favorite highlight (cannot reliably match preset to `nowPlaying`) |
| Favorites loading | `speaker.getFavorites()` called once on card appear (`.task` modifier) | Lazy load; cards that never expand to show favorites avoid the REST call |
| Empty favorites | Row absent (no empty placeholder) | Design-spec §4.2 |
| Haptics on tap | `HapticEngine.shared.commandRecognised()` for transport and favorite taps | Design-spec §5.2 |
| Haptics at volume limit | `HapticEngine.shared.limitReached()` when slider value reaches 0 or 100 mid-drag | Design-spec §5.2 |
| Confirmation countdown | None for touch actions | Design-spec §5.1 — touch is unambiguous |
| Mute | Voice-only in v1.4 | Design-spec UQ-2 resolved |
| Error feedback | Existing toast surface (`.error`) | Design-spec §5.3 — toast behaviour unchanged |

---

## Goals

- The user can play, pause, set volume, and start a favorite from the now-playing card without speaking a command.
- The user can perform any of those four actions in one tap (no menus, no confirmation step).
- A volume change applied to a grouped speaker reaches every member of the group within one network round-trip per member.
- A speaker with no favorites does not show an empty favorites row.
- A speaker that is stopped/idle still allows the user to start playback or jump straight to a favorite.
- All new controls are reachable by VoiceOver and keyboard, with explicit labels and limit announcements.
- No voice command, intent, or parser path is altered.

---

## Out of Scope (this version)

See design-spec-touch-playback-controls.md §8. Notable exclusions:

- Separate stop control — pause is functionally equivalent on Mozart speakers.
- Seek/scrub within a track — Mozart API does not expose position.
- Skip next/previous, queue management.
- Mute as a touch control — voice-only.
- Broadcast-to-all-speakers touch — voice-only.
- Multiroom join/leave from the card — covered by Feature 2 (`design-spec-multiroom-grouping.md`).
- Live Activity, Lock Screen, or WidgetKit changes.

---

## User Stories

The user stories below describe end-user touch interactions on `SpeakerCard`. iOS-side voice behaviour is unchanged from v1.3 and is not duplicated here.

---

**US-70 — Play and pause by touch**
> As a user, I want to tap a single button on the now-playing card to start or stop the audio so that I do not have to speak a command for the most basic playback action.

**Acceptance criteria:**
- When the speaker is in the playing state, the card shows a single centred toggle button rendered as a `DarkGlassIconButton` with `pause.fill` icon and `.default` role (white).
- When the speaker is in the paused or buffering state, the toggle button shows `play.fill` and `.confirm` role (gold).
- When the speaker is in the stopped/idle state, the card shows only a full-width `DarkGlassButton` pill with label "Play", `play.fill` icon, and `.confirm` role (gold). No volume bar or now-playing panel is visible in this state.
- Tapping the toggle while playing calls `speaker.pause()` exactly once and fires `HapticEngine.shared.commandRecognised()` synchronously on tap.
- Tapping the toggle while paused, buffering, or stopped calls `speaker.play()` exactly once and fires `HapticEngine.shared.commandRecognised()` synchronously on tap.
- No confirmation countdown appears.
- The button icon, role (gold/white), and the wider card layout update within one frame of the speaker's `state` property changing (driven by `@Observable` re-render).
- VoiceOver reads the button as "Pause" when playing and "Play" when paused/stopped.
- The button hit area is at least 44 × 44 pt (guaranteed by `DarkGlassIconButton`).
- A failed `pause()` or `play()` call (network or HTTP error) surfaces through the existing toast mechanism with `HapticEngine.shared.errorOccurred()` and leaves the button visual state untouched (driven by the speaker's actual state).

---

**US-71 — Set volume by touch**
> As a user, I want to drag along the volume bar to set a precise volume level so that I do not have to issue multiple "louder" / "quieter" voice commands to reach the level I want.

**Acceptance criteria:**
- The existing static gold volume bar is replaced by an interactive `Slider(value:in:step:)` with range `0...100` and `step: 5`.
- The slider has an invisible thumb (custom `SliderStyle`); the gold fill is the touch affordance.
- The slider is only shown in the playing, paused, and buffering states (not in stopped/idle, per design-spec §3).
- The numeric volume readout next to the slider updates live during drag (every value change), reflecting the dragged value.
- `speaker.setVolume(_:)` is called exactly once per drag interaction, on drag end (`Slider`'s `onEditingChanged` transitioning `true → false`). It is NOT called on intermediate drag points.
- When the dragged value reaches `0` or `100` mid-drag, `HapticEngine.shared.limitReached()` fires once per limit boundary crossing.
- VoiceOver announces "Volume at maximum" (EN) / "Lydstyrken er på maksimum" (DA) when the limit is reached at 100, and the corresponding minimum string at 0.
- A failed `setVolume(_:)` call leaves the on-card volume reading at whatever the speaker's last-known `volume` property is (driven by `@Observable` re-render after the failure restores the prior value via WS event).

---

**US-72 — Start a favorite by touch**
> As a user, I want to tap a favorite name to start playing it so that I can switch sources without speaking the favorite's name.

**Acceptance criteria:**
- When the card appears, `speaker.getFavorites()` is called once asynchronously via `.task`.
- If `getFavorites()` returns at least one favorite, the card renders a `ScrollView(.horizontal, showsIndicators: false)` containing one `DarkGlassButton` per favorite, with the favorite's display name as label, no icon, `.default` role.
- If `getFavorites()` returns zero favorites or throws, no favorites row is rendered (the row is absent — not empty space).
- The favorites row is shown in the playing, paused, buffering, and stopped states.
- In the stopped state, the favorites row appears below the full-width Play pill.
- Tapping a favorite calls `speaker.playFavorite(presetIndex:)` exactly once with the index matching that favorite's position in the returned array.
- `HapticEngine.shared.commandRecognised()` fires synchronously on tap.
- All favorites are always rendered with `.default` role (no `.confirm` highlight for an "active" favorite — design-spec UQ-1 resolved).
- VoiceOver reads each favorite button as the favorite's display name (no active-playing suffix).
- A failed `playFavorite(_:)` call surfaces through the existing toast mechanism with `HapticEngine.shared.errorOccurred()`.
- A failed `getFavorites()` call is logged at WARN and the row is omitted; no toast is shown (silent failure for a passive load).

---

**US-73 — Volume change broadcasts to a group**
> As a user, when I drag the volume on a speaker that is grouped with other speakers, I want every speaker in that group to change volume to the same level so that the room remains balanced without me having to adjust each speaker individually.

**Acceptance criteria:**
- When the `SpeakerCard` is bound to a `SpeakerGroup` whose `members` count is greater than 1, drag-end on the slider fires `setVolume(_:)` on **every** member concurrently using `withTaskGroup`.
- All member calls are dispatched concurrently (not in series). The slider drag is not blocked waiting for completion.
- A failure on any one member is logged at ERROR with the failing speaker's identifier; success or failure of one member does not block the others.
- If at least one member call succeeds and at least one fails, a single error toast is shown with the count of failed members (e.g. "Volume failed on 1 speaker").
- If all member calls fail, the standard error toast is shown and `HapticEngine.shared.errorOccurred()` fires.
- For a single-speaker card (group `members.count == 1` or no group abstraction in use), the behaviour is identical to a single `speaker.setVolume(_:)` call.
- Transport (`play`, `pause`) actions are NOT broadcast to group members — they are sent to the host speaker only (`group.hostSpeaker`), per design-spec UQ-3.

---

## Technical Requirements

### Component placement

All three additions live inside `SpeakerCard.cardContent` (file `iOS/Voxio/Features/Home/SpeakerCard.swift`), inserted **below** the existing `volumeTrack(level:)` view in the playing/paused/buffering branch, and replacing the entire body of the stopped branch with the stopped-state layout.

The view layout in the playing/paused/buffering state, top to bottom:
1. `headerSection` (unchanged)
2. `nowPlayingPanel` (unchanged)
3. Volume slider (US-71) — replaces the current `volumeTrack(level:)` GeometryReader implementation.
4. Transport row containing the play/pause `DarkGlassIconButton` (US-70).
5. Favorites row (US-72), if `favorites.isEmpty == false`.

The view layout in the stopped state, top to bottom:
1. `headerSection` (unchanged)
2. Full-width Play `DarkGlassButton` pill (US-70 stopped variant).
3. Favorites row (US-72), if `favorites.isEmpty == false`.

### Data model additions

`SpeakerCard` gains the following local state:
- `@State private var favorites: [Favorite] = []` — populated by `.task` on appear via `speaker.getFavorites()`.
- `@State private var dragVolume: Int? = nil` — holds the slider's live value during drag; reset to `nil` on drag end so the source of truth returns to `speaker.volume`.
- `@State private var lastLimitHaptic: Int? = nil` — tracks whether a limit haptic has already fired for the current drag at 0 or 100, to avoid repeat firing on the same boundary within one drag.

`SpeakerCard`'s init signature accepts an optional `SpeakerGroup` for US-73. If only a single `Speaker` is passed (current usage), it is wrapped in `SpeakerGroup.single(speaker)` internally. The card calls volume on `group.members`; transport on `group.hostSpeaker`.

### Volume slider — wiring contract

```
Slider(value: Binding<Double>(
           get: { Double(dragVolume ?? speaker.volume ?? 0) },
           set: { newValue in
               let clamped = Int(newValue)
               dragVolume = clamped
               handleLimitHaptic(clamped)
           }),
       in: 0...100,
       step: 5,
       onEditingChanged: { editing in
           if editing == false {
               let final = dragVolume ?? speaker.volume ?? 0
               Task { await broadcastVolume(final) }
               dragVolume = nil
               lastLimitHaptic = nil
           }
       })
```

`broadcastVolume(_ level: Int) async` (added on `SpeakerGroup` or as a helper in `SpeakerCard`) iterates `group.members` inside `withTaskGroup(of: Result<Void, Error>.self)`, calls `member.setVolume(level)` on each, collects results, and surfaces any failures via the existing toast mechanism.

The custom `SliderStyle` is implemented as a private `ButtonStyle`-equivalent for `Slider` — SwiftUI does not expose a true `SliderStyle` protocol on iOS 26, so the implementation uses a `ZStack` of `Capsule` (track) + `Capsule` (gold fill, width proportional to value) wrapped in a `.gesture(DragGesture)` that maps drag-x to `value`. This view is private to `SpeakerCard.swift` and named `InteractiveVolumeBar`.

### Limit haptic

Inside the slider value setter:
- If the new clamped value is `0` and `lastLimitHaptic != 0`, fire `HapticEngine.shared.limitReached()` and announce "Volume at minimum"; set `lastLimitHaptic = 0`.
- If the new clamped value is `100` and `lastLimitHaptic != 100`, fire `HapticEngine.shared.limitReached()` and announce "Volume at maximum"; set `lastLimitHaptic = 100`.
- If the new clamped value is between `1` and `99`, set `lastLimitHaptic = nil` so a subsequent return to a limit re-arms the haptic.

### Transport row — wiring contract

A `Group` view that switches on `speaker.playbackState`:
- `.playing` or `.buffering` → `DarkGlassIconButton(systemImage: "pause.fill", role: .default, accessibilityLabel: "Pause") { onPauseTapped() }`
- `.paused` → `DarkGlassIconButton(systemImage: "play.fill", role: .confirm, accessibilityLabel: "Play") { onPlayTapped() }`
- `.stopped` → `DarkGlassButton(label: "Play", systemImage: "play.fill", role: .confirm) { onPlayTapped() }` (full-width pill, used in the stopped-state layout above)

`onPauseTapped()` fires `HapticEngine.shared.commandRecognised()` then dispatches `Task { try? await group.hostSpeaker.pause() }` with error handling that surfaces a toast on failure.

`onPlayTapped()` fires `HapticEngine.shared.commandRecognised()` then dispatches `Task { try? await group.hostSpeaker.play() }` with the same error handling.

Both icon buttons are placed in an `HStack` with `.frame(maxWidth: .infinity)` so the icon button is centred. Horizontal padding `Spacing.s24`; vertical padding `Spacing.s16` top, `Spacing.s20` bottom (per design-spec §1.2).

### Favorites row — wiring contract

```
.task {
    do {
        favorites = try await speaker.getFavorites()
    } catch {
        Log.warn("[\(speaker.name)] getFavorites failed: \(error)")
        favorites = []
    }
}
```

The row, when `favorites.isEmpty == false`:

```
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: Spacing.s8) {
        ForEach(Array(favorites.enumerated()), id: \.offset) { index, fav in
            DarkGlassButton(label: fav.displayName, role: .default) {
                HapticEngine.shared.commandRecognised()
                Task {
                    do {
                        try await speaker.playFavorite(presetIndex: index)
                    } catch {
                        showErrorToast(...)
                        HapticEngine.shared.errorOccurred()
                    }
                }
            }
            .fixedSize()
        }
    }
    .padding(.horizontal, Spacing.s24)
}
```

The trailing fade gradient mask (per design-spec §4.2) is applied via `.mask(LinearGradient)` on the `ScrollView`.

The `presetIndex` is the **array position** of the favorite in `speaker.getFavorites()`'s returned array. This is the contract that `Speaker.playFavorite(presetIndex:)` already implements (see `iOS/Voxio/Features/Home/Speaker.swift` line 231).

### Accessibility

- `DarkGlassIconButton` and `DarkGlassButton` already accept `accessibilityLabel` — pass the strings from design-spec Appendix B.
- The transport row container uses `.accessibilityElement(children: .contain)` so VoiceOver navigates each button individually.
- Limit announcements use `AccessibilityNotification.Announcement(...).post()` (iOS 17+ API; iOS 26 supported).
- VoiceOver order within the card: header → now-playing panel → volume slider → transport button → favorites (top to bottom matches view tree order).
- Existing card-level `.accessibilityElement(children: .ignore) + .accessibilityLabel(...)` on the outer `SpeakerCard` must be reconsidered: the new controls require their own VoiceOver targets, so the card-level ignore must be loosened to `.accessibilityElement(children: .contain)` (or removed) so child controls become reachable. The card's overall summary (`accessibilityDescription`) is moved to a `.accessibilityLabel` on the header section only.

---

## Error States

| Scenario | Expected Behaviour |
|---|---|
| Tap play/pause toggle while network unreachable | `Speaker.play()` / `pause()` throws `MozartError.unreachable`. Existing error toast displayed. `HapticEngine.shared.errorOccurred()` fires. Button visual state remains driven by `speaker.state` (does not flip optimistically). |
| Tap play/pause toggle and HTTP 5xx | Same as above; error toast shows the error message from `MozartError.httpError`. |
| Tap play/pause and request times out (5 s) | `MozartError.timeout`. Same toast + haptic behaviour. |
| Slider drag end and `setVolume` fails on a single speaker | Error toast: "Volume failed on 1 speaker". Logged at ERROR with speaker identifier. The slider's visual position re-renders to whatever WS event arrives next (which may be the previous level). |
| Slider drag end and `setVolume` fails on all members of a group | Error toast: "Volume failed on N speakers" where N = `members.count`. `HapticEngine.shared.errorOccurred()` fires once. |
| Slider drag end and `setVolume` succeeds on some, fails on others | Error toast: "Volume failed on N speakers" where N = failed count. `HapticEngine.shared.errorOccurred()` fires once. |
| Slider drag reaches limit (0 or 100) mid-drag | `HapticEngine.shared.limitReached()` fires once for that boundary; VoiceOver announces "Volume at maximum" or "Volume at minimum". Re-fires only after the value leaves the limit and returns. |
| Favorite tap fails (e.g. `MozartError.unreachable`) | Existing error toast displayed. `HapticEngine.shared.errorOccurred()` fires. |
| `getFavorites()` throws on card appear | Logged at WARN. `favorites` remains empty. Row absent. No toast (silent failure for a passive load). |
| `getFavorites()` returns empty array | Row absent (no empty placeholder, no "No favorites" message). |
| Speaker transitions from playing → stopped while user is dragging slider | The drag state (`dragVolume`) continues to drive the visual position until drag end. On drag end, the slider disappears (stopped state hides the slider per design-spec §3). The pending `setVolume` still dispatches; if the speaker has gone fully offline the call surfaces an error toast as above. |
| Speaker transitions to stopped while pause/play tap is in flight | The button visual updates to the stopped-state Play pill on the next frame; the in-flight call completes or errors as normal. |
| Speaker is removed from `SpeakerGroup.members` mid-drag | The `withTaskGroup` iteration uses the snapshot of `group.members` taken at drag-end, so the removed speaker still receives the call. If the removed speaker is unreachable, it surfaces as a per-speaker failure (per the group-failure rows above). |
| User taps Play in stopped state but no source is configured on the speaker | `Speaker.play()` is called; if the underlying API rejects (no source), the standard error toast appears. The card remains in the stopped state until a state change event arrives. |

---

## Non-Functional Requirements

**Latency**

- Tap on play/pause: API request dispatched within 50 ms of touch-up. Visual state update follows the WS playback-state event (typical < 1 s on local network).
- Slider drag end: `setVolume` API request dispatched within 50 ms of drag-end. Per-speaker request completes within the existing `MozartClient` 5 s timeout.
- Group volume broadcast: all member requests dispatched concurrently within 50 ms of drag-end (not staggered).
- Favorite tap: `playFavorite` API request dispatched within 50 ms of touch-up.
- `getFavorites()` on card appear: must not block initial card render. Card renders without favorites row first, then re-renders when favorites load (typical < 500 ms on warm Mozart speaker).

**Accessibility**

- All interactive controls expose a `accessibilityLabel`.
- Volume limits announced via `AccessibilityNotification.Announcement`.
- All hit areas ≥ 44 × 44 pt.
- VoiceOver navigation order matches visual top-to-bottom order.
- Reduce Motion: the existing `reduceMotion`-aware animations on `SpeakerCard` are unaffected. The slider drag is not animated; the gold fill follows touch directly.
- Increase Contrast: `DarkGlassIconButton` and `DarkGlassButton` already adapt borders for `.increased` colour contrast (existing behaviour unchanged).

**Privacy and telemetry**

- No new telemetry events. Touch actions are not logged to the backend in v1.4.
- All existing logging via `Log.info` / `Log.error` continues to apply (same `[speaker name]` prefix).

**Network and offline**

- All four touch actions use the existing `MozartClient` (or `BNRClient`) HTTP path. No new endpoints introduced.
- Mozart 5 s request timeout applies. iOS app already handles `MozartError.timeout` / `unreachable` / `httpError`.

**Compatibility**

- iOS 26 minimum (unchanged).
- No changes to `Info.plist` keys.
- No changes to `MozartClient`, `BNRClient`, `Speaker`, or `SpeakerGroup` public API surfaces beyond the new `broadcastVolume(_:)` helper.

---

## Open Questions

*All design questions are resolved (see design-spec UQ-1 through UQ-3). The following implementation question remains:*

1. **Where should the group volume broadcast helper live?** — Owner: iOS lead. Default assumption: add `func setVolumeOnAllMembers(_ level: Int) async -> [Result<Void, Error>]` on `SpeakerGroup` (file `iOS/Voxio/Core/Models/Group.swift`). Alternative: keep it as a private helper inside `SpeakerCard.swift`. The `SpeakerGroup` location is preferred for reuse by Feature 2 (multiroom grouping) and Feature 3 (swipeable session view), but defer the decision until those features start.

---

## Resolved Decisions

| Question | Decision |
|---|---|
| Active-favorite highlight | None — favorites are always `.default` role. Reliable matching of a preset to `nowPlaying` is not possible (design-spec UQ-1). |
| Mute button on the transport row | None in v1.4 — mute remains voice-only (design-spec UQ-2). |
| Group touch scope — transport | Transport (play/pause) targets the lead speaker only; followers mirror state automatically (design-spec UQ-3). |
| Group touch scope — volume | Volume broadcasts to all `group.members` concurrently (design-spec UQ-3). |
| Stop control | Removed — pause is functionally equivalent on Mozart (design-spec §1.2). |
| Volume +/− buttons | Removed — volume is set via slider only (design-spec §1.2). |
| Confirmation countdown for touch | None — touch is unambiguous (design-spec §5.1). |
| API call timing on slider drag | On drag end (`onEditingChanged: false`), not per drag point (design-spec §1.3, §5.4). |
| Slider step | `step: 5`, range `0...100` (design-spec §1.3). |
| Slider thumb | Invisible — gold fill is the affordance (design-spec §1.3). |
| Favorites empty state | Row absent (no placeholder) (design-spec §4.2). |
| Favorites visibility in stopped state | Shown below the Play pill (design-spec §4.3). |
| Favorites loading | Async on card appear via `.task` (design-spec §4 implicit; this spec confirms). |
