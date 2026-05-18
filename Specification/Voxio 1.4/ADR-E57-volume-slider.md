# ADR-E57 — Interactive Volume Slider (E-57): InteractiveVolumeBar Component, Drag Gesture Model, Group Volume Broadcast, Limit Haptic

**Status:** Accepted
**Date:** 2026-05-12
**Deciders:** Engineering Lead
**Refs:** ADR-002-voxio-1.4-ios.md (D4, token-lock, @MainActor invariant), ADR-E56-play-pause-toggle.md (SpeakerCard shape, resolvedGroup, showErrorToast), spec-touch-playback-controls.md v1.0 (US-71, US-73, Technical Requirements §Volume slider wiring contract, Error States), design-spec-touch-playback-controls.md v1.2 (§1.3, §5.2, §5.4, §7), epics-and-tasks-touch-playback-controls.md v1.0 (E-57 T-5701–T-5709), CLAUDE.md

---

## 1. Decision

The existing static `volumeTrack(level:)` private method in `SpeakerCard.swift` is replaced by a reusable `InteractiveVolumeBar` view extracted to `iOS/Voxio/DesignSystem/InteractiveVolumeBar.swift`. The component is implemented using a `GeometryReader` + two `Capsule` views with a `DragGesture(minimumDistance: 0)` overlay rather than a native SwiftUI `Slider` — preserving the existing visual fidelity of the gold fill track and avoiding the native thumb element entirely. Volume dispatch fires once per drag end (not per drag point), mediated by two `@State` properties on `SpeakerCard` (`dragVolume: Int?` and `lastLimitHaptic: Int?`). Group volume broadcast is housed in a new `SpeakerGroup.setVolumeOnAllMembers(_ level: Int) async -> [(speaker: Speaker, result: Result<Void, Error>)]` method (T-5704) using `withTaskGroup` for concurrent fan-out with per-member partial-failure tolerance, consistent with ADR-002 D4. The `HapticEngine.limitReached()` method already exists and requires no modification.

---

## 2. Context

### Prior decisions and constraints

**ADR-002 D4 — volume broadcast on `SpeakerGroup`.** ADR-002 established `SpeakerGroup.setVolumeOnAllMembers(_:)` as the canonical fan-out helper returning per-speaker `Result` values so the caller can surface "Volume failed on N speakers". E-57 T-5704 implements it.

**ADR-E56 — `resolvedGroup` and `showErrorToast`.** E-56 (shipped, commit `120f08c`) delivered three surfaces E-57 depends on:
- `private var resolvedGroup: SpeakerGroup { group ?? SpeakerGroup.single(speaker) }` — group-aware dispatch mechanism E-57's `broadcastVolume` calls.
- `private func showErrorToast(_ message: String)` — error surface E-57 uses for partial and total broadcast failures.
- `@Binding var errorMessage: String?` — backing the toast helper.
- `cardContent` switches on `speaker.playbackState` — slider renders only in playing/paused/buffering branch.

**ADR-002 token-lock.** No new tokens. All values used (`Spacing.s24`, `Spacing.s12`, gold `#C8A97E`) are pre-existing.

**ADR-002 @MainActor invariant.** `SpeakerGroup` is `@Observable @MainActor`. `withTaskGroup` child tasks called from a `@MainActor` context inherit the actor context; `Speaker.setVolume(_:)` is `@MainActor` — no cross-actor boundary.

**Existing `volumeTrack(level:)`.** `SpeakerCard.swift` lines 223–246 use a `GeometryReader` containing a `ZStack` of two `Capsule` views, gold fill proportional to `level`, height 4 pt, trailing volume number. `InteractiveVolumeBar` must match this appearance exactly.

**`HapticEngine.limitReached()` already exists** at line 13 of `HapticEngine.swift`: `func limitReached() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }`. No new method required.

**`SpeakerGroup.setVolumeOnAllMembers` does not yet exist.** New work in T-5704.

**`Speaker.setVolume(_:)` optimistically updates local state** on success (lines 206–209 of `Speaker.swift`). This is intentional.

**Spec inconsistency — gesture model.** `spec-touch-playback-controls.md` describes a native `Slider(value:in:step:)`. `epics-and-tasks-touch-playback-controls.md` T-5701 specifies a custom `DragGesture(minimumDistance: 0)` because "SwiftUI does not expose a true `SliderStyle` protocol on iOS 26". The epics doc is adopted; the functional spec's `Slider` pseudocode is intent, not literal API.

---

## 3. Options Considered

### Gesture model: Option A — Custom `DragGesture(minimumDistance: 0)` on a styled `GeometryReader` track (chosen)

`GeometryReader` containing a `ZStack` of two `Capsule` views (track + gold fill) with a transparent overlay `Rectangle` carrying `DragGesture(minimumDistance: 0)`. Drag maps `location.x / geometry.size.width` to clamped 0–100 snapped to nearest 5. `onChanged` fires `onEditingChanged(true)` on the first call; `onEnded` fires `onEditingChanged(false)`.

Advantages: zero visible thumb, full visual control, identical to existing track. `DragGesture(minimumDistance: 0)` treats a tap-in-place as a zero-distance drag → tap snaps to value.

### Gesture model: Option B — Native `Slider` with custom `SliderStyle`

`SliderStyle` is not a public protocol on iOS 26. ZStack overlay workarounds are fragile. Native `Slider` also introduces an accessibility-visible thumb that doesn't match design intent. Rejected.

### Group volume dispatch: Option A — `withTaskGroup` returning per-speaker `Result` (chosen)

Concurrent fan-out, one child task per member. Per-member errors wrapped in `Result` so caller can count failures. Matches ADR-002 D4 verbatim.

### Group volume dispatch: Option B — Sequential `await`

Worst case `n × 5 s timeout`. Unacceptable UX. Rejected.

### Group volume dispatch: Option C — Fan-out at call site in `SpeakerCard.broadcastVolume`

Less testable; contradicts ADR-002 D4 preference for housing the helper on `SpeakerGroup`. Rejected.

---

## 4. Rationale

Custom `DragGesture` wins for visual fidelity, stability on iOS 26, and exact `onChanged`/`onEnded` lifecycle. `withTaskGroup` on `SpeakerGroup` encapsulates fan-out in a testable model type, matches ADR-002 D4 precisely, and follows the existing `Speaker.initialize()` precedent. `HapticEngine.limitReached()` already exists — no API growth.

---

## 5. Consequences

- **E-58 (favorites) is independent of E-57** — can land in either order.
- **F2 (multiroom) does not consume `setVolumeOnAllMembers`** — confirmed in master spec. F2 is not blocked.
- **`SpeakerGroup` grows one new async method** — future callers reuse without duplication.
- **T-5709 unit test** would target the `SpeakerGroup` helper. NOTE: this repo has no XCTest target — substitute with test-plan coverage rather than an actual XCTest file.
- **Drag-end dispatch** lags visual slider during drag (design-spec §5.4) — intentional, not regression.
- **Partial-failure toast** "Volume failed on N speakers" is a new string — inline literal acceptable for v1.4.
- **`dragVolume: Int? = nil` and `lastLimitHaptic: Int? = nil`** are view-local `@State`.
- **WS events during drag** are dominated by `dragVolume` — slider doesn't visually jump mid-drag.

---

## 6. File-Level Plan

### New files

| Path | Purpose | Tasks |
|---|---|---|
| `iOS/Voxio/DesignSystem/InteractiveVolumeBar.swift` | Reusable volume bar: `GeometryReader` + two `Capsule` + `DragGesture(minimumDistance: 0)`; `@Binding var value: Int`, `onEditingChanged`, `.accessibilityAdjustableAction` | T-5701, T-5706 |

### Modified files

| Path | Change | Tasks |
|---|---|---|
| `iOS/Voxio/Features/Home/SpeakerCard.swift` | Replace `volumeTrack(level:)` with `InteractiveVolumeBar` binding; add `@State dragVolume`, `@State lastLimitHaptic`; add `handleLimitHaptic(_:)`, `broadcastVolume(_:) async`; padding `Spacing.s12` top/bottom | T-5702, T-5703, T-5705 |
| `iOS/Voxio/Core/Models/Group.swift` | Add `func setVolumeOnAllMembers(_ level: Int) async -> [(speaker: Speaker, result: Result<Void, Error>)]` using `withTaskGroup` | T-5704 |

No changes to `HapticEngine.swift`, `DesignTokens.swift`, `BeoColor.swift`, networking, or backend.

---

## 7. Public Interface Contract

```swift
// MARK: - InteractiveVolumeBar (NEW — E-57 T-5701 + T-5706)
// File: iOS/Voxio/DesignSystem/InteractiveVolumeBar.swift

struct InteractiveVolumeBar: View {
    @Binding var value: Int                       // 0–100, snapped to multiples of 5
    let onEditingChanged: (Bool) -> Void          // true = drag started; false = drag ended

    // Behavioural contracts:
    // 1. Body: GeometryReader → ZStack of two Capsule views (track + gold fill) with
    //    transparent Rectangle overlay carrying DragGesture(minimumDistance: 0).
    // 2. Track: .white.opacity(0.12), height 4 pt.
    // 3. Gold fill: Color(hex: "#C8A97E"), width = geo.size.width * CGFloat(value) / 100, height 4 pt.
    //    .animation(.easeOut(duration: 0.3), value: value) for external value changes only.
    // 4. Trailing volume number: Text("\(value)"), font .system(size: 12, weight: .medium),
    //    foregroundStyle(.secondary), .frame(width: 28, alignment: .trailing). Outside the
    //    GeometryReader, in an HStack to the right of the track.
    // 5. DragGesture.onChanged: map location.x / geo.size.width → clamped 0–100 → snapped to
    //    nearest 5 → write to value binding. Fire onEditingChanged(true) on the FIRST onChanged
    //    call per gesture (tracked via @State private var isEditing: Bool).
    // 6. DragGesture.onEnded: final write; fire onEditingChanged(false). Reset isEditing.
    // 7. Accessibility:
    //    .accessibilityLabel("Volume")
    //    .accessibilityValue("\(value) percent")
    //    .accessibilityAdjustableAction { direction in
    //        switch direction {
    //        case .increment: value = min(100, value + 5); onEditingChanged(true); onEditingChanged(false)
    //        case .decrement: value = max(0,   value - 5); onEditingChanged(true); onEditingChanged(false)
    //        default: break
    //        }
    //    }
    // 8. Limit announcements posted by caller (SpeakerCard.handleLimitHaptic), not by this view.
    // 9. Reduce Motion: gold fill follows touch directly; no spring on drag.
}
```

```swift
// MARK: - SpeakerGroup.setVolumeOnAllMembers (NEW — E-57 T-5704)
// File: iOS/Voxio/Core/Models/Group.swift

extension SpeakerGroup {
    func setVolumeOnAllMembers(_ level: Int) async -> [(speaker: Speaker, result: Result<Void, Error>)] {
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
    }
}
```

```swift
// MARK: - SpeakerCard additions (E-57 T-5702 + T-5703 + T-5705)
// File: iOS/Voxio/Features/Home/SpeakerCard.swift

@State private var dragVolume: Int? = nil
@State private var lastLimitHaptic: Int? = nil

// Replaces volumeTrack(level:):
InteractiveVolumeBar(
    value: Binding<Int>(
        get: { dragVolume ?? speaker.volume ?? 0 },
        set: { newValue in dragVolume = newValue; handleLimitHaptic(newValue) }),
    onEditingChanged: { editing in
        if !editing {
            let final = dragVolume ?? speaker.volume ?? 0
            Task { await broadcastVolume(final) }
            dragVolume = nil
            lastLimitHaptic = nil
        }
    })
.padding(.horizontal, Spacing.s24)
.padding(.vertical, Spacing.s12)

private func handleLimitHaptic(_ value: Int) {
    if value == 0 && lastLimitHaptic != 0 {
        HapticEngine.shared.limitReached()
        AccessibilityNotification.Announcement("Volume at minimum").post()
        lastLimitHaptic = 0
    } else if value == 100 && lastLimitHaptic != 100 {
        HapticEngine.shared.limitReached()
        AccessibilityNotification.Announcement("Volume at maximum").post()
        lastLimitHaptic = 100
    } else if value > 0 && value < 100 {
        lastLimitHaptic = nil
    }
}

private func broadcastVolume(_ level: Int) async {
    let results = await resolvedGroup.setVolumeOnAllMembers(level)
    let failed = results.filter { if case .failure = $0.result { return true } else { return false } }
    guard !failed.isEmpty else { return }
    for (spk, result) in failed {
        if case .failure(let error) = result {
            Log.error("[\(spk.name)] setVolume(\(level)) failed: \(error)")
        }
    }
    let suffix = failed.count == 1 ? "speaker" : "speakers"
    showErrorToast("Volume failed on \(failed.count) \(suffix)")
    HapticEngine.shared.errorOccurred()
}
```

Key behavioural contracts the Test Writer should assert:

1. `InteractiveVolumeBar` with `value = 50` renders gold fill at exactly 50% of track width.
2. Drag from 20 → 60 → binding receives 60, `onEditingChanged(true)` fires on first onChanged.
3. Drag end → `onEditingChanged(false)` fires exactly once; intermediate positions don't fire `false`.
4. Tap at 75% with no drag → value snaps to 75 (minimumDistance: 0 treats taps as zero-distance drags).
5. `handleLimitHaptic(0)` → `HapticEngine.shared.limitReached()` + "Volume at minimum" announcement.
6. `handleLimitHaptic(100)` → `HapticEngine.shared.limitReached()` + "Volume at maximum" announcement.
7. `handleLimitHaptic(0)` twice → fires only on the first call (gated by `lastLimitHaptic`).
8. `handleLimitHaptic(50)` after `handleLimitHaptic(0)` → resets gate; subsequent `(0)` fires again.
9. `setVolumeOnAllMembers(50)` with two members → both `setVolume(50)` called concurrently.
10. One member failure → `[(ok, .success), (err, .failure)]`.
11. `broadcastVolume(50)` with one failure → "Volume failed on 1 speaker"; errorOccurred haptic; Log.error.
12. `broadcastVolume(50)` all success → no toast; no haptic.
13. WS event mid-drag → slider unaffected (`dragVolume != nil` dominates).
14. Drag end on stopped speaker → no crash (slider not rendered in `.stopped`).

---

## 8. Conflicts Flagged

### CF-1: Gesture model inconsistency — RESOLVED HERE

Functional spec describes native `Slider`; epics doc T-5701 specifies custom `DragGesture` citing absent `SliderStyle` on iOS 26. Both agree on the end-user contract. This ADR adopts the custom `DragGesture` model. Functional spec pseudocode is intent, not literal API.

### CF-2: `Speaker.setVolume(_:)` optimistically updates `speaker.volume`

After successful single-speaker volume drag, `speaker.volume` updates immediately before WS event arrives. After drag end, `dragVolume = nil` → slider reads `speaker.volume` (= `final`). Documented asymmetry vs E-56 transport (non-optimistic) — intentional: volume has no observable side-effect that makes optimism harmful.

### CF-3: Localised strings for partial-failure toast

"Volume failed on N speaker(s)" not yet in `UIStrings`. Acceptable as inline literal for v1.4 (rare failure path; EN+DA only).

### CF-4: F2 reusability bonus

F2 (multiroom) does not consume `setVolumeOnAllMembers`, but it's available if ever needed.

### CF-5: `AccessibilityNotification.Announcement` API

iOS 17+ API replacing `UIAccessibility.post`. iOS 26 target — safe.

### CF-6: T-5709 unit test — no XCTest target in this repo

ADR §6 listed `iOS/VoxioTests/SpeakerGroupTests.swift` as a new file. **Override:** this repo has no XCTest target. The Test Writer produces test plan coverage instead. The Implementer SHOULD NOT create an XCTest file.

---

## 9. Platform Constraint Checks

| API | Introduced | Used | Status |
|---|---|---|---|
| `DragGesture(minimumDistance:)` | iOS 13 | `InteractiveVolumeBar` | Safe |
| `withTaskGroup` | iOS 15 | `setVolumeOnAllMembers` | Safe |
| `UINotificationFeedbackGenerator().notificationOccurred(.warning)` | iOS 10 | `HapticEngine.limitReached()` | Safe (existing) |
| `AccessibilityNotification.Announcement(_:).post()` | iOS 17 | `handleLimitHaptic` | Safe |
| `.accessibilityAdjustableAction` | iOS 15 | `InteractiveVolumeBar` | Safe |

No constraint violations.

---

## 10. Task Gate

| Task | Status | Reason |
|---|---|---|
| T-5701 — Create `InteractiveVolumeBar.swift` | UNBLOCKED | E-56 branch structure shipped |
| T-5702 — Replace `volumeTrack(level:)`; add `dragVolume` + `lastLimitHaptic` state | UNBLOCKED (after T-5701) | Requires component |
| T-5703 — `handleLimitHaptic(_:)` | UNBLOCKED (after T-5702) | `limitReached()` already exists |
| T-5704 — `setVolumeOnAllMembers(_:)` on `SpeakerGroup` | UNBLOCKED | Independent; parallel with T-5701 |
| T-5705 — `broadcastVolume(_:)`; wire to `onEditingChanged` | UNBLOCKED (after T-5702 + T-5704) | `showErrorToast` shipped in E-56 |
| T-5706 — A11y `.accessibilityAdjustableAction` + label + value | UNBLOCKED (after T-5702 + T-5703) | VoiceOver adjust shares onEditingChanged path |
| T-5707 — Manual single-speaker test | DEFERRED (device required) | All prior tasks merged |
| T-5708 — Manual multi-speaker test | DEFERRED (two devices required) | After T-5705 |
| T-5709 — `SpeakerGroup` unit test — OVERRIDDEN to test-plan coverage only | DEFERRED | No XCTest target in repo |

---

**Verdict: PROCEED**
