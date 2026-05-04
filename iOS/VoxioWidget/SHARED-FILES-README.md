# VoxioWidget Target Membership — Required Xcode Steps

The widget extension (`VoxioWidget` target) references types defined in main-app source files.
Because `PBXFileSystemSynchronizedRootGroup` auto-compiles files only for the target owning
the folder, files under `iOS/Voxio/` are NOT in the widget target by default.

You must add the following files to the `VoxioWidget` target's **Target Membership** via
Xcode's File Inspector (right-hand panel → Target Membership → tick `VoxioWidget`):

---

## Required files (add to VoxioWidget target membership)

### Design system

| File | Why needed |
|---|---|
| `iOS/Voxio/DesignSystem/DesignTokens.swift` | `BeoType`, `Spacing`, `WidgetButtonToken`, `DarkGlassButtonTokens` |
| `iOS/Voxio/DesignSystem/BeoColor.swift` | `BeoColor.labelPrimary`, `.labelSecondary`, `.accent`, `.separator` |

### App Intents (for `Button(intent:)` in widget views)

| File | Why needed |
|---|---|
| `iOS/Voxio/Core/Intents/VoxioIntents.swift` | `PlaybackToggleIntent`, `AdjustVolumeIntent`, `MuteIntent`, `SpeakerEntity` |

**Note:** `VoxioIntents.swift` also references `SpeakerStore`, `Speaker`, `LanguageService`,
and `IntentStrings`. Those transitive dependencies must also be added (listed below), OR
the intent types can be refactored to not depend on main-app singletons when running in the
widget process. The intents' `perform()` methods execute in the **main app process** (via
`AudioPlaybackIntent` routing), so the widget only needs the type declarations to compile —
the runtime dependencies are never called in the widget process. However, the Swift compiler
still requires all referenced types to be visible.

### Transitive dependencies of VoxioIntents.swift

| File | Why needed |
|---|---|
| `iOS/Voxio/Core/Intents/SpeakerStore.swift` | Referenced by `PlaybackToggleIntent.perform()` |
| `iOS/Voxio/Core/Intents/IntentStrings.swift` | Referenced by all intent `perform()` methods |
| `iOS/Voxio/Core/Intents/VoxioShortcutsProvider.swift` | Part of the intents module (may import shared types) |
| `iOS/Voxio/Features/Home/Speaker.swift` | `Speaker` type used by `SpeakerStore` |
| `iOS/Voxio/Core/Protocols/SpeakerClient.swift` | Protocol conformance used by `Speaker` |
| `iOS/Voxio/Core/Protocols/SpeakerEventSource.swift` | Protocol conformance used by `Speaker` |
| `iOS/Voxio/Core/Models/SpeakerEvent.swift` | `SpeakerEvent` used by `SpeakerEventSource` |
| `iOS/Voxio/Core/Models/SpeakerIdentifier.swift` | `SpeakerIdentifier`, `SpeakerPlatform` |
| `iOS/Voxio/Core/Models/Playback.swift` | `PlaybackValue`, `PlaybackMetadata`, `SpeakerPlaybackState` |
| `iOS/Voxio/Core/Models/Volume.swift` | `Volume` model |
| `iOS/Voxio/Core/Models/Battery.swift` | `BatteryState` |
| `iOS/Voxio/Core/Models/Favorite.swift` | `Favorite` |
| `iOS/Voxio/Core/Models/BeolinkPeer.swift` | `BeolinkPeer` |
| `iOS/Voxio/Core/Models/BeoEvent.swift` | `BeoEvent` |
| `iOS/Voxio/Core/Errors/SpeakerError.swift` | `SpeakerError` |
| `iOS/Voxio/Core/Logger.swift` | `Log` used by `Speaker` |
| `iOS/Voxio/Core/Language/Language.swift` | `Language`, `LanguageService` |
| `iOS/Voxio/Core/Networking/MozartClient.swift` | Cast in `Speaker.loadVolume()` and `playFavorite()` |
| `iOS/Voxio/Core/Networking/MozartError.swift` | `MozartError` |
| `iOS/Voxio/Core/Networking/MozartEvents.swift` | `MozartEvents` |

---

## Alternative: Refactor strategy to reduce widget target dependency surface

Instead of adding the full intent + speaker graph to the widget target, consider extracting
just the intent type declarations into a separate file `iOS/VoxioWidget/WidgetIntentStubs.swift`
that redeclares the minimum needed for `Button(intent:)`:

```swift
// WidgetIntentStubs.swift — widget target only
import AppIntents

// These declarations mirror the main-app types. The widget only needs the type signature;
// perform() is never called in the widget process (AudioPlaybackIntent routes to the app).

extension PlaybackToggleIntent { }   // Just needs to be visible as a type
```

This is only viable if `PlaybackToggleIntent` is declared in a file that IS already in both
targets (e.g. if `VoxioIntents.swift` is added). There is no way to avoid adding at minimum
`VoxioIntents.swift` to the widget target.

**Recommended action:** Add `VoxioIntents.swift` and all files in the transitive dependency
list above to the `VoxioWidget` target membership. This is the lowest-risk path. The
compiler will catch any remaining missing types.

---

## Files that DO NOT need to be added (already in widget target)

All files under `iOS/VoxioWidget/` are already compiled into the widget extension target by
Xcode's synchronized root group:
- `VoxioWidget.swift`
- `VoxioWidgetBundle.swift`
- `VoxioWidgetControl.swift`
- `VoxioWidgetProvider.swift`
- `VoxioWidgetIntent.swift`
- `VoxioWidgetSmallView.swift`
- `VoxioWidgetMediumView.swift`

---

## Build errors to expect before target membership is set

```
Cannot find type 'PlaybackToggleIntent' in scope     — VoxioWidgetSmallView.swift, VoxioWidgetMediumView.swift
Cannot find type 'AdjustVolumeIntent' in scope       — VoxioWidgetMediumView.swift
Cannot find 'BeoColor' in scope                      — VoxioWidgetSmallView.swift, VoxioWidgetMediumView.swift
Cannot find 'BeoType' in scope                       — VoxioWidgetSmallView.swift, VoxioWidgetMediumView.swift
Cannot find 'Spacing' in scope                       — VoxioWidgetSmallView.swift, VoxioWidgetMediumView.swift
Cannot find 'WidgetButtonToken' in scope             — VoxioWidgetSmallView.swift, VoxioWidgetMediumView.swift
```

These errors are all resolved by adding the files listed above to the `VoxioWidget` target.
