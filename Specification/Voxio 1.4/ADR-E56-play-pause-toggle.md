# ADR-E56 — Play/Pause Toggle Button (E-56): SpeakerCard Transport Row, Stopped-State Variant, Group-Aware Dispatch, Error-Toast Helper

**Status:** Accepted
**Date:** 2026-05-12
**Deciders:** Engineering Lead
**Refs:** ADR-002-voxio-1.4-ios.md (D4, D6, token-lock, @MainActor invariant), ADR-E52-session-card-strip.md (SpeakerCard call site), ADR-E53-group-chip-row.md (groupMembers parameter, .accessibilityElement loosening), ADR-E54-bottom-bar-redesign.md (PlaybackBars extraction), ADR-E55-discovery-offline-states.md (idle-card slot), spec-touch-playback-controls.md v1.0 (US-70, US-73, Technical Requirements, Error States), design-spec-touch-playback-controls.md v1.2 (§1.2, §2.1, §3.1, §5, Appendix B), epics-and-tasks-touch-playback-controls.md v1.0 (E-56 T-5601–T-5609), CLAUDE.md

---

## 1. Decision

`SpeakerCard.cardContent` is refactored to switch on `speaker.playbackState` (a four-case `SpeakerPlaybackState` enum: `.playing`, `.paused`, `.buffering`, `.stopped`) rather than the current `speaker.isPlaying` boolean. This is a pure scaffolding refactor (T-5601) that creates the correct branch structure for all three F1 epics and for F3's stopped-state idle card slot. A private `transportRow` computed view is added below the existing volume track in the playing/paused/buffering branch, rendering a single centred `DarkGlassIconButton` at 52 pt visual / 64 pt hit area — achieved by adding a `size` parameter to the existing `DarkGlassIconButton` component while keeping the 36 pt default for all current call sites. The stopped-state branch renders a header plus a full-width `DarkGlassButton` Play pill; no now-playing panel and no volume track. Transport actions (play and pause) are dispatched to the lead speaker only through a group-aware model: `SpeakerCard` gains an optional `SpeakerGroup` initialiser parameter — if only a `Speaker` is passed, it is internally wrapped via `SpeakerGroup.single(speaker)` — and all tap handlers call `group.hostSpeaker.play()` / `group.hostSpeaker.pause()`. Error feedback routes through a private `showErrorToast(_ message: String)` helper on `SpeakerCard` backed by an `@Binding var errorMessage: String?` from `HomeView` (or the idle-card branch of `cardArea`) — the same binding that E-57 and E-58 will reuse.

---

## 2. Context

### Prior decisions and constraints

**ADR-002 D4 — volume broadcast on `SpeakerGroup`.** ADR-002 established `SpeakerGroup.setVolumeOnAllMembers(_:)` as the fan-out helper for group volume (E-57 T-5704). E-56 does NOT yet need this helper — transport (play/pause) is targeted at the lead speaker only per design-spec UQ-3 resolved. However, the `SpeakerGroup` parameter introduced in T-5605 is the same structural addition that E-57 will rely on for volume broadcast, making T-5605 the ordering dependency that prevents E-57 from starting without E-56.

**ADR-002 D6 — favorites lazy load cached on Speaker.** Favorites load (E-58 T-5801) calls `speaker.getFavorites()`, which is already implemented as `client.getSources()` in `MozartClient+SpeakerClient.swift`. E-56 does not interact with the favorites surface; the stopped-state branch created in T-5606 reserves the slot below the Play pill where E-58 will mount the favorites row.

**ADR-002 token-lock.** No new `BeoColor`, `Spacing`, `Radius`, `BeoAnimation`, or `BeoType` tokens are introduced. All values used in E-56 (`Spacing.s16`, `Spacing.s20`, `Spacing.s24`, `BeoColor.accent`, `BeoAnimation.spring`) are pre-existing in `DesignTokens.swift`.

**ADR-002 @MainActor invariant.** `Speaker` and `SpeakerGroup` are `@Observable @MainActor`. `HapticEngine` is also `@MainActor`. The `commandRecognised()` haptic is fired synchronously in tap handlers (on the main actor); the async `play()` / `pause()` dispatch is wrapped in `Task { @MainActor in ... }`. No cross-actor boundary issues arise.

**ADR-E53 groupMembers parameter.** E-53 added `var groupMembers: [Speaker] = []` to `SpeakerCard` and confirmed that `SessionStripView` is the sole caller that passes a non-empty array. E-56 T-5605 adds an optional `SpeakerGroup` parameter alongside `groupMembers`. These two parameters serve different purposes: `groupMembers` feeds the chip row (display-only, owned by E-53/F3); `group` feeds the transport and volume dispatch (owned by F1). Both default to a safe single-speaker interpretation when omitted, so all existing call sites remain valid.

**ADR-E53 .accessibilityElement loosening.** E-53 §8 CF-2 noted that `SpeakerCard` currently uses `.accessibilityElement(children: .ignore)` and that this must be loosened for interactive controls to be reachable by VoiceOver. E-56 T-5607 performs this loosening to `.accessibilityElement(children: .contain)` and relocates the card-level summary to the header section.

**ADR-E55 idle-card slot.** E-55's home-screen state machine (T-5505) reserves the `else if let speaker = displayedSpeaker` branch of the `.hasContent` case for a single idle (stopped) `SpeakerCard`. The F1 stopped-state card variant (header + Play pill + favorites row) renders in this slot when the displayed speaker's `playbackState == .stopped`. E-56 T-5606 implements this stopped-state branch inside `SpeakerCard.cardContent`.

**ADR-E54 PlaybackBars extraction.** E-54 T-5401 extracted `PlaybackBars` to `iOS/Voxio/Features/Home/Components/PlaybackBars.swift`. E-56 T-5604 updates `PlaybackBars` to accept a `playbackState` parameter so the bars freeze at their `lo` height when paused.

**Existing toast mechanism.** `HomeView` holds `@State private var currentToast: Toast?` and renders `ToastView`. There is no existing `@Binding var errorMessage` passed to `SpeakerCard`. The chosen mechanism is `@Binding var errorMessage: String?` passed from `SpeakerCard` call sites in `HomeView.cardArea`.

**`DarkGlassIconButton` current size.** The existing component sizes its icon at `DarkGlassButtonTokens.iconOnlySize` (36 pt) and hit area at `minWidth: 44, minHeight: 44`. E-56 requires 52 pt visual / 64 pt hit area — adding `var size: CGFloat = DarkGlassButtonTokens.iconOnlySize` accommodates this without breaking existing call sites.

**`SpeakerPlaybackState` already exists.** `SpeakerClient.swift` defines the four-case enum. `Speaker.playbackState` is already implemented.

**`SpeakerGroup.single(_:)` already exists** in `Group.swift`.

---

## 3. Options Considered

### Option A — Inline named computed properties in `SpeakerCard.swift` (chosen)

Split `SpeakerCard.cardContent` into named private computed properties (`transportRow`, `stoppedStateBody`) within the same file. All state, tap handlers, and helpers live in the same file.

Advantages: single file ownership; consistent with existing pattern; Swift `private` works within file extensions. Disadvantages: file growth (~450 lines after all three F1 epics) — acceptable.

### Option B — Extract sub-views into separate files

Extract `TransportRowView`, `StoppedStateCardView` as separate structs. Rejected because both are too tightly coupled to `SpeakerCard`'s state and the `showErrorToast` closure dependency. `InteractiveVolumeBar` (E-57 T-5701) IS a legitimate extraction to `DesignSystem/` because it is a reusable design-system component.

### Option C — EnvironmentObject for error surface

Rejected — adds a hidden contract for a single use case. `@Binding` is explicit at every call site.

---

## 4. Rationale

Option A wins because `SpeakerCard`'s transport, volume, and favorites controls share `@State` properties tightly coupled to the card. The `@Binding var errorMessage: String?` approach keeps toast rendering in `HomeView` while making the dependency visible at every call site. The group-aware dispatch (wrapping a solo `Speaker` in `SpeakerGroup.single()` internally) follows the ADR-002 D4 pattern and opens a clean path for F2 multiroom grouping.

---

## 5. Consequences

- **E-57 unblocked by T-5601 + T-5605 + T-5606.** Slider integration (T-5702) requires T-5601 + T-5701; `broadcastVolume` wiring (T-5705) requires T-5606's `showErrorToast`.
- **E-58 unblocked by T-5601 + T-5606.** Favorites loading state requires the card branch structure; favorites row view requires the stopped-state layout.
- **F2 can consume `SpeakerGroup` parameter on `SpeakerCard`** without modification — transport dispatch already routes to `group.hostSpeaker`.
- **`DarkGlassIconButton` size parameter affects no existing call sites** — all four current call sites use the 36 pt default.
- **`.accessibilityElement(children: .contain)` on `SpeakerCard`** — interactive controls become individually reachable by VoiceOver. Card-level summary moves to `headerSection`.
- **`PlaybackBars` state threading** — additive `playbackState` parameter; default `.playing` preserves existing call sites.
- **`showErrorToast(@Binding)` is a shared contract across E-56, E-57, E-58.**

---

## 6. File-Level Plan

### Modified files

| Path | Change | Tasks |
|---|---|---|
| `iOS/Voxio/Features/Home/SpeakerCard.swift` | Refactor `cardContent` to `switch speaker.playbackState`; add `group:` and `@Binding errorMessage:` init params; add `transportRow` view, stopped-state branch, `onPlayTapped()`, `onPauseTapped()`, `showErrorToast(_:)`; loosen accessibilityElement to `.contain`. | T-5601, T-5602, T-5603, T-5604, T-5605, T-5606, T-5607 |
| `iOS/Voxio/DesignSystem/DarkGlassButton.swift` | Add `var size: CGFloat = DarkGlassButtonTokens.iconOnlySize` to `DarkGlassIconButton`; scale image frame and hit area. | T-5602 |
| `iOS/Voxio/Features/Home/Components/PlaybackBars.swift` | Add `var playbackState: SpeakerPlaybackState = .playing`; freeze animation when state != .playing/.buffering. | T-5604 |
| `iOS/Voxio/Features/Home/HomeView.swift` | Add `@State private var cardErrorMessage: String?`; pass binding to `SpeakerCard` call sites; `.onChange(of: cardErrorMessage)` creates Toast. | T-5606 |
| `iOS/Voxio/Features/Home/SessionStripView.swift` | Add `@Binding var errorMessage: String?` pass-through to each `SpeakerCard`. | T-5606 |
| `iOS/Voxio/Core/Strings/UIStrings.swift` | Add `play` ("Play"/"Afspil") and `pause` ("Pause"/"Pause") accessibility labels. | T-5607 |

### New files

None for E-56. (`InteractiveVolumeBar.swift` is E-57 T-5701.)

---

## 7. Public Interface Contract

```swift
// MARK: - SpeakerCard (updated initialiser — E-56 T-5605 / T-5606)
// File: iOS/Voxio/Features/Home/SpeakerCard.swift

struct SpeakerCard: View {
    var speaker: Speaker
    var isExpanded: Bool
    var roll: Double
    var pitch: Double
    var groupMembers: [Speaker] = []            // E-53 — chip row display; unchanged
    var group: SpeakerGroup? = nil              // NEW E-56 — transport + volume dispatch
    @Binding var errorMessage: String?          // NEW E-56 — routes errors to HomeView toast

    // Behavioural contracts:
    //
    // 1. cardContent switches on speaker.playbackState, not speaker.isPlaying.
    //    .playing/.paused/.buffering → playing branch (header + nowPlayingPanel + volumeTrack + transportRow).
    //    .stopped → stopped branch (header + Play pill).
    // 2. nowPlayingPanel renders in playing/paused/buffering (paused-state title still readable).
    // 3. Stopped branch omits nowPlayingPanel, volumeTrack, transportRow.
    // 4. GroupChipRow renders only in playing/paused/buffering when groupMembers is non-empty.
}
```

```swift
// MARK: - Transport button (E-56 T-5602)
// Private computed view on SpeakerCard. Rendered in playing/paused/buffering branch below volumeTrack.

// Layout:
//   HStack { Spacer(); DarkGlassIconButton(...); Spacer() }
//       .padding(.horizontal, Spacing.s24).padding(.top, Spacing.s16).padding(.bottom, Spacing.s20)
//
// Switch on speaker.playbackState:
//   .playing, .buffering →
//       DarkGlassIconButton(systemImage: "pause.fill", role: .default, size: 52,
//                           accessibilityLabel: UIStrings.forLanguage(...).pause, action: onPauseTapped)
//   .paused →
//       DarkGlassIconButton(systemImage: "play.fill", role: .confirm, size: 52,
//                           accessibilityLabel: UIStrings.forLanguage(...).play, action: onPlayTapped)
//
// .accessibilityElement(children: .contain) on the transport row container.
```

```swift
// MARK: - DarkGlassIconButton (updated — E-56 T-5602)
// File: iOS/Voxio/DesignSystem/DarkGlassButton.swift

struct DarkGlassIconButton: View {
    let systemImage: String
    var role: Role = .default
    let accessibilityLabel: String
    var size: CGFloat = DarkGlassButtonTokens.iconOnlySize   // NEW — default 36 pt; pass 52 for transport
    let action: () -> Void

    // Behavioural contracts:
    // 1. Image frame: .frame(width: size, height: size)
    // 2. Hit area: .frame(minWidth: max(44, size + 12), minHeight: max(44, size + 12))
    //    — >= 44 pt at the 36 pt default; 64 pt at the 52 pt transport size.
    // 3. All existing call sites omit size → 36 pt default. No visual regression.
}
```

```swift
// MARK: - Transport tap handlers (E-56 T-5603 + T-5605)
// Private methods on SpeakerCard.

// onPlayTapped()
//   1. HapticEngine.shared.commandRecognised()  — synchronous, on main actor
//   2. Task { @MainActor in
//          do { try await resolvedGroup.hostSpeaker.play() }
//          catch { showErrorToast(errorMessage(for: error)); HapticEngine.shared.errorOccurred() }
//      }
//
// onPauseTapped() — identical, calling resolvedGroup.hostSpeaker.pause().
//
// Constraints:
// - No optimistic state update — speaker.playbackState drives the icon via @Observable re-render.
// - Button does not disable between tap and state update — final state wins on rapid taps.
// - HapticEngine fires on every tap.
```

```swift
// MARK: - Stopped-state Play pill (E-56 T-5606)
// Used in .stopped branch of SpeakerCard.cardContent.

// DarkGlassButton(
//     label: UIStrings.forLanguage(...).play,
//     systemImage: "play.fill",
//     role: .confirm,
//     action: onPlayTapped
// )
// .frame(maxWidth: .infinity)
// .padding(.horizontal, Spacing.s24).padding(.top, Spacing.s20).padding(.bottom, Spacing.s20)
//
// Uses the same onPlayTapped() as the transport row — no separate handler.
```

```swift
// MARK: - showErrorToast (E-56 T-5606)
// Private method on SpeakerCard. Reused by E-57 and E-58 unchanged.

private func showErrorToast(_ message: String) {
    errorMessage = message
}

// HomeView's onChange(of: cardErrorMessage) creates Toast(kind: .error(message:list:)) → showToast(_:).
// After showToast, HomeView resets cardErrorMessage = nil so subsequent errors fire.
// Toast rendering stays in HomeView; SpeakerCard knows nothing of Toast types.
```

```swift
// MARK: - Group-aware dispatch (E-56 T-5605)

// Within SpeakerCard:
//   private var resolvedGroup: SpeakerGroup { group ?? SpeakerGroup.single(speaker) }
//
// Transport: resolvedGroup.hostSpeaker.play() / .pause()
// Volume (E-57): resolvedGroup.setVolumeOnAllMembers(_:)
//
// 1. With group == nil, resolvedGroup.hostSpeaker === speaker. Solo card behaves like calling speaker.play().
// 2. With multi-member group, transport hits hostSpeaker only — followers mirror via B&O Mozart protocol.
// 3. SessionStripView passes no `group` in E-56 (defaults to nil). E-57 or F2 may set it.
```

```swift
// MARK: - PlaybackBars (updated — E-56 T-5604)
// File: iOS/Voxio/Features/Home/Components/PlaybackBars.swift

struct PlaybackBars: View {
    var height: CGFloat = 20
    var playbackState: SpeakerPlaybackState = .playing   // NEW E-56

    // 1. playbackState == .playing or .buffering → bars animate (existing behaviour).
    // 2. playbackState == .paused / .stopped / other → bars static at lo height.
    // 3. Default .playing preserves existing call sites.
}
```

```swift
// MARK: - SessionStripView (updated — E-56 T-5606)
// File: iOS/Voxio/Features/Home/SessionStripView.swift

struct SessionStripView: View {
    let groups: [SpeakerGroup]
    @Binding var selectedSpeaker: Speaker?
    let roll: Double
    let pitch: Double
    let isCommandActive: Bool
    @Binding var errorMessage: String?          // NEW — pass-through to SpeakerCard

    // Same binding shared across all cards in the strip. Concurrent errors: last write wins.
}
```

Key behavioural contracts the Test Writer should assert:

1. `speaker.playbackState == .playing` → transportRow with `pause.fill` + `.default` role.
2. `speaker.playbackState == .paused` → transportRow with `play.fill` + `.confirm` (gold) role.
3. `speaker.playbackState == .buffering` → transportRow with `pause.fill` + `.default` (same as playing).
4. `speaker.playbackState == .stopped` → Play pill rendered; transportRow + nowPlayingPanel + volumeTrack absent.
5. Tapping pause fires `HapticEngine.shared.commandRecognised()` synchronously before the async dispatch.
6. Failed `play()`/`pause()` sets `errorMessage` binding to non-nil; does NOT optimistically change state.
7. `group == nil` → `resolvedGroup.hostSpeaker === speaker`.
8. Multi-member group → transport hits host only.
9. `DarkGlassIconButton(size: 52)` → 52 pt image, 64 pt hit area.
10. `DarkGlassIconButton(size: 36)` (default) → identical to pre-E-56.
11. `PlaybackBars(playbackState: .paused)` → static bars.
12. `.accessibilityElement(children: .contain)` after T-5607 — header summary + reachable transport.
13. `SpeakerCard` calls without `errorMessage:` produce compile errors — expected migration signal.

---

## 8. Conflicts Flagged

### CF-1: `@Binding var errorMessage` breaks all `SpeakerCard` call sites (no default possible)

`@Binding` in SwiftUI structs cannot have default values. Adding `@Binding var errorMessage: String?` is a breaking change at every call site. Current call sites:
- `HomeView.cardArea` idle branch — must add `errorMessage: $cardErrorMessage`.
- `SessionStripView` `ForEach` — must thread through (after `SessionStripView` itself gains the binding).
- SwiftUI `#Preview` blocks — must add `.constant(nil)`.

Compile-time failure that T-5605/T-5606 PR must resolve. Not a correctness risk.

**Mitigation option:** Use `var onError: (String) -> Void = { _ in }` closure instead — has a default value, no call-site break. The trade-off is `HomeView` creates the closure inline. Either approach works; the `@Binding` approach is chosen for SwiftUI symmetry, but the Implementer may switch to the closure approach.

### CF-2: design-spec §4.2 contradicts spec on active-favorite role (E-58 issue, not E-56)

`design-spec-touch-playback-controls.md §4.2` says active favorite is `.confirm` (gold). `spec-touch-playback-controls.md` resolves UQ-1 to always `.default`. Functional spec wins. E-56 is not affected; flagged for E-58 awareness.

### CF-3: `SessionStripView` modification conflicts with F2 E-59

F2 / E-59 T-5905 modifies `SessionStripView.body`'s `ForEach`. E-56 T-5606 also modifies it. Recommended sequencing: E-56 T-5606 lands before F2 starts E-59.

### CF-4: `PlaybackBars` parameter addition merge risk with F3 E-55 — **NOT AN ISSUE**

E-55 is fully merged. No active F3 branch touches `PlaybackBars.swift`. Confirmed zero risk.

### CF-5: F2 can reuse `group` parameter on `SpeakerCard` for free

Once E-56 T-5605 adds `var group: SpeakerGroup? = nil`, F2 can pass real multi-member groups without further `SpeakerCard` modification. Bonus, not a conflict.

---

## 9. Task Gate

| Task | Status | Reason |
|---|---|---|
| T-5601 — Refactor `cardContent` to `switch playbackState` | UNBLOCKED | No dependencies; `SpeakerPlaybackState` exists |
| T-5602 — `transportRow` view + `DarkGlassIconButton.size` param | UNBLOCKED (after T-5601) | Requires T-5601 branch structure |
| T-5603 — `onPlayTapped()` / `onPauseTapped()` handlers | UNBLOCKED (after T-5602) | Requires button call sites; `showErrorToast` can be stubbed pending T-5606 |
| T-5604 — `PlaybackBars` `playbackState` param | UNBLOCKED (after T-5601) | Parallel with T-5602 |
| T-5605 — Optional `SpeakerGroup` on `SpeakerCard`; route dispatch | UNBLOCKED (after T-5603) | Requires handler bodies; `SpeakerGroup.single()` exists |
| T-5606 — Stopped-state Play pill; `showErrorToast`; `HomeView` + `SessionStripView` binding | UNBLOCKED (after T-5601) | Layout from T-5601; finalise tap wiring after T-5605 |
| T-5607 — `.accessibilityElement(children: .contain)`; relocate summary | UNBLOCKED (after T-5602 + T-5606) | Requires interactive controls to verify VO order |
| T-5608 — Manual test on Mozart speaker | DEFERRED (manual on device) | All prior tasks must be merged on device |
| T-5609 — SwiftUI previews for all four states | UNBLOCKED (after T-5602 + T-5606) | Requires layouts to exist |

---

**Verdict: PROCEED**
