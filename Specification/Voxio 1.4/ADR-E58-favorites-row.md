# ADR-E58 — Favorites Row (E-58): Async Load, Scrollable Pill Row, `playFavorite` Dispatch, Empty-State Absence

**Status:** Accepted
**Date:** 2026-05-12
**Deciders:** Engineering Lead
**Refs:** ADR-002-voxio-1.4-ios.md (D6, token-lock, @MainActor invariant), ADR-E56-play-pause-toggle.md (SpeakerCard shape, `resolvedGroup`, `showErrorToast`, branch structure, CF-2), ADR-E57-volume-slider.md (DesignSystem/ extraction pattern — NOT applied here), spec-touch-playback-controls.md v1.0 (US-72, Technical Requirements, Resolved Decisions UQ-1), design-spec-touch-playback-controls.md v1.2 (§4, §7, Appendix B), epics-and-tasks-touch-playback-controls.md v1.0 (E-58 T-5801–T-5806), CLAUDE.md (Mozart `/scenes`, `/playback/preset/{id}/trigger`)

---

## 1. Decision

The favorites row is a `@ViewBuilder` private computed view (`favoritesRow`) on `SpeakerCard`, not extracted to `DesignSystem/` (feature-level coupling). It mounts in **both** branches of `SpeakerCard.cardContent`: at the bottom of the playing/paused/buffering branch (below `transportRow`, above `GroupChipRow`) and at the bottom of the stopped branch (below `stoppedPlayPill`). Favorites load via `.task` calling `speaker.getFavorites()`, with the result stored in `@State private var favorites: [Favorite] = []`. When the array is empty or the call throws, the row is entirely absent (zero height). All favorites render with `DarkGlassButton` at `.default` role — overriding the design-spec §4.2 conditional-gold rule per spec UQ-1. Taps fire `HapticEngine.shared.commandRecognised()` then dispatch `speaker.playFavorite(presetIndex: fav.presetIndex)` — using the `presetIndex` on the `Favorite` model, NOT the array enumeration offset.

---

## 2. Context

### Prior decisions and constraints

**ADR-002 D6 — Favorites lazy load, intended to be cached on `Speaker`.** D6 specified `Speaker.favorites: [Favorite]` and `Speaker.favoritesState: FavoritesLoadState`. The shipped codebase doesn't implement these properties: `Speaker.getFavorites()` (line 227) is a direct `client.getSources()` call with no caching, and the pre-existing cache lives in `FavoritesService` (a `@MainActor` class for the voice pipeline). The epics doc T-5801 explicitly chose view-local `@State private var favorites` via `.task`, which is the effective spec.

**ADR-E56 surfaces E-58 reuses:**
- `cardContent` switches on `speaker.playbackState` with playing/paused/buffering vs stopped branches.
- `showErrorToast(_:)` for `playFavorite` failures.
- `@Binding var errorMessage: String?` backing the toast.
- `resolvedGroup` exists but E-58 doesn't use it — favorites target the card's own speaker.

**ADR-E56 CF-2 — spec UQ-1 role override.** This conflict was first flagged in E-56's ADR and is the central architectural choice for E-58. `design-spec §4.2` would render the active favorite as `.confirm` (gold); spec UQ-1 says always `.default` because matching the active favorite isn't possible — Mozart's `nowPlaying` doesn't expose the preset ID.

**`Favorite` model.**
```swift
struct Favorite: Identifiable {
    let id: String          // scene UUID
    let displayName: String
    let presetIndex: Int    // 1-based; assigned by MozartClient.getFavorites() as offset + 1
}
```
`MozartClient.playFavorite(presetIndex:)` calls `POST /playback/preset/{presetIndex}/trigger`. The call site uses `fav.presetIndex`, NOT `array.enumerated().offset`.

**`HapticEngine.commandRecognised()` already exists** (line 9). No new method.

**`FavoritesService` coexistence.** `FavoritesService` caches by `speaker.host` for the voice pipeline. E-58 does NOT use `FavoritesService` in `SpeakerCard` — it calls `speaker.getFavorites()` directly. Both paths source from the same `/scenes` endpoint; eventual consistency is acceptable.

**ADR-002 token-lock.** No new tokens. Uses `Spacing.s8`, `Spacing.s24`, `Spacing.s20`.

**ADR-002 @MainActor invariant.** `.task` runs in the view's `@MainActor` context. `Speaker` is `@MainActor`. No cross-actor issues.

---

## 3. Options Considered

### A — View-local `@State private var favorites` on `SpeakerCard` (chosen)

Load via `.task`, store in `@State`. Failure → empty array, WARN log, no toast. Row renders only when non-empty. This matches the epics doc T-5801 exactly.

Advantages: minimal change footprint; `.task` lifecycle correct (fires once on appear, cancelled on disappear); silent failure is right UX for passive load; consistent with E-57's `dragVolume` view-local state pattern.

Disadvantages: re-appears refetch (acceptable in v1.4 — `/scenes` is lightweight).

### B — Cache favorites on `Speaker` per ADR-002 D6 intent

Add `Speaker.favorites: [Favorite]` and `Speaker.favoritesState: FavoritesLoadState`. Survives card disappear/reappear and multi-callsite reuse.

Disadvantages: requires `Speaker` API growth; introduces a second cache alongside `FavoritesService`; contradicts shipped `Speaker.swift`; epics doc explicitly chose view-local. Rejected.

### C — Reuse `FavoritesService` in `SpeakerCard`

Disadvantage: `FavoritesService.listFavorites` returns `[String]`, losing `presetIndex`. API mismatch. Rejected.

---

## 4. Rationale

Option A matches the epics doc, avoids `Speaker` API growth, avoids dual caching, and provides correct silent-failure UX. The `.task` lifecycle is sufficient for v1.4's single-card-per-speaker display. The `fav.presetIndex` call site is mandated by the `Favorite` model and validated by existing `FavoritesService` usage.

---

## 5. Consequences

- **F1 closes entirely after E-58.**
- **`SpeakerCard.swift` grows ~40 lines.** Total still < 550 lines after F1.
- **No new file** — `favoritesRow` is private to `SpeakerCard`.
- **`UIStrings` gains `couldNotStartFavorite`** (EN: "Could not start favorite" / DA: "Kunne ikke starte favorit") for error toast.
- **Re-fetch on re-appear** is accepted; future versions can add caching via Option B.
- **`presetIndex` contract**: `fav.presetIndex`, not array offset. Epics doc T-5803 snippet is wrong and superseded here.
- **`FavoritesService` and `SpeakerCard` are independent.** Different cache lifecycles, both authoritative against same endpoint.
- **Accessibility loosening** (`.accessibilityElement(children: .contain)` from E-56 T-5607) covers the `ScrollView` inside `favoritesRow` — no additional card-level change.

---

## 6. File-Level Plan

### Modified files

| Path | Change | Tasks |
|---|---|---|
| `iOS/Voxio/Features/Home/SpeakerCard.swift` | Add `@State private var favorites: [Favorite] = []`; `.task` modifier; `private var favoritesRow: some View`; `private var trailingFadeGradient: some View`; `private func onFavoriteTapped(fav:)`; mount `favoritesRow` in both `cardContent` branches | T-5801, T-5802, T-5803, T-5804 |
| `iOS/Voxio/Core/Strings/UIStrings.swift` | Add `couldNotStartFavorite: String` with EN/DA | T-5803 |

### New files

None. `favoritesRow` is feature-coupled to `SpeakerCard`.

### No changes to

`Speaker.swift`, `Group.swift`, `HapticEngine.swift`, `DarkGlassButton.swift`, `DesignTokens.swift`, `BeoColor.swift`, `MozartClient.swift`, any backend file.

---

## 7. Public Interface Contract

```swift
// MARK: - SpeakerCard additions (E-58 T-5801–T-5804)
// File: iOS/Voxio/Features/Home/SpeakerCard.swift
// SpeakerCard init signature is UNCHANGED — no new parameters.

@State private var favorites: [Favorite] = []

// .task modifier on the outer card view body:
//
// .task {
//     do {
//         favorites = try await speaker.getFavorites()
//     } catch {
//         Log.warn("[\(speaker.name)] getFavorites failed: \(error)")
//         favorites = []
//     }
// }
//
// Contracts:
// 1. Success: favorites populated from getSources() return.
// 2. Throw: favorites = []; WARN log; no toast.
// 3. Re-appear re-fires .task; stale favorites overwritten atomically.

@ViewBuilder
private var favoritesRow: some View {
    if favorites.isEmpty == false {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s8) {
                ForEach(favorites) { fav in
                    DarkGlassButton(label: fav.displayName, role: .default) {
                        onFavoriteTapped(fav: fav)
                    }
                    .fixedSize()
                }
            }
            .padding(.horizontal, Spacing.s24)
        }
        .mask(trailingFadeGradient)
        .padding(.top, Spacing.s8)
        .padding(.bottom, Spacing.s20)
        .accessibilityElement(children: .contain)
    }
    // Empty → EmptyView() — zero height, no placeholder.
}

// ForEach keyed on fav.id (scene UUID) — avoids id collisions on re-fetch.

private var trailingFadeGradient: some View {
    LinearGradient(
        stops: [
            .init(color: .white, location: 0),
            .init(color: .white, location: 0.85),
            .init(color: .clear,  location: 1.0)
        ],
        startPoint: .leading,
        endPoint:   .trailing
    )
}

private func onFavoriteTapped(fav: Favorite) {
    HapticEngine.shared.commandRecognised()
    Task {
        do {
            try await speaker.playFavorite(presetIndex: fav.presetIndex)
        } catch {
            Log.error("[\(speaker.name)] playFavorite(\(fav.presetIndex)) failed: \(error)")
            showErrorToast(ui.couldNotStartFavorite)
            HapticEngine.shared.errorOccurred()
        }
    }
}

// CRITICAL: use fav.presetIndex (1-based Mozart preset, stored on the model),
// NOT the ForEach enumeration offset. Epics doc T-5803 snippet is incorrect on this point;
// existing FavoritesService.play(index:on:) uses fav.presetIndex — validates the pattern.

// cardContent mount points:
//   Playing/paused/buffering branch:
//       headerSection → nowPlayingPanel → InteractiveVolumeBar → transportRow
//       → favoritesRow    ← NEW
//       → if !groupMembers.isEmpty { GroupChipRow(...) }
//
//   Stopped branch:
//       headerSection → stoppedPlayPill
//       → favoritesRow    ← NEW
```

```swift
// MARK: - Speaker (no changes required) — existing
// File: iOS/Voxio/Features/Home/Speaker.swift

func getFavorites() async throws -> [Favorite]         // line 227 — routes to client.getSources()
func playFavorite(presetIndex: Int) async throws       // line 231 — routes to MozartClient.playFavorite or activateSource
```

```swift
// MARK: - UIStrings addition
// File: iOS/Voxio/Core/Strings/UIStrings.swift

var couldNotStartFavorite: String
// EN: "Could not start favorite"
// DA: "Kunne ikke starte favorit"
```

```swift
// MARK: - Empty-state semantics
// favorites.isEmpty == true → @ViewBuilder emits nothing → SwiftUI EmptyView, zero height.
// No "No favorites" label, no spinner, no placeholder. Spec US-72 acceptance criterion.

// MARK: - Accessibility (T-5804)
// 1. Each DarkGlassButton already sets .accessibilityLabel(label) = fav.displayName.
// 2. ScrollView: .accessibilityElement(children: .contain).
// 3. VoiceOver order: header → nowPlayingPanel → InteractiveVolumeBar → transport → favoritesRow → GroupChipRow.
// 4. No new AccessibilityNotification announcements (favorites have no limit).
```

Key behavioural contracts the Test Writer should assert:

1. `getFavorites()` returns 3 items → favoritesRow renders 3 `DarkGlassButton` pills, all `.default` role.
2. `getFavorites()` returns 0 → favoritesRow absent (no height contribution).
3. `getFavorites()` throws → favoritesRow absent; WARN log; no toast.
4. Tap pill → `HapticEngine.shared.commandRecognised()` fires synchronously; `speaker.playFavorite(presetIndex: fav.presetIndex)` dispatched.
5. `playFavorite` throws → `showErrorToast(ui.couldNotStartFavorite)`; `HapticEngine.shared.errorOccurred()`; `Log.error`.
6. `.stopped` state → favoritesRow appears below `stoppedPlayPill`.
7. `.playing` state → favoritesRow appears below `transportRow`, above `GroupChipRow`.
8. All pills `.default` role even when a favorite matches `speaker.nowPlaying.primaryLine`. NEVER `.confirm` (UQ-1).
9. `.task` fires exactly once per appearance; re-appear triggers a fresh fetch.
10. `Favorite.presetIndex` is passed to `playFavorite`, NOT ForEach enumeration offset.
11. `favoritesRow` is `.accessibilityElement(children: .contain)` — VoiceOver navigates each pill.
12. `DarkGlassButton` accessibility label = `fav.displayName` with no suffix.

---

## 8. Conflicts Flagged

### CF-1: design-spec §4.2 vs spec UQ-1 — ROLE CONFLICT — SPEC WINS

design-spec §4.2: "If a favorite is currently active: role `.confirm` (gold label)."
spec UQ-1 resolved: "No active-favorite highlight. Favorites always `.default`. Matching the active favorite reliably is not possible — Mozart's `nowPlaying` doesn't expose the preset ID."

Spec overrides design-spec. **All favorites render `.default`, always.** Re-flagged here because E-58 is the implementing epic — no ambiguity permitted.

### CF-2: Epics doc T-5803 `presetIndex` call site is incorrect — CORRECTED HERE

The epics doc T-5803 snippet uses:
```swift
ForEach(Array(favorites.enumerated()), id: \.offset) { index, fav in
    DarkGlassButton(label: fav.displayName, role: .default) {
        onFavoriteTapped(index: index)
    }
}
// ...
try await speaker.playFavorite(presetIndex: index)   // ← WRONG: offset, not presetIndex
```

`Favorite.presetIndex` is assigned by `MozartClient.getFavorites()` as `offset + 1`. `MozartClient.playFavorite(presetIndex:)` posts to `/playback/preset/\(presetIndex)/trigger`. The correct call is `speaker.playFavorite(presetIndex: fav.presetIndex)`. The existing `FavoritesService` uses `fav.presetIndex` — validates the correct pattern.

This ADR's §7 specifies: `ForEach(favorites) { fav in ... }` keyed on `fav.id`, and `speaker.playFavorite(presetIndex: fav.presetIndex)`.

### CF-3: `GroupChipRow` ordering in playing branch

VStack after E-58: headerSection → nowPlayingPanel → InteractiveVolumeBar → transportRow → **favoritesRow** → GroupChipRow. F1 spec places favorites at position 5; E-53 places GroupChipRow at bottom. `favoritesRow` is inserted above GroupChipRow. No conflict — verify order during implementation.

### CF-4: ADR-002 D6 caching model not implemented in `Speaker` — ACCEPTED DEVIATION

D6 specified `Speaker.favorites: [Favorite]` and `Speaker.favoritesState`. Shipped code has neither. The epics doc and this ADR accept view-local `@State` for v1.4. The retry button mentioned in D6 isn't in the design-spec and isn't implemented. v1.5 may revisit.

---

## 9. Platform Constraint Checks

| API | Introduced | Status |
|---|---|---|
| `.task` modifier on View | iOS 15 | Safe |
| `ScrollView(.horizontal, showsIndicators: false)` | iOS 13 | Safe |
| `LinearGradient` mask | iOS 13 | Safe |
| `.fixedSize()` | iOS 13 | Safe |
| `HapticEngine.commandRecognised()` / `errorOccurred()` | iOS 10 | Safe (existing) |

No constraint violations.

---

## 10. Task Gate

| Task | Status | Reason |
|---|---|---|
| T-5801 — `@State favorites`; `.task` async load | UNBLOCKED | E-56 shipped; `Speaker.getFavorites()` exists |
| T-5802 — `favoritesRow` view; `trailingFadeGradient`; mount in both branches | UNBLOCKED (after T-5801) | E-56 branches are the mount points |
| T-5803 — `onFavoriteTapped(fav:)`; `UIStrings.couldNotStartFavorite` | UNBLOCKED (after T-5802) | `showErrorToast` shipped; MUST use `fav.presetIndex` not offset |
| T-5804 — Accessibility on ScrollView; per-pill labels | UNBLOCKED (after T-5802) | `DarkGlassButton` already sets `.accessibilityLabel` |
| T-5805 — Manual test on Mozart speaker with presets | DEFERRED (device required) | All prior tasks merged |
| T-5806 — SwiftUI previews: 5-favorites, 3-favorites stopped, 0-favorites | UNBLOCKED (after T-5802) | Stub `getSources()` returns configured array |

---

**Verdict: PROCEED**
