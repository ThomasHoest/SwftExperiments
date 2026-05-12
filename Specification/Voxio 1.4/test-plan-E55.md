# Test Plan — E-55 Discovery and Offline States

**Status:** Draft
**Date:** 2026-05-12
**Refs:** ADR-E55-discovery-offline-states.md, spec-home-screen-redesign.md US-63/US-64/US-65/US-66, design-spec-home-screen-redesign.md §4/§5, epics-and-tasks-home-screen-redesign.md E-55

---

## 1. Scope

This plan covers the testable interface contract introduced by E-55: the `NetworkMonitor` `@Observable @MainActor` class and its `pathUpdateHandler` main-actor hop; the `HomeState` four-case enum and its derivation from `(network.isOnWifi, discovery.didSettle, discoveredSpeakerCount)`; the `DiscoveryStateView` three-branch rendering including the 10-second "Still looking…" timer and the accessibility announcement guard; the `PulseRingsView` Reduce Motion variant; the `ConnectionStatusChip` rewrite with its private `ChipState` enum and the degenerate `connected(0)` edge case; `SpeakerDiscoveryService.restart()` and `MdnsDiscovery.reset()` synchronous clearing; the `scheduleAutoRetry` 30-second `Task` and its cancellation contract; and the `HomeView` offline gating of `voiceFeedback`, `SpeakerSelectorPill`, and `startListening`.

Every ADR §7 behavioural assertion, every AC from US-63, US-64, US-65, and US-66, and the full `HomeState` transition matrix are covered by at least one TC.

What is out of scope:

- E-52 session card strip internals (covered by `test-plan-E52.md`).
- E-53 group chip row (covered by `test-plan-E53.md`).
- E-54 bottom bar `PlaybackBars` and connector line (covered by `test-plan-E54.md`).
- F1 touch playback controls and F2 multiroom drag-and-drop — both operate entirely within the `.hasContent` branch and are unaffected by E-55.
- Backend, telemetry, CI/CD.
- The `NWPathMonitor` OS-level callbacks on real hardware (deferred to manual verification T-5515).

---

## 2. Test Environment

| Item | Value |
|---|---|
| Platform | iOS 26, iPhone (portrait) |
| Framework | SwiftUI, `@Observable @MainActor`, `Network.framework` |
| Test harness | XCTest (unit) + XCUITest (UI/acceptance) — no separate test target exists in the repo at plan-authoring time. Unit tests belong in a new `VoxioTests` target; UI tests in `VoxioUITests`. |
| Accessibility testing | Xcode Accessibility Inspector + VoiceOver on device/simulator |
| Reduce Motion | iOS Settings → Accessibility → Motion → Reduce Motion |
| Network doubles | `NetworkMonitorStub: @Observable @MainActor` — exposes `var isOnWifi: Bool` and `var isAvailable: Bool` as directly writable properties; replaces the real `NWPathMonitor` for unit and integration tests. |
| Discovery doubles | `SpeakerDiscoveryServiceStub` — exposes writable `didSettle: Bool`, `allSpeakers: [Speaker]`, and `groups: [SpeakerGroup]`; a `restartCallCount: Int` counter; satisfies the `@MainActor ObservableObject` contract. |
| Source files under test | `iOS/Voxio/Core/Discovery/NetworkMonitor.swift`, `iOS/Voxio/Core/Discovery/SpeakerDiscoveryService.swift`, `iOS/Voxio/Core/Discovery/MdnsDiscovery.swift`, `iOS/Voxio/Features/Home/HomeView.swift`, `iOS/Voxio/Features/Home/DiscoveryStateView.swift`, `iOS/Voxio/Features/Home/PulseRingsView.swift`, `iOS/Voxio/Features/Home/ConnectionStatusChip.swift`, `iOS/Voxio/Core/Strings/DiscoveryStrings.swift` |
| `HomeState` visibility | ADR §8 CF-6 notes `HomeState` is `private` to `HomeView`. Where unit assertions require direct instantiation, promote to `internal` and extract to a separate file. Tests that cannot access `HomeState` directly assert via `DiscoveryStateView(state:)` which is the testable seam per CF-6. |

---

## 3. Unit-Level Test Cases (NetworkMonitor + HomeState transitions)

These cases test the `NetworkMonitor` observable and the `HomeState` computed property logic in isolation. `HomeState` is exercised by constructing the three inputs `(isOnWifi, didSettle, speakerCount)` and asserting which enum case is returned (or which branch `DiscoveryStateView` renders).

---

### TC-E55-U01

**ID:** TC-E55-U01
**Target:** `NetworkMonitor` — default values avoid offline-state flash
**Setup:** Instantiate `NetworkMonitor()` without calling `start()`.
**Action:** Read `isOnWifi` and `isAvailable` immediately after construction.
**Expected:** `isOnWifi == true` and `isAvailable == true`. The defaults must not be `false` — a `false` default would briefly flash the offline state in `HomeView` during the window between view mount and the first `NWPathMonitor` callback (per ADR §2 Context and T-5501 requirement).
**Covers ADR contract assertion:** §7 `NetworkMonitor` — "defaults to `true` to avoid an offline-state flash"
**Covers spec AC:** US-65 AC-1 (offline state shown only when `NWPathMonitor` explicitly reports no Wi-Fi)

---

### TC-E55-U02

**ID:** TC-E55-U02
**Target:** `NetworkMonitor` — `update(from:)` sets `isOnWifi` correctly for Wi-Fi path
**Setup:** Obtain a `NWPath` stub where `path.status == .satisfied` and `path.usesInterfaceType(.wifi) == true`. Call `monitor.update(from: path)` (or the equivalent internal path via the `pathUpdateHandler` forwarding).
**Action:** Read `isOnWifi` and `isAvailable` after the update.
**Expected:** `isOnWifi == true`, `isAvailable == true`. Both properties must be set on `@MainActor`. The test must call `update(from:)` on the main actor (use `await MainActor.run { ... }` in async test context).
**Covers ADR contract assertion:** §7 `NetworkMonitor` — `isOnWifi = path.status == .satisfied && path.usesInterfaceType(.wifi)`
**Covers spec AC:** US-65 AC-1 (Wi-Fi status drives the home-screen state machine)

---

### TC-E55-U03

**ID:** TC-E55-U03
**Target:** `NetworkMonitor` — `update(from:)` sets `isOnWifi = false` for cellular-only path
**Setup:** Obtain a `NWPath` stub where `path.status == .satisfied` and `path.usesInterfaceType(.wifi) == false` (cellular only). Call `monitor.update(from: path)`.
**Action:** Read `isOnWifi`.
**Expected:** `isOnWifi == false`. `isAvailable == true` (cellular is still a satisfied path, but the app treats cellular-only as offline because B&O speakers require LAN). The app does not distinguish "cellular" from "truly offline" — both produce `isOnWifi == false` and therefore the `.offline` `HomeState`.
**Covers ADR contract assertion:** §7 `NetworkMonitor` — `isOnWifi` false for cellular
**Covers spec AC:** US-65 AC-1; spec-home-screen-redesign.md §Network state table (cellular → `isOnWifi == false`)

---

### TC-E55-U04

**ID:** TC-E55-U04
**Target:** `NetworkMonitor` — `update(from:)` hops to `@MainActor`
**Setup:** Inspect the `pathUpdateHandler` implementation in `NetworkMonitor.start()` via code review or by verifying `update(from:)` is always called inside `Task { @MainActor in ... }`.
**Action:** Confirm that `monitor.pathUpdateHandler = { [weak self] path in Task { @MainActor in self?.update(from: path) } }` (or equivalent) is present, and that `update(from:)` itself is declared `@MainActor` (or called within a main-actor `Task`).
**Expected:** The `DispatchQueue(label: "com.voxio.networkmonitor")` background queue is used only for monitoring; all property mutations (`isOnWifi`, `isAvailable`) occur on the main actor. This is a code-review assertion verifiable via `@testable import Voxio` and the Swift concurrency checker (enable `SWIFT_STRICT_CONCURRENCY = complete`). No data race warnings must be emitted.
**Covers ADR contract assertion:** §7 `NetworkMonitor` — "Background queue + `Task { @MainActor in ... }` hop"
**Covers spec AC:** ADR §5 Consequences — actor isolation requirement for NetworkMonitor

---

### TC-E55-U05

**ID:** TC-E55-U05
**Target:** `HomeState` — `!isOnWifi` wins over all other conditions
**Setup:** Use `NetworkMonitorStub(isOnWifi: false)` and `SpeakerDiscoveryServiceStub(didSettle: true, speakerCount: 5)`. Compute `homeState` (or render `HomeView` with these stubs and inspect which branch of `cardArea` is active).
**Action:** Read the resulting `HomeState`.
**Expected:** `homeState == .offline`. Even though `didSettle == true` and `speakerCount > 0`, the `!isOnWifi` guard is hit first and returns `.offline` immediately. The priority order is: `!isOnWifi` → `.offline`; `speakerCount > 0` → `.hasContent`; `didSettle` → `.noSpeakersFound`; else → `.discovering`.
**Covers ADR contract assertion:** §7 `HomeState` — "State priority: `!isOnWifi` wins over everything"
**Covers spec AC:** US-65 AC-1; design-spec §5.2 state machine table row (`isOnWifi == false` → Offline regardless of other inputs)

---

### TC-E55-U06

**ID:** TC-E55-U06
**Target:** `HomeState` — `speakerCount > 0` wins over `didSettle` (first speaker found mid-scan)
**Setup:** `isOnWifi: true`, `didSettle: false`, `speakerCount: 1`.
**Action:** Compute `homeState`.
**Expected:** `homeState == .hasContent`. The `speakerCount > 0` check runs before the `didSettle` check. The first speaker found during the pre-settle window immediately transitions the UI to `.hasContent`, not to `.noSpeakersFound`. This matches ADR §7: "if `discoveredSpeakerCount > 0 { return .hasContent }` before `if discovery.didSettle { return .noSpeakersFound }`".
**Covers ADR contract assertion:** §7 `HomeState` — "`speakerCount > 0` wins over settle state"
**Covers spec AC:** US-63 AC-5 ("When the first speaker resolves, the discovery UI cross-fades to the normal home screen")

---

### TC-E55-U07

**ID:** TC-E55-U07
**Target:** `HomeState` — `.discovering` when on Wi-Fi, not settled, zero speakers
**Setup:** `isOnWifi: true`, `didSettle: false`, `speakerCount: 0`.
**Action:** Compute `homeState`.
**Expected:** `homeState == .discovering`. This is the nominal pre-settle state immediately after view mount on a healthy Wi-Fi network.
**Covers ADR contract assertion:** §7 `HomeState` — `case discovering: // isOnWifi && !didSettle && speakerCount == 0`
**Covers spec AC:** US-63 AC-1 (pre-settle discovery UI shown)

---

### TC-E55-U08

**ID:** TC-E55-U08
**Target:** `HomeState` — `.noSpeakersFound` when on Wi-Fi, settled, zero speakers
**Setup:** `isOnWifi: true`, `didSettle: true`, `speakerCount: 0`.
**Action:** Compute `homeState`.
**Expected:** `homeState == .noSpeakersFound`. The state machine reaches this after `didSettle` fires with no discovered speakers.
**Covers ADR contract assertion:** §7 `HomeState` — `case noSpeakersFound: // isOnWifi && didSettle && speakerCount == 0`
**Covers spec AC:** US-64 AC-1 (post-settle empty state shown)

---

### TC-E55-U09

**ID:** TC-E55-U09
**Target:** `HomeState` — `layoutKey` returns distinct strings for all four cases
**Setup:** Construct each of the four `HomeState` values: `.offline`, `.discovering`, `.noSpeakersFound`, `.hasContent`.
**Action:** Read `layoutKey` for each.
**Expected:** The four keys are `"offline"`, `"discovering"`, `"noSpeakersFound"`, and `"hasContent"` — all distinct. No two cases produce the same key. This ensures the `.animation(BeoAnimation.toast, value: homeState.layoutKey)` modifier in `HomeView` fires on every state transition and never spuriously fires when the state is unchanged.
**Covers ADR contract assertion:** §7 `HomeState.layoutKey` — four distinct string values
**Covers spec AC:** design-spec §4.4 / §5.4 — cross-fades fire on all state transitions

---

### TC-E55-U10

**ID:** TC-E55-U10
**Target:** `HomeState` — transition matrix: offline → discovering on Wi-Fi restore
**Setup:** Start with `isOnWifi: false` → `homeState == .offline`. Then flip `isOnWifi = true` with `didSettle: false`, `speakerCount: 0`.
**Action:** Re-compute `homeState` after the flip.
**Expected:** `homeState == .discovering`. The state machine does not skip discovering and jump directly to `.noSpeakersFound` — `didSettle` is reset to `false` by `SpeakerDiscoveryService.restart()` which is called from the `.onChange(of: network.isOnWifi)` handler (or from HomeView's lifecycle) when Wi-Fi is restored.
**Covers ADR contract assertion:** §7 `HomeState` transition matrix — offline → discovering
**Covers spec AC:** US-65 AC-7 ("When Wi-Fi restored, offline UI cross-fades to the discovery UI"); US-65 AC-8 ("Discovery starts automatically")

---

### TC-E55-U11

**ID:** TC-E55-U11
**Target:** `HomeState` — transition matrix: discovering → hasContent (first speaker found)
**Setup:** Start with `isOnWifi: true`, `didSettle: false`, `speakerCount: 0` → `homeState == .discovering`. Then set `speakerCount = 1`.
**Action:** Re-compute `homeState`.
**Expected:** `homeState == .hasContent`. Transition is immediate — does not wait for `didSettle`.
**Covers ADR contract assertion:** §7 `HomeState` — `speakerCount > 0` wins over settle state
**Covers spec AC:** US-63 AC-5

---

### TC-E55-U12

**ID:** TC-E55-U12
**Target:** `HomeState` — transition matrix: discovering → noSpeakersFound (settle fires empty)
**Setup:** Start with `isOnWifi: true`, `didSettle: false`, `speakerCount: 0` → `homeState == .discovering`. Then set `didSettle = true` (with `speakerCount` remaining 0).
**Action:** Re-compute `homeState`.
**Expected:** `homeState == .noSpeakersFound`.
**Covers ADR contract assertion:** §7 `HomeState` transition matrix — discovering → noSpeakersFound
**Covers spec AC:** US-64 AC-1

---

### TC-E55-U13

**ID:** TC-E55-U13
**Target:** `HomeState` — transition matrix: noSpeakersFound → discovering (Search Again / restart)
**Setup:** Start with `isOnWifi: true`, `didSettle: true`, `speakerCount: 0` → `homeState == .noSpeakersFound`. Simulate `restart()` by setting `didSettle = false`.
**Action:** Re-compute `homeState`.
**Expected:** `homeState == .discovering`. After `restart()`, `didSettle` is synchronously reset to `false`, so the state machine returns `.discovering` in the very next SwiftUI evaluation cycle.
**Covers ADR contract assertion:** §7 `SpeakerDiscoveryService` — "After restart(): didSettle == false, groups.isEmpty == true → homeState becomes .discovering"
**Covers spec AC:** US-64 AC-3 ("Search Again triggers restart and transitions back to pre-settle UI")

---

### TC-E55-U14

**ID:** TC-E55-U14
**Target:** `HomeState` — transition matrix: noSpeakersFound → offline (Wi-Fi drops)
**Setup:** Start with `isOnWifi: true`, `didSettle: true`, `speakerCount: 0` → `homeState == .noSpeakersFound`. Then set `isOnWifi = false`.
**Action:** Re-compute `homeState`.
**Expected:** `homeState == .offline`. The `!isOnWifi` guard fires first regardless of `didSettle` or `speakerCount`.
**Covers ADR contract assertion:** §7 `HomeState` — `!isOnWifi` wins over everything
**Covers spec AC:** US-65 AC-1

---

### TC-E55-U15

**ID:** TC-E55-U15
**Target:** `HomeState` — transition matrix: hasContent → offline (Wi-Fi drops mid-session)
**Setup:** Start with `isOnWifi: true`, `didSettle: true`, `speakerCount: 2` → `homeState == .hasContent`. Then set `isOnWifi = false`.
**Action:** Re-compute `homeState`.
**Expected:** `homeState == .offline`. The cached `groups` array may still hold two speakers, but `isOnWifi == false` takes priority and returns `.offline`. The `discoveredSpeakerCount > 0` check is never reached. The bottom bar must be hidden (per ADR §5 Consequences CF-5 and US-65 AC-3).
**Covers ADR contract assertion:** §7 `HomeState` — `!isOnWifi` wins; ADR §5 CF-5 (offline with cached speakers → bar hidden)
**Covers spec AC:** US-65 AC-3 (bottom bar hidden in offline state); spec-home-screen-redesign.md error states "Wi-Fi drops while speakers are playing"

---

### TC-E55-U16

**ID:** TC-E55-U16
**Target:** `HomeState` — transition matrix: hasContent → noSpeakersFound (all speakers removed)
**Setup:** Start with `isOnWifi: true`, `didSettle: true`, `speakerCount: 2` → `homeState == .hasContent`. Then set `speakerCount = 0` (all speakers removed, `didSettle` remains `true`).
**Action:** Re-compute `homeState`.
**Expected:** `homeState == .noSpeakersFound`. The `didSettle == true && speakerCount == 0` branch fires. The UI must show the post-settle empty state with the "Search again" button.
**Covers ADR contract assertion:** §7 `HomeState` transition matrix — hasContent → noSpeakersFound
**Covers spec AC:** spec-home-screen-redesign.md error states "All speakers disappear post-discovery"

---

## 4. Unit-Level Test Cases (ConnectionStatusChip ChipState)

These cases test `ConnectionStatusChip` in isolation by constructing it with explicit `isOnWifi`, `didSettle`, and `speakerCount` inputs and asserting on the rendered content or the private `ChipState` value (accessible via `@testable import Voxio`).

---

### TC-E55-C01

**ID:** TC-E55-C01
**Target:** `ConnectionStatusChip` — `ChipState.offline` when `isOnWifi == false`
**Setup:** Instantiate `ConnectionStatusChip(isOnWifi: false, didSettle: true, speakerCount: 5)`.
**Action:** Inspect the rendered symbol and label text (or read `chipState` via `@testable import`).
**Expected:** `chipState == .offline`. Symbol is `wifi.slash`. Label text is `strings.chipNoWifi` ("No Wi-Fi" / "Ingen Wi-Fi"). Chip uses `BeoColor.muted` (secondary) text colour per ADR §7. The `speakerCount` of 5 is ignored — `!isOnWifi` evaluates to `.offline` before the `didSettle` check.
**Covers ADR contract assertion:** §7 `ConnectionStatusChip` — `guard isOnWifi else { return .offline }`
**Covers spec AC:** US-66 AC-2 ("No Wi-Fi" when `isOnWifi == false`)

---

### TC-E55-C02

**ID:** TC-E55-C02
**Target:** `ConnectionStatusChip` — `ChipState.searching` when on Wi-Fi and not settled
**Setup:** `ConnectionStatusChip(isOnWifi: true, didSettle: false, speakerCount: 0)`.
**Action:** Inspect `chipState`, symbol, and label.
**Expected:** `chipState == .searching`. Symbol is `wifi`. Label is `strings.chipSearching` ("Searching…" / "Søger…"). Colour is `BeoColor.muted`.
**Covers ADR contract assertion:** §7 `ConnectionStatusChip` — `guard didSettle else { return .searching }`
**Covers spec AC:** US-66 AC-1 ("Searching…" when `isOnWifi == true && didSettle == false`)

---

### TC-E55-C03

**ID:** TC-E55-C03
**Target:** `ConnectionStatusChip` — `ChipState.connected(n)` when settled with speakers
**Setup:** `ConnectionStatusChip(isOnWifi: true, didSettle: true, speakerCount: 3)`.
**Action:** Inspect `chipState`, symbol, and label.
**Expected:** `chipState == .connected(3)`. Symbol is `wifi`. Label renders the integer `"3"` (the existing number-only display for parity per US-66 AC-2). Colour is green (the existing connected colour).
**Covers ADR contract assertion:** §7 `ConnectionStatusChip` — `return .connected(speakerCount)`
**Covers spec AC:** US-66 AC-1 ("n speakers" when `isOnWifi == true && didSettle == true`)

---

### TC-E55-C04

**ID:** TC-E55-C04
**Target:** `ConnectionStatusChip` — degenerate `connected(0)` renders "0" with wifi symbol (not "No Wi-Fi")
**Setup:** `ConnectionStatusChip(isOnWifi: true, didSettle: true, speakerCount: 0)`.
**Action:** Inspect `chipState`, symbol, and label.
**Expected:** `chipState == .connected(0)`. Symbol is `wifi` (not `wifi.slash`). Label renders `"0"`. This is the correct post-settle-zero behaviour per ADR §7 and US-66 AC-3: "if Wi-Fi is up but no speakers were found, the chip shows '0 speakers' (a degenerate case of the n-speakers form)." The chip does NOT show "No Wi-Fi" in this case, because `isOnWifi == true`.
**Covers ADR contract assertion:** §7 `ConnectionStatusChip` — "Edge case: isOnWifi && didSettle && speakerCount == 0 → .connected(0) — renders '0' with wifi symbol (not 'No Wi-Fi')"
**Covers spec AC:** US-66 AC-3 (degenerate post-settle-zero case)

---

### TC-E55-C05

**ID:** TC-E55-C05
**Target:** `ConnectionStatusChip` — `accessibilityLabel` per state
**Setup:** Instantiate the chip for each of the three states.
**Action:** Read `.accessibilityLabel` from each rendered chip via the accessibility element tree.
**Expected:**
- `.searching` → `"Searching for speakers"` (strings.a11y.chipSearching)
- `.offline` → `"No Wi-Fi connection"` (strings.a11y.chipOffline)
- `.connected(n)` → existing "n speaker(s) connected" string (unchanged from v1.3)
The chip remains `.accessibilityElement(children: .ignore)` in all states.
**Covers ADR contract assertion:** §7 `ConnectionStatusChip` accessibility labels
**Covers spec AC:** US-66 AC-5 ("VoiceOver label per design spec §5.5")

---

### TC-E55-C06

**ID:** TC-E55-C06
**Target:** `ConnectionStatusChip` — chip copy updates within one animation frame of state change
**Setup:** Render `ConnectionStatusChip(isOnWifi: true, didSettle: false, speakerCount: 0)` (searching state). Allow the view to render.
**Action:** Flip `didSettle = true`. Allow one SwiftUI update cycle.
**Expected:** The chip label transitions from "Searching…" to "0" (connected state) within one SwiftUI update frame. No intermediate "No Wi-Fi" state is shown. This verifies the spec NFR: "Chip copy updates within one animation frame of the underlying state change" (US-66 AC-6).
**Covers ADR contract assertion:** §7 `ConnectionStatusChip` reactivity
**Covers spec AC:** US-66 AC-6

---

## 5. Integration Test Cases (DiscoveryStateView + PulseRingsView)

These cases render `DiscoveryStateView` (and its sub-component `PulseRingsView`) in isolation with an injected `HomeState` value and assert on visible content, animation behaviour, and timer-driven sub-label appearance.

---

### TC-E55-I01

**ID:** TC-E55-I01
**Target:** `DiscoveryStateView(.discovering)` — renders searching label and pulse rings
**Setup:** Instantiate `DiscoveryStateView(state: .discovering, onSearchAgain: {})`.
**Action:** Inspect the view hierarchy.
**Expected:** `PulseRingsView` is present. The label `Text(strings.searching)` ("Searching for speakers…") is visible in `BeoType.body`, `BeoColor.muted`. No "No speakers found" title. No "Search again" button. No "No Wi-Fi" title. The orb opacity is 1.0 (full, with pulse per design-spec §4.2). The "Still looking…" sub-label is absent at time zero.
**Covers ADR contract assertion:** §7 `DiscoveryStateView` — `.discovering` branch: "PulseRingsView behind orb at full opacity"
**Covers spec AC:** US-63 AC-1 (pre-settle discovery UI shown)

---

### TC-E55-I02

**ID:** TC-E55-I02
**Target:** `DiscoveryStateView(.discovering)` — "Still looking…" appears after 10 s
**Setup:** Instantiate `DiscoveryStateView(state: .discovering, onSearchAgain: {})`. Use a fake clock or override `Task.sleep` via a test hook, or advance a `Clock` dependency by 10 seconds.
**Action:** Advance time by 10 seconds without changing `state`. Read the view hierarchy.
**Expected:** The sub-label `Text(strings.stillLooking)` ("Still looking…" / "Søger stadig…") is now visible, styled in `BeoType.caption`, `BeoColor.muted` at 0.6 opacity. The primary searching label remains visible alongside it. The sub-label appeared because the `.task(id: state)` task ran to completion (10-second sleep fired) without a state change cancelling it.
**Covers ADR contract assertion:** §7 `DiscoveryStateView` — "After 10 s without state change: Text(strings.stillLooking) appears"
**Covers spec AC:** US-63 AC-3 ("Still looking…" appears after 10 seconds)

---

### TC-E55-I03

**ID:** TC-E55-I03
**Target:** `DiscoveryStateView(.discovering)` — "Still looking…" disappears on state change before 10 s
**Setup:** Instantiate `DiscoveryStateView(state: .discovering, onSearchAgain: {})`. Advance time by 5 seconds (before the 10-second threshold).
**Action:** Change `state` to `.noSpeakersFound`. Read the view hierarchy.
**Expected:** The "Still looking…" sub-label does NOT appear (the `.task(id: state)` is cancelled by the state change before the 10-second sleep completes). `stillLookingShown` resets to `false` when the task is cancelled because `.task(id:)` cancels and restarts on `id` changes. The view now renders the `.noSpeakersFound` branch (dim orb, "No speakers found" title, "Search again" button).
**Covers ADR contract assertion:** §7 `DiscoveryStateView` — "`@State stillLookingShown` driven by `.task(id: state)`"; cancellation on state change
**Covers spec AC:** US-63 AC-3 (sub-label appears only during discovering state)

---

### TC-E55-I04

**ID:** TC-E55-I04
**Target:** `DiscoveryStateView(.noSpeakersFound)` — renders dim orb, title, body, Search Again button
**Setup:** Instantiate `DiscoveryStateView(state: .noSpeakersFound, onSearchAgain: {})`.
**Action:** Inspect the view hierarchy.
**Expected:** Orb is present at 0.4 opacity with no pulse. Title `Text(strings.noSpeakersTitle)` in `BeoType.nowPlaying`. Body `Text(strings.noSpeakersBody)` in `BeoType.body`, `BeoColor.muted`. A `DarkGlassButton` (or equivalent styled button) with label `strings.searchAgain` ("Search again") is present. `PulseRingsView` is absent or opacity 0. The "Still looking…" sub-label is absent.
**Covers ADR contract assertion:** §7 `DiscoveryStateView` — `.noSpeakersFound` branch
**Covers spec AC:** US-64 AC-2 (post-settle empty state shows heading, body, and Search Again button)

---

### TC-E55-I05

**ID:** TC-E55-I05
**Target:** `DiscoveryStateView(.noSpeakersFound)` — "Search again" tap calls `onSearchAgain` and shows spinner
**Setup:** Instantiate with `var searchAgainCalled = false; DiscoveryStateView(state: .noSpeakersFound, onSearchAgain: { searchAgainCalled = true })`.
**Action:** Simulate tapping the "Search again" button. Inspect (a) `searchAgainCalled` and (b) the button's internal state (`isSearching`).
**Expected:** `searchAgainCalled == true`. Immediately after the tap, `isSearching = true` — the button shows an inline `ProgressView()`. The `onSearchAgain` closure is called exactly once per tap. The button does not trigger `onSearchAgain` again if tapped while `isSearching == true` (guard against double-taps during the in-flight spinner period).
**Covers ADR contract assertion:** §7 `DiscoveryStateView` — `.noSpeakersFound` "On tap: isSearching = true; onSearchAgain()"
**Covers spec AC:** US-64 AC-3 (tapping "Search again" triggers restart and transitions back to pre-settle)

---

### TC-E55-I06

**ID:** TC-E55-I06
**Target:** `DiscoveryStateView(.noSpeakersFound)` — `isSearching` resets on state change
**Setup:** Tap "Search again" so `isSearching = true`. Then change `state` to `.discovering`.
**Action:** Inspect `isSearching` after the state transition.
**Expected:** `isSearching` resets to `false` (per ADR §7: "Reset isSearching on state change"). The view no longer shows the inline `ProgressView` in the button area because the state has moved to the discovering branch.
**Covers ADR contract assertion:** §7 `DiscoveryStateView` — "Reset isSearching on state change"
**Covers spec AC:** US-64 AC-3

---

### TC-E55-I07

**ID:** TC-E55-I07
**Target:** `DiscoveryStateView(.offline)` — renders very-dim orb, title, body, auto-recovery label, no button
**Setup:** Instantiate `DiscoveryStateView(state: .offline, onSearchAgain: {})`.
**Action:** Inspect the view hierarchy.
**Expected:** Orb is present at 0.2 opacity with no animation. Title `Text(strings.offlineTitle)` ("No Wi-Fi") in `BeoType.nowPlaying`. Body `Text(strings.offlineBody)` in `BeoType.body`, `BeoColor.muted`. Sub-label `Text(strings.offlineAutoRecovery)` ("Recovers automatically when Wi-Fi reconnects") in `BeoType.caption`, `BeoColor.muted` at 0.6 opacity. No button is present. `PulseRingsView` is absent. `onSearchAgain` is not called.
**Covers ADR contract assertion:** §7 `DiscoveryStateView` — `.offline` branch: "orb at 0.2 opacity, no animation; Title + body + autoRecovery sub-label. No button."
**Covers spec AC:** US-65 AC-2 (offline state shows heading, body paragraph, auto-recovery sub-label); US-65 AC-6 (no manual retry button)

---

### TC-E55-I08

**ID:** TC-E55-I08
**Target:** `DiscoveryStateView` — a11y announcements: `lastAnnouncedState` guard prevents repeated posts
**Setup:** Instantiate `DiscoveryStateView(state: .discovering, onSearchAgain: {})`. Use an accessibility notification spy that counts calls to `AccessibilityNotification.Announcement`. Allow first render.
**Action:** Trigger a second render of the same `.discovering` state (e.g. re-render with an unrelated environment change). Count the announcement posts.
**Expected:** The announcement "Searching for speakers" (strings.a11y.searching) is posted exactly once — on the first render. Subsequent re-renders with `state == .discovering` are suppressed by `lastAnnouncedState == state` guard. No duplicate VoiceOver announcement fires. This verifies the `@State lastAnnouncedState` mechanism described in ADR §7.
**Covers ADR contract assertion:** §7 `DiscoveryStateView` — "A11y announcements (T-5508): `@State lastAnnouncedState`; on state change, post once"
**Covers spec AC:** US-63 AC-8 ("VoiceOver announces 'Searching for speakers' once")

---

### TC-E55-I09

**ID:** TC-E55-I09
**Target:** `DiscoveryStateView` — a11y announcement: offline → discovering posts `wifiRestored`
**Setup:** Instantiate with `state: .offline`. Allow first render (posts `.offline` announcement). Then change `state` to `.discovering`.
**Action:** Inspect the accessibility notification calls after the state change.
**Expected:** The announcement `strings.a11y.wifiRestored` ("Wi-Fi connected, searching for speakers") is posted once after the transition from `.offline` to `.discovering`. The earlier `.offline` announcement was posted when entering offline state. The guard `lastAnnouncedState == .offline && newState == .discovering` triggers the `wifiRestored` string (not the generic `searching` string). Total announcement calls after both transitions: 2 (one `.offline`, one `wifiRestored`).
**Covers ADR contract assertion:** §7 `DiscoveryStateView` — "offline → discovering (from offline): strings.a11y.wifiRestored"
**Covers spec AC:** US-65 AC-8 ("Wi-Fi restored: VoiceOver announces 'Wi-Fi connected, searching for speakers'")

---

### TC-E55-I10

**ID:** TC-E55-I10
**Target:** `DiscoveryStateView` — a11y announcement: nil → discovering posts `searching` (not `wifiRestored`)
**Setup:** Instantiate with `state: .discovering` from nil (first render, no prior state).
**Action:** Inspect the accessibility notification calls.
**Expected:** The announcement `strings.a11y.searching` ("Searching for speakers") is posted once. The `wifiRestored` announcement is NOT posted — that string is reserved for the offline→discovering transition per ADR §7 rule `nil → discovering: strings.a11y.searching`.
**Covers ADR contract assertion:** §7 `DiscoveryStateView` — "nil → discovering: strings.a11y.searching"
**Covers spec AC:** US-63 AC-8

---

### TC-E55-I11

**ID:** TC-E55-I11
**Target:** `PulseRingsView` — Reduce Motion: single static ring
**Setup:** Instantiate `PulseRingsView()` with `@Environment(\.accessibilityReduceMotion) = true`.
**Action:** Inspect the view hierarchy and check for animation state.
**Expected:** Exactly one `Circle().stroke` shape is present, with `BeoColor.accent.opacity(0.1)` and a fixed `.frame(width: 200, height: 200)`. No `repeatForever` animation is active. The orb pulse is not controlled by `PulseRingsView` itself (it is animated in `HomeView`). `.accessibilityHidden(true)` is applied to the entire view.
**Covers ADR contract assertion:** §7 `PulseRingsView` — "Reduce Motion: single Circle().stroke(BeoColor.accent.opacity(0.1), lineWidth: 1).frame(200)"
**Covers spec AC:** US-63 AC-6 ("The Reduce Motion variant per design spec §4.2 is respected")

---

### TC-E55-I12

**ID:** TC-E55-I12
**Target:** `PulseRingsView` — Reduce Motion off: three rings with staggered animation
**Setup:** Instantiate `PulseRingsView()` with `@Environment(\.accessibilityReduceMotion) = false`.
**Action:** Inspect the view hierarchy on appear.
**Expected:** Three `Circle().stroke(BeoColor.accent, lineWidth: 1)` shapes are present. Ring 1 starts expanding immediately on `.onAppear`. Ring 2 has a 0.6 s delay. Ring 3 has a 1.2 s delay. Each ring animates diameter from 96 pt to 200 pt over 2.0 s with `.easeOut`, opacity from 0.15 to 0, and `repeatForever(autoreverses: false)`. `.accessibilityHidden(true)` is applied.
**Covers ADR contract assertion:** §7 `PulseRingsView` — "3 Circle().stroke. Ring 2 delay 0.6 s; Ring 3 delay 1.2 s"
**Covers spec AC:** US-63 AC-1 (pulse rings visible during pre-settle); design-spec §4.2

---

### TC-E55-I13

**ID:** TC-E55-I13
**Target:** `PulseRingsView` — `.accessibilityHidden(true)` regardless of Reduce Motion
**Setup:** Instantiate `PulseRingsView()` with both `reduceMotion = false` and `reduceMotion = true` variants.
**Action:** Inspect `.isAccessibilityElement` on the root container in each variant.
**Expected:** `.accessibilityHidden(true)` is applied in both variants. The rings do not appear in the VoiceOver element tree under any motion setting. They are purely decorative.
**Covers ADR contract assertion:** §7 `PulseRingsView` — ".accessibilityHidden(true) on the whole view"
**Covers spec AC:** design-spec §4.5 ("The pulse rings are accessibilityHidden(true) — decorative")

---

## 6. Acceptance Test Cases (HomeView four-state routing + voice/bar gating)

These cases test `HomeView` end-to-end with stubbed `NetworkMonitor` and `SpeakerDiscoveryService`. They are integration/acceptance-level tests and may be implemented as XCUITest or snapshot tests.

---

### TC-E55-A01

**ID:** TC-E55-A01
**Target:** `HomeView.cardArea` — `.offline` branch renders `DiscoveryStateView` with offline state
**Setup:** Render `HomeView` with `NetworkMonitorStub(isOnWifi: false)` and any discovery stub. Observe the `cardArea` region.
**Action:** Inspect which component occupies the `cardArea`.
**Expected:** `DiscoveryStateView(state: .offline, ...)` is rendered. The E-52 `SessionStripView` and the E-52 `emptyState` are not rendered. The `SpeakerSelectorPill` bar is hidden (`!network.isOnWifi` gate from T-5512). The `voiceFeedback` view is hidden.
**Covers ADR contract assertion:** §7 `HomeState` — `.offline` branch; §5 Consequences — "In .offline state: both `voiceFeedback` and `SpeakerSelectorPill` must be hidden"
**Covers spec AC:** US-65 AC-1 (offline state shown when `isOnWifi == false`); US-65 AC-3 (bottom bar hidden); US-65 AC-4 (voice feedback hidden)

---

### TC-E55-A02

**ID:** TC-E55-A02
**Target:** `HomeView.cardArea` — `.discovering` branch renders `DiscoveryStateView` with discovering state
**Setup:** Render `HomeView` with `NetworkMonitorStub(isOnWifi: true)` and `SpeakerDiscoveryServiceStub(didSettle: false, speakerCount: 0)`.
**Action:** Inspect `cardArea`.
**Expected:** `DiscoveryStateView(state: .discovering, ...)` is rendered. `PulseRingsView` is visible. The "Searching for speakers…" label is present. `SpeakerSelectorPill` bar is hidden (zero speakers means the `>= 1` guard from T-5408 hides it naturally — no additional `isOnWifi` gate needed per ADR §5 Consequences).
**Covers ADR contract assertion:** §7 `HomeState` — `.discovering` branch
**Covers spec AC:** US-63 AC-1; US-63 AC-2 ("bottom bar not shown until at least one speaker is discovered")

---

### TC-E55-A03

**ID:** TC-E55-A03
**Target:** `HomeView.cardArea` — `.noSpeakersFound` branch renders `DiscoveryStateView` with no-speakers state
**Setup:** Render `HomeView` with `NetworkMonitorStub(isOnWifi: true)` and `SpeakerDiscoveryServiceStub(didSettle: true, speakerCount: 0)`.
**Action:** Inspect `cardArea`.
**Expected:** `DiscoveryStateView(state: .noSpeakersFound, ...)` is rendered. Dim orb (0.4 opacity, no pulse). "No speakers found" title and body present. "Search again" button present. `SpeakerSelectorPill` bar is hidden. Voice feedback is visible (per ADR §8 CF-4: `voiceFeedback` must NOT be hidden in `.noSpeakersFound` — only hidden in `.offline`).
**Covers ADR contract assertion:** §7 `HomeState` — `.noSpeakersFound` branch; ADR §8 CF-4 (voiceFeedback NOT hidden in noSpeakersFound)
**Covers spec AC:** US-64 AC-1; US-64 AC-4 ("Bottom bar not shown in this state")

---

### TC-E55-A04

**ID:** TC-E55-A04
**Target:** `HomeView.cardArea` — `.hasContent` branch preserves E-52 three-branch body intact
**Setup:** Render `HomeView` with `NetworkMonitorStub(isOnWifi: true)` and `SpeakerDiscoveryServiceStub(didSettle: true, speakerCount: 2, playingGroups: [groupA, groupB])`.
**Action:** Inspect `cardArea`.
**Expected:** The `.hasContent` branch is active. The existing E-52 `SessionStripView` (or `SpeakerCard` / `emptyState` for the idle-speaker sub-cases) is rendered — the E-52 three-branch body is preserved verbatim inside `case .hasContent:` per ADR §2 Context (ADR-E52 CF-2 requirement). `DiscoveryStateView` is not rendered. `SpeakerSelectorPill` bar is visible.
**Covers ADR contract assertion:** §7 `HomeState` — `.hasContent` branch; ADR §5 Consequences — "E-52 session strip preserved"
**Covers spec AC:** US-63 AC-5 (first speaker found → normal home screen); F1/F2 unaffected (ADR §5 CF-7)

---

### TC-E55-A05

**ID:** TC-E55-A05
**Target:** `HomeView` — `voiceFeedback` hidden only in `.offline` state, visible in discovering/noSpeakersFound/hasContent
**Setup:** Render `HomeView` cycling through all four `HomeState` values via stub manipulation.
**Action:** Observe `voiceFeedback` visibility in each state.
**Expected:**
- `.offline`: `voiceFeedback` hidden (per US-65 AC-4 and ADR §5 Consequences).
- `.discovering`: `voiceFeedback` visible (waveform shown while listening regardless of speaker count, per ADR §8 CF-4).
- `.noSpeakersFound`: `voiceFeedback` visible.
- `.hasContent`: `voiceFeedback` visible.
The gate must use `if network.isOnWifi { voiceFeedback }` — not a state-machine switch — so that it stays visible in `.discovering` and `.noSpeakersFound`.
**Covers ADR contract assertion:** ADR §8 CF-4 — `voiceFeedback` hidden ONLY when offline
**Covers spec AC:** US-65 AC-4 (voice feedback hidden offline); US-63 AC-1 (searching UI shown but voice remains active)

---

### TC-E55-A06

**ID:** TC-E55-A06
**Target:** `HomeView` — `startListening` gated on `isOnWifi`; `.onChange(of: isOnWifi)` re-triggers on restore
**Setup:** Render `HomeView`. Start with `NetworkMonitorStub(isOnWifi: false)`. Confirm `startListening` was NOT called. Transition to `isOnWifi: true` (simulating Wi-Fi restore). Also satisfy `hasCompletedOnboarding == true` and `langService.hasExplicitlyChosen == true`.
**Action:** Flip `isOnWifi` from `false` to `true`. Allow the `.onChange(of: network.isOnWifi)` handler to fire.
**Expected:** `startListening()` is called once after the flip. The voice recognition pipeline starts. If `isOnWifi` remains `true` on subsequent re-renders, `startListening()` is not called again (the `.onChange` fires only on changes). The onboarding guard (`hasCompletedOnboarding && langService.hasExplicitlyChosen`) is checked before calling `startListening`.
**Covers ADR contract assertion:** §7 `HomeView` — "`startListening` gated on `isOnWifi`"; "`.onChange(of: network.isOnWifi)` re-triggers when restored"
**Covers spec AC:** US-65 AC-4 (voice recognition does not start while offline); US-65 AC-5 (no Wi-Fi chip copy and no mic); spec §Technical Requirements `startListening` gate

---

### TC-E55-A07

**ID:** TC-E55-A07
**Target:** `HomeView` — `SpeakerSelectorPill` hidden when offline with cached speakers (CF-5 edge case)
**Setup:** Render `HomeView` with `NetworkMonitorStub(isOnWifi: true)` and two discovered speakers in `groups`. Confirm `SpeakerSelectorPill` is visible. Then flip `isOnWifi = false`.
**Action:** Inspect `SpeakerSelectorPill` visibility after the flip.
**Expected:** `SpeakerSelectorPill` is hidden even though `groups` still contains two speakers. The `network.isOnWifi` gate in T-5512 fires before the `>= 1` check from T-5408 would otherwise show the bar. This is the CF-5 edge case: offline with cached speakers → bar must hide.
**Covers ADR contract assertion:** ADR §8 CF-5 — "offline state could coexist with a non-empty groups array; T-5512 must explicitly gate SpeakerSelectorPill on network.isOnWifi"
**Covers spec AC:** US-65 AC-3 (bottom bar hidden in offline state)

---

### TC-E55-A08

**ID:** TC-E55-A08
**Target:** `HomeView` — `ConnectionStatusChip` call site passes three inputs from live state
**Setup:** Read `HomeView.statusBar` source (code review via `@testable import` or source inspection).
**Action:** Confirm the `ConnectionStatusChip` call site shape matches ADR §7: `ConnectionStatusChip(isOnWifi: network.isOnWifi, didSettle: discovery.didSettle, speakerCount: discovery.groups.flatMap(\.members).count)`.
**Expected:** All three parameters are present. No old single-`speakerCount` call remains. `speakerCount` is derived from `flatMap(\.members).count` (total discovered speakers), not from `playingGroups.count` (session count). This is a code-review assertion.
**Covers ADR contract assertion:** §7 `ConnectionStatusChip` call site (T-5504)
**Covers spec AC:** US-66 AC-1 (chip inputs correctly wired)

---

### TC-E55-A09

**ID:** TC-E55-A09
**Target:** `HomeView` — `NetworkMonitor` lifecycle: `start()` on appear, `stop()` on disappear
**Setup:** Instantiate `HomeView` with a `NetworkMonitorSpy` that records `start()` and `stop()` calls.
**Action:** Trigger `onAppear` (view appears). Then trigger `onDisappear` (view disappears).
**Expected:** `start()` is called once on `onAppear`. `stop()` is called once on `onDisappear`. The monitor does not start before `onAppear` (the default `isOnWifi = true` provides safe defaults during the pre-start window). No double-start or double-stop.
**Covers ADR contract assertion:** §7 `NetworkMonitor.start()` / `stop()` lifecycle
**Covers spec AC:** spec §Technical Requirements `NetworkMonitor` lifecycle ("Started in onAppear, paused on onDisappear")

---

## 7. Error States and Boundary Values

---

### TC-E55-E01

**ID:** TC-E55-E01
**Target:** `SpeakerDiscoveryService.restart()` — synchronous state reset before `start()`
**Setup:** Create a `SpeakerDiscoveryService` (or stub) with `allSpeakers = [speakerA]`, `groups = [groupA]`, `didSettle = true`. Also hold a `MdnsDiscovery` instance with non-empty `foundHosts`.
**Action:** Call `restart()`. Immediately (without waiting for any async completion) read `allSpeakers`, `groups`, `didSettle`, and `MdnsDiscovery.foundHosts`.
**Expected:**
- `allSpeakers.isEmpty == true`
- `groups.isEmpty == true`
- `didSettle == false`
- `MdnsDiscovery.foundHosts.isEmpty == true` (and `serviceNameToHost`, `serviceNameToType`, `pendingServices` all empty)
These must all be true synchronously before `start()` begins any network activity. This ensures `HomeView` reads zero speakers immediately and transitions to `.discovering`.
**Covers ADR contract assertion:** §7 `SpeakerDiscoveryService` — "restart(): cancel autoRetryTask, stop(), discovery.reset(), allSpeakers = [], groups = [], didSettle = false, start()"
**Covers spec AC:** US-64 AC-3 (restart triggers back to pre-settle UI immediately)

---

### TC-E55-E02

**ID:** TC-E55-E02
**Target:** `MdnsDiscovery.reset()` — clears all four dictionaries
**Setup:** Populate `MdnsDiscovery` with mock entries: `foundHosts = ["host1": ipA]`, `serviceNameToHost = ["svc1": "host1"]`, `serviceNameToType = ["svc1": "_bangolufsen._tcp"]`, `pendingServices = ["svc2"]`.
**Action:** Call `reset()`.
**Expected:** All four collections are empty: `foundHosts.isEmpty`, `serviceNameToHost.isEmpty`, `serviceNameToType.isEmpty`, `pendingServices.isEmpty`. This confirms CF-2 from ADR §8 is resolved: without `reset()`, the duplicate-host guard would prevent re-discovery of the same speakers after `restart()`.
**Covers ADR contract assertion:** §7 `MdnsDiscovery.reset()` — "clears foundHosts, serviceNameToHost, serviceNameToType, pendingServices"
**Covers spec AC:** ADR §8 CF-2 (duplicate-host guard bypassed after reset)

---

### TC-E55-E03

**ID:** TC-E55-E03
**Target:** `SpeakerDiscoveryService.restart()` — idempotent
**Setup:** Call `restart()` on a service with no in-flight tasks (cold state: `allSpeakers = []`, `didSettle = false`).
**Action:** Call `restart()` a second time immediately after the first.
**Expected:** No crash. `allSpeakers` remains empty. `didSettle` remains `false`. The second call is handled gracefully — the `autoRetryTask?.cancel()` guard at the top of `restart()` tolerates `nil`. `start()` is called a second time; the implementation must guard against double-start (this is an existing `SpeakerDiscoveryService` invariant — confirm `start()` is idempotent or verify `stop()` before the second `start()` prevents the double-start).
**Covers ADR contract assertion:** §7 `SpeakerDiscoveryService` — "restart() is idempotent"
**Covers spec AC:** spec error states — "`discovery.restart()` fails to discover any new speakers within 30 s" → auto-retry continues safely

---

### TC-E55-E04

**ID:** TC-E55-E04
**Target:** `scheduleAutoRetry` — cancels when `addSpeaker` is called
**Setup:** Drive `SpeakerDiscoveryService` to the post-settle-empty state: `didSettle = true`, `allSpeakers = []`. Confirm `autoRetryTask` is scheduled. Advance time by 15 seconds (before the 30-second fire).
**Action:** Call `addSpeaker(speakerA)`. Advance time past 30 seconds.
**Expected:** `autoRetryTask` is cancelled at the point `addSpeaker` runs. `restart()` is NOT called after the 30-second window (because the task was cancelled). `allSpeakers` contains `speakerA` and `didSettle` is unchanged. `homeState` is `.hasContent` (speaker found).
**Covers ADR contract assertion:** §7 `scheduleAutoRetry` — "Cancelled in addSpeaker() (when allSpeakers becomes non-empty)"
**Covers spec AC:** US-63 AC-4 ("auto-retry every 30 s silently") — specifically that auto-retry stops when a speaker is found

---

### TC-E55-E05

**ID:** TC-E55-E05
**Target:** `scheduleAutoRetry` — cancels at the start of `restart()`
**Setup:** Drive to post-settle-empty state; `autoRetryTask` is scheduled.
**Action:** Call `restart()` manually (simulating the "Search again" button tap).
**Expected:** `autoRetryTask` is cancelled synchronously at the top of `restart()` before `stop()` is called. After `restart()` completes, a new `autoRetryTask` will be scheduled again only once the next `didSettle = true` + empty condition is met. This prevents re-entry: the cancelled task cannot call `restart()` concurrently with the manual `restart()`.
**Covers ADR contract assertion:** §7 `SpeakerDiscoveryService` — "autoRetryTask cancelled before stop() in restart() to prevent re-entry"
**Covers spec AC:** US-64 AC-3 (manual "Search again" triggers clean restart)

---

### TC-E55-E06

**ID:** TC-E55-E06
**Target:** `scheduleAutoRetry` — fires after 30 s when condition persists
**Setup:** Drive to post-settle-empty state. Confirm `autoRetryTask` is scheduled.
**Action:** Advance time by 30 seconds without any `addSpeaker` or manual `restart()` calls. Confirm `didSettle == true && allSpeakers.isEmpty` still holds at the time the task fires.
**Expected:** `restart()` is called automatically after the 30-second sleep. `didSettle` is reset to `false`, `allSpeakers` and `groups` are cleared, and `homeState` transitions to `.discovering` — the same as a manual "Search again". No UI change beyond the continued pulse rings and state transition animation.
**Covers ADR contract assertion:** §7 `scheduleAutoRetry` — "try? await Task.sleep(for: .seconds(30)); guard !Task.isCancelled, let self; guard self.didSettle && self.allSpeakers.isEmpty; await self.restart()"
**Covers spec AC:** US-63 AC-4 ("The discovery service auto-retries the scan every 30 seconds silently")

---

### TC-E55-E07

**ID:** TC-E55-E07
**Target:** `scheduleAutoRetry` — does NOT fire if condition no longer holds at 30-s mark
**Setup:** Drive to post-settle-empty state; `autoRetryTask` is scheduled. At T+29 s, call `addSpeaker(speakerA)` (which should have cancelled the task per TC-E55-E04). Advance to T+31 s.
**Action:** Observe whether `restart()` is called at T+30 s.
**Expected:** `restart()` is NOT called. The guard at line `guard self.didSettle && self.allSpeakers.isEmpty` would have evaluated to `false` (since a speaker was added). Even if the task somehow was not cancelled by `addSpeaker`, the guard inside the `Task` body prevents the erroneous `restart()`. No crash.
**Covers ADR contract assertion:** §7 `scheduleAutoRetry` — defensive guard inside the task body
**Covers spec AC:** US-63 AC-4 (auto-retry does not restart discovery when a speaker has been found)

---

### TC-E55-E08

**ID:** TC-E55-E08
**Target:** `HomeView` — Wi-Fi flap: rapid offline→online→offline does not produce stale state
**Setup:** Render `HomeView`. Start `isOnWifi: true`, `didSettle: true`, `speakerCount: 1` → `.hasContent`. Flip `isOnWifi: false` → `.offline`. Immediately flip back `isOnWifi: true` → `didSettle: false` after `restart()`.
**Action:** Allow all SwiftUI update cycles to process.
**Expected:** The final state is `.discovering` (because `restart()` was called on Wi-Fi restore, resetting `didSettle`). No crash. No stale `HomeState` that shows `.noSpeakersFound` while `didSettle == false`. This confirms that `restart()` is called in the `.onChange(of: network.isOnWifi)` handler (when `isOnWifi` becomes true) and synchronously clears state before SwiftUI re-evaluates `homeState`.
**Covers ADR contract assertion:** §7 `HomeState` transitions — re-entrancy after Wi-Fi flap
**Covers spec AC:** spec error states "Wi-Fi flaps (drops and immediately returns) — each event drives one transition"

---

### TC-E55-E09

**ID:** TC-E55-E09
**Target:** `DiscoveryStateView` — `onSearchAgain` closure ignored when `state != .noSpeakersFound`
**Setup:** Instantiate `DiscoveryStateView(state: .offline, onSearchAgain: { fatalError("Should not be called") })`.
**Action:** Render the view. Inspect whether any tap gesture or automatic call could invoke `onSearchAgain`.
**Expected:** No crash. `onSearchAgain` is never invoked. The `.offline` branch does not render a button. There is no accidental trigger path. This validates that the closure is truly ignored for non-`noSpeakersFound` states (per ADR §7: "The `onSearchAgain` closure is non-nil only for `.noSpeakersFound` — the view ignores it in `.offline` and `.discovering` branches").
**Covers ADR contract assertion:** §7 `DiscoveryStateView` — "`onSearchAgain` ignored when state != .noSpeakersFound"
**Covers spec AC:** US-65 AC-6 (no button in offline state)

---

### TC-E55-E10

**ID:** TC-E55-E10
**Target:** `DiscoveryStateView` — Reduce Motion: state transition uses opacity only (no scale)
**Setup:** Enable Reduce Motion. Render `DiscoveryStateView(state: .discovering, ...)`. Then transition to `state: .noSpeakersFound`.
**Action:** Inspect the transition animation applied to the `cardArea` switch.
**Expected:** The `.animation(BeoAnimation.toast, value: homeState.layoutKey)` produces an opacity-only cross-fade with Reduce Motion enabled — no `.scaleEffect` modifier is applied to the outgoing or incoming branch. This matches design-spec §Motion ("State label colour change: cross-fade on BeoAnimation.toast. Reduce Motion: instantaneous").
**Covers ADR contract assertion:** §7 `HomeState.layoutKey` + `.animation(BeoAnimation.toast)` modifier
**Covers spec AC:** spec §Accessibility ("Reduce Motion: all decorative motion suspends")

---

## 8. Coverage Matrix (AC/ER → TC IDs)

| AC / Contract Assertion | TC IDs | Status |
|---|---|---|
| **ADR §7 NetworkMonitor default `isOnWifi = true`** | TC-E55-U01 | Covered |
| **ADR §7 NetworkMonitor `isOnWifi` from Wi-Fi path** | TC-E55-U02 | Covered |
| **ADR §7 NetworkMonitor `isOnWifi = false` from cellular** | TC-E55-U03 | Covered |
| **ADR §7 NetworkMonitor main-actor hop** | TC-E55-U04 | Covered (code review) |
| **ADR §7 NetworkMonitor lifecycle (start/stop)** | TC-E55-A09 | Covered |
| **ADR §7 HomeState — `!isOnWifi` wins over all** | TC-E55-U05, TC-E55-U15 | Covered |
| **ADR §7 HomeState — `speakerCount > 0` wins over settle** | TC-E55-U06, TC-E55-U11 | Covered |
| **ADR §7 HomeState — `.discovering` case** | TC-E55-U07, TC-E55-A02 | Covered |
| **ADR §7 HomeState — `.noSpeakersFound` case** | TC-E55-U08, TC-E55-A03 | Covered |
| **ADR §7 HomeState — `.offline` case** | TC-E55-U05, TC-E55-A01 | Covered |
| **ADR §7 HomeState — `.hasContent` case** | TC-E55-U06, TC-E55-A04 | Covered |
| **ADR §7 HomeState — `layoutKey` four distinct strings** | TC-E55-U09 | Covered |
| **ADR §7 HomeState transition: offline → discovering** | TC-E55-U10, TC-E55-A09 | Covered |
| **ADR §7 HomeState transition: discovering → hasContent** | TC-E55-U11 | Covered |
| **ADR §7 HomeState transition: discovering → noSpeakersFound** | TC-E55-U12 | Covered |
| **ADR §7 HomeState transition: noSpeakersFound → discovering (restart)** | TC-E55-U13 | Covered |
| **ADR §7 HomeState transition: noSpeakersFound → offline** | TC-E55-U14 | Covered |
| **ADR §7 HomeState transition: hasContent → offline** | TC-E55-U15 | Covered |
| **ADR §7 HomeState transition: hasContent → noSpeakersFound** | TC-E55-U16 | Covered |
| **ADR §7 DiscoveryStateView — .discovering branch** | TC-E55-I01, TC-E55-A02 | Covered |
| **ADR §7 DiscoveryStateView — "Still looking…" after 10 s** | TC-E55-I02 | Covered |
| **ADR §7 DiscoveryStateView — "Still looking…" reset on state change** | TC-E55-I03 | Covered |
| **ADR §7 DiscoveryStateView — .noSpeakersFound branch** | TC-E55-I04, TC-E55-A03 | Covered |
| **ADR §7 DiscoveryStateView — onSearchAgain tap + isSearching** | TC-E55-I05 | Covered |
| **ADR §7 DiscoveryStateView — isSearching reset on state change** | TC-E55-I06 | Covered |
| **ADR §7 DiscoveryStateView — .offline branch** | TC-E55-I07, TC-E55-A01 | Covered |
| **ADR §7 DiscoveryStateView — onSearchAgain ignored in offline/discovering** | TC-E55-E09 | Covered |
| **ADR §7 DiscoveryStateView — a11y lastAnnouncedState guard** | TC-E55-I08 | Covered |
| **ADR §7 DiscoveryStateView — offline→discovering posts wifiRestored** | TC-E55-I09 | Covered |
| **ADR §7 DiscoveryStateView — nil→discovering posts searching** | TC-E55-I10 | Covered |
| **ADR §7 PulseRingsView — 3 rings, stagger 0/0.6/1.2 s** | TC-E55-I12 | Covered |
| **ADR §7 PulseRingsView — Reduce Motion: single static ring** | TC-E55-I11 | Covered |
| **ADR §7 PulseRingsView — accessibilityHidden(true)** | TC-E55-I13 | Covered |
| **ADR §7 ChipState.offline — wifi.slash, No Wi-Fi copy** | TC-E55-C01 | Covered |
| **ADR §7 ChipState.searching — wifi, Searching… copy** | TC-E55-C02 | Covered |
| **ADR §7 ChipState.connected(n) — wifi, integer label** | TC-E55-C03 | Covered |
| **ADR §7 ChipState.connected(0) degenerate case** | TC-E55-C04 | Covered |
| **ADR §7 ConnectionStatusChip accessibilityLabel per state** | TC-E55-C05 | Covered |
| **ADR §7 ConnectionStatusChip reactivity (one frame)** | TC-E55-C06 | Covered |
| **ADR §7 ConnectionStatusChip call site shape** | TC-E55-A08 | Covered (code review) |
| **ADR §7 SpeakerDiscoveryService.restart() — synchronous reset** | TC-E55-E01 | Covered |
| **ADR §7 MdnsDiscovery.reset() — clears four dictionaries** | TC-E55-E02 | Covered |
| **ADR §7 restart() idempotent** | TC-E55-E03 | Covered |
| **ADR §7 scheduleAutoRetry — cancelled by addSpeaker** | TC-E55-E04 | Covered |
| **ADR §7 scheduleAutoRetry — cancelled by restart()** | TC-E55-E05 | Covered |
| **ADR §7 scheduleAutoRetry — fires at 30 s** | TC-E55-E06 | Covered |
| **ADR §7 scheduleAutoRetry — guard prevents fire if condition cleared** | TC-E55-E07 | Covered |
| **ADR §7 voiceFeedback + SpeakerSelectorPill hidden offline** | TC-E55-A01, TC-E55-A05 | Covered |
| **ADR §7 startListening gated on isOnWifi + onChange re-trigger** | TC-E55-A06 | Covered |
| **ADR §8 CF-4 — voiceFeedback NOT hidden in discovering/noSpeakersFound** | TC-E55-A03, TC-E55-A05 | Covered |
| **ADR §8 CF-5 — SpeakerSelectorPill hidden offline even with cached speakers** | TC-E55-A07 | Covered |
| **US-63 AC-1** — pre-settle discovery UI shown (pulse rings + searching label) | TC-E55-U07, TC-E55-I01, TC-E55-A02 | Covered |
| **US-63 AC-2** — bottom bar not shown until first speaker discovered | TC-E55-A02 | Covered |
| **US-63 AC-3** — "Still looking…" after 10 s | TC-E55-I02, TC-E55-I03 | Covered |
| **US-63 AC-4** — auto-retry every 30 s silently | TC-E55-E06, TC-E55-E04, TC-E55-E07 | Covered |
| **US-63 AC-5** — first speaker found → cross-fade to normal home screen | TC-E55-U06, TC-E55-U11, TC-E55-A04 | Covered |
| **US-63 AC-6** — Reduce Motion variant respected | TC-E55-I11 | Covered |
| **US-63 AC-7** — ConnectionStatusChip "Searching…" during pre-settle | TC-E55-C02 | Covered |
| **US-63 AC-8** — VoiceOver announces "Searching for speakers" once | TC-E55-I08, TC-E55-I10 | Covered |
| **US-64 AC-1** — post-settle empty state shown when Wi-Fi up, settled, 0 speakers | TC-E55-U08, TC-E55-I04, TC-E55-A03 | Covered |
| **US-64 AC-2** — state shows dim orb + heading + body + Search Again button | TC-E55-I04 | Covered |
| **US-64 AC-3** — "Search again" → restart → pre-settle UI | TC-E55-I05, TC-E55-U13, TC-E55-E01 | Covered |
| **US-64 AC-4** — bottom bar not shown in this state | TC-E55-A03 | Covered |
| **US-64 AC-5** — ConnectionStatusChip behaviour during manual retry | TC-E55-C02, TC-E55-C04 | Covered |
| **US-64 AC-6** — VoiceOver button label "Search again for speakers" | TC-E55-I05 (partial — label assertion) | Covered (label only; pronunciation deferred to T-5516) |
| **US-65 AC-1** — offline state shown when `isOnWifi == false` | TC-E55-U05, TC-E55-A01 | Covered |
| **US-65 AC-2** — offline state: very-dim orb + heading + body + auto-recovery sub-label | TC-E55-I07 | Covered |
| **US-65 AC-3** — bottom bar hidden offline | TC-E55-A01, TC-E55-A07 | Covered |
| **US-65 AC-4** — voice feedback + mic hidden; voice recognition does not start | TC-E55-A01, TC-E55-A05, TC-E55-A06 | Covered |
| **US-65 AC-5** — ConnectionStatusChip shows "No Wi-Fi" + wifi.slash | TC-E55-C01 | Covered |
| **US-65 AC-6** — no manual retry button in offline state | TC-E55-I07, TC-E55-E09 | Covered |
| **US-65 AC-7** — Wi-Fi restored: offline → discovering auto-transition | TC-E55-U10, TC-E55-A06 | Covered |
| **US-65 AC-8** — transition: BeoAnimation.toast then BeoAnimation.spring | TC-E55-E10 (partial — Reduce Motion) | Covered (timing deferred to T-5515) |
| **US-65 AC-9** — VoiceOver: "No Wi-Fi connection" entering offline | TC-E55-I09 (covers the offline announcement) | Covered |
| **US-65 AC-10** — VoiceOver: "Wi-Fi connected, searching for speakers" on restore | TC-E55-I09 | Covered |
| **US-66 AC-1** — chip shows "Searching…" / "No Wi-Fi" / "n speakers" | TC-E55-C01, TC-E55-C02, TC-E55-C03 | Covered |
| **US-66 AC-2** — "n speakers" uses existing number-only display | TC-E55-C03 | Covered |
| **US-66 AC-3** — post-settle-zero: chip shows "0 speakers" (not "No Wi-Fi") | TC-E55-C04 | Covered |
| **US-66 AC-4** — chip styling unchanged from v1.3 | Code review / snapshot (deferred) | Deferred to visual comparison |
| **US-66 AC-5** — VoiceOver label per state | TC-E55-C05 | Covered |
| **US-66 AC-6** — chip copy updates within one animation frame | TC-E55-C06 | Covered |
| **Error state: Wi-Fi drops while speakers are playing** | TC-E55-U15, TC-E55-A07 | Covered |
| **Error state: Wi-Fi flaps (drops and immediately returns)** | TC-E55-E08 | Covered |
| **Error state: all speakers disappear post-discovery** | TC-E55-U16 | Covered |
| **Error state: restart() fails to find speakers within 30 s** | TC-E55-E06 (auto-retry continues), TC-E55-E03 | Covered |
| **Re-entrancy: autoRetryTask cancel before stop() in restart()** | TC-E55-E05 | Covered |
| **Re-entrancy: NetworkMonitor pathUpdateHandler → main actor** | TC-E55-U04 | Covered (code review) |

---

## 9. Spec Gaps Discovered

The following ambiguities or omissions were identified during test-plan authoring. None are implementation blockers; each is flagged for the Spec Author and Architect to resolve before QA sign-off.

**Gap 1 — `discovery.restart()` vs `discovery.start()` inconsistency in US-64**

US-64 AC-3 in `spec-home-screen-redesign.md` states: "Tapping 'Search again' triggers `discovery.start()` and immediately transitions back to the pre-settle discovery UI." ADR §7 and the epics document (T-5505, T-5507) consistently use `discovery.restart()` (not `start()`) as the entry point for the Search Again button, because `restart()` clears `didSettle`, `allSpeakers`, and calls `MdnsDiscovery.reset()` — `start()` alone would not reset `didSettle` and could not transition back to `.discovering`. The spec text should be corrected to read `discovery.restart()`.

**Gap 2 — `voiceFeedback` gating in `.discovering` and `.noSpeakersFound` not confirmed by spec**

ADR §8 CF-4 says "`voiceFeedback` is hidden only when offline (per US-65)." US-65 AC-4 says "The voice waveform and mic-status label are hidden in this state [offline]." This is clear. However, neither the spec nor the design-spec explicitly states that `voiceFeedback` MUST be visible during `.discovering` and `.noSpeakersFound`. TC-E55-A05 asserts it is visible (based on CF-4), but the spec should add an explicit positive statement to US-63 and US-64 (e.g. "The voice waveform and mic feedback remain visible during the discovery state") to close the ambiguity.

**Gap 3 — Auto-retry scheduling trigger not fully specified**

ADR §7 states: "`scheduleAutoRetry()` invoked from `scheduleInitialSettle` after setting `didSettle = true` (when `allSpeakers.isEmpty`)." However, neither the spec nor the epics task T-5511 confirms what happens if `didSettle` is set to `true` while `allSpeakers` is non-empty (e.g. speakers are found before the settle timer fires). The implication is that `scheduleAutoRetry` is guarded by `allSpeakers.isEmpty` — TC-E55-E04 and TC-E55-E07 cover the cancellation path but cannot confirm the scheduling guard without explicit spec text. The spec should state: "`scheduleAutoRetry` is called only when `didSettle` transitions to `true` with `allSpeakers.isEmpty`; if `allSpeakers` is non-empty at settle time, no auto-retry is scheduled."

**Gap 4 — `DiscoveryStrings.forLanguage` fallback on unknown language**

ADR §7 defines `DiscoveryStrings.forLanguage(_ language: Language) -> DiscoveryStrings` but does not specify the fallback behaviour when `language` is a value not covered by the existing `.english` / `.danish` cases. The existing `GroupChipStrings` / `UIStrings` pattern in the codebase should be consulted for the established fallback (likely `.english`). A spec note should confirm: "`forLanguage` falls back to `.english` for any unrecognised `Language` value."

**Gap 5 — `isSearching` double-tap guard not specified**

TC-E55-I05 asserts that tapping "Search again" while `isSearching == true` (during an in-flight restart) should not call `onSearchAgain` a second time. ADR §7 does not specify this guard explicitly — it says "On tap: isSearching = true; onSearchAgain()" but does not say "guard !isSearching". The spec (or ADR) should explicitly state: "The Search Again button is disabled (or its tap gesture is guarded by `!isSearching`) while `isSearching == true` to prevent double-invocation."

**Gap 6 — `isAvailable` property usage not consumed by F3**

ADR §7 defines `isAvailable: Bool = true` on `NetworkMonitor` as "informational only, not consumed by F3 UI." No test cases are written for `isAvailable` because there is no specified behaviour driven by it in E-55. If `isAvailable` is intended for future features, the ADR should note which future epic will consume it and what its semantics are relative to `isOnWifi`. Without a consumer, the property risks becoming dead code.

**Gap 7 — Transition timing on offline→discovering not unit-testable**

US-65 AC-8 specifies: "The transition uses `BeoAnimation.toast` (200 ms opacity fade) followed by `BeoAnimation.spring` for the orb restore." TC-E55-E10 covers Reduce Motion behaviour but the exact two-phase timing (toast then spring) cannot be unit-tested without animation introspection tools. This is deferred to manual verification (T-5515). The spec should clarify whether the `BeoAnimation.spring` applies to the orb opacity change or to a separate `.scaleEffect` — the current wording "orb restore" is ambiguous.

---

## 10. Tests Deferred to Manual Device Verification

The following items cannot be fully automated at the unit or XCUITest level and are deferred to the manual verification tasks T-5515, T-5516, and T-5517 defined in the epics document.

| Item | Reason for deferral | Epic task |
|---|---|---|
| Full state machine walkthrough on device with real NWPathMonitor callbacks | `NWPathMonitor` OS-level timing is non-deterministic in simulators; requires physical device with Wi-Fi toggle | T-5515 items (a)–(g) |
| Visual quality of pulse ring expansion animation (96→200 pt, 2.0 s, easeOut) | Animation timing and visual quality require real-time observation; cannot be asserted by XCTest frame inspection | T-5517 item (a) |
| Orb idle pulse suspension in Reduce Motion (pre-settle state) | Orb pulse is a `@State` animation inside the orb component; requires visual confirmation that the animation is truly suspended, not just that the modifier is applied | T-5517 item (b) |
| Cross-fade quality between state transitions (toast 200 ms + spring orb restore) | Animation blending requires visual inspection on device; XCUITest cannot measure sub-frame timing | T-5515 item (f); design-spec §5.4 |
| VoiceOver announcement spoken aloud on device | `AccessibilityNotification.Announcement` posting can be unit-tested but the actual VoiceOver speech output requires the screen reader active on device | T-5516 items (a)–(e) |
| VoiceOver "Search again for speakers" spoken label (pronunciation) | Requires VoiceOver active; `accessibilityLabel` string is covered by TC-E55-I05 but the spoken form requires device verification | T-5516 item (d) |
| Wi-Fi flap debounce acknowledgement (rapid toggle may produce visible flicker) | Rapid NWPath events are not reproducible reliably in XCUITest; acknowledged in spec error states as "no debouncing in F3" | T-5515 item (g) |
| `ConnectionStatusChip` glass-capsule visual styling unchanged from v1.3 | Snapshot comparison against v1.3 baseline requires a reference screenshot; styling is a code-review assertion for padding/radius/font size values | US-66 AC-4 |
| "Still looking…" sub-label visual opacity (0.6) confirmation | Opacity value can be inspected via `@testable import` but visual appearance on dark background requires screenshot review | T-5515 item (a) |
| Reduce Motion: orb scale spring absent on state transitions | `BeoAnimation.spring` scaleEffect absence is checked by TC-E55-E10 for opacity, but the "no scale" assertion requires Instruments / render-tree inspection | T-5517 item (d) |
