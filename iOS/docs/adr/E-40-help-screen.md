# ADR E-40 — Redesigned Help Screen

**Status:** Accepted
**Date:** 2026-05-05
**Epic:** E-40 (Voxio 1.3, Feature 3)
**User story:** US-65

---

## Decision

`HelpView` is implemented as a new standalone SwiftUI file at `iOS/Voxio/Features/Help/HelpView.swift`, presented as a `.sheet` from two call sites: the existing `questionmark.circle` toolbar button in `HomeView` (rewired from `HintCardView`) and the "Help" row in `SettingsView` (E-39 T-3906). Speaker-name placeholders are resolved at sheet-open time from `SpeakerDiscoveryService` and passed in as value-type arguments, keeping `HelpView` side-effect-free and trivially previewable. `HintCardView` is removed from the `voiceFeedback` VStack but the file is **retained on disk** because `hasSeenHint` migration in E-38 T-3804 still references that `@AppStorage` key.

---

## Context

- `HintCardView` is a small inline card showing three examples; it auto-shows on first launch and can be recalled via the `questionmark.circle` toolbar button.
- In v1.3 the first-launch role transfers to `OnboardingView` (E-38); the toolbar button becomes a full reference sheet (21 examples across three categories, EN + DA).
- The `Language` enum and `LanguageService.shared.activeLanguage` provide the active language source of truth.
- Existing strings use static structs (`UIStrings`, `CommandStrings`) keyed on `Language` case. `HelpView` follows this pattern to avoid introducing a `.xcstrings` migration dependency out of scope for E-40.

---

## Options Considered

**Option A — Static example list, custom card layout (chosen)**

Hardcoded `[HelpSection]` / `[HelpRow]` populated at compile time. Speaker-name substitution is the only runtime computation. Layout uses `BeoColor.cardBg`-filled rounded cards inside a `ScrollView` per design spec §3.6.

- Pro: zero live-service dependencies; previewable without a running speaker; robust if discovery is slow.
- Con: new command added to the pipeline must also be added here manually.

**Option B — Dynamic list derived from `VoiceCommand` enum cases**

- Con: `VoiceCommand` carries no example strings; adding them would couple the command model to UI concerns. Rejected.

**Option C — Reuse `HintCardView` with expanded data**

- Con: `HintCardView` is designed as an inline card, not a full-height sheet. Rejected.

---

## Rationale

Option A fits the existing architecture pattern and satisfies every acceptance criterion in US-65. The static list is acceptable because the command vocabulary is stable within a release cycle; additions go through the spec and will be caught in review.

Passing speaker names as `init` arguments (rather than observing `SpeakerDiscoveryService` inside `HelpView`) aligns with design spec §3.7.1: "computed at sheet-open time and remains stable for the duration the sheet is open."

---

## Consequences

- `HelpView` has no live state dependencies and is fully previewable with `#Preview`.
- When a new command category is added, developers must update both the parser and the `HelpView` static data. A `// MARK: — keep in sync with VoiceCommand` comment documents this obligation.
- `HintCardView.swift` stays on disk but becomes dead UI code once E-38 lands. Add `// TODO: E-38 — delete after hasSeenHint migration confirmed` to the top of the file.
- `HomeView` loses `showHintManually`, `shouldShowHint`, and the `HintCardView(...)` render site; `hasSeenHint` `@AppStorage` key is kept until E-38 ships.

---

## File-Level Plan

### New files

| Path | Purpose |
|---|---|
| `iOS/Voxio/Features/Help/HelpView.swift` | Sheet: header, language indicator, ScrollView with three section cards |
| `iOS/Voxio/Features/Help/HelpSection.swift` | Value types `HelpSection`, `HelpRow`; factory `HelpSection.all(speakerA:speakerB:)` |

### Modified files

| Path | Change |
|---|---|
| `iOS/Voxio/Features/Home/HomeView.swift` | T-4006: add `@State private var showHelp = false`; `.sheet(isPresented: $showHelp)`; rewire `questionmark.circle` to `showHelp = true`; remove `shouldShowHint`, `showHintManually`, `HintCardView`; retain `@AppStorage("hasSeenHint")` until E-38 ships |
| `iOS/Voxio/Features/Home/HintCardView.swift` | Add `// TODO: E-38 — delete after hasSeenHint migration confirmed` comment |

---

## Public Interface Contract

### `HelpView`

```swift
struct HelpView: View {
    let speakerA: String?       // nil → falls back to "[Speaker]"
    let speakerB: String?       // nil → falls back to "[Speaker B]"
    let activeLanguage: Language
    @Binding var isPresented: Bool
}
```

Call site in `HomeView`:

```swift
.sheet(isPresented: $showHelp) {
    let members = discovery.groups.flatMap(\.members)
    HelpView(
        speakerA: members.first?.name,
        speakerB: members.dropFirst().first?.name,
        activeLanguage: langService.activeLanguage,
        isPresented: $showHelp
    )
}
```

### `HelpSection` / `HelpRow`

```swift
struct HelpRow {
    let actionEN: String
    let actionDA: String
    let phraseEN: String
    let phraseDA: String
}

struct HelpSection {
    let titleEN: String
    let titleDA: String
    let rows: [HelpRow]

    static func all(speakerA: String?, speakerB: String?) -> [HelpSection]
}
```

`HelpSection.all(speakerA:speakerB:)` returns all three sections with placeholders already substituted, making `HelpView` a pure renderer.

### E-39 `SettingsView` integration

`SettingsView` holds `@State private var showHelp = false` and presents `HelpView` with the same arguments. The Implementer of E-39 is responsible for this wiring.

---

## Conflicts Flagged

1. **T-4006 vs. E-38 T-3804 (`hasSeenHint` key):** Retain `@AppStorage("hasSeenHint")` in `HomeView` through the E-38 sprint; remove only after T-3804 migration is confirmed shipped.

2. **`shouldShowHint` animation removal:** The `.animation(.easeInOut, value: shouldShowHint)` on the `voiceFeedback` VStack must be dropped along with `shouldShowHint`. No replacement animation is needed.

3. **Design spec Open Question 3 (language toggle scope):** The Help sheet language toggle is per-session display only (does not change recognition language). Add caption: "Display only. Change app language in Settings." Flag as trivially removable if product owner prefers toggle = change language.

4. **Design spec Open Question 4 (Dynamic Type at `accessibility4`+):** The action-label column wraps at large sizes. Use `.dynamicTypeSize` environment value to switch to a stacked layout at `accessibility4`+.
