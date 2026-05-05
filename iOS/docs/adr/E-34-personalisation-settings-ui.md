# ADR E-34 — Personalisation Settings UI

**Status:** Accepted
**Date:** 2026-05-05
**Epic:** E-34 (Voxio 1.3, Feature 1)
**User stories:** US-49, US-51, US-52

---

## Decision

The Personalisation Settings UI is implemented as three new SwiftUI views pushed via `NavigationStack` from within the `SettingsView` sheet (E-39). `PersonalisationStore` — already shipped in E-33 — exposes all methods required by the UI without modification. A new `ConfirmedCommandRecord` value type is added to `PersonalisationStore.swift` alongside the existing `AliasRecord`, together with a `confirmedCommands(for:)` fetch method, so the Learned Phrases screen has a stable value-type surface to bind to. The two-step Add/Edit Alias sheet is a self-contained `AliasEditSheet` view with internal `@State` step tracking. All persistence calls go through `PersonalisationStore` on `@MainActor`; no background contexts are introduced for E-34.

---

## Context

- iOS 26, Xcode 16+, `PBXFileSystemSynchronizedRootGroup` — every `.swift` file dropped into `iOS/Voxio/` is compiled automatically; no pbxproj editing is required.
- Swift 6 strict concurrency is active. `PersonalisationStore` is `@MainActor final class`, which eliminates any sendability issue when binding its properties to SwiftUI views that are also `@MainActor`.
- `PersistenceController.shared` is already instantiated on app launch. The `viewContext` is the only context used by `PersonalisationStore`; this is the correct context for `@MainActor` SwiftUI reads.
- `PersonalisationStore` is already constructed in `HomeView.init()` and stored as `@State private var personalisationStore`. E-34 views need a reference to this same instance, not a second one. The store must be passed down — not re-created — to avoid a second Core Data context competing with the first.
- `SettingsView` (E-39) is the entry point. E-34 is blocked on E-39 scaffolding the `NavigationStack` the alias and learned-phrases screens are pushed onto. However, both screens can be built and previewed in isolation before E-39 ships.
- `HomeView` does not yet have a Settings sheet (`showSettings` state binding, gear toolbar button). That is E-39 T-3901/T-3902. E-34 does not wire the entry point — it delivers the screens that E-39 navigates to.
- `SpeakerDiscoveryService` and its `groups` list are needed by the Add/Edit Alias sheet step 2 (speaker selector). The sheet receives the discovered speaker list as a value-type argument resolved at sheet-open time, consistent with the `HelpView` pattern established in E-40.
- `VoxioWidgetExtension` target uses `PBXFileSystemSynchronizedBuildFileExceptionSet` to selectively include a subset of `iOS/Voxio/` files. The widget's exception list does not include any `Features/Settings/` path, so all new files in `Features/Settings/` are automatically excluded from the widget target with no manual project change needed.
- Design tokens (`Spacing`, `Radius`, `BeoAnimation`, `BeoType`) and `BeoColor` all exist and cover every measurement cited in `design-spec-alias-management.md`. No new tokens are required.
- `DarkGlassButtonTokens` already defines `pressedScale` (0.95) and `pressSpringResponse` (0.3), which the primary CTA gold-fill button variant reuses.

---

## Options Considered

### Option A — NavigationStack inside SettingsView sheet (chosen)

`SettingsView` contains a `NavigationStack`. The "Aliases" and "Learned phrases" rows use `NavigationLink` to push `AliasListView` and `LearnedPhrasesView` onto the same stack. The Add/Edit sheet is a separate `.sheet` modifier on `AliasListView`.

- Pro: standard iOS navigation pattern; back-button labelled automatically. No custom navigation state machine.
- Pro: `SettingsView` owns the stack and can later add more navigation destinations (E-36 Shared Data screen) without touching E-34 files.
- Pro: `PersonalisationStore` can be passed as a single argument to the initial `NavigationLink` destinations, then forwarded to the `AliasEditSheet`.
- Con: the sheet is modal and the inner push navigation uses the sheet's stack — iOS allows this, but the sheet cannot be arbitrarily resized mid-navigation. Spec requires `.large` detent for the sheet container, which is the safest default.

### Option B — Separate full-screen navigation (rejected)

Present `AliasListView` as its own `.fullScreenCover`.

- Con: inconsistent with the spec's decision (§ Technical Context): "Modal `.sheet` anchored to an icon button in the `HomeView` toolbar." All Settings content lives in one sheet. Rejected.

### Option C — Each sub-screen as its own `.sheet` (rejected)

`SettingsView` uses `.sheet` for Aliases and `.sheet` for Learned Phrases, with no `NavigationStack`.

- Con: eliminates the standard iOS back-navigation pattern; creates three stacked modals which iOS limits in practice. Rejected.

---

## Rationale

Option A matches the spec intent and reuses a pattern already present in `LanguagePickerSheet` and `HelpView`. It avoids custom navigation state while keeping all personalisation content within the single Settings sheet. The `PersonalisationStore` injection from `HomeView` is the right pattern because E-33's ADR already established that `HomeView` owns the store; E-34 views are simply consumers of the same instance.

---

## Consequences

### PersonalisationStore gap — `ConfirmedCommandRecord` and `confirmedCommands(for:)`

`PersonalisationStore` already exposes every alias operation required by T-3402 and T-3405. However, it does not yet expose a `confirmedCommands(for:)` fetch returning value types, nor a `ConfirmedCommandRecord` struct. The `matchConfirmedCommand` method is a lookup, not a listing method. T-3403 (Learned Phrases screen) needs a listing. Two additions are required before T-3403 can be implemented:

```swift
struct ConfirmedCommandRecord: Identifiable {
    let id: UUID
    let speakerId: String
    let transcription: String
    let intent: CommandIntent
    let lastUsedAt: Date
    let useCount: Int64
}

// In PersonalisationStore:
func confirmedCommands(for speakerId: String) -> [ConfirmedCommandRecord]
```

These additions belong in `PersonalisationStore.swift` as a prerequisite for T-3403.

### PersonalisationStore `saveAlias` does not validate for the "Voxio" wake-word or duplicate phrases

`design-spec-alias-management.md` §3 (Issue 3, resolved) requires that `PersonalisationStore.saveAlias()` enforce the Voxio reserved-word block. Currently it does not. T-3402 implementers must either add the guard inside `saveAlias()` (preferred) or enforce it exclusively in the UI layer.

### `AliasEditSheet` step 2 speaker selector uses `MdnsDiscovery`-resolved speaker list

The speaker selector in step 2 requires a snapshot of discovered speakers at sheet-open time. This is passed as a `[Speaker]` argument to `AliasEditSheet`, consistent with the `HelpView` pattern. The sheet does not observe `SpeakerDiscoveryService` live.

### `BeoAnimation.cardExpand` covers the step 1 → step 2 transition

The animation token already exists in `DesignTokens.swift`. No new animation value is needed.

### `interactiveDismissDisabled` for dirty-form detection

`design-spec-alias-management.md` §2.7 requires `.interactiveDismissDisabled(isDirty)`. This is the SwiftUI-recommended pattern and works cleanly on iOS 26.

### Widget target is unaffected

All new files land in `iOS/Voxio/Features/Settings/`. The widget exception set only explicitly allows specific `Core/`, `DesignSystem/`, and `Features/Home/Speaker.swift` files. New paths under `Features/Settings/` are not in that allow-list and therefore do not compile into `VoxioWidgetExtension`. No project file changes are needed.

### `@MainActor` Core Data access from SwiftUI — no issue

`PersonalisationStore` is `@MainActor final class`. SwiftUI views are inherently `@MainActor`. All CRUD calls from E-34 views run on the main actor, using `PersistenceController.shared.viewContext`.

### Swift 6 strict concurrency — `NSBatchDeleteRequest` in `clearAllConfirmedCommands`

`clearAllConfirmedCommands()` uses `NSBatchDeleteRequest`, which bypasses `NSManagedObjectContext` change-tracking. A `context.refreshAllObjects()` call must be added after the batch delete to ensure the Learned Phrases list reflects the cleared state immediately. This is a correctness fix required in T-3403.

---

## Platform Constraint Checks

1. **`SFSpeechRecognizer` session conflict** — Two simultaneous `SFSpeechRecognizer` sessions targeting the same locale cannot both be active. The mic button in `AliasEditSheet` step 1 must pause or stop the main `VoiceToText` session while alias phrase dictation is running, then restart it on sheet dismiss. A `pause()`/`resume()` method on `VoiceToText` is the cleanest approach, but stopping and restarting around the sheet lifetime is an acceptable fallback.

2. **`Picker` styled `.segmented` above 3 speakers** — SwiftUI's `.segmented` style renders unreadably narrow above 3 segments. The spec (§2.5.2) mandates switching to a `Menu`-style picker above 3 speakers. This must be an explicit conditional in the view code based on `speakers.count > 3`.

3. **`SwiftUI.List` `.swipeActions`** (T-3405) — available since iOS 15; no availability guard needed on iOS 26.

4. **`interactiveDismissDisabled`** (§2.7) — available since iOS 15; no issue.

5. **`detents: [.medium, .large]`** for the Add/Edit sheet (§2.2) — available since iOS 16; no issue on iOS 26.

---

## File-Level Plan

### New files

| Path | Purpose |
|---|---|
| `iOS/Voxio/Features/Settings/AliasListView.swift` | T-3402 — grouped alias list, swipe-to-delete, per-speaker bulk delete, empty state |
| `iOS/Voxio/Features/Settings/AliasEditSheet.swift` | T-3402 / T-3405 — two-step Add/Edit modal; mic-button dictation; step indicator; live preview panel |
| `iOS/Voxio/Features/Settings/LearnedPhrasesView.swift` | T-3403 — confirmed-command list grouped by speaker; swipe-to-delete; "Clear all" action |

### Modified files

| Path | Change |
|---|---|
| `iOS/Voxio/Core/Personalisation/PersonalisationStore.swift` | Add `ConfirmedCommandRecord` struct; add `confirmedCommands(for:)` fetch method; add `context.refreshAllObjects()` after `NSBatchDeleteRequest` in `clearAllConfirmedCommands()` |

### Files not changed by E-34

`SettingsView` (E-39), `HomeView`, `CommandParserRouter`, `PersistenceController` — all unchanged.

---

## Public Interface Contract

### `AliasListView`

```swift
struct AliasListView: View {
    let store: PersonalisationStore
    let discoveredSpeakers: [Speaker]   // resolved at sheet-open time in SettingsView
}
```

### `AliasEditSheet`

```swift
struct AliasEditSheet: View {
    enum Mode {
        case add
        case edit(AliasRecord)
    }
    let mode: Mode
    let store: PersonalisationStore
    let discoveredSpeakers: [Speaker]
    @Binding var isPresented: Bool
}
```

### `LearnedPhrasesView`

```swift
struct LearnedPhrasesView: View {
    let store: PersonalisationStore
}
```

### `ConfirmedCommandRecord` (addition to `PersonalisationStore.swift`)

```swift
struct ConfirmedCommandRecord: Identifiable {
    let id: UUID
    let speakerId: String
    let transcription: String
    let intent: CommandIntent
    let lastUsedAt: Date
    let useCount: Int64
}
```

### New method on `PersonalisationStore`

```swift
func confirmedCommands(for speakerId: String) -> [ConfirmedCommandRecord]
```

---

## Conflicts Flagged

1. **T-3401 is in E-39 scope, not E-34.** The "Voice control" section toggle row and "Aliases" / "Learned phrases" navigation rows inside `SettingsView` are wired by E-39 T-3904. E-34 delivers the destination screens only.

2. **T-3404 (`isEnabled` toggle) deliverable** — `PersonalisationStore.isEnabled` is already readable and writable from E-33. T-3404 has no code work beyond the E-39 row wiring.

3. **`SFSpeechRecognizer` session conflict** — See Platform Constraint 1. The implementer must coordinate the alias dictation session with the main `VoiceToText` session.

4. **Favourite name resolution in step 2 detail control A** — The sheet should read from `speaker.favorites` at step 2 open time and trigger a background `GET /scenes` refresh. The exact API to call depends on `Speaker.swift` implementation details.

5. **`PBXFileSystemSynchronizedRootGroup` auto-compilation confirmed** — New files in `Features/Settings/` compile into Voxio target, not widget target.

---

PROCEED
