# ADR E-38 — First-boot Onboarding Screen

**Status:** Accepted
**Date:** 2026-05-05
**Epic:** E-38 (Voxio 1.3, Feature 3)
**User stories:** US-60, US-66

---

## Decision

Introduce `OnboardingView` as a new full-screen SwiftUI view presented via `.fullScreenCover` attached to `HomeView`. Persistence is controlled by a new `@AppStorage("hasCompletedOnboarding")` key. A one-time migration writes `hasCompletedOnboarding = true` when `hasSeenHint == true` so returning users skip onboarding automatically. Microphone and speech-recognition permission requests move from `VoiceToText.start()` to the onboarding dismiss handler. `OnboardingView` is also presentable as a re-showable `.sheet` from Settings (E-39 T-3906) via a `Bool` binding that controls the sheet without touching `hasCompletedOnboarding`.

---

## Context

- The app currently shows `HintCardView` inline on first launch, gated by `@AppStorage("hasSeenHint")` in `HomeView`.
- Microphone and speech-recognition permissions are currently requested inside `VoiceToText.start()`.
- `HomeView.onAppear` already guards on `!langService.hasExplicitlyChosen` before calling `startListening()`, establishing the pattern for gate-checks before the audio pipeline.
- Per T-2209: every `.fullScreenCover` content view must include `.preferredColorScheme(.dark)`.
- On first launch no speaker has been discovered; the orb cannot be reused as-is. Design spec §1.4 provides a static radial-gradient `Circle()` fallback.

---

## Options Considered

**Option A — Attach `.fullScreenCover` in `VoxioApp`**
- Con: `VoxioApp` is a `Scene` body; `.fullScreenCover` requires a `View`. Increases coupling for a screen that must interact with `HomeView` state. Rejected.

**Option B — Attach `.fullScreenCover` in `HomeView` (chosen)**
- Pro: collocated with `hasSeenHint` (migration source), existing `showLanguagePicker` gating pattern, and the permission-request call site. The dismiss handler can call `startListening()` directly.
- Con: `HomeView` gains another `@AppStorage` property — consistent with existing pattern.

**Option C — Migration via dedicated `ViewModifier`**
- Unnecessary abstraction for a two-line `onAppear` check. Rejected.

---

## Rationale

Option B keeps all first-launch sequencing in one place. `HomeView.onAppear` already owns "should we show the language picker before starting audio?"; adding "should we show onboarding?" is identical in structure. Collocating migration, cover presentation, and the `startListening()` call avoids distributed state for a single flow.

---

## Consequences

- `HomeView` gains `@AppStorage("hasCompletedOnboarding")` and `@State private var showOnboardingSheet = false`.
- `HintCardView` is removed from the `voiceFeedback` VStack; `hasSeenHint` key retained read-only for migration.
- `VoiceToText.start()` no longer calls `SFSpeechRecognizer.requestAuthorization` or `AVAudioApplication.requestRecordPermission`.
- `HomeView.onAppear` gate-chain order: (1) if `!hasCompletedOnboarding` → show fullScreenCover; (2) else if language not chosen → show picker; (3) else → `startListening()`.
- All new `.swift` files auto-compile via `PBXFileSystemSynchronizedRootGroup`.

---

## File-Level Plan

### New files

| Path | Purpose |
|---|---|
| `iOS/Voxio/Features/Onboarding/OnboardingView.swift` | Full-screen cover + sheet-mode content; owns `onDismiss: () -> Void` and `isReshow: Bool` |

### Modified files

| Path | Change |
|---|---|
| `iOS/Voxio/Features/Home/HomeView.swift` | Add `@AppStorage("hasCompletedOnboarding")`, `@State showOnboardingSheet`, migration in `onAppear`, `.fullScreenCover`, remove `shouldShowHint`/`showHintManually`/`HintCardView` |
| `iOS/Voxio/Core/Voice/VoiceToText.swift` | Remove `SFSpeechRecognizer.requestAuthorization` + `AVAudioApplication.requestRecordPermission` from `start()` |
| `iOS/Voxio/Features/Home/HintCardView.swift` | Delete file (or tombstone until E-38 migration confirmed) |

---

## Public Interface Contract

```swift
struct OnboardingView: View {
    /// Called when the user taps "Get started" on the first-launch cover.
    /// Performs: set hasCompletedOnboarding = true, request permissions, dismiss.
    var onDismiss: () -> Void

    /// true  → presented as .sheet from Settings; no permission requests; does not write hasCompletedOnboarding.
    /// false → presented as .fullScreenCover; runs the full dismiss flow.
    var isReshow: Bool = false
}
```

`OnboardingView.body` must include `.preferredColorScheme(.dark)` on its root.

### Migration logic (in `HomeView.onAppear`)

```swift
if hasSeenHint && !hasCompletedOnboarding {
    hasCompletedOnboarding = true
}
```

### Re-show from Settings (E-39 T-3906)

`SettingsView` receives `showOnboardingSheet: Binding<Bool>`. Tapping "Show introduction again" sets it to `true`. `HomeView` holds `.sheet(isPresented: $showOnboardingSheet)` presenting `OnboardingView(isReshow: true, onDismiss: { showOnboardingSheet = false })`. This sheet does not modify `hasCompletedOnboarding`.

---

## Conflicts Flagged

1. **Permission sequencing:** Call `SFSpeechRecognizer.requestAuthorization` first; in its completion handler call `AVAudioApplication.requestRecordPermission`. Use `Task { @MainActor in ... }` to hold the cover open while permissions resolve — do not dismiss synchronously.

2. **`onAppear` re-fire after cover dismissal:** SwiftUI re-runs `onAppear` on the underlying view after the cover dismisses. If this is unreliable on iOS 26, add an `onChange(of: hasCompletedOnboarding)` trigger for `startListening()`.

3. **`hasSeenHint` key permanence:** Retain `@AppStorage("hasSeenHint")` in `HomeView` through the E-38 sprint. Remove only after T-3804 is confirmed shipped and the migration has run for at least one release.
