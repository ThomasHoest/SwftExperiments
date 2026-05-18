# Test Plan — E-60 Join Chip Loading State

**Status:** Draft
**Date:** 2026-05-12
**Refs:** ADR-E60-join-chip-loading.md, spec-multiroom-grouping.md US-80/US-81/US-83, design-spec-multiroom-grouping.md §4/§6.3, epics-and-tasks-multiroom-grouping.md E-60 (T-6001–T-6005)

---

## 1. Scope

This plan covers every testable contract introduced by E-60:

- `SessionViewModel.handleJoinDrop(source:target:)` full implementation replacing the E-59 stub — all success and failure paths, the idempotency guard, the 10-second `withThrowingTaskGroup` timeout, key lifecycle in `joinsInFlight`, haptic dispatch, `onError` callback routing, `mergeIntoSpeakerGroup` call ordering, `lastDropCompletedAt` update, `pulseChip` firing, and the 350 ms debounce before `refreshGroups()`.
- `ChipKind.loading(name: String)` — the new enum case added to `GroupChipRow.swift`; exhaustive switch compile-time contract; rendering properties (ProgressView, opacity, no tap gesture, accessibility label).
- `SpeakerCard.chipData` extension — loading chips appended after overflow computation; settled-wins dedup rule; loading chips excluded from overflow threshold; edge case of a speaker present in both `groupMembers` and `joinsInFlight`.
- `joinsInFlightUnion` reactive write in `SessionStripView` — fires on `joinsInFlight` mutations (not only on group-array changes); propagation to `SpeakerSelectorPill.isDraggable` within one render cycle.
- `onError` callback — delivered on `@MainActor`; writes `errorMessage` binding; message string variants for timeout, unreachable, and generic errors.
- `GroupingStrings` additions — five new string keys; EN and DA presence.
- `lastDropCompletedAt` — set on successful join; observed by coach-mark dismiss path.
- ≥ 300 ms debounce before `refreshGroups()` — satisfied by the 350 ms `Task.sleep` on the success path.

### What is explicitly out of scope

- E-61 `handleRemoveTap` — that epic owns its own test plan.
- E-59 drag infrastructure (stubs, ghost pill, drop zone border, coach-mark trigger) — covered by test-plan-E59.md.
- `SpeakerClient.join(peer:)` transport-layer correctness (Mozart/BNR network calls).
- `SpeakerDiscoveryService.mergeIntoSpeakerGroup` or `refreshGroups` internals — tested at the boundary (whether they are called, when, in what order).
- Backend, telemetry pipeline, voice command path.
- Manual LAN integration test (T-6005) — deferred to §10.

---

## 2. Test Environment

| Item | Value |
|---|---|
| Platform | iOS 26, iPhone (portrait) |
| Framework | SwiftUI, Swift 6, `@Observable @MainActor`, `withThrowingTaskGroup` |
| Test harness | No XCTest target exists. All TCs are manual verification procedures, static code-review assertions, or Xcode preview/simulator assertions. Where XCTest pseudocode appears, it is labelled "(XCTest — conditional on VoxioTests target)". |
| Accessibility testing | Xcode Accessibility Inspector + VoiceOver on simulator |
| Source files under test | `iOS/Voxio/Features/Home/SessionViewModel.swift` (modified), `iOS/Voxio/Features/Home/Components/GroupChipRow.swift` (modified), `iOS/Voxio/Features/Home/SpeakerCard.swift` (modified), `iOS/Voxio/Features/Home/SessionStripView.swift` (modified), `iOS/Voxio/Core/Strings/GroupingStrings.swift` (modified) |
| Speaker doubles | `SpeakerStub: @Observable @MainActor` — writable `identifier: SpeakerIdentifier`, `name: String`, `client: SpeakerClientSpy`. `SpeakerDiscoveryServiceSpy` — records `mergeIntoSpeakerGroupCallCount`, `refreshGroupsCallCount`; injectable `groups: [SpeakerGroup]`. |
| SpeakerClient double | `SpeakerClientSpy` — `var joinResult: Result<Void, Error> = .success(())`. `var joinDelay: Duration = .zero`. `join(peer:)` awaits `joinDelay` then delivers `joinResult`. Records `joinCallCount`. |
| HapticEngine double | `HapticEngineSpy` — records `commandRecognisedCallCount`, `errorOccurredCallCount` (extending E-59 spy). |
| onError double | `ErrorCapture` — `var messages: [String] = []`; closure `{ self.messages.append($0) }`. |
| Fixtures | `mozartSource = SpeakerStub(host: "192.168.1.10", jid: "src@beozone.local", name: "Stue")`, `mozartTarget = SpeakerStub(host: "192.168.1.20", jid: "tgt@beozone.local", name: "Badeværelse")`. Key for source: `"src@beozone.local"`. |

---

## 3. Unit-Level Test Cases — handleJoinDrop Happy Path

These cases target the full success path of `handleJoinDrop` in isolation, using `SpeakerClientSpy` that resolves immediately without delay.

---

### TC-E60-U01

**ID:** TC-E60-U01
**Title:** Happy path — key inserted into joinsInFlight synchronously on call
**ADR contract:** §7 "Insert `source.identifier.id` into `joinsInFlight`" — happens on the main actor before the Task is launched.
**Setup:** `vm = SessionViewModel(group: …, discovery: discoveryStub, onError: …)`. `spy.joinResult = .success(())`, `spy.joinDelay = .zero`.
**Action:** Call `vm.handleJoinDrop(source: mozartSource, target: mozartTarget)`. Immediately after the synchronous portion returns (before awaiting any Tasks), read `vm.joinsInFlight`.
**Expected:** `vm.joinsInFlight.contains("src@beozone.local") == true`. The key is present before any async work has a chance to remove it.
**Covers:** ADR §7 behavioural contract #1 (insert precedes Task launch); US-81 AC (loading chip appears "within one animation frame of the drop").

---

### TC-E60-U02

**ID:** TC-E60-U02
**Title:** Happy path — HapticEngine.commandRecognised fires synchronously before Task
**ADR contract:** §7 behavioural contract #2 — "HapticEngine.shared.commandRecognised() fires synchronously on the main actor."
**Setup:** Inject `HapticEngineSpy` as `HapticEngine.shared`. `spy.joinDelay = .milliseconds(50)`.
**Action:** Call `vm.handleJoinDrop(source: mozartSource, target: mozartTarget)`. Read `spy.commandRecognisedCallCount` immediately (synchronously, without yielding the actor).
**Expected:** `spy.commandRecognisedCallCount == 1`. The haptic fires in the synchronous portion of `handleJoinDrop`, not inside the detached Task.
**Covers:** ADR §7 contract #2; design-spec §4.1 step 1 ("HapticEngine.shared.commandRecognised() fires immediately").

---

### TC-E60-U03

**ID:** TC-E60-U03
**Title:** Happy path — mergeIntoSpeakerGroup called on success, key removed after merge
**ADR contract:** §7 contract #4 — "On success: `mergeIntoSpeakerGroup` fires BEFORE `joinsInFlight.remove` — model update visible while loading chip is still mounted; chip resolves to .member in the same render pass."
**Setup:** `spy.joinResult = .success(())`, `spy.joinDelay = .zero`. Await Task completion.
**Action:** Inside `SpeakerDiscoveryServiceSpy.mergeIntoSpeakerGroup`, record whether `joinsInFlight.contains(key)` is still true at the moment of the merge call.
**Expected:** At the time `mergeIntoSpeakerGroup` executes, `vm.joinsInFlight.contains("src@beozone.local") == true`. After the full success block completes, `vm.joinsInFlight.contains("src@beozone.local") == false`.
**Covers:** ADR §7 contract #4; US-81 AC ("chip transitions to full-opacity … source pill regains full opacity").

---

### TC-E60-U04

**ID:** TC-E60-U04
**Title:** Happy path — pulseChip fires immediately on success, before 350 ms sleep
**ADR contract:** §7 contract #6 — "pulsingChips.insert fires immediately on success, before the 350 ms sleep."
**Setup:** `spy.joinResult = .success(())`, `spy.joinDelay = .zero`. Observe `vm.pulsingChips`.
**Action:** After awaiting Task completion (but before 350 ms has elapsed), check `vm.pulsingChips`.
**Expected:** `vm.pulsingChips.contains("src@beozone.local") == true` immediately after success block fires. The chip id is present before `Task.sleep(.milliseconds(350))` completes.
**Covers:** ADR §7 contract #6; design-spec §4.1 step 7 (pulse plays "on success").

---

### TC-E60-U05

**ID:** TC-E60-U05
**Title:** Happy path — lastDropCompletedAt set on successful join
**ADR contract:** §7 contract #7 — "lastDropCompletedAt = Date() fires on every successful join."
**Setup:** `vm.lastDropCompletedAt` is nil initially. `spy.joinResult = .success(())`.
**Action:** Call `vm.handleJoinDrop(…)`. Await Task completion. Read `vm.lastDropCompletedAt`.
**Expected:** `vm.lastDropCompletedAt != nil`. The value is approximately the current date (within 1 second of the call). Calling `handleJoinDrop` a second time (new source) updates `lastDropCompletedAt` again.
**Covers:** ADR §5 "Coach-mark dismiss path"; ADR §7 contract #7; design-spec §4.1 step 7 / US-84 AC ("coach mark is dismissed permanently if the user completes a successful drop").

---

### TC-E60-U06

**ID:** TC-E60-U06
**Title:** Happy path — 350 ms sleep occurs before refreshGroups, satisfying ≥ 300 ms debounce
**ADR contract:** §5 "The ≥ 300 ms debounce is `Task.sleep(for: .milliseconds(350))` inside the success branch … BEFORE calling `refreshGroups()`." ADR-003 §5 contract 6.
**Setup:** `spy.joinResult = .success(())`. Record wall-clock time in `SpeakerDiscoveryServiceSpy.refreshGroups()` and compare with time of merge call.
**Action:** Note the timestamp when `mergeIntoSpeakerGroup` is called. Note the timestamp when `refreshGroups()` is called.
**Expected:** `refreshGroups` is called at least 300 ms after `mergeIntoSpeakerGroup`. `discoveryStub.refreshGroupsCallCount == 1` after full Task completion. `discoveryStub.mergeIntoSpeakerGroupCallCount == 1` and precedes `refreshGroupsCallCount`.
**Covers:** ADR §5 "Debounce implementation"; ADR-003 §5 contract 6; spec TR-4 step 3.

---

### TC-E60-U07

**ID:** TC-E60-U07
**Title:** Happy path — key removed from joinTasks on success
**ADR contract:** §7 "self.joinTasks.removeValue(forKey: key)" on the success path.
**Setup:** `spy.joinResult = .success(())`.
**Action:** After `handleJoinDrop` synchronous portion: `vm.joinTasks["src@beozone.local"] != nil`. After Task completes: read `vm.joinTasks`.
**Expected:** `vm.joinTasks["src@beozone.local"] == nil` after success. The task is cleaned up.
**Covers:** ADR §7 success path cleanup; spec TR-4 step 3.

---

### TC-E60-U08

**ID:** TC-E60-U08
**Title:** Idempotency — re-entry while key present returns immediately, no duplicate Task
**ADR contract:** §7 "guard !joinsInFlight.contains(key) else { return }" and behavioural contract #1 (idempotency).
**Setup:** `spy.joinDelay = .seconds(5)` (slow join, keeps key in flight). Call `vm.handleJoinDrop(source: mozartSource, target: mozartTarget)` once. Key is now in `joinsInFlight`. Call again immediately with the same source.
**Action:** Check `vm.joinTasks.count`, `spy.joinCallCount`, `spy.commandRecognisedCallCount` after both calls.
**Expected:** `spy.joinCallCount == 1` (client called only once). `vm.joinTasks.count == 1`. `spy.commandRecognisedCallCount == 1`. The second call is a no-op — no new Task, no new haptic, no new key insertion.
**Covers:** ADR §7 behavioural contract #1 (idempotency); spec TR-4 (defensive guard on re-entry); US-81 ("Drop occurs while another join from the same source is in flight").

---

## 4. Unit-Level Test Cases — handleJoinDrop Error and Timeout Paths

---

### TC-E60-U09

**ID:** TC-E60-U09
**Title:** Timeout path — SpeakerError.timeout thrown; key removed; errorOccurred fires; onError called with timeout message
**ADR contract:** §7 behavioural contract #9 — "SpeakerError.timeout → 'Couldn't add NAME — connection timed out'." ADR §5 "ADR-002 D5 — 10-second timeout."
**Setup:** `spy.joinResult = .failure(SpeakerError.timeout)`. `spy.joinDelay = .zero` (throw immediately without waiting 10 s — simulates timeout error from the task group race, since `SpeakerError.timeout` is what `joinWithTimeout` throws when the sleep leg wins).
**Action:** Call `vm.handleJoinDrop(source: mozartSource, target: mozartTarget)`. Await Task completion.
**Expected:**
- `vm.joinsInFlight.contains("src@beozone.local") == false` (key removed on failure path).
- `vm.joinTasks["src@beozone.local"] == nil` (task cleaned up).
- `hapticSpy.errorOccurredCallCount == 1`.
- `errorCapture.messages.count == 1`.
- `errorCapture.messages[0]` contains both the speaker name `"Stue"` and the timeout reason (e.g. "connection timed out" or the DA equivalent depending on active language).
- `discoveryStub.mergeIntoSpeakerGroupCallCount == 0` (no merge on failure).
- `discoveryStub.refreshGroupsCallCount == 0` (no refresh on failure).
**Covers:** ADR §7 contract #9 (timeout message); ADR §5 consequences "Debounce implementation"; spec error table row "throws SpeakerError.timeout"; US-81 AC ("On API failure: chip fades out … error toast appears with the speaker name and reason").

---

### TC-E60-U10

**ID:** TC-E60-U10
**Title:** Unreachable path — SpeakerError.unreachable thrown; onError called with unreachable message
**ADR contract:** §7 contract #9 — "SpeakerError.unreachable → 'Couldn't add NAME — speaker unreachable'."
**Setup:** `spy.joinResult = .failure(SpeakerError.unreachable)`.
**Action:** Await Task completion.
**Expected:**
- `errorCapture.messages[0]` contains `"Stue"` and the unreachable reason substring (e.g. "speaker unreachable" or DA equivalent).
- `hapticSpy.errorOccurredCallCount == 1`.
- `vm.joinsInFlight.contains("src@beozone.local") == false`.
**Covers:** ADR §7 contract #9 (unreachable variant); spec error table row "throws SpeakerError.unreachable".

---

### TC-E60-U11

**ID:** TC-E60-U11
**Title:** Generic error path — unknown error thrown; onError called with generic message (no reason suffix)
**ADR contract:** §7 contract #9 — "Other → 'Couldn't add NAME'."
**Setup:** `spy.joinResult = .failure(URLError(.networkConnectionLost))` (an error that is neither `.timeout` nor `.unreachable`).
**Action:** Await Task completion.
**Expected:**
- `errorCapture.messages[0]` contains `"Stue"` but does NOT contain "timed out" or "unreachable".
- The message is the generic form (no reason suffix appended).
- `hapticSpy.errorOccurredCallCount == 1`.
- `vm.joinsInFlight.contains("src@beozone.local") == false`.
**Covers:** ADR §7 contract #9 (generic variant); spec error table "throws other error".

---

### TC-E60-U12

**ID:** TC-E60-U12
**Title:** 10-second client-side timeout — withThrowingTaskGroup races join against Task.sleep(10 s)
**ADR contract:** ADR §5 "ADR-002 D5 — 10-second client-side timeout enforced via `withThrowingTaskGroup`." ADR §7 `joinWithTimeout` pseudocode.
**Setup:** `spy.joinDelay = .seconds(15)` (join never completes within 10 s). Do NOT use `spy.joinResult` override — let the spy hang. Time the test with a 12-second wall-clock budget.
**Action:** Call `vm.handleJoinDrop(…)`. Await Task completion (it should complete in ~10 s due to the timeout leg winning).
**Expected:**
- Task completes in ≤ 11 seconds (timeout fires at 10 s).
- `errorCapture.messages[0]` contains the timeout reason (the sleep leg throws `SpeakerError.timeout`).
- `hapticSpy.errorOccurredCallCount == 1`.
- `vm.joinsInFlight.contains("src@beozone.local") == false`.
**Note:** This is a slow test. Mark it as `@SlowTest` or equivalent; run separately from fast unit tests. Acceptable in the CI pipeline only in nightly/integration builds.
**Covers:** ADR §7 `joinWithTimeout`; ADR §5 consequences; ADR-002 D5; US-81 AC ("up to 10 seconds per UQ-3"); spec §4.1 step 4 "10-second client-side timeout."

---

### TC-E60-U13

**ID:** TC-E60-U13
**Title:** onError callback — delivered on @MainActor; writes to binding
**ADR contract:** §7 behavioural contract #8 — "onError is always called on the main actor."
**Setup:** `errorCapture` records messages AND the thread it is called on (`Thread.isMainThread`).
**Action:** Call `vm.handleJoinDrop(…)` with `spy.joinResult = .failure(SpeakerError.timeout)`. Await Task completion.
**Expected:** `errorCapture.calledOnMainThread == true`. The message is delivered on the main actor, satisfying the `@MainActor` isolation required to write to an `@Binding<String>`.
**Covers:** ADR §7 contract #8; ADR §3.3 Option A "SessionStripView injects a closure that writes to HomeView's errorMessage binding — same plumbing E-56 already uses."

---

### TC-E60-U14

**ID:** TC-E60-U14
**Title:** SUCCESS but mergeIntoSpeakerGroup has no effect (host group disappeared mid-flight)
**ADR contract:** ADR §7 "the merge is a no-op if the target group no longer exists" — spec TR-4 step 5. This documents the currently-undefined-but-contractually-safe behavior.
**Setup:** `spy.joinResult = .success(())`. Arrange `discoveryStub.mergeIntoSpeakerGroup` to be a no-op (group absent from discovery). No crash expected.
**Action:** Call `vm.handleJoinDrop(…)`. Await Task completion. Observe `vm.joinsInFlight`, `vm.lastDropCompletedAt`, `discoveryStub.refreshGroupsCallCount`.
**Expected:**
- No crash or exception.
- `vm.joinsInFlight.contains("src@beozone.local") == false` (key removed normally).
- `vm.lastDropCompletedAt != nil` (date is set — the success path ran to completion even though the merge was a no-op).
- `discoveryStub.refreshGroupsCallCount == 1` (refresh still fires; it will reconstruct the correct state from the network).
**Covers:** ADR §5 "On success … model mutation is a no-op if the host group no longer exists"; spec TR-4 step 5; US-81 AC (background-during-flight scenario).

---

## 5. Integration Test Cases — ChipKind.loading Rendering and chipData Extension

---

### TC-E60-I01

**ID:** TC-E60-I01
**Title:** ChipKind.loading exhaustive switch — adding .loading case compiles without @unknown default
**ADR contract:** ADR §5 "No `@unknown default` — future cases must compile-break." ADR-E59 §5 "E-59 must NOT add `@unknown default` to the switch."
**Verification type:** Static code review.
**Action:** Open `iOS/Voxio/Features/Home/Components/GroupChipRow.swift`. Locate `GroupChipRow.body`'s switch statement over `chip.kind`. Verify all three cases are handled exhaustively: `.member`, `.overflow(Int)`, `.loading(name: String)`.
**Expected:**
- The switch is exhaustive with exactly three `case` branches.
- There is NO `default:` or `@unknown default:` branch.
- Build succeeds with Swift 6 strict concurrency checks enabled (`-strict-concurrency=complete`).
- If `.loading` is absent, the build fails with "Switch must be exhaustive" — confirming the compile-break contract from ADR-E53 §5 CF-3.
**Covers:** ADR-E60 §5 "ChipKind enum growth policy"; ADR-E53 §5 CF-3 compile-break intent; ADR-E59 §5 constraints.

---

### TC-E60-I02

**ID:** TC-E60-I02
**Title:** Loading chip rendering — ProgressView visible, name label present, chip at 0.6 opacity
**ADR contract:** §7 GroupChipRow rendering contract #1 (ProgressView 10 pt) and #2 (0.6 opacity); design-spec §4.2.
**Verification type:** Xcode Preview or SwiftUI simulator visual inspection.
**Setup:** Construct a `GroupChipRow` in an Xcode Preview that includes a `ChipData` with `kind: .loading(name: "Stue")`.
**Action:** Render the preview. Inspect the chip visually.
**Expected:**
- A circular `ProgressView` (10 pt frame) appears on the leading edge of the chip label.
- The name "Stue" is visible as the label text.
- The overall chip opacity is 0.6 (visually dimmed compared to a `.member` chip alongside it).
- The chip background is the same capsule shape as `.member` chips (white at 0.07 opacity).
- No `+` prefix icon — ProgressView replaces it.
**Covers:** ADR §7 rendering contract #1–#2; design-spec §4.1 step 3 / §4.2 "loading state (dimmed label + inline spinner)"; US-81 AC.

---

### TC-E60-I03

**ID:** TC-E60-I03
**Title:** Loading chip is not interactive — no tap gesture, no drag source
**ADR contract:** §7 rendering contract #4 — "No .onTapGesture — loading chips are non-interactive (US-81)." ADR §5 E-61 note — "E-61 attaches a tap gesture to .member chips only."
**Verification type:** Code review + Xcode Preview hit-test inspection.
**Action (code review):** Confirm the `.loading(name:)` case in `GroupChipRow.body` has no `.onTapGesture`, no `Button` wrapper, no `.draggable`, no `.contentShape` that would enable tapping.
**Action (simulator):** In a preview with a loading chip, attempt to tap the chip. Confirm no action fires.
**Expected:**
- No tap handler attached to the loading chip view.
- The chip has no `.accessibilityRole(.button)` (it is a status element, not a control).
- VoiceOver announces the chip using `.accessibilityLabel` only (not as a button).
**Covers:** ADR §7 contract #4; US-81 AC ("The loading chip is not interactive — tapping it does nothing"); ADR §5 E-61 precondition.

---

### TC-E60-I04

**ID:** TC-E60-I04
**Title:** Loading chip accessibility label uses connectingFormat string
**ADR contract:** §7 rendering contract #3 — ".accessibilityLabel uses strings.connectingFormat = 'Connecting %@…' / 'Forbinder %@…'."
**Verification type:** Xcode Accessibility Inspector + code review.
**Action:** Open Accessibility Inspector against a preview containing a `.loading(name: "Stue")` chip with English locale.
**Expected:**
- Accessibility label reads `"Connecting Stue…"`.
- With Danish locale active, label reads `"Forbinder Stue…"`.
- The format string is sourced from `GroupingStrings.connectingFormat` — not hardcoded.
**Covers:** ADR §7 contract #3; design-spec Appendix B (`a11y.chip.loading`); US-81 AC (accessibility).

---

### TC-E60-I05

**ID:** TC-E60-I05
**Title:** chipData — loading chips appear AFTER overflow chip, never before
**ADR contract:** §7 `SpeakerCard.chipData` contract #1 — "Loading chips append AFTER overflow chip. Never count toward overflow threshold."
**Setup:** `groupMembers = [A, B, C, D]` (4 members → overflow triggered at >3). `joinsInFlight = {"src@beozone.local"}`. Expected settled chips: [A, B] + `.overflow(2)`. Loading chip for Stue should follow the overflow chip.
**Action:** Compute `chipData` from a `SpeakerCard` with 4 `groupMembers` and one in-flight join. Inspect the resulting array.
**Expected:**
- `chipData[0].kind == .member` (speaker A)
- `chipData[1].kind == .member` (speaker B)
- `chipData[2].kind == .overflow(2)`
- `chipData[3].kind == .loading(name: "Stue")`
- `chipData.count == 4`
- The overflow count is still 2 (not 3 — loading chip does NOT increment overflow).
**Covers:** ADR §7 chipData contract #1; design-spec §4.2 (chip row shows both settled and loading); US-81 AC.

---

### TC-E60-I06

**ID:** TC-E60-I06
**Title:** chipData dedup — speaker in BOTH groupMembers AND joinsInFlight; settled chip wins
**ADR contract:** §7 `SpeakerCard.chipData` contract #2 — "If a speaker is in both groupMembers AND joinsInFlight (model/task race), the settled chip wins; loading chip is omitted."
**Setup:** `groupMembers = [mozartSource]` (source speaker already merged into group — merge happened, key not yet removed from joinsInFlight). `joinsInFlight = {"src@beozone.local"}`.
**Action:** Compute `chipData`.
**Expected:**
- `chipData.count == 1`.
- `chipData[0].kind == .member` (settled chip, not loading).
- No `.loading` chip present for the same speaker.
**Covers:** ADR §7 chipData contract #2; "settledIds guard" in chipData logic; ADR §7 contract #4 (merge fires before key removal — ensures this case is exercised in the real flow).

---

### TC-E60-I07

**ID:** TC-E60-I07
**Title:** chipData with no joinsInFlight — result matches pre-E-60 chipData exactly
**ADR contract:** ADR §5 E-61 precondition — E-60 must not change `ChipData`'s stored properties; loading chip path is additive only.
**Setup:** `joinsInFlight = []`. `groupMembers = [A, B]`.
**Action:** Compute `chipData`. Compare with the result of the pre-E-60 chip computation (members only, no loading chips).
**Expected:**
- `chipData.count == 2`.
- Both chips have `kind == .member`.
- No `.loading` chips are appended.
- Regression: no change to settled chip behavior.
**Covers:** ADR §5 "E-61 must not be precluded" (stored property stability); regression guard.

---

### TC-E60-I08

**ID:** TC-E60-I08
**Title:** chipData — multiple in-flight joins produce multiple loading chips
**ADR contract:** chipData iterates `vm.joinsInFlight` and appends one chip per id not in settledIds.
**Setup:** `groupMembers = [A]`. `joinsInFlight = {"src1", "src2"}` (two concurrent in-flight joins). `resolveSpeaker` returns `SpeakerStub(name: "Stue")` for "src1" and `SpeakerStub(name: "Kitchen")` for "src2".
**Action:** Compute `chipData`.
**Expected:**
- `chipData.count == 3` (one .member + two .loading chips).
- `.member` chip for A.
- Two `.loading` chips with names "Stue" and "Kitchen" (order is deterministic based on `Set` iteration — note: Set iteration order is not guaranteed; test should check for presence, not position).
**Covers:** spec TR-4 last row in error table "User drags a pill while a join from a different source is already in flight on the same card — allowed."

---

### TC-E60-I09

**ID:** TC-E60-I09
**Title:** chipData — JID-keyed Mozart source that fails resolveSpeaker lookup falls back to raw JID string
**ADR contract:** ADR §5 CF-3 / §7 chipData contract #3 — "Mozart speakers whose joinsInFlight key is a JID may miss and fall back to displaying the raw JID string. Cosmetic degradation acceptable."
**Setup:** `joinsInFlight = {"unknown@beozone.local"}`. `discoveryGroups` has no speaker with `jid == "unknown@beozone.local"`. `resolveSpeaker` returns `nil`.
**Action:** Compute `chipData`.
**Expected:**
- A `.loading` chip is appended with `name == "unknown@beozone.local"` (the raw JID string as fallback).
- No crash.
- No nil chip in the array.
**Covers:** ADR §5 CF-3 (cosmetic degradation); ADR §7 chipData fallback path.

---

## 6. Acceptance Test Cases — joinsInFlightUnion Reactive Write and Coach Mark Dismiss

---

### TC-E60-A01

**ID:** TC-E60-A01
**Title:** joinsInFlightUnion reactive write — fires on joinsInFlight insert (not only on group-array changes)
**ADR contract:** ADR §5 "E-60 T-6004 adds `.onChange(of: sessionVMs.values.map { $0.joinsInFlight })` in `SessionStripView` so the binding writes propagate on every `joinsInFlight` mutation." ADR §7 SessionStripView wiring contract #1.
**Verification type:** Code review + Xcode simulator state inspection.
**Action (code review):** Open `iOS/Voxio/Features/Home/SessionStripView.swift`. Confirm two `.onChange` observers are present:
  1. The existing `.onChange(of: groups.map(\.id))` (from E-59 cleanup).
  2. The new `.onChange(of: sessionVMs.values.map { $0.joinsInFlight })` (E-60 T-6004).
**Action (simulator):** In a running session, call `vm.handleJoinDrop(…)`. Inspect `HomeView.joinsInFlightUnion` (via Xcode state viewer or debug print) immediately after the synchronous insertion.
**Expected:**
- `joinsInFlightUnion` contains the source speaker's key within the same render cycle as the `joinsInFlight` insertion.
- A group-array change alone is NOT required for the union to update — the `.onChange` on `joinsInFlight` itself triggers the write.
**Covers:** ADR §5 "Reactive joinsInFlightUnion write"; ADR §7 SessionStripView contract #1; spec TR-5 "source pill renders at 0.5 opacity for the full call duration."

---

### TC-E60-A02

**ID:** TC-E60-A02
**Title:** joinsInFlightUnion propagates to SpeakerSelectorPill.isDraggable within one render cycle
**ADR contract:** ADR §7 SessionStripView contract #3 — "Write propagates to HomeView's @State within the same render cycle."
**Verification type:** Xcode simulator inspection.
**Setup:** At least one idle (draggable) pill in the bottom bar. No joins in flight initially. Confirm the pill renders at full opacity.
**Action:** Initiate a `handleJoinDrop` call (or simulate it via a debug button injecting directly into `vm.joinsInFlight`). Observe the pill in the next frame.
**Expected:**
- The source pill transitions from 1.0 to 0.5 opacity within one render cycle of the `joinsInFlight` insert.
- `SpeakerSelectorPill.isDraggable` returns `false` for the in-flight speaker (confirmed via code review: the `joinsInFlightUnion.contains(speaker.identifier.id)` branch returns false).
- The `.draggable` modifier is absent from the pill for the duration of the join.
**Covers:** ADR §5 "Reactive joinsInFlightUnion write"; spec TR-5; US-81 AC ("source pill remains at 0.5 opacity … non-draggable … until API call resolves").

---

### TC-E60-A03

**ID:** TC-E60-A03
**Title:** joinsInFlightUnion clears — pill regains full opacity after success
**ADR contract:** On success path, key removed from `joinsInFlight` → `joinsInFlightUnion` no longer contains it → `isDraggable` returns true → pill at 1.0 opacity.
**Setup:** Source pill at 0.5 opacity during in-flight join. `spy.joinResult = .success(())`.
**Action:** Await join Task completion (success path runs). Observe the source pill.
**Expected:**
- Source pill transitions back to 1.0 opacity within one render cycle of the `joinsInFlight` removal.
- `vm.joinsInFlight.isEmpty == true`.
- `vm.joinsInFlightUnion.isEmpty == true` (as computed on `SessionStripView`).
**Covers:** US-81 AC ("source pill regains full opacity"); spec TR-5.

---

### TC-E60-A04

**ID:** TC-E60-A04
**Title:** joinsInFlightUnion clears — pill regains full opacity after failure
**ADR contract:** Failure path also removes key from `joinsInFlight` → same pill restoration as TC-E60-A03.
**Setup:** Source pill at 0.5 opacity during in-flight join. `spy.joinResult = .failure(SpeakerError.timeout)`.
**Action:** Await join Task completion (failure path). Observe the source pill.
**Expected:**
- Source pill transitions back to 1.0 opacity and becomes draggable again.
- Error toast is shown (TC-E60-U09 covers the message content).
**Covers:** US-81 AC ("On API failure … source pill regains full opacity and is draggable again"); spec TR-5.

---

### TC-E60-A05

**ID:** TC-E60-A05
**Title:** Coach mark dismiss — lastDropCompletedAt change triggers onDismiss path
**ADR contract:** ADR §5 "Coach-mark dismiss path — Add `var lastDropCompletedAt: Date? = nil` on `SessionViewModel`… `HomeView` or `SessionStripView` observes via `.onChange(of:)` and triggers coach-mark `onDismiss`."
**Verification type:** Code review + Xcode simulator.
**Action (code review):** In `SessionStripView.swift` (or `HomeView.swift`), confirm a `.onChange(of: sessionVM.lastDropCompletedAt)` (or equivalent) observer calls the coach mark's `onDismiss` closure.
**Action (simulator):** With the coach mark showing (first-time eligible drag scenario), complete a successful join. Confirm the coach mark fades out.
**Expected:**
- Coach mark dismisses on the render cycle following `lastDropCompletedAt` being set.
- `@AppStorage("hasSeenGroupingCoachMark")` is set to `true` (the `onDismiss` path in `GroupingCoachMark` writes it).
- Coach mark does not reappear after dismissal.
**Covers:** ADR §5 "Coach-mark dismiss path"; US-84 AC ("dismissed permanently if the user completes a successful drop"); spec TR-7.

---

### TC-E60-A06

**ID:** TC-E60-A06
**Title:** Coach mark dismiss — NOT triggered on failure (lastDropCompletedAt unchanged)
**ADR contract:** ADR §7 contract #7 — "lastDropCompletedAt = Date() fires on every successful join" — by implication, it does NOT fire on failure.
**Setup:** Coach mark visible (`hasSeenGroupingCoachMark = false`). `spy.joinResult = .failure(SpeakerError.timeout)`.
**Action:** Complete a failed join. Observe coach mark.
**Expected:**
- `vm.lastDropCompletedAt` remains `nil` (or unchanged if previously set).
- Coach mark is NOT dismissed by the failure path.
- Coach mark still auto-dismisses after 3 seconds per the existing timer (E-59 contract).
**Covers:** ADR §7 contract #7 (fires on success only); US-84 AC (3-second auto-dismiss remains operative on failure).

---

## 7. Error States and Boundary Values

---

### TC-E60-E01

**ID:** TC-E60-E01
**Title:** Boundary — joinsInFlight key uses SpeakerIdentifier.id (JID-first, host fallback)
**ADR contract:** `let key = source.identifier.id` — `id` is `jid ?? host` per ADR-E59 §7.
**Setup:** Two source speakers: `mozartSource` (has JID) and `aseSource` (jid = nil, host = "192.168.1.30").
**Action:** For each, call `handleJoinDrop`, capture the key used in `joinsInFlight`.
**Expected:**
- `mozartSource` → key is `"src@beozone.local"` (JID wins).
- `aseSource` → key is `"192.168.1.30"` (host fallback when JID is nil).
- Both keys are non-empty strings.
**Covers:** ADR §7 "let key = source.identifier.id"; ADR-E59 §7 contract #2 (".id is always non-empty").

---

### TC-E60-E02

**ID:** TC-E60-E02
**Title:** Boundary — empty joinsInFlight at load; no phantom loading chips
**ADR contract:** `chipData` only iterates `vm.joinsInFlight` when it is non-empty. Default state must produce zero loading chips.
**Setup:** Fresh `SessionViewModel` with `joinsInFlight = []`. `groupMembers = [A]`.
**Action:** Compute `chipData`. Inspect for loading chips.
**Expected:** `chipData` contains exactly one `.member` chip for A. No `.loading` chips.
**Covers:** Regression guard for chipData extension; spec US-82 ("chip row lists every member… F2 makes no visual change to the chip presentation").

---

### TC-E60-E03

**ID:** TC-E60-E03
**Title:** Boundary — overflow computation unaffected when multiple loading chips present
**ADR contract:** ADR §7 chipData contract #1 — loading chips "never count toward overflow threshold."
**Setup:** `groupMembers = [A, B, C]` (3 members — exactly at the 3-member boundary; overflow only triggers at >3). `joinsInFlight = {"src1", "src2"}`.
**Action:** Compute `chipData`.
**Expected:**
- Overflow is NOT triggered (settled count is 3, not >3).
- `chipData = [.member(A), .member(B), .member(C), .loading("Stue"), .loading("Kitchen")]`.
- `chipData.count == 5`.
- No `.overflow` chip present.
**Covers:** ADR §7 chipData contract #1 (loading chips excluded from overflow threshold).

---

### TC-E60-E04

**ID:** TC-E60-E04
**Title:** GroupingStrings additions — all five new keys present in English and Danish
**ADR contract:** ADR §7 `GroupingStrings` additions — five keys: `joinFailed`, `joinFailedGeneric`, `joinFailedTimeout`, `joinFailedUnreachable`, `connectingFormat`.
**Verification type:** Code review.
**Action:** Open `iOS/Voxio/Core/Strings/GroupingStrings.swift`. Confirm all five properties exist on the struct. Confirm `GroupingStrings.english` and `GroupingStrings.danish` both supply non-empty values for all five.
**Expected:**
- `GroupingStrings.english.joinFailed` matches the format `"Couldn't add %@ — %@"` (two placeholders).
- `GroupingStrings.english.joinFailedGeneric` matches `"Couldn't add %@"` (one placeholder).
- `GroupingStrings.english.joinFailedTimeout` is a non-empty reason suffix (e.g. `"connection timed out"`).
- `GroupingStrings.english.joinFailedUnreachable` is a non-empty reason suffix (e.g. `"speaker unreachable"`).
- `GroupingStrings.english.connectingFormat` matches `"Connecting %@…"`.
- All DA equivalents are non-empty and distinct from EN values.
- `GroupingStrings.forLanguage(.english)` returns the english static instance; `.forLanguage(.danish)` returns the danish static instance.
**Covers:** ADR §7 GroupingStrings contract; ADR CF-1 (no ToastCenter — error message routed via strings struct); design-spec Appendix B.

---

### TC-E60-E05

**ID:** TC-E60-E05
**Title:** errorToastText mapper — switch is exhaustive over SpeakerError cases used in E-60
**ADR contract:** ADR §7 `errorToastText(for:speakerName:)` switch — `.timeout`, `.unreachable`, `default`.
**Verification type:** Code review.
**Action:** Open `SessionViewModel.errorToastText(for:speakerName:)`. Confirm the switch covers `.timeout` and `.unreachable` as explicit cases with distinct messages, and that all other errors fall to `default`.
**Expected:**
- `.timeout` case returns `String(format: strings.joinFailed, speakerName, strings.joinFailedTimeout)`.
- `.unreachable` case returns `String(format: strings.joinFailed, speakerName, strings.joinFailedUnreachable)`.
- `default` case returns `String(format: strings.joinFailedGeneric, speakerName)`.
- No magic string literals in the switch — all text sourced from `GroupingStrings`.
**Covers:** ADR §7 `errorToastText` implementation; ADR §7 contracts #9; spec error table (3 error rows).

---

### TC-E60-E06

**ID:** TC-E60-E06
**Title:** pulsingChips auto-clears after 400 ms
**ADR contract:** ADR §7 `pulseChip(for:)` — "insert the speaker's identifier id into the set, schedule a Task to remove it after 0.4 s."
**Setup:** `spy.joinResult = .success(())`. Observe `vm.pulsingChips` over time.
**Action:** After Task success completes, confirm chip id is in `pulsingChips`. Wait 450 ms. Check `pulsingChips` again.
**Expected:**
- `vm.pulsingChips.contains("src@beozone.local") == true` immediately after success.
- `vm.pulsingChips.contains("src@beozone.local") == false` after 450 ms.
- The chip id does not remain permanently in `pulsingChips`.
**Covers:** ADR §7 `pulseChip` implementation; design-spec §4.1 step 7 ("brief pulse … 1.0 → 0.7 → 1.0 over 0.4 s").

---

### TC-E60-E07

**ID:** TC-E60-E07
**Title:** SessionViewModel.init signature — onError parameter present; no default; breaks old call sites
**ADR contract:** ADR §5 CF-6 — "Adding `onError: @escaping (String) -> Void` to `init` requires updating the construction site."
**Verification type:** Build-time verification.
**Action:** Confirm `SessionViewModel.init(group:discovery:onError:)` is the canonical initializer. Confirm all call sites in `SessionStripView.resolvedSessionVM(for:)` pass a valid `onError` closure. Confirm no call site omits the parameter (it has no default value — intentional, per ADR CF-6 to force the updater to wire it correctly).
**Expected:**
- Build succeeds with the updated call site in `SessionStripView`.
- No other call site in the project is missing `onError`.
**Covers:** ADR §5 CF-6; ADR §6 "resolvedSessionVM(for:) — update to inject onError."

---

## 8. Coverage Matrix — AC/ER to TC IDs

| AC / Requirement | Test Case(s) |
|---|---|
| **US-81 AC** — loading chip appears within one frame of drop | TC-E60-U01, TC-E60-I02, TC-E60-A01 |
| **US-81 AC** — loading chip persists for full call duration (up to 10 s) | TC-E60-U01, TC-E60-U12 |
| **US-81 AC** — success: chip transitions to full opacity + pulse | TC-E60-U03, TC-E60-U04, TC-E60-E06 |
| **US-81 AC** — failure: chip fades out; source pill regains opacity; error toast appears | TC-E60-U09, TC-E60-U10, TC-E60-U11, TC-E60-A04 |
| **US-81 AC** — loading chip is not interactive | TC-E60-I03 |
| **US-81 AC** — in-flight task continues if app backgrounds or card scrolls off-screen | TC-E60-U14 (host-gone variant), §10 TC-E60-M01 |
| **US-81 AC** — mergeIntoSpeakerGroup called only after API success (non-optimistic) | TC-E60-U03, TC-E60-U09 |
| **US-80 AC** — source pill at 0.5 opacity during in-flight join | TC-E60-A01, TC-E60-A02 |
| **US-80 AC** — source pill non-draggable during in-flight join | TC-E60-A02 |
| **US-84 AC** — coach mark dismissed on successful drop | TC-E60-A05 |
| **US-84 AC** — coach mark NOT dismissed on failure | TC-E60-A06 |
| **ADR §7 contract #1** — key inserted before Task launches | TC-E60-U01 |
| **ADR §7 contract #2** — commandRecognised fires synchronously | TC-E60-U02 |
| **ADR §7 contract #3** — Task is NOT cancelled on view teardown | TC-E60-U14, §10 TC-E60-M01 |
| **ADR §7 contract #4** — merge BEFORE key remove | TC-E60-U03 |
| **ADR §7 contract #5** — refreshGroups after ≥ 300 ms | TC-E60-U06 |
| **ADR §7 contract #6** — pulseChip fires before 350 ms sleep | TC-E60-U04 |
| **ADR §7 contract #7** — lastDropCompletedAt set on success | TC-E60-U05, TC-E60-A05 |
| **ADR §7 contract #8** — onError on @MainActor | TC-E60-U13 |
| **ADR §7 contract #9** — error message variants (timeout/unreachable/generic) | TC-E60-U09, TC-E60-U10, TC-E60-U11, TC-E60-E05 |
| **ADR §7 chipData contract #1** — loading chips after overflow, not counted | TC-E60-I05, TC-E60-E03 |
| **ADR §7 chipData contract #2** — settled chip wins over loading when same speaker | TC-E60-I06 |
| **ADR §7 chipData contract #3** — JID-miss fallback to raw string | TC-E60-I09 |
| **ADR §5 — exhaustive switch, no @unknown default** | TC-E60-I01 |
| **ADR §5 — debounce 350 ms** | TC-E60-U06 |
| **ADR §5 — coach-mark dismiss via lastDropCompletedAt** | TC-E60-A05, TC-E60-A06 |
| **ADR §5 CF-3 — chipData no new stored properties on ChipData** | TC-E60-I07 |
| **ADR §5 CF-6 — onError required in init, no default** | TC-E60-E07 |
| **ADR-003 §5 contract 6 — ≥ 300 ms debounce** | TC-E60-U06 |
| **design-spec §4.2 — 0.6 opacity on loading chip** | TC-E60-I02 |
| **design-spec §4.1 step 1 — commandRecognised immediately** | TC-E60-U02 |
| **design-spec §6.3 — join NOT optimistic** | TC-E60-U03 |
| **GroupingStrings five new keys (EN + DA)** | TC-E60-E04 |
| **Idempotency** | TC-E60-U08 |
| **10-second client-side timeout (ADR-002 D5)** | TC-E60-U12 |
| **joinsInFlightUnion reactive write** | TC-E60-A01, TC-E60-A02, TC-E60-A03, TC-E60-A04 |

---

## 9. Spec Gaps Discovered

The following gaps or ambiguities were identified during test case derivation. They do not block E-60 implementation but should be addressed before E-61 or the final F2 acceptance pass.

### SG-1: lastDropCompletedAt observable wiring not specified in a single file

ADR-E60 §5 states "HomeView or SessionStripView observes via `.onChange(of:)` and triggers coach-mark `onDismiss`" but does not specify which file owns this observer. TC-E60-A05 references it but the implementer must choose. Recommendation: add the observer to `SessionStripView` alongside the existing `.onChange(of: groups.map(\.id))` pattern, so all join-lifecycle side-effects are co-located.

### SG-2: pulsingChips visibility in GroupChipRow is undefined in ADR-E60

ADR-E60 §6 adds `pulsingChips: Set<String>` to `SessionViewModel` and §7 defines `pulseChip(for:)`, but there is no ADR contract specifying how `GroupChipRow` reads `pulsingChips` to animate the settled chip. The pulse animation (opacity keyframe 1.0 → 0.7 → 1.0 over 0.4 s) is described in the epics doc T-6003 and design-spec §4.1 step 7 but is not in ADR-E60 §7. TC-E60-E06 can verify the set lifecycle in isolation, but the rendering connection is untested without a contract. Recommendation: add a chipData or GroupChipRow rendering contract to ADR-E60 §7 specifying how `pulsingChips` drives the opacity animation, or document it in the T-6003 implementation note.

### SG-3: Multiple loading chips — Set iteration order is non-deterministic

TC-E60-I08 and TC-E60-E03 both test multiple loading chips but note that `Set<String>` iteration order is non-deterministic in Swift. The chipData computation iterates `vm.joinsInFlight` which is a `Set`. The chip row renders these via `ForEach` whose identity is based on `ChipData.id` (a UUID). This means loading chips may appear in a different order across renders. The spec does not define a stable sort order for loading chips. This is acceptable for v1.4 but should be noted as a known cosmetic non-determinism. If a stable order is required, `joinsInFlight` should be changed to an `[String]` (ordered) or `OrderedSet`.

### SG-4: onError closure capture in resolvedSessionVM is a retain cycle risk

ADR-E60 §7 SessionStripView wiring shows `onError: { [errorMessageBinding = $errorMessage] msg in errorMessageBinding.wrappedValue = msg }`. The closure captures `$errorMessage` by value (the `Binding` struct, not the view). This is safe as a value capture. However, the ADR does not specify whether `SessionViewModel` holds a strong or weak reference to the closure. In Swift, closures stored as `@escaping` are retained. Since `SessionViewModel` is `@Observable` and not owned by the view hierarchy beyond `@State`, there should be no retain cycle — but this is worth a code-review verification step. No dedicated TC needed, but the implementer should note it.

### SG-5: errorToastText uses LanguageService.shared — not injectable for unit testing

ADR-E60 §7 `errorToastText(for:speakerName:)` calls `GroupingStrings.forLanguage(LanguageService.shared.activeLanguage)`. This couples the private static method to a shared singleton, making it harder to test the Danish message variants without manipulating global state. TC-E60-E04 and TC-E60-U09–U11 only verify English variants unless `LanguageService.shared.activeLanguage` is configurable in tests. Recommendation: make `errorToastText` take an explicit `GroupingStrings` parameter (or inject via `LanguageService`) so tests can exercise both locales without global state mutation.

---

## 10. Tests Deferred to Manual Device Verification (T-6005)

The following test cases require a real B&O Mozart speaker on a LAN and cannot be verified in simulator. They correspond to the verification steps in T-6005 and are not covered by TCs in §3–§7.

---

### TC-E60-M01

**ID:** TC-E60-M01 (manual, device)
**Title:** Full LAN integration — drop to join; loading chip appears; resolves to settled chip on API success
**Steps:** (1) Drag idle pill onto playing card. Confirm loading chip appears within one frame. Confirm source pill dims to 0.5 opacity. Confirm spinner animates for the full `beolinkExpand` duration (1–3 s on a healthy LAN). (2) On API return: confirm chip transitions to full opacity with pulse. Confirm source pill regains 1.0 opacity. Confirm `refreshGroups` fires and the chip row reflects the speaker as a settled member.
**Expected:** All E-60 visual contracts met on-device. `os_log` shows `[SessionVM] handleJoinDrop` entering the success path.
**Deferred reason:** Requires live Mozart speaker; `beolinkExpand` cannot be mocked in simulator.
**Reference:** T-6005 step 1 and step 2.

---

### TC-E60-M02

**ID:** TC-E60-M02 (manual, device)
**Title:** Full LAN integration — timeout scenario; loading chip fades; error toast appears
**Steps:** Force a failure (airplane-mode the host speaker mid-call, or use a stub client configured to throw `.timeout`). Confirm: loading chip fades out. Source pill regains full opacity. Error toast appears with speaker name and "connection timed out" reason. Error haptic fires.
**Expected:** All failure-path visual contracts met. `os_log` shows error path entered.
**Deferred reason:** Requires live Mozart speaker or a network-isolation technique.
**Reference:** T-6005 step 3.

---

### TC-E60-M03

**ID:** TC-E60-M03 (manual, device)
**Title:** Background app during in-flight join; join completes correctly on foreground return
**Steps:** Initiate a join, immediately background the app for 2 seconds, return to foreground. Confirm the join completed (success or failure) and model was updated correctly.
**Expected:** Task is not cancelled by backgrounding. Chip row and pill state reflect the final outcome.
**Deferred reason:** Requires live Mozart speaker for realistic timing.
**Reference:** T-6005 step 5; spec US-81 AC ("If the user backgrounds the app … the Task continues to completion").

---

### TC-E60-M04

**ID:** TC-E60-M04 (manual, device)
**Title:** While join is in flight, confirm source pill cannot be re-dragged
**Steps:** Initiate a join. While spinner is showing, attempt to long-press the source pill in the bottom bar.
**Expected:** Long-press has no effect. Pill is at 0.5 opacity. No drag ghost appears.
**Deferred reason:** Drag gesture interaction requires physical device to verify long-press threshold and gesture lifecycle.
**Reference:** T-6005 step 4; spec TR-5.
