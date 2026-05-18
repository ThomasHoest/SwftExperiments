# Test Plan — E-58 Favorites Row

**Status:** Draft
**Date:** 2026-05-12
**Refs:** ADR-E58-favorites-row.md, spec-touch-playback-controls.md US-72, design-spec-touch-playback-controls.md §4, epics-and-tasks-touch-playback-controls.md E-58 (T-5801–T-5806)

---

## 1. Scope

This plan covers the testable interface contract introduced by E-58: the `@State private var favorites: [Favorite] = []` property on `SpeakerCard`; the `.task` modifier that loads favorites asynchronously on card appear via `speaker.getFavorites()`; the `favoritesRow` private `@ViewBuilder` computed view (horizontal `ScrollView`, `HStack` of `DarkGlassButton` pills, trailing fade gradient, zero-height empty state); the `onFavoriteTapped(fav:)` private method (haptic dispatch + `playFavorite(presetIndex:)` call + error toast path); the `UIStrings.couldNotStartFavorite` localised string (EN/DA); and the mounting of `favoritesRow` in both `cardContent` branches (playing/paused/buffering and stopped).

All 12 ADR §7 behavioural assertions are mapped to at least one TC. All US-72 acceptance criteria are covered.

Key overrides to note throughout this plan:

- **CF-1 / UQ-1:** `design-spec-touch-playback-controls.md §4.2` states that an active favorite renders with role `.confirm` (gold). This is overridden by `spec-touch-playback-controls.md` Resolved Decisions (UQ-1) and confirmed as `ADR-E58-favorites-row.md §8 CF-1`. **All tests assert `.default` role always, regardless of `speaker.nowPlaying`.**
- **CF-2:** `epics-and-tasks-touch-playback-controls.md T-5803` snippet uses `ForEach(Array(favorites.enumerated()), id: \.offset)` and passes `presetIndex: index` (enumeration offset). This is **incorrect** per ADR §8 CF-2. **All tests assert `fav.presetIndex` (the value on the `Favorite` model) is passed to `playFavorite`, and that `ForEach` is keyed on `fav.id` (scene UUID).**

What is out of scope:

- E-56 play/pause toggle (covered in test-plan-E56.md).
- E-57 interactive volume slider (covered in test-plan-E57.md).
- US-70, US-71, US-73 acceptance criteria.
- `Speaker.getFavorites()` and `MozartClient` internals — only call-counts and thrown errors are observed from `SpeakerCard`.
- `HapticEngine.commandRecognised()` / `errorOccurred()` internal implementations (already shipped; only call-counts are asserted).
- `FavoritesService` — this plan does not test the voice-pipeline favorites cache; it is independent of `SpeakerCard`.
- SwiftUI preview correctness (T-5806 is a visual verification task; no XCTest assertion).
- Backend, telemetry, voice pipeline.

---

## 2. Test Environment

| Item | Value |
|---|---|
| Platform | iOS 26, iPhone (portrait) |
| Framework | SwiftUI, `@Observable @MainActor`, `.task` lifecycle |
| Test harness | No XCTest target exists in this repo (confirmed by ADR §8 CF-4 analogue and E-57 test plan precedent). All TCs are manual verification procedures or static/code-review assertions unless a future XCTest target is created. Where XCTest is noted, it is conditional on the target being added. |
| Accessibility testing | Xcode Accessibility Inspector + VoiceOver on device/simulator |
| Source files under test | `iOS/Voxio/Features/Home/SpeakerCard.swift` (modified), `iOS/Voxio/Core/Strings/UIStrings.swift` (modified) |
| Files NOT modified by E-58 | `Speaker.swift`, `Group.swift`, `HapticEngine.swift`, `DarkGlassButton.swift`, `DesignTokens.swift`, `BeoColor.swift`, `MozartClient.swift`, `FavoritesService.swift`, any backend file |
| Speaker doubles | `SpeakerStub: @Observable @MainActor` — writable `playbackState`, `nowPlaying`, `volume`; injectable `getFavoritesResult: Result<[Favorite], Error>`; records `getFavoritesCallCount: Int`; injectable `playFavoriteError: Error?`; records `playFavoriteCallCount: Int` and `lastPlayFavoritePresetIndex: Int?`. Extended from the E-56/E-57 stub (adds favorites recording). |
| Favorite test fixtures | `Favorite(id: "uuid-A", displayName: "Morning", presetIndex: 1)`, `Favorite(id: "uuid-B", displayName: "Dinner", presetIndex: 2)`, `Favorite(id: "uuid-C", displayName: "Jazz", presetIndex: 3)`. For 5-favorite tests: add `Favorite(id: "uuid-D", displayName: "Sleep", presetIndex: 4)`, `Favorite(id: "uuid-E", displayName: "Party", presetIndex: 5)`. |
| HapticEngine double | `HapticEngineSpy` recording `commandRecognisedCallCount: Int`, `errorOccurredCallCount: Int`, and call sequence. Same spy defined in test-plan-E56 and test-plan-E57. |
| Toast surface double | `ToastSpy` recording `showErrorToastMessages: [String]`. Injected via the same `@Binding var errorMessage: String?` mechanism established in E-56 T-5606. |
| Locale | EN (default), DA (localisation tests only). |

---

## 3. Unit-Level Test Cases — favoritesRow Rendering and Empty-State

These cases target `favoritesRow` in isolation: the `@ViewBuilder` conditional, pill count, `DarkGlassButton` role, `ForEach` identity, trailing fade gradient presence, and empty-state absence. Where XCTest ViewInspector is unavailable, these become manual canvas/device verification steps.

---

### TC-E58-U01

**ID:** TC-E58-U01
**Target:** `favoritesRow` — renders 3 pills when `favorites` contains 3 items
**ADR assertion:** §7 assertion #1 — "`getFavorites()` returns 3 items → favoritesRow renders 3 `DarkGlassButton` pills."
**Setup:** `SpeakerStub` configured with `getFavoritesResult = .success([morning, dinner, jazz])`. `SpeakerCard` in `.playing` state. After `.task` completes, `favorites = [morning, dinner, jazz]`.
**Action:** Inspect `favoritesRow` view tree.
**Expected:** The `ScrollView(.horizontal, showsIndicators: false)` is present. The `HStack` inside contains exactly 3 `DarkGlassButton` children. Labels are "Morning", "Dinner", "Jazz" in that order. Each button's `role` is `.default`. The row occupies non-zero height.
**Covers spec AC:** US-72 AC-2 (at least one favorite → row renders with one button per favorite); ADR §7 assertion #1.

---

### TC-E58-U02

**ID:** TC-E58-U02
**Target:** `favoritesRow` — absent when `favorites` is empty (zero items returned)
**ADR assertion:** §7 assertion #2 — "`getFavorites()` returns 0 → favoritesRow absent (no height contribution)."
**Setup:** `SpeakerStub` with `getFavoritesResult = .success([])`. `SpeakerCard` in `.playing` state. After `.task` completes, `favorites = []`.
**Action:** Inspect `favoritesRow` view tree and measure its effective layout height contribution to `cardContent`.
**Expected:** `favoritesRow` emits `EmptyView()` (the `if favorites.isEmpty == false` branch is not entered). The `ScrollView` is NOT rendered. No placeholder text. No "No favorites" label. Zero height contribution. Layout below `transportRow` jumps directly to `GroupChipRow` (or the end of the `VStack`) without any gap from the favorites area.
**Covers spec AC:** US-72 AC-3 (zero favorites → row absent, not empty space); ADR §7 assertion #2; spec Resolved Decisions "Favorites empty state".

---

### TC-E58-U03

**ID:** TC-E58-U03
**Target:** `favoritesRow` — all pills use `.default` role regardless of `speaker.nowPlaying`
**ADR assertion:** §7 assertion #8 — "All pills `.default` role even when a favorite matches `speaker.nowPlaying.primaryLine`. NEVER `.confirm` (UQ-1)."
**Setup:** `SpeakerStub` with `getFavoritesResult = .success([morning, dinner, jazz])` and `nowPlaying.primaryLine = "Morning"` (simulating that the "Morning" favorite is currently active). `SpeakerCard` in `.playing` state.
**Action:** Inspect `role` property on each of the 3 rendered `DarkGlassButton` instances.
**Expected:** ALL three pills have `role = .default` (white label). The "Morning" pill does NOT use `role = .confirm` (gold). This asserts UQ-1 override: the design-spec §4.2 conditional gold rule is NOT applied. No active-favorite highlight under any `nowPlaying` condition.
**Covers spec AC:** US-72 AC-8 (all favorites always `.default` role — no `.confirm` highlight); ADR §7 assertion #8; ADR §8 CF-1 (spec overrides design-spec).

---

### TC-E58-U04

**ID:** TC-E58-U04
**Target:** `favoritesRow` — `ForEach` keyed on `fav.id` (scene UUID), not on offset
**ADR assertion:** §7 assertion — "ForEach keyed on `fav.id` (scene UUID), not offset."
**Setup:** `SpeakerStub` with 3 favorites. Inspect the `ForEach` initialiser in source code: `ForEach(favorites) { fav in ... }` (uses `Favorite: Identifiable` with `id: String` — scene UUID). Contrast with the **incorrect** epics T-5802 snippet: `ForEach(Array(favorites.enumerated()), id: \.offset)`.
**Action (static):** Code review `SpeakerCard.swift` — confirm `ForEach` uses the `Identifiable` conformance of `Favorite` (i.e. `ForEach(favorites) { fav in ... }` or `ForEach(favorites, id: \.id) { fav in ... }`). Confirm it does NOT use `ForEach(Array(favorites.enumerated()), id: \.offset)`.
**Action (runtime):** In a SwiftUI preview with 3 favorites, re-fetch (simulate re-appear) and verify no identity collision warnings or pill reordering.
**Expected:** `ForEach` is keyed on `fav.id` (scene UUID). No SwiftUI identity warnings. If two favorites happened to have the same `displayName` but different UUIDs, they would still be distinguished correctly.
**Covers spec AC:** ADR §7 final assertion ("ForEach keyed on `fav.id`"); ADR §8 CF-2 (epics T-5802 incorrect offset keying).

---

### TC-E58-U05

**ID:** TC-E58-U05
**Target:** `favoritesRow` — trailing fade gradient mask present when row renders
**Setup:** `SpeakerStub` with `getFavoritesResult = .success([morning, dinner, jazz])`. `SpeakerCard` in `.playing` state.
**Action:** Inspect `favoritesRow` view tree for the `.mask(trailingFadeGradient)` modifier applied to the `ScrollView`.
**Expected:** The `ScrollView` has a `LinearGradient` mask applied. The gradient starts at `white` (leading), holds `white` at location 0.85, then fades to `clear` at location 1.0 (trailing). This matches ADR §7 `trailingFadeGradient` definition. The gradient is on the trailing end, signalling scrollability per design-spec §4.2.
**Covers spec AC:** design-spec §4.2 (trailing fade gradient mask); ADR §7 `trailingFadeGradient` definition.

---

### TC-E58-U06

**ID:** TC-E58-U06
**Target:** `favoritesRow` — renders with 1 favorite (boundary: minimum non-empty array)
**Setup:** `SpeakerStub` with `getFavoritesResult = .success([morning])` (single item).
**Action:** Inspect `favoritesRow` after `.task` completes.
**Expected:** The row is rendered (non-empty). The `HStack` contains exactly 1 `DarkGlassButton` with label "Morning" and `role = .default`. The `ScrollView` is present. No crash.
**Covers spec AC:** US-72 AC-2 (at least one favorite → row renders); lazy load boundary value 1.

---

### TC-E58-U07

**ID:** TC-E58-U07
**Target:** `favoritesRow` — renders with 5 favorites (boundary: many, confirming scroll)
**Setup:** `SpeakerStub` with `getFavoritesResult = .success([morning, dinner, jazz, sleep, party])` (5 favorites).
**Action:** Inspect `favoritesRow` after `.task` completes.
**Expected:** The `HStack` contains exactly 5 `DarkGlassButton` pills. All have `role = .default`. On a typical iPhone width, 3–4 pills are visible; the remaining pills are accessible via horizontal scroll. The trailing fade gradient is present. No pill is truncated without the gradient signal.
**Covers spec AC:** US-72 AC-2; design-spec §4.2 (maximum visible 3 at typical iPhone width; scroll for more); lazy load boundary value "many".

---

### TC-E58-U08

**ID:** TC-E58-U08
**Target:** `favoritesRow` — padding matches design tokens (`Spacing.s8`, `Spacing.s24`, `Spacing.s20`)
**Setup:** `SpeakerStub` with 3 favorites. `SpeakerCard` in `.playing` state.
**Action (static):** Code review `SpeakerCard.swift` — confirm `favoritesRow` applies:
- `HStack(spacing: Spacing.s8)` between pills.
- `.padding(.horizontal, Spacing.s24)` on the `HStack` (inner horizontal padding).
- `.padding(.top, Spacing.s8)` on the `ScrollView` (below transport row divider).
- `.padding(.bottom, Spacing.s20)` on the `ScrollView`.
**Expected:** All four padding values match design-spec §4.2 (`Spacing.s8` spacing, `Spacing.s24` horizontal, `Spacing.s8` top, `Spacing.s20` bottom). No new tokens introduced (ADR §2 token-lock: only `Spacing.s8`, `Spacing.s24`, `Spacing.s20` used).
**Covers spec AC:** design-spec §4.2 (vertical/horizontal padding); ADR §2 token-lock.

---

### TC-E58-U09

**ID:** TC-E58-U09
**Target:** `favoritesRow` — each pill has `.fixedSize()` modifier
**Setup:** `SpeakerStub` with 3 favorites with varying name lengths ("Morning", "Very Long Favorite Name", "Jazz").
**Action (static):** Code review — confirm each `DarkGlassButton` in `favoritesRow` has `.fixedSize()` applied.
**Action (visual):** Render in SwiftUI preview. Confirm "Very Long Favorite Name" pill does not get clipped to fit the `HStack`; it extends the `HStack` width, enabling horizontal scroll.
**Expected:** Each pill uses `.fixedSize()` (causes it to display at its intrinsic content size). Long names are not truncated; they contribute to `HStack` width and cause horizontal scrolling. Short names are not stretched.
**Covers spec AC:** ADR §7 interface contract (`.fixedSize()` per pill); design-spec §4.2 (pills do not truncate).

---

## 4. Unit-Level Test Cases — .task Lifecycle

These cases target the `.task` modifier behaviour: single fire on appear, silent-failure handling on throw, re-fire on re-appear, and the absence of any toast on load failure.

---

### TC-E58-U10

**ID:** TC-E58-U10
**Target:** `.task` — fires exactly once on initial card appear; `getFavorites()` called once
**ADR assertion:** §7 assertion #9 — "`.task` fires exactly once per appearance."
**Setup:** `SpeakerStub` with `getFavoritesResult = .success([morning, dinner, jazz])`. `SpeakerCard` freshly instantiated and appeared once.
**Action:** Allow `.task` to complete. Check `stub.getFavoritesCallCount`.
**Expected:** `stub.getFavoritesCallCount == 1`. `favorites` state = `[morning, dinner, jazz]`. The `.task` modifier runs the block once, not repeatedly, during a single appearance.
**Covers spec AC:** US-72 AC-1 (when card appears, `getFavorites()` called once asynchronously via `.task`); ADR §7 assertion #9.

---

### TC-E58-U11

**ID:** TC-E58-U11
**Target:** `.task` — `getFavorites()` throws → `favorites` remains `[]`; WARN logged; no toast; row absent
**ADR assertion:** §7 assertion #3 — "`getFavorites()` throws → favoritesRow absent; WARN log; no toast."
**Setup:** `SpeakerStub` with `getFavoritesResult = .failure(MozartError.unreachable)`. Inject `ToastSpy` and a `LogSpy` recording WARN-level messages.
**Action:** Allow `.task` to complete (the `catch` block fires).
**Expected:**
- `favorites` state = `[]` (reset to empty array in the catch block).
- `favoritesRow` is absent (zero height — `favorites.isEmpty == true`).
- `ToastSpy.showErrorToastMessages` is empty (no toast for load failure — silent failure).
- `LogSpy.warnMessages` contains exactly one message matching the pattern `"[<speaker.name>] getFavorites failed: <error>"`.
- `HapticEngineSpy.commandRecognisedCallCount == 0` and `errorOccurredCallCount == 0` (no haptic on load failure).
**Covers spec AC:** US-72 AC-11 (getFavorites failure logged at WARN, row omitted, no toast); ADR §7 assertion #3; spec Error States row "getFavorites() throws on card appear"; lazy load throw path.

---

### TC-E58-U12

**ID:** TC-E58-U12
**Target:** `.task` — re-appear triggers a fresh `getFavorites()` call; stale favorites overwritten atomically
**ADR assertion:** §7 assertion #9 — "Re-appear triggers a fresh fetch."
**Setup:** `SpeakerStub` initially with `getFavoritesResult = .success([morning, dinner])`. `SpeakerCard` appears → `.task` completes → `favorites = [morning, dinner]`. Card then disappears (`.task` is cancelled). Card re-appears. Update `stub.getFavoritesResult = .success([morning, dinner, jazz])` before re-appear.
**Action:** After re-appear, allow the second `.task` to complete.
**Expected:** `stub.getFavoritesCallCount == 2` (second call after re-appear). `favorites` state = `[morning, dinner, jazz]` (updated atomically from the second call). The `favoritesRow` renders 3 pills. The stale 2-item array is no longer visible. The re-fetch replaces the entire array in one `@State` assignment.
**Covers spec AC:** US-72 AC-1 (called once on appear — implies re-appear fires again); ADR §7 assertion #9 ("re-appear triggers a fresh fetch"); ADR §3 Option A rationale ("re-appears refetch acceptable").

---

### TC-E58-U13

**ID:** TC-E58-U13
**Target:** `.task` — cancelled when card disappears before completion; no state mutation after cancellation
**Setup:** `SpeakerStub` with `getFavoritesResult` set to a slow response (200 ms artificial delay via `Task.sleep`). `SpeakerCard` appears and disappears before the 200 ms complete.
**Action:** Measure `stub.getFavoritesCallCount` and `favorites` state after the card has disappeared.
**Expected:** The in-flight `getFavorites()` call is cancelled by the `.task` modifier lifecycle. `favorites` state remains `[]` (no mutation after disappear). No WARN log is emitted for a cancellation-only failure (Swift's `CancellationError` should be swallowed or logged distinctly). No crash. No dangling `Task` retaining `SpeakerCard`.
**Covers spec AC:** US-72 AC-1 (`.task` ensures call is cancelled on disappear); ADR §9 platform constraint (`.task` modifier introduced iOS 15, cancels on disappear).

---

## 5. Integration Test Cases — onFavoriteTapped and showErrorToast

These cases test the `onFavoriteTapped(fav:)` tap handler: synchronous haptic dispatch, `playFavorite(presetIndex: fav.presetIndex)` call with the correct index, error toast on failure, and the WARN/ERROR log distinction.

---

### TC-E58-I01

**ID:** TC-E58-I01
**Target:** `onFavoriteTapped` — `commandRecognised` haptic fires synchronously before `playFavorite` dispatch
**ADR assertion:** §7 assertion #4 — "Tap pill → `HapticEngine.shared.commandRecognised()` fires synchronously; `speaker.playFavorite(presetIndex: fav.presetIndex)` dispatched."
**Setup:** `SpeakerStub` with 3 favorites, `playFavoriteError = nil` (success). Inject `HapticEngineSpy`.
**Action:** Simulate a tap on the "Dinner" pill (index 1, `presetIndex: 2`).
**Expected:**
- `HapticEngineSpy.commandRecognisedCallCount == 1` (fired synchronously on tap — before the async `playFavorite` dispatch completes).
- `stub.playFavoriteCallCount == 1`.
- `stub.lastPlayFavoritePresetIndex == 2` (the `Favorite.presetIndex` field, NOT the array offset 1).
- `HapticEngineSpy.errorOccurredCallCount == 0` (no error).
- `ToastSpy.showErrorToastMessages` is empty.
**Covers spec AC:** US-72 AC-7 (`commandRecognised` fires synchronously on tap); US-72 AC-6 (`playFavorite(presetIndex:)` called once); ADR §7 assertion #4.

---

### TC-E58-I02

**ID:** TC-E58-I02
**Target:** `onFavoriteTapped` — uses `fav.presetIndex` NOT enumeration offset
**ADR assertion:** §7 assertion #10 — "`Favorite.presetIndex` is passed to `playFavorite`, NOT ForEach enumeration offset."
**Setup:** `SpeakerStub` with favorites array `[morning(presetIndex:1), dinner(presetIndex:2), jazz(presetIndex:3)]`. Tap the third pill ("Jazz", array position index 2, `presetIndex: 3`).
**Action:** Simulate tap on "Jazz". Check `stub.lastPlayFavoritePresetIndex`.
**Expected:** `stub.lastPlayFavoritePresetIndex == 3` (the `Favorite.presetIndex` value on the model). NOT `2` (the zero-based enumeration offset). This directly validates the ADR §8 CF-2 correction over the incorrect epics T-5803 snippet.
**Covers spec AC:** ADR §7 assertion #10; ADR §8 CF-2 (presetIndex contract correction).

---

### TC-E58-I03

**ID:** TC-E58-I03
**Target:** `onFavoriteTapped` — uses `fav.presetIndex` for non-sequential preset indices
**Setup:** `SpeakerStub` with favorites array where `presetIndex` values are non-contiguous: `[Favorite(id:"A", displayName:"Morning", presetIndex:1), Favorite(id:"B", displayName:"Jazz", presetIndex:5)]`. (Position 0 has `presetIndex: 1`; position 1 has `presetIndex: 5`, NOT `2`.)
**Action:** Tap the "Jazz" pill (array position 1).
**Expected:** `stub.lastPlayFavoritePresetIndex == 5`. NOT `1` (the array offset). This confirms the model's `presetIndex` drives the call, not any arithmetic on the array position.
**Covers spec AC:** ADR §7 assertion #10; ADR §8 CF-2; MozartClient contract (`POST /playback/preset/{presetIndex}/trigger`).

---

### TC-E58-I04

**ID:** TC-E58-I04
**Target:** `onFavoriteTapped` — `playFavorite` throws → error toast with `UIStrings.couldNotStartFavorite` (EN)
**ADR assertion:** §7 assertion #5 — "`playFavorite` throws → `showErrorToast(ui.couldNotStartFavorite)`; `HapticEngine.shared.errorOccurred()`; `Log.error`."
**Setup:** `SpeakerStub` with `playFavoriteError = MozartError.unreachable`. Inject `ToastSpy`, `HapticEngineSpy`, `LogSpy`. Locale = EN.
**Action:** Tap the "Morning" pill. Wait for the async `Task` inside `onFavoriteTapped` to complete.
**Expected:**
- `ToastSpy.showErrorToastMessages` contains exactly `"Could not start favorite"` (EN string from `UIStrings.couldNotStartFavorite`).
- `HapticEngineSpy.errorOccurredCallCount == 1`.
- `LogSpy.errorMessages` contains exactly one message matching `"[<speaker.name>] playFavorite(1) failed: <error>"`.
- `HapticEngineSpy.commandRecognisedCallCount == 1` (still fired synchronously on tap, before the failure was known).
**Covers spec AC:** US-72 AC-10 (failed `playFavorite` surfaces through existing toast mechanism with `errorOccurred`); ADR §7 assertion #5; spec Error States "Favorite tap fails".

---

### TC-E58-I05

**ID:** TC-E58-I05
**Target:** `onFavoriteTapped` — `playFavorite` throws → error toast uses `UIStrings.couldNotStartFavorite` (DA)
**Setup:** Same as TC-E58-I04, but locale = DA. `UIStrings` should resolve `couldNotStartFavorite = "Kunne ikke starte favorit"`.
**Action:** Tap any pill. Wait for the `Task` to complete.
**Expected:** `ToastSpy.showErrorToastMessages` contains exactly `"Kunne ikke starte favorit"` (DA string from `UIStrings.couldNotStartFavorite`). No EN string appears.
**Covers spec AC:** ADR §5 (`UIStrings` gains `couldNotStartFavorite` with EN/DA localisation); coverage requirement (error toast text uses `UIStrings.couldNotStartFavorite` localised correctly EN/DA).

---

### TC-E58-I06

**ID:** TC-E58-I06
**Target:** `onFavoriteTapped` — `playFavorite` throws → error toast uses `UIStrings.couldNotStartFavorite`, NOT a hardcoded string
**Setup:** Inject a mock `UIStrings` where `couldNotStartFavorite` is set to a sentinel value `"SENTINEL_STRING"`. Trigger a `playFavorite` failure.
**Action:** Check the toast message.
**Expected:** `ToastSpy.showErrorToastMessages` contains `"SENTINEL_STRING"`. This confirms `onFavoriteTapped` calls `showErrorToast(ui.couldNotStartFavorite)` (using the localised strings struct), NOT a hardcoded string literal like `"Could not start favorite"`. If the toast message is hardcoded, this test fails.
**Covers spec AC:** ADR §5 (UIStrings addition); ADR §7 interface contract (`showErrorToast(ui.couldNotStartFavorite)` with the localised reference).

---

### TC-E58-I07

**ID:** TC-E58-I07
**Target:** `onFavoriteTapped` — `playFavorite` throws `MozartError.timeout` → same error path as unreachable
**Setup:** `SpeakerStub` with `playFavoriteError = MozartError.timeout`. Inject spies.
**Action:** Tap a pill. Wait for async completion.
**Expected:** Same outcome as TC-E58-I04 — toast appears, `errorOccurred` fires, error is logged. The error path is consistent regardless of the specific `MozartError` variant (timeout, unreachable, httpError). `commandRecognised` call count remains 1.
**Covers spec AC:** US-72 AC-10; spec Error States "Favorite tap fails (e.g. MozartError.unreachable)" (by extension to timeout).

---

### TC-E58-I08

**ID:** TC-E58-I08
**Target:** `onFavoriteTapped` — `playFavorite` throws `MozartError.httpError(503)` → same error path
**Setup:** `SpeakerStub` with `playFavoriteError = MozartError.httpError(503)`. Inject spies.
**Action:** Tap a pill. Wait for async completion.
**Expected:** Toast = `UIStrings.couldNotStartFavorite` (EN/DA). `errorOccurred` fires once. Log.error contains the error. Consistent with TC-E58-I04.
**Covers spec AC:** US-72 AC-10; spec Error States "Tap play/pause toggle and HTTP 5xx" (by extension to favorites).

---

### TC-E58-I09

**ID:** TC-E58-I09
**Target:** `onFavoriteTapped` — `commandRecognised` fires synchronously (before async `Task` starts)
**ADR assertion:** §7 assertion #4 — "Tap pill → `HapticEngine.shared.commandRecognised()` fires synchronously."
**Setup:** `SpeakerStub` with a slow `playFavorite` response (200 ms delay, success). Inject `HapticEngineSpy` with call-time recording.
**Action:** Tap a pill. Record the timestamp of `commandRecognised` fire. Record the timestamp when `playFavorite` returns.
**Expected:** `commandRecognised` timestamp precedes `playFavorite` completion by ≥ 200 ms. `commandRecognised` fires in the same synchronous call frame as the tap handler — before the `Task { ... }` block completes.
**Covers spec AC:** US-72 AC-7 (`commandRecognised` fires synchronously on tap); design-spec §5.2 (transport and favorite taps fire `commandRecognised`).

---

### TC-E58-I10

**ID:** TC-E58-I10
**Target:** `onFavoriteTapped` — multiple rapid taps on the same pill dispatch multiple `playFavorite` calls
**Setup:** `SpeakerStub` with 200 ms `playFavorite` delay, success. 
**Action:** Simulate 3 rapid taps on the "Morning" pill in quick succession (before any `Task` completes).
**Expected:** `stub.playFavoriteCallCount == 3`. `HapticEngineSpy.commandRecognisedCallCount == 3`. `ToastSpy.showErrorToastMessages` is empty (all succeed). No crash, no deadlock, no assertion failure. The spec does not debounce tap actions — each tap dispatches independently (consistent with E-56 behaviour for play/pause).
**Covers spec AC:** US-72 AC-6 (`playFavorite(presetIndex:)` called exactly once per tap — verified that each tap fires once, not that rapid taps are deduplicated); spec NFR (50 ms dispatch target per tap).

---

## 6. Acceptance Test Cases — Both cardContent Branches; End-to-End

These cases verify the mounting position of `favoritesRow` inside both `cardContent` branches: playing/paused/buffering (below `transportRow`, above `GroupChipRow`) and stopped (below `stoppedPlayPill`). Each scenario drives the full `SpeakerCard` view with a stubbed `Speaker`.

---

### TC-E58-A01

**ID:** TC-E58-A01
**Target:** Playing branch — `favoritesRow` mounts below `transportRow`, above `GroupChipRow`
**ADR assertion:** §7 assertion #7 — "`.playing` state → favoritesRow appears below `transportRow`, above `GroupChipRow`."
**Setup:** `SpeakerStub` in `.playing` state with `getFavoritesResult = .success([morning, dinner, jazz])`. `SpeakerCard` with a non-empty `groupMembers` (so `GroupChipRow` is rendered — verifies the "above GroupChipRow" assertion).
**Action:** Allow `.task` to complete. Inspect the `VStack` order in `cardContent`.
**Expected:** VStack children order (top to bottom):
1. `headerSection`
2. `nowPlayingPanel`
3. `InteractiveVolumeBar` (E-57)
4. `transportRow` (E-56)
5. `favoritesRow` ← NEW (this position)
6. `GroupChipRow` (E-53)
`favoritesRow` is present at position 5. `GroupChipRow` is at position 6 (below). No other view exists between `transportRow` and `favoritesRow`.
**Covers spec AC:** US-72 AC-4 (favorites row shown in playing state); ADR §7 assertion #7; ADR §8 CF-3 (VStack order after E-58); spec Technical Requirements §Component placement.

---

### TC-E58-A02

**ID:** TC-E58-A02
**Target:** Paused branch — `favoritesRow` renders in paused state (same branch as playing)
**ADR assertion:** §7 assertion #7 (by extension to paused state); US-72 AC-4 ("shown in playing, paused, buffering, and stopped states").
**Setup:** `SpeakerStub` in `.paused` state with 3 favorites.
**Action:** Allow `.task` to complete. Inspect `favoritesRow` presence.
**Expected:** `favoritesRow` is rendered in the paused branch. The `transportRow` shows `play.fill` icon (E-56 behaviour). Favorites are visible below the `transportRow`. All pills are `.default` role.
**Covers spec AC:** US-72 AC-4 (favorites row shown in paused state).

---

### TC-E58-A03

**ID:** TC-E58-A03
**Target:** Buffering branch — `favoritesRow` renders in buffering state
**Setup:** `SpeakerStub` in `.buffering` state with 3 favorites.
**Action:** Allow `.task` to complete. Inspect `favoritesRow` presence.
**Expected:** `favoritesRow` rendered. Buffering is part of the playing/paused/buffering branch. All pills `.default` role.
**Covers spec AC:** US-72 AC-4 (favorites row shown in buffering state).

---

### TC-E58-A04

**ID:** TC-E58-A04
**Target:** Stopped branch — `favoritesRow` mounts below `stoppedPlayPill`
**ADR assertion:** §7 assertion #6 — "`.stopped` state → favoritesRow appears below `stoppedPlayPill`."
**Setup:** `SpeakerStub` in `.stopped` state with `getFavoritesResult = .success([morning, dinner, jazz])`.
**Action:** Allow `.task` to complete. Inspect the stopped-branch `VStack` order.
**Expected:** Stopped-branch VStack children order (top to bottom):
1. `headerSection`
2. `stoppedPlayPill` (full-width `DarkGlassButton` with label "Play", `role: .confirm`) (E-56)
3. `favoritesRow` ← NEW
`favoritesRow` is at position 3, below the play pill. No `nowPlayingPanel`, no `InteractiveVolumeBar`, no `transportRow` rendered in this branch.
**Covers spec AC:** US-72 AC-5 (in stopped state, favorites row appears below the full-width Play pill); US-72 AC-4 (favorites shown in stopped state); ADR §7 assertion #6; spec Technical Requirements §Component placement (stopped state layout).

---

### TC-E58-A05

**ID:** TC-E58-A05
**Target:** Stopped branch — tapping a favorite while stopped dispatches `playFavorite` with correct `presetIndex`
**Setup:** `SpeakerStub` in `.stopped` state with 3 favorites. `playFavoriteError = nil`.
**Action:** Allow `.task` to complete. Tap the "Jazz" pill (position 2, `presetIndex: 3`).
**Expected:** `stub.lastPlayFavoritePresetIndex == 3`. `HapticEngineSpy.commandRecognisedCallCount == 1`. No toast. The speaker's `play()` is NOT called (the favorite tap calls `playFavorite`, not `play`). The card transitions to the playing branch when the speaker state updates (driven by WS event — not asserted here; WS layer is out of scope).
**Covers spec AC:** US-72 AC-5 (user can start a specific favorite directly from stopped state); US-72 AC-6 (playFavorite called with correct presetIndex); ADR §7 assertion #6.

---

### TC-E58-A06

**ID:** TC-E58-A06
**Target:** State transition — `favoritesRow` persists across state change from stopped → playing
**Setup:** `SpeakerStub` with 3 favorites. Card appears in `.stopped` state. `.task` completes.
**Action:** Simulate `speaker.playbackState` changing to `.playing` (as if a WS event arrived after tapping the Play pill).
**Expected:** The card re-renders from the stopped branch to the playing/paused/buffering branch. `favoritesRow` remains visible in the new branch (same `@State favorites` array — not cleared on state change). `getFavoritesCallCount` remains 1 (`.task` does not re-fire on state change, only on card re-appear). All 3 pills remain at `.default` role.
**Covers spec AC:** US-72 AC-4 (favorites shown in playing state); ADR §7 assertion #9 (`.task` fires once per appearance — state changes do not re-trigger it).

---

### TC-E58-A07

**ID:** TC-E58-A07
**Target:** End-to-end happy path — card appears in playing state, 3 favorites load, tap "Dinner", speaker changes source
**ADR assertion:** Covers §7 assertions #1, #4, #7, #10 together in a single end-to-end flow.
**Setup:** `SpeakerStub` in `.playing` state with `getFavoritesResult = .success([morning, dinner, jazz])` and `playFavoriteError = nil`. Inject `HapticEngineSpy` and `ToastSpy`.
**Action:**
1. Render `SpeakerCard`. Wait for `.task` to complete.
2. Verify 3 pills are visible.
3. Tap "Dinner" pill.
4. Allow the async `Task` in `onFavoriteTapped` to complete.
**Expected:**
1. `favorites` count = 3. `favoritesRow` renders below `transportRow`.
2. All pills: `role = .default`.
3. `commandRecognisedCallCount == 1` (synchronous on tap).
4. `stub.lastPlayFavoritePresetIndex == 2` (Dinner's `presetIndex`, not array offset 1).
5. `ToastSpy.showErrorToastMessages` is empty (success path).
6. `errorOccurredCallCount == 0`.
**Covers spec AC:** US-72 (all ACs together): AC-1, AC-2, AC-4, AC-6, AC-7, AC-8.

---

### TC-E58-A08

**ID:** TC-E58-A08
**Target:** End-to-end failure path — card appears, 3 favorites load, tap "Jazz", `playFavorite` fails, toast shows
**ADR assertion:** §7 assertion #5 end-to-end.
**Setup:** `SpeakerStub` in `.playing` state with 3 favorites and `playFavoriteError = MozartError.unreachable`. Inject spies. Locale = EN.
**Action:**
1. Render `SpeakerCard`. Wait for `.task`.
2. Tap "Jazz".
3. Wait for `Task` completion.
**Expected:**
1. `commandRecognisedCallCount == 1` (before failure known).
2. `stub.lastPlayFavoritePresetIndex == 3` (Jazz's presetIndex).
3. `ToastSpy.showErrorToastMessages == ["Could not start favorite"]`.
4. `errorOccurredCallCount == 1`.
5. `favoritesRow` remains rendered (the load was already successful; the tap failure does not clear `favorites`).
**Covers spec AC:** US-72 AC-10; ADR §7 assertion #5; spec Error States "Favorite tap fails".

---

## 7. Error States and Boundary Values

This section consolidates boundary-value and error-state coverage not captured as primary assertions in sections 3–6.

---

### TC-E58-E01

**ID:** TC-E58-E01
**Target:** `getFavorites()` returns exactly 0 items → row absent, no placeholder, no "No favorites" text
**Boundary:** Lazy load count = 0.
**Setup:** `SpeakerStub` with `getFavoritesResult = .success([])`. `SpeakerCard` in `.playing` state.
**Action:** Allow `.task` to complete. Inspect full `cardContent` view tree.
**Expected:** No `ScrollView` in `favoritesRow` area. No `Text` reading "No favorites" or similar placeholder. No visible gap or empty space where the row would be (the `@ViewBuilder` emits `EmptyView()` at zero height). Card layout is identical to a card with no `favoritesRow` at all.
**Covers spec AC:** US-72 AC-3 (zero favorites → row absent with no placeholder); spec Resolved Decisions "Favorites empty state"; ADR §7 `favoritesRow` interface ("Empty → EmptyView() — zero height, no placeholder").

---

### TC-E58-E02

**ID:** TC-E58-E02
**Target:** `getFavorites()` throws `MozartError.timeout` → same silent-failure path as unreachable
**Boundary:** Lazy load throw path.
**Setup:** `SpeakerStub` with `getFavoritesResult = .failure(MozartError.timeout)`. Inject `ToastSpy` and `LogSpy`.
**Action:** Allow `.task` to complete.
**Expected:** `favorites = []`. `favoritesRow` absent. WARN log emitted. No toast. Consistent with TC-E58-U11.
**Covers spec AC:** US-72 AC-3 (getFavorites throws → row absent); US-72 AC-11 (logged at WARN, no toast).

---

### TC-E58-E03

**ID:** TC-E58-E03
**Target:** `getFavorites()` returns 1 favorite (minimum non-empty) → row present, 1 pill
**Boundary:** Lazy load count = 1.
**Setup:** `SpeakerStub` with `getFavoritesResult = .success([morning])`.
**Action:** Allow `.task` to complete.
**Expected:** `favoritesRow` rendered. 1 pill, label "Morning", `role = .default`. `ScrollView` present (even with 1 pill — no conditional rendering based on count > 1). Trailing gradient present.
**Covers spec AC:** US-72 AC-2 (at least one favorite → row rendered); boundary value 1.

---

### TC-E58-E04

**ID:** TC-E58-E04
**Target:** `getFavorites()` returns 5 favorites → row present, 5 pills
**Boundary:** Lazy load count = many (5).
**Setup:** `SpeakerStub` with `getFavoritesResult = .success([morning, dinner, jazz, sleep, party])`.
**Action:** Allow `.task` to complete.
**Expected:** `favoritesRow` renders 5 `DarkGlassButton` pills. All `.default` role. Horizontal scroll available. No crash on large count. `favorites` state = array of 5.
**Covers spec AC:** US-72 AC-2; design-spec §4.2 (scroll for more than 3 visible); boundary value "many".

---

### TC-E58-E05

**ID:** TC-E58-E05
**Target:** `UIStrings.couldNotStartFavorite` — EN value is exactly "Could not start favorite"
**Setup:** Access `UIStrings` with locale = EN.
**Action (static):** Inspect `UIStrings.swift` source. Read the EN value of `couldNotStartFavorite`.
**Expected:** EN string = `"Could not start favorite"` (exact match, correct capitalisation, no trailing spaces or period). This is the string shown in the error toast to English users.
**Covers spec AC:** ADR §5 (UIStrings addition, EN value).

---

### TC-E58-E06

**ID:** TC-E58-E06
**Target:** `UIStrings.couldNotStartFavorite` — DA value is exactly "Kunne ikke starte favorit"
**Setup:** Access `UIStrings` with locale = DA.
**Action (static):** Inspect `UIStrings.swift` source. Read the DA value of `couldNotStartFavorite`.
**Expected:** DA string = `"Kunne ikke starte favorit"` (exact match, correct Danish spelling with no accents errors). This matches ADR §5 specification.
**Covers spec AC:** ADR §5 (UIStrings addition, DA value).

---

### TC-E58-E07

**ID:** TC-E58-E07
**Target:** `favoritesRow` absent in stopped state when `getFavorites()` throws
**Boundary:** Throw path in stopped state.
**Setup:** `SpeakerStub` in `.stopped` state with `getFavoritesResult = .failure(MozartError.unreachable)`.
**Action:** Allow `.task` to complete. Inspect stopped-branch `cardContent`.
**Expected:** Stopped branch renders only `headerSection` + `stoppedPlayPill`. `favoritesRow` is absent. No "No favorites" placeholder. No toast. WARN logged. The stopped state layout correctly handles the absent favorites row — `stoppedPlayPill` is the bottom element.
**Covers spec AC:** US-72 AC-3 (throw → row absent); ADR §7 assertion #3 and #6 (stopped + throw combination).

---

### TC-E58-E08

**ID:** TC-E58-E08
**Target:** Tapping multiple different favorites rapidly dispatches each with their own `fav.presetIndex`
**Boundary:** Concurrent dispatches with different `presetIndex` values.
**Setup:** `SpeakerStub` with 3 favorites (presetIndex: 1, 2, 3), 100 ms delay each, no errors.
**Action:** Tap "Morning" (presetIndex:1), then immediately tap "Jazz" (presetIndex:3) before the first `Task` completes.
**Expected:** `stub.playFavoriteCallCount == 2`. The two `lastPlayFavoritePresetIndex` values observed across the two calls are 1 and 3. No shared mutable state collision (each `onFavoriteTapped` call captures its own `fav` value). No crash.
**Covers spec AC:** US-72 AC-6 (each tap calls `playFavorite` exactly once); ADR §7 assertion #4 (each tap dispatches independently).

---

## 8. Coverage Matrix (AC/ER → TC IDs)

| Requirement | Source | TC IDs |
|---|---|---|
| **ADR §7 assertion #1** — 3 items → 3 pills, all `.default` | ADR-E58 §7 | TC-E58-U01, TC-E58-A07 |
| **ADR §7 assertion #2** — 0 items → row absent | ADR-E58 §7 | TC-E58-U02, TC-E58-E01 |
| **ADR §7 assertion #3** — throws → absent; WARN; no toast | ADR-E58 §7 | TC-E58-U11, TC-E58-E02, TC-E58-E07 |
| **ADR §7 assertion #4** — tap → `commandRecognised` sync; `playFavorite(presetIndex: fav.presetIndex)` dispatched | ADR-E58 §7 | TC-E58-I01, TC-E58-I02, TC-E58-I09, TC-E58-A07 |
| **ADR §7 assertion #5** — `playFavorite` throws → toast; `errorOccurred`; `Log.error` | ADR-E58 §7 | TC-E58-I04, TC-E58-I05, TC-E58-A08 |
| **ADR §7 assertion #6** — `.stopped` → row below `stoppedPlayPill` | ADR-E58 §7 | TC-E58-A04, TC-E58-A05, TC-E58-E07 |
| **ADR §7 assertion #7** — `.playing` → row below `transportRow`, above `GroupChipRow` | ADR-E58 §7 | TC-E58-A01 |
| **ADR §7 assertion #8** — all pills `.default` even when matches `nowPlaying` | ADR-E58 §7 | TC-E58-U03 |
| **ADR §7 assertion #9** — `.task` fires once per appear; re-appear refetches | ADR-E58 §7 | TC-E58-U10, TC-E58-U12 |
| **ADR §7 assertion #10** — `fav.presetIndex` NOT offset | ADR-E58 §7 | TC-E58-I02, TC-E58-I03, TC-E58-A05, TC-E58-A07 |
| **ADR §7 assertion #11** — `.accessibilityElement(children: .contain)` on row | ADR-E58 §7 | TC-E58-X01 |
| **ADR §7 assertion #12** — per-pill `.accessibilityLabel = fav.displayName` | ADR-E58 §7 | TC-E58-X02 |
| **CF-1** — `.default` role always (design-spec §4.2 conditional `.confirm` overridden) | ADR-E58 §8 CF-1 | TC-E58-U03 |
| **CF-2** — `ForEach` keyed on `fav.id`, not offset; `fav.presetIndex` not offset | ADR-E58 §8 CF-2 | TC-E58-U04, TC-E58-I02, TC-E58-I03 |
| **US-72 AC-1** — `getFavorites()` called once via `.task` on appear | spec US-72 | TC-E58-U10, TC-E58-U12 |
| **US-72 AC-2** — ≥1 favorite → ScrollView + 1 DarkGlassButton per fav, `.default` role | spec US-72 | TC-E58-U01, TC-E58-U06, TC-E58-E03, TC-E58-E04 |
| **US-72 AC-3** — 0 favorites or throws → row absent | spec US-72 | TC-E58-U02, TC-E58-U11, TC-E58-E01, TC-E58-E02 |
| **US-72 AC-4** — row shown in playing, paused, buffering, stopped states | spec US-72 | TC-E58-A01, TC-E58-A02, TC-E58-A03, TC-E58-A04 |
| **US-72 AC-5** — stopped state: row below full-width Play pill | spec US-72 | TC-E58-A04, TC-E58-A05 |
| **US-72 AC-6** — tap → `playFavorite(presetIndex:)` called exactly once with correct index | spec US-72 | TC-E58-I01, TC-E58-I02, TC-E58-I03 |
| **US-72 AC-7** — `commandRecognised` fires synchronously on tap | spec US-72 | TC-E58-I01, TC-E58-I09 |
| **US-72 AC-8** — all favorites always `.default` role (no `.confirm` highlight) | spec US-72 | TC-E58-U03 |
| **US-72 AC-9** — VoiceOver reads each button as `fav.displayName`, no suffix | spec US-72 | TC-E58-X02 |
| **US-72 AC-10** — failed `playFavorite` → toast + `errorOccurred` | spec US-72 | TC-E58-I04, TC-E58-I05, TC-E58-I07, TC-E58-A08 |
| **US-72 AC-11** — failed `getFavorites()` → WARN log; row omitted; no toast | spec US-72 | TC-E58-U11, TC-E58-E02, TC-E58-E07 |
| **Lazy load — count 0** | Coverage req. | TC-E58-U02, TC-E58-E01 |
| **Lazy load — count 1** | Coverage req. | TC-E58-U06, TC-E58-E03 |
| **Lazy load — count 5** | Coverage req. | TC-E58-U07, TC-E58-E04 |
| **Lazy load — throw path → empty + WARN** | Coverage req. | TC-E58-U11, TC-E58-E02 |
| **Empty-state: ZERO height, no placeholder, no label** | Coverage req. | TC-E58-U02, TC-E58-E01 |
| **Role: ALL pills `.default` (never `.confirm`)** | Coverage req. | TC-E58-U03 |
| **Tap: `commandRecognised` + `playFavorite(presetIndex: fav.presetIndex)`** | Coverage req. | TC-E58-I01, TC-E58-I02, TC-E58-I09 |
| **Error toast uses `UIStrings.couldNotStartFavorite` EN** | Coverage req. | TC-E58-I04, TC-E58-E05 |
| **Error toast uses `UIStrings.couldNotStartFavorite` DA** | Coverage req. | TC-E58-I05, TC-E58-E06 |
| **Playing branch: row below `transportRow` above `GroupChipRow`** | Coverage req. | TC-E58-A01 |
| **Stopped branch: row below `stoppedPlayPill`** | Coverage req. | TC-E58-A04 |
| **Accessibility: row `.accessibilityElement(children: .contain)`** | Coverage req. | TC-E58-X01 |
| **Accessibility: per-pill `.accessibilityLabel = fav.displayName`** | Coverage req. | TC-E58-X02 |
| **ForEach keyed on `fav.id` (scene UUID), not offset** | Coverage req. | TC-E58-U04 |
| **`.task` re-fires on re-appear (acceptable; verifies lifecycle)** | Coverage req. | TC-E58-U12 |
| **UIStrings EN exact value** | ADR §5 | TC-E58-E05 |
| **UIStrings DA exact value** | ADR §5 | TC-E58-E06 |
| **Trailing fade gradient mask** | design-spec §4.2 | TC-E58-U05 |
| **`.fixedSize()` per pill** | ADR §7 contract | TC-E58-U09 |
| **Design tokens: `Spacing.s8`, `Spacing.s24`, `Spacing.s20`** | ADR §2 token-lock | TC-E58-U08 |

---

## 9. Accessibility Test Cases

### TC-E58-X01

**ID:** TC-E58-X01
**Target:** `favoritesRow` — `ScrollView` has `.accessibilityElement(children: .contain)`
**ADR assertion:** §7 assertion #11 — "`favoritesRow` is `.accessibilityElement(children: .contain)` — VoiceOver navigates each pill."
**Setup:** `SpeakerStub` with 3 favorites. `SpeakerCard` rendered with VoiceOver enabled (or Accessibility Inspector).
**Action (static):** Code review `SpeakerCard.swift` — confirm `.accessibilityElement(children: .contain)` is applied to the `ScrollView` inside `favoritesRow` (matching ADR §7 interface contract).
**Action (device):** With VoiceOver on, navigate the card. Verify that each pill is a separate VoiceOver focus target (swipe right moves focus from pill to pill), not a single "scroll view with N items" announcement.
**Expected (static):** `.accessibilityElement(children: .contain)` modifier present on the `ScrollView`. Not `.accessibilityElement(children: .ignore)` (which would hide pills) or absent (which may not expose individual pills through the scroll container).
**Expected (device):** VoiceOver can navigate to each individual pill by swiping. Focus moves header → nowPlayingPanel → volumeBar → transportRow → favoritesRow pill 1 → pill 2 → pill 3 → GroupChipRow (in playing state).
**Covers spec AC:** US-72 AC-9 (VoiceOver reads each button); ADR §7 assertion #11; design-spec §7 (all buttons expose `accessibilityLabel`).

---

### TC-E58-X02

**ID:** TC-E58-X02
**Target:** Each `DarkGlassButton` — `accessibilityLabel = fav.displayName`, no suffix
**ADR assertion:** §7 assertion #12 — "`DarkGlassButton` accessibility label = `fav.displayName` with no suffix."
**Setup:** 3 favorites: "Morning", "Dinner", "Jazz". `speaker.nowPlaying.primaryLine = "Morning"` (to verify no active suffix is added per UQ-1).
**Action:** Inspect `accessibilityLabel` on each pill via Accessibility Inspector or XCUITest `.accessibilityLabel` property.
**Expected:**
- Pill 1: `accessibilityLabel == "Morning"` (exactly — no " (playing)" or " (active)" suffix).
- Pill 2: `accessibilityLabel == "Dinner"`.
- Pill 3: `accessibilityLabel == "Jazz"`.
No suffix is appended regardless of whether the favorite matches `speaker.nowPlaying` (UQ-1: active-favorite highlight not implemented — design-spec Appendix B `a11y.favoritePlaying` is explicitly removed).
**Covers spec AC:** US-72 AC-9 (VoiceOver reads as display name, no active-playing suffix); ADR §7 assertion #12; design-spec §7 and Appendix B (`a11y.favoritePlaying` removed at UQ-1).

---

### TC-E58-X03

**ID:** TC-E58-X03
**Target:** VoiceOver navigation order — card header before favorites pills; GroupChipRow after favorites
**Setup:** `SpeakerStub` in `.playing` state with 3 favorites and non-empty group members. VoiceOver enabled.
**Action:** Navigate the full `SpeakerCard` in sequence by swiping right with VoiceOver.
**Expected:** Navigation order (per ADR §7 accessibility section, design-spec §7, spec Accessibility): header → nowPlayingPanel → volumeBar → transportRow pause/play button → favoritesRow pill 1 → pill 2 → pill 3 → GroupChipRow chip(s). `favoritesRow` pills appear between `transportRow` and `GroupChipRow` in VoiceOver traversal order, matching the visual top-to-bottom layout.
**Covers spec AC:** design-spec §7 (VoiceOver order within card); ADR §7 assertion #11.

---

### TC-E58-X04

**ID:** TC-E58-X04
**Target:** Accessibility — favorites row absent when `getFavorites()` throws (VoiceOver not misled)
**Setup:** `SpeakerStub` with `getFavoritesResult = .failure(MozartError.unreachable)`. VoiceOver on.
**Action:** Navigate the `SpeakerCard` with VoiceOver.
**Expected:** VoiceOver does not announce any element in the favorites row area. Navigation jumps from `transportRow` to `GroupChipRow` (or end of card) without any empty-container focus stop. There is no phantom focus target for the hidden row.
**Covers spec AC:** US-72 AC-3 (row absent on throw — accessibility correctly reflects this absence).

---

## 10. Spec Gaps Discovered

The following gaps and inconsistencies were identified during preparation of this test plan. They do not block implementation but should be resolved or acknowledged.

### SG-1 — Epics T-5803 `presetIndex` vs `fav.presetIndex` inconsistency (documented; superseded)

`epics-and-tasks-touch-playback-controls.md T-5803` uses `presetIndex: index` (enumeration offset). `ADR-E58-favorites-row.md §8 CF-2` identifies this as incorrect and mandates `fav.presetIndex`. `ADR §7` and `spec-touch-playback-controls.md` US-72 AC-6 both state the index "matching that favorite's position in the returned array" — which in context means the `Favorite` model's own `presetIndex` field (1-based, set by `MozartClient.getFavorites()` as `offset + 1`). The ADR supersedes the epics doc. **TC-E58-I02 and TC-E58-I03 are the authoritative regression tests for this contract.**

### SG-2 — `spec-touch-playback-controls.md` US-72 AC-6 ambiguous phrasing

US-72 AC-6 reads: "Tapping a favorite calls `speaker.playFavorite(presetIndex:)` exactly once with the index matching that favorite's position in the returned array." The phrase "position in the returned array" is ambiguous — it could mean zero-based offset or the `Favorite.presetIndex` field. The ADR §8 CF-2 correction clarifies that `fav.presetIndex` (the model field) is the correct interpretation. Recommend amending US-72 AC-6 to: "...with `presetIndex: fav.presetIndex` (the 1-based Mozart preset index stored on the `Favorite` model, NOT the array enumeration offset)."

### SG-3 — `spec-touch-playback-controls.md` Technical Requirements §Favorites row wiring contract uses incorrect snippet

The spec's §Favorites row wiring contract section reproduces the same incorrect `ForEach(Array(favorites.enumerated()), id: \.offset)` pattern as the epics doc (inherited from the same draft). This should be updated to `ForEach(favorites) { fav in ... }` with `speaker.playFavorite(presetIndex: fav.presetIndex)` to be consistent with ADR §8 CF-2.

### SG-4 — `.task` cancellation behaviour on `MozartError.cancelled` not specified

The spec and ADR do not distinguish between a `Task.cancel()`-triggered `CancellationError` (benign — card disappeared) and a genuine `MozartError` thrown by `getFavorites()`. The current `.task` catch block logs at WARN for both, which may produce spurious WARN logs on normal navigation. Recommend the catch block check for `CancellationError` and suppress the WARN log in that case. Not blocking for v1.4 — logged as a future refinement.

### SG-5 — No UI test coverage for `AccessibilityNotification` in E-58

Unlike E-57 which uses `AccessibilityAnnouncementSpy` for volume limit announcements, E-58 introduces no new `AccessibilityNotification` announcements. TC-E58-X01 through TC-E58-X04 rely on Xcode Accessibility Inspector or VoiceOver device testing. No spy infrastructure is needed for E-58 accessibility tests.

### SG-6 — `UIStrings` struct shape not specified

ADR §7 adds `var couldNotStartFavorite: String` to `UIStrings`. The current `UIStrings` struct shape (e.g. whether it is a `struct` with locale-switching or a simple `enum` with computed properties) is not documented in the ADR or spec. Test plans TC-E58-I05, TC-E58-E05, TC-E58-E06 assume locale switching is possible at runtime for test purposes. If `UIStrings` uses a static locale snapshot, DA tests must run in a DA-locale simulator. Implementer should document the `UIStrings` resolution mechanism in the PR.

---

## 11. Tests Deferred to Manual Device Verification

The following test cases require a physical Mozart speaker with configured presets and cannot be automated without a device or a live Mozart API stub:

| Deferred Item | Rationale | Corresponding Task |
|---|---|---|
| T-5805 Manual test matrix item 1: favorites row populates within ~500 ms | Requires live `/scenes` endpoint response timing. | T-5805 |
| T-5805 Manual test matrix item 2: tap favorite → speaker switches source within ~2 s | Requires live `POST /playback/preset/{id}/trigger` and WS state event. | T-5805 |
| T-5805 Manual test matrix item 3: tap another favorite without issue | Requires sequential live API calls. | T-5805 |
| T-5805 Manual test matrix item 4: tap favorite from stopped state → card transitions to playing | Requires live state transition via WS. | T-5805 |
| T-5805 Manual test matrix item 5: disconnected speaker → tap favorite → error toast + haptic | Requires simulated network disconnect on device. | T-5805 |
| T-5805 Manual test matrix item 6: speaker with zero presets → row absent | Requires a Mozart speaker with no scenes configured. | T-5805 |
| T-5805 Manual test matrix item 7: `getSources()` returns error → row absent + WARN | Requires a Mozart speaker returning a non-2xx on `/scenes`. | T-5805 |
| T-5805 Manual test matrix item 8: VoiceOver navigation of row on device | Requires physical VoiceOver interaction on device. | T-5804, T-5805 |
| T-5806 SwiftUI preview visual verification | Requires visual inspection of preview canvas against design-spec §4.2. | T-5806 |
| Haptic pattern feel for `commandRecognised` on favorite tap | Physical haptic feedback quality is subjective and requires device. | T-5805 |
