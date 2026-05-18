# Test Plan — E-59 Drag-to-Join Infrastructure

**Status:** Draft
**Date:** 2026-05-12
**Refs:** ADR-E59-drag-to-join-infrastructure.md, spec-multiroom-grouping.md US-80/US-81, design-spec-multiroom-grouping.md §2/§3/§6, epics-and-tasks-multiroom-grouping.md E-59 (T-5901–T-5910)

---

## 1. Scope

This plan covers the testable interface contract introduced by E-59: the `SpeakerIdentifier: Transferable` conformance and its `CodableRepresentation` round-trip; the new `var id: String` computed property on `SpeakerIdentifier`; `SessionViewModel`'s scaffolding (construction, `dropZoneActive`, `joinsInFlight`, `resolveSpeaker(_:)`, the `handleJoinDrop` stub, and the `handleRemoveTap` stub); the `isDraggable(_:)` helper and pill-opacity rules on `SpeakerSelectorPill`; the `.draggable` modifier presence/absence contract; the three new `HapticEngine` methods (`dragLifted`, `dragEnteredDropZone`, `dragCancelled`) and their generator contracts; the `.dropDestination` wiring on `SpeakerCard` (self-drop rejection, unresolvable-id rejection, valid-drop dispatch, return-value contract); the gold-border visibility rule driven by `dropZoneActive`; the per-card independence of `isTargeted`; `GroupingCoachMark` show/hide/auto-dismiss logic and `@AppStorage` persistence; and the `SessionStripView` `@State sessionVMs` dictionary lifecycle.

All eight ADR-E59 §7 behavioural contracts (across the five interface blocks) and all ADR-E59 §8 conflict resolutions (CF-1 through CF-7) are mapped to at least one TC. All US-80 and US-84 acceptance criteria that are verifiable in E-59 scope are covered.

### What is explicitly out of scope

- `handleJoinDrop` full implementation — that is E-60 (T-6001). The E-59 stub is tested only for non-throw, non-mutation, and log-call behaviour.
- `handleRemoveTap` full implementation — that is E-61 (T-6101). Stub behaviour only.
- The loading-chip variant in `GroupChipRow` — E-60 (T-6002). `GroupChipRow.swift` is NOT touched in E-59; its current `.member`/`.overflow` switch must remain unchanged.
- `refreshGroups()` — called by E-60 after `handleJoinDrop` completes; E-59 must not call it.
- `SpeakerClient.join(peer:)` and `SpeakerClient.leave()` internals.
- US-81, US-82, US-83 acceptance criteria (those belong to E-60 and E-61).
- Backend, telemetry, voice pipeline.

---

## 2. Test Environment

| Item | Value |
|---|---|
| Platform | iOS 26, iPhone (portrait) |
| Framework | SwiftUI, `@Observable @MainActor`, `Transferable`, `UniformTypeIdentifiers` |
| Test harness | No XCTest target exists in this repo (confirmed by ADR §8 CF-4 analogue and E-57/E-58 test plan precedent). All TCs are manual verification procedures, static code-review assertions, or Xcode preview assertions. Where XCTest is noted as conditional, it applies only when a `VoxioTests` target is later added. |
| Accessibility testing | Xcode Accessibility Inspector + VoiceOver on device/simulator |
| Source files under test | `iOS/Voxio/Core/Models/SpeakerIdentifier+Transferable.swift` (new), `iOS/Voxio/Features/Home/SessionViewModel.swift` (new), `iOS/Voxio/Features/Home/GroupingCoachMark.swift` (new), `iOS/Voxio/Core/Strings/GroupingStrings.swift` (new), `iOS/Voxio/Core/HapticEngine.swift` (modified), `iOS/Voxio/Features/Home/SpeakerSelectorPill.swift` (modified), `iOS/Voxio/Features/Home/SessionStripView.swift` (modified), `iOS/Voxio/Features/Home/SpeakerCard.swift` (modified), `iOS/Voxio/Features/Home/HomeView.swift` (modified) |
| Files explicitly NOT modified in E-59 | `iOS/Voxio/Features/Home/Components/GroupChipRow.swift` (E-60 owns `.loading`), `iOS/Voxio/Core/Discovery/SpeakerDiscoveryService.swift` (no E-59 change), `iOS/Voxio/Core/Protocols/SpeakerClient.swift` (no E-59 change) |
| Speaker doubles | `SpeakerStub: @Observable @MainActor` — writable `identifier: SpeakerIdentifier`, `playbackState`, `groups`, `name`; extended from E-57/E-58 stubs. `SpeakerDiscoveryServiceStub` — injectable `groups: [SpeakerGroup]` array; records `refreshGroupsCallCount: Int`. |
| HapticEngine double | `HapticEngineSpy` recording `dragLiftedCallCount: Int`, `dragEnteredDropZoneCallCount: Int`, `dragCancelledCallCount: Int`, appended to the existing E-56/E-58 spy. |
| Log spy | `LogSpy` recording `.info` messages (for stub log assertions). |
| SpeakerIdentifier fixtures | `mozartId = SpeakerIdentifier(host: "192.168.1.10", jid: "abc@beozone.local", platform: .mozart)`, `aseId = SpeakerIdentifier(host: "192.168.1.20", jid: nil, platform: .ase)`, `mozartIdSameJid = SpeakerIdentifier(host: "192.168.1.99", jid: "abc@beozone.local", platform: .mozart)`. |

---

## 3. Unit-Level Test Cases — Transferable + SpeakerIdentifier.id

These cases target `SpeakerIdentifier+Transferable.swift` in isolation: the `CodableRepresentation` round-trip and the `id` computed property contract. They are conditional XCTest assertions under `VoxioTests/SpeakerIdentifierTransferableTests.swift` when a test target exists; otherwise manual code-review verifications.

---

### TC-E59-U01

**ID:** TC-E59-U01
**Target:** `SpeakerIdentifier: Transferable` — encode/decode round-trip preserves all three fields
**ADR contract:** §7 `SpeakerIdentifier` contract #1 — "A `SpeakerIdentifier` round-tripped through `JSONEncoder`/`JSONDecoder` produces an equal value (== on all three fields: `host`, `jid`, `platform`)."
**Setup:** Construct `mozartId = SpeakerIdentifier(host: "192.168.1.10", jid: "abc@beozone.local", platform: .mozart)`. Encode to `Data` via `JSONEncoder`. Decode from `Data` via `JSONDecoder`.
**Action:** Assert decoded value == `mozartId`.
**Expected:** Decoded `SpeakerIdentifier` has `host == "192.168.1.10"`, `jid == "abc@beozone.local"`, `platform == .mozart`. `==` operator (Hashable + Equatable from Codable conformance) returns `true` for all three fields simultaneously.
**Covers:** ADR §7 contract #1; spec TR-1; T-5901 unit test requirement.

---

### TC-E59-U02

**ID:** TC-E59-U02
**Target:** `SpeakerIdentifier: Transferable` — encode/decode round-trip with nil JID (ASE case)
**ADR contract:** §7 contract #1 — round-trip equality on all three fields, including when `jid` is nil.
**Setup:** `aseId = SpeakerIdentifier(host: "192.168.1.20", jid: nil, platform: .ase)`. Encode → decode.
**Action:** Assert decoded value == `aseId`.
**Expected:** Decoded `jid == nil`, `host == "192.168.1.20"`, `platform == .ase`. The optional `jid` key round-trips correctly — absent in JSON when nil, decoded as nil.
**Covers:** ADR §7 contract #1; spec TR-1 (ASE platform variant).

---

### TC-E59-U03

**ID:** TC-E59-U03
**Target:** `SpeakerIdentifier.id` — JID wins when non-nil
**ADR contract:** §7 contract #3 — "Two `SpeakerIdentifier`s with the same JID have the same `.id` even when host differs."
**Setup:** `mozartId.jid = "abc@beozone.local"`. `mozartIdSameJid.jid = "abc@beozone.local"` (different `host`).
**Action:** Assert `mozartId.id == mozartIdSameJid.id`.
**Expected:** Both return `"abc@beozone.local"`. The `host` difference does not affect `.id` when `jid` is non-nil.
**Covers:** ADR §7 contract #3; ADR §8 CF-1 (`id` property requirement); spec TR-4 (`joinsInFlight` Set key).

---

### TC-E59-U04

**ID:** TC-E59-U04
**Target:** `SpeakerIdentifier.id` — host fallback when JID is nil
**ADR contract:** `var id: String { jid ?? host }` — when `jid == nil`, returns `host`.
**Setup:** `aseId = SpeakerIdentifier(host: "192.168.1.20", jid: nil, platform: .ase)`.
**Action:** Assert `aseId.id == "192.168.1.20"`.
**Expected:** `id` returns the host string `"192.168.1.20"`. Does not return `nil`, empty string, or crash.
**Covers:** ADR §7 contract #2 — "`.id` is always non-empty"; ADR §8 CF-1.

---

### TC-E59-U05

**ID:** TC-E59-U05
**Target:** `SpeakerIdentifier.id` — never empty (invariant)
**ADR contract:** §7 contract #2 — "`.id` is always non-empty (host is non-empty per `SpeakerDiscovery` contract)."
**Setup (static):** Code-review `SpeakerDiscoveryService` / `MdnsDiscovery` init path to confirm `host` is never assigned an empty string. Also inspect `SpeakerIdentifier+Transferable.swift` to confirm `var id: String { jid ?? host }` — the nil-coalescing expression returns `host` when `jid` is nil, and `host` is guaranteed non-empty by the init contract.
**Action:** Static analysis only. Confirm no code path can produce `SpeakerIdentifier(host: "", jid: nil, ...)`.
**Expected:** `host` is always a non-empty DNS hostname or IP address string. Therefore `id` is never `""`.
**Covers:** ADR §7 contract #2; defensive invariant for `joinsInFlight: Set<String>` key safety.

---

### TC-E59-U06

**ID:** TC-E59-U06
**Target:** `SpeakerIdentifier: Transferable` — `transferRepresentation` uses `CodableRepresentation(contentType: .data)`
**ADR contract:** §7 — "extension `SpeakerIdentifier: Transferable { static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .data) } }`"
**Setup (static):** Inspect `SpeakerIdentifier+Transferable.swift`.
**Action:** Verify `transferRepresentation` body is exactly `CodableRepresentation(contentType: .data)`. Verify the `UTType` is `.data` (not `.json`, `.text`, or a custom UTI). Verify there is NO second `TransferRepresentation` in the array (no `DataRepresentation`, no `FileRepresentation`).
**Expected:** Exactly one `CodableRepresentation(contentType: .data)` conformance. Matches ADR §7 and spec TR-1.
**Covers:** ADR §7 Transferable interface contract; spec TR-1 ADR-002 D3 alignment.

---

## 4. Unit-Level Test Cases — SessionViewModel.resolveSpeaker + Stubs

These cases target `SessionViewModel.swift`: construction, `resolveSpeaker(_:)` matching logic, and the stub-method behaviour contracts. They are conditional XCTest assertions under `VoxioTests/SessionViewModelTests.swift` when a test target exists.

---

### TC-E59-U07

**ID:** TC-E59-U07
**Target:** `SessionViewModel.resolveSpeaker(_:)` — matches by JID first when non-nil
**ADR contract:** §7 `SessionViewModel` contract #1 — "matches by `identifier.jid` first (when non-nil), then by `identifier.host`."
**Setup:** `SpeakerDiscoveryServiceStub.groups` contains two groups. Group A has `hostSpeaker` with `identifier = SpeakerIdentifier(host: "10.0.0.1", jid: "abc@beozone.local", platform: .mozart)`. Group B has a member with `identifier = SpeakerIdentifier(host: "10.0.0.99", jid: "abc@beozone.local", platform: .mozart)` (same JID, different host — simulates race window). Construct `sessionVM = SessionViewModel(group: groupA, discovery: stub)`. `droppedId = SpeakerIdentifier(host: "10.0.0.1", jid: "abc@beozone.local", platform: .mozart)`.
**Action:** Call `sessionVM.resolveSpeaker(droppedId)`.
**Expected:** Returns the speaker whose `identifier.jid == "abc@beozone.local"`. The first match by JID is returned. If multiple JID matches exist, the first one from `discovery.groups.flatMap(\.members)` is returned. Does not fall through to host matching when JID is present.
**Covers:** ADR §7 contract #1; spec TR-3 (`sessionViewModel.resolveSpeaker(droppedId)`).

---

### TC-E59-U08

**ID:** TC-E59-U08
**Target:** `SessionViewModel.resolveSpeaker(_:)` — host fallback when JID is nil
**ADR contract:** §7 contract #1 — "then by `identifier.host`."
**Setup:** `SpeakerDiscoveryServiceStub.groups` contains a solo group with `hostSpeaker.identifier = SpeakerIdentifier(host: "192.168.1.20", jid: nil, platform: .ase)`. `droppedId = SpeakerIdentifier(host: "192.168.1.20", jid: nil, platform: .ase)`.
**Action:** Call `sessionVM.resolveSpeaker(droppedId)`.
**Expected:** Returns the ASE speaker matched by `host == "192.168.1.20"`. JID is nil on both sides, so host comparison is used exclusively.
**Covers:** ADR §7 contract #1; ADR §8 CF-4 (ASE host-fallback path).

---

### TC-E59-U09

**ID:** TC-E59-U09
**Target:** `SessionViewModel.resolveSpeaker(_:)` — returns nil for unknown identifier
**ADR contract:** §7 contract #1 — "Returns nil when no match found."
**Setup:** `SpeakerDiscoveryServiceStub.groups` contains speakers with known identifiers. `unknownId = SpeakerIdentifier(host: "10.99.99.99", jid: "unknown@beozone", platform: .mozart)` — present in neither `jid` nor `host` match in any group member.
**Action:** Call `sessionVM.resolveSpeaker(unknownId)`.
**Expected:** Returns `nil`. No crash. No side effect on `sessionVM.joinsInFlight` or `dropZoneActive`.
**Covers:** ADR §7 contract #1; drop-destination rejection path (unresolvable → return false).

---

### TC-E59-U10

**ID:** TC-E59-U10
**Target:** `SessionViewModel.resolveSpeaker(_:)` — searches `discovery.groups.flatMap(\.members)`, not a private `allSpeakers` property
**ADR contract:** ADR §8 CF-4 — "`discovery.allSpeakers` is private; use `discovery.groups.flatMap(\.members)`."
**Setup (static):** Code-review `SessionViewModel.swift` `resolveSpeaker(_:)` implementation. Confirm the lookup reads `discovery.groups.flatMap(\.members)` — not `discovery.allSpeakers`.
**Action:** Static analysis. Verify no reference to `discovery.allSpeakers` (private) in `resolveSpeaker`.
**Expected:** Implementation uses only the public `discovery.groups` property. If the target exists, a `@testable import` test that calls `resolveSpeaker` with a discovery stub holding speakers only in `groups` (not in any `allSpeakers`-equivalent) confirms no access to private state.
**Covers:** ADR §8 CF-4 resolution.

---

### TC-E59-U11

**ID:** TC-E59-U11
**Target:** `SessionViewModel.handleJoinDrop` stub — does not throw, does not mutate `joinsInFlight`, logs call
**ADR contract:** §7 `SessionViewModel` contract (stub note) — "Stub must not throw, must not mutate `joinsInFlight`, and must log the call."
**Setup:** Construct `sessionVM`. Inject `LogSpy`. Set `sessionVM.joinsInFlight = []`. Create `sourceStub` with `name = "Stue"`, `targetStub` with `name = "Badeværelse"`.
**Action:** Call `sessionVM.handleJoinDrop(source: sourceStub, target: targetStub)`.
**Expected:**
- No error or exception thrown.
- `sessionVM.joinsInFlight` remains `[]` (unchanged — E-60 T-6001 fills this in).
- `LogSpy.infoMessages` contains exactly one message matching `"[SessionVM] handleJoinDrop stub: Stue → Badeværelse"` (per ADR §7 stub log contract).
- `sessionVM.dropZoneActive` is unchanged.
- `sessionVM.joinTasks` is empty.
**Covers:** ADR §7 stub contract; ADR §5 "E-59 leaves it as a stub"; E-60 forward-compat (E-60 fills in; E-59 must not mutate pre-emptively).

---

### TC-E59-U12

**ID:** TC-E59-U12
**Target:** `SessionViewModel.handleRemoveTap` stub — does not throw, does not mutate state, logs call
**ADR contract:** §7 stub contract — "E-59: stub — logs the call and returns. E-61 T-6101: full implementation."
**Setup:** Construct `sessionVM`. Inject `LogSpy`. `speakerStub.name = "Kitchen"`.
**Action:** Call `sessionVM.handleRemoveTap(speakerStub)`.
**Expected:**
- No error or exception thrown.
- `LogSpy.infoMessages` contains one message matching `"[SessionVM] handleRemoveTap stub: Kitchen"` (per ADR §7 stub log contract).
- `sessionVM.joinsInFlight` unchanged (`[]`).
- No call to `discovery.refreshGroups()` (stub confirmed via `discoveryStub.refreshGroupsCallCount == 0`).
**Covers:** ADR §7 stub contract; E-61 forward-compat.

---

### TC-E59-U13

**ID:** TC-E59-U13
**Target:** `SessionViewModel` initial state — `dropZoneActive` false, `joinsInFlight` empty, `joinTasks` empty
**ADR contract:** §7 SessionViewModel interface — "`var dropZoneActive: Bool = false`", "`var joinsInFlight: Set<String> = []`", "`private(set) var joinTasks: [String: Task<Void, Never>] = [:]`".
**Setup:** Construct `SessionViewModel(group: soloGroup, discovery: discoveryStub)`.
**Action:** Inspect initial property values immediately after construction.
**Expected:** `dropZoneActive == false`, `joinsInFlight == []`, `joinTasks == [:]`. No background work initiated on construction.
**Covers:** ADR §7 SessionViewModel interface; `@MainActor` isolation (constructor runs on main actor).

---

### TC-E59-U14

**ID:** TC-E59-U14
**Target:** `SessionViewModel.dropZoneActive` — annotated `@MainActor`; mutations are main-actor-isolated
**ADR contract:** §7 contract #2 — "`dropZoneActive` and `joinsInFlight` mutations are on `@MainActor`."
**Setup (static):** Code-review `SessionViewModel.swift`. Verify the class declaration is `@Observable @MainActor final class SessionViewModel`.
**Action:** Confirm the class-level `@MainActor` annotation covers all stored properties and methods. Confirm no `nonisolated` override exists on `dropZoneActive` or `joinsInFlight`.
**Expected:** All property mutations are implicitly guarded by `@MainActor`. No `DispatchQueue.main.async` wrappers needed from call sites. Safe to write from SwiftUI's `withAnimation` call inside `isTargeted`.
**Covers:** ADR §7 contract #2; spec NFR Concurrency section.

---

## 5. Integration Test Cases — isDraggable + Ghost Preview + Haptics

These cases target `SpeakerSelectorPill.swift` and `HapticEngine.swift`: the `isDraggable(_:)` eligibility rules, pill opacity, `.draggable` modifier presence/absence, ghost preview shape, and the three new haptic methods. These are static code-review assertions or SwiftUI preview/simulator verifications.

---

### TC-E59-I01

**ID:** TC-E59-I01
**Target:** `isDraggable(_:)` — returns false when speaker is playing host of any group
**ADR contract:** ADR §7 `SpeakerSelectorPill` — "Returns false when: (a) speaker is `hostSpeaker` of any group in `groups` with `playbackState == .playing`."
**Setup:** `discoveryGroups` contains one group where `hostSpeaker.id == targetSpeaker.id` and the group's `playbackState == .playing`. `joinsInFlightUnion = []`.
**Action:** Call `isDraggable(targetSpeaker)` (via pill's private helper, inspected via static review or a `@testable` wrapper).
**Expected:** Returns `false`. The playing-host pill cannot be dragged (it is the destination, not the source). Note: the check is `playbackState == .playing` — a stopped/paused host is also ineligible per spec TR-2 item (a).
**Covers:** ADR §7 `isDraggable` contract (a); spec TR-2; US-80 AC-2 (ineligible pill does not drag); design-spec §1.2.

---

### TC-E59-I02

**ID:** TC-E59-I02
**Target:** `isDraggable(_:)` — returns false when speaker is member of a multi-member group
**ADR contract:** ADR §7 `SpeakerSelectorPill` — "Returns false when: (b) speaker is a member of any group in `groups` with `members.count > 1`."
**Setup:** `discoveryGroups` has a 2-member group `[hostSpeaker, targetSpeaker]`. `targetSpeaker` is a member (not host). `joinsInFlightUnion = []`.
**Action:** Call `isDraggable(targetSpeaker)`.
**Expected:** Returns `false`. A speaker already in any multi-member group is non-draggable (UQ-2 resolved: already-grouped speakers stay put). `members.count > 1` is the threshold — a solo group of 1 does not trigger this branch.
**Covers:** ADR §7 `isDraggable` contract (b); spec TR-2 condition 2; design-spec §1.2; US-80 AC-2.

---

### TC-E59-I03

**ID:** TC-E59-I03
**Target:** `isDraggable(_:)` — returns false when speaker identifier is in `joinsInFlightUnion`
**ADR contract:** ADR §7 `SpeakerSelectorPill` — "Returns false when: (c) `speaker.identifier.id` is in `joinsInFlightUnion`."
**Setup:** `targetSpeaker.identifier = mozartId`. `joinsInFlightUnion = Set(["abc@beozone.local"])` (contains `mozartId.id`). `discoveryGroups` has `targetSpeaker` in a solo group.
**Action:** Call `isDraggable(targetSpeaker)` with `joinsInFlightUnion` parameter.
**Expected:** Returns `false`. Source-pill lockout during an in-flight join prevents re-dragging the same speaker. This uses `speaker.identifier.id` (the `jid ?? host` computed property from T-5901) as the Set key.
**Covers:** ADR §7 `isDraggable` contract (c); spec TR-5; design-spec §4.1 step 6.

---

### TC-E59-I04

**ID:** TC-E59-I04
**Target:** `isDraggable(_:)` — returns true when none of the three conditions hold
**ADR contract:** ADR §7 — "Returns true otherwise."
**Setup:** `targetSpeaker` is in a solo group (members.count == 1), not the playing host of any group, and `targetSpeaker.identifier.id` is not in `joinsInFlightUnion`.
**Action:** Call `isDraggable(targetSpeaker)`.
**Expected:** Returns `true`. Speaker is eligible to be dragged. The pill renders at `1.0` opacity and receives the `.draggable` modifier.
**Covers:** ADR §7 `isDraggable` happy-path; spec TR-2 positive case.

---

### TC-E59-I05

**ID:** TC-E59-I05
**Target:** `SpeakerSelectorPill` — non-draggable pills render at `0.5` opacity
**ADR contract:** ADR §7 pill rendering contract — "All pills: `.opacity(isDraggable(speaker) ? 1.0 : 0.5)`."
**Setup:** Configure `SpeakerSelectorPill` with a speaker that is non-draggable (e.g. is a playing host).
**Action (static):** Code-review `SpeakerSelectorPill.swift` — confirm `.opacity(isDraggable(speaker) ? 1.0 : 0.5)` is applied to the pill root view. Not `0.6`, not `0.4`, exactly `0.5`.
**Action (visual):** SwiftUI preview with a non-draggable speaker. Confirm the pill renders visually dimmed at 50% opacity.
**Expected:** Non-draggable pill opacity == `0.5`. Draggable pill opacity == `1.0`. Design-spec §1.2 "Idle (not draggable — playing host or already grouped): 0.5 opacity" is satisfied.
**Covers:** ADR §7 pill rendering contract; design-spec §1.2; spec TR-2; US-80 AC-2.

---

### TC-E59-I06

**ID:** TC-E59-I06
**Target:** `SpeakerSelectorPill` — `.draggable` modifier ABSENT (not nil) for non-draggable pills
**ADR contract:** ADR §7 — "Non-draggable pills: `.draggable` modifier OMITTED (not nil — absent)."
**Setup (static):** Code-review `SpeakerSelectorPill.swift`. Locate the branch where `isDraggable(speaker) == false`.
**Action:** Verify the non-draggable branch does NOT call `.draggable(...)` in any form — not with a nil payload, not with an empty closure. The modifier is entirely absent from the view modifier chain.
**Expected:** No `.draggable` call for non-draggable speakers. ADR CF-3 from spec TR-2 and epics T-5903 note: "Do NOT call `.draggable(nil)` or pass an empty payload — omit the modifier entirely." Calling `.draggable(nil)` behaves inconsistently across iOS versions.
**Covers:** ADR §7 pill rendering contract ("OMITTED, not nil — absent"); spec TR-2; epics T-5903 note.

---

### TC-E59-I07

**ID:** TC-E59-I07
**Target:** `SpeakerSelectorPill` — draggable pills receive `.draggable(speaker.identifier) { dragPreviewCapsule }` modifier
**ADR contract:** ADR §7 — "Draggable pills get `.draggable(speaker.identifier) { dragPreviewCapsule(speaker) }`."
**Setup (static):** Code-review `SpeakerSelectorPill.swift`. Locate the draggable branch.
**Action:** Confirm `.draggable(speaker.identifier)` is called with `speaker.identifier` (the `SpeakerIdentifier` value type). Confirm the drag preview closure returns a view styled as a `DarkGlassButton` capsule at `0.85` opacity, `1.06×` scale (per design-spec §2.1). Confirm `.simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in HapticEngine.shared.dragLifted() })` is attached to draggable pills.
**Expected:** `.draggable` is called once per draggable pill with the correct `SpeakerIdentifier` payload. Ghost preview matches design-spec §2.1. Long-press haptic wiring is present.
**Covers:** ADR §7 pill rendering contract; design-spec §2.1; design-spec §6.2 `dragLifted`; epics T-5903/T-5904.

---

### TC-E59-I08

**ID:** TC-E59-I08
**Target:** `SpeakerSelectorPill` — `joinsInFlightUnion` parameter has default of `[]` to preserve pre-E-59 call sites
**ADR contract:** ADR §7 `SpeakerSelectorPill` — "`var joinsInFlightUnion: Set<String> = []` — Default keeps pre-E-59 call sites valid."
**Setup (static):** Code-review `SpeakerSelectorPill.swift` struct definition.
**Action:** Confirm `joinsInFlightUnion` is declared with a default value of `[]` (empty set). Confirm pre-existing call sites in `HomeView` or elsewhere that omit this parameter still compile without changes.
**Expected:** Parameter has default `= []`. No breaking change to existing call sites. E-60 T-6004 can add the union aggregation later without touching all call sites simultaneously.
**Covers:** ADR §7 interface contract; ADR §5 "E-59 ensures `isDraggable` helper takes `joinsInFlightUnion: Set<String>` as a parameter so T-6004 can be added without changing the helper's signature."

---

### TC-E59-I09

**ID:** TC-E59-I09
**Target:** `HapticEngine.dragLifted()` — calls `UIImpactFeedbackGenerator(style: .medium).impactOccurred()`
**ADR contract:** ADR §7 HapticEngine additions — "`func dragLifted() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }`"
**Setup (static):** Code-review `HapticEngine.swift` — locate `dragLifted()` method.
**Action:** Confirm the method body calls `UIImpactFeedbackGenerator(style: .medium)` (not `.light`, not `.heavy`, not `.rigid`). Confirm `.impactOccurred()` is called (not `.prepare()` only). Confirm the method is `@MainActor` (class is already `@MainActor final class`).
**Expected:** Method signature: `func dragLifted()`. Generator: `UIImpactFeedbackGenerator(style: .medium)`. Matches design-spec §6.2 "Drag initiated (long press held) → `dragLifted()`". The `.medium` style produces the tactile "lift" sensation described in design-spec §1.1.
**Covers:** ADR §7 HapticEngine contract; design-spec §6.2; epics T-5904 prereq.

---

### TC-E59-I10

**ID:** TC-E59-I10
**Target:** `HapticEngine.dragEnteredDropZone()` — calls `UIImpactFeedbackGenerator(style: .light).impactOccurred()`
**ADR contract:** ADR §7 — "`func dragEnteredDropZone() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }`"
**Setup (static):** Code-review `HapticEngine.swift` — locate `dragEnteredDropZone()`.
**Action:** Confirm generator is `.light` (not `.medium`). Confirm `.impactOccurred()` called.
**Expected:** `UIImpactFeedbackGenerator(style: .light).impactOccurred()`. Light impact signals "ghost entered zone" without the weight of the lift haptic. Design-spec §6.2: "Ghost enters drop zone → `dragEnteredDropZone()`."
**Covers:** ADR §7 HapticEngine contract; design-spec §6.2; epics T-5905 prereq.

---

### TC-E59-I11

**ID:** TC-E59-I11
**Target:** `HapticEngine.dragCancelled()` — calls `UINotificationFeedbackGenerator().notificationOccurred(.warning)`
**ADR contract:** ADR §7 — "`func dragCancelled() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }`"
**Setup (static):** Code-review `HapticEngine.swift` — locate `dragCancelled()`.
**Action:** Confirm the method uses `UINotificationFeedbackGenerator` (not `UIImpactFeedbackGenerator`). Confirm `.notificationOccurred(.warning)` (not `.error`, not `.success`). Note: this method is best-effort per ADR §5 — the cancel callback may not be available on all iOS 26 builds.
**Expected:** `UINotificationFeedbackGenerator().notificationOccurred(.warning)`. Warning notification matches the "drag cancelled" semantic per design-spec §6.2 and design-spec §2.2.
**Covers:** ADR §7 HapticEngine contract; design-spec §6.2; ADR §8 CF-6 (best-effort, non-blocking); epics T-5908.

---

### TC-E59-I12

**ID:** TC-E59-I12
**Target:** `HapticEngine` — existing five methods unchanged by E-59 additions
**ADR contract:** ADR §7 — "existing methods unchanged."
**Setup (static):** Code-review `HapticEngine.swift` after E-59 additions.
**Action:** Confirm the five pre-existing methods are still present and their bodies are unchanged: `commandRecognised()`, `sheetAppeared()`, `actionConfirmed()`, `errorOccurred()`, `limitReached()`. Confirm total method count is now 8 (5 existing + 3 new).
**Expected:** No existing method body, signature, or visibility was altered. The three new methods are additive only.
**Covers:** Regression test for ADR §7 ("existing methods unchanged").

---

## 6. Acceptance Test Cases — Drop Destination + Gold Border + Coach Mark

These cases cover `SpeakerCard.swift` (`.dropDestination` wiring, gold border, `sessionVM` optional), `SessionStripView.swift` (`sessionVMs` dictionary lifecycle), and `GroupingCoachMark.swift` (trigger, dismiss, persist). They are manual verification or SwiftUI preview assertions unless a UI test target exists.

---

### TC-E59-A01

**ID:** TC-E59-A01
**Target:** `SpeakerCard` — self-drop rejected; returns false; no side effects
**ADR contract:** ADR §7 `SpeakerCard` contract #2 — "Self-drop (`source.id == hostSpeaker.id`) returns `false`; no side effects."
**Setup:** `sessionVM.group.hostSpeaker.identifier = mozartId`. A drag of `mozartId` is simulated as the dropped item (source == host). Inject `HapticEngineSpy` and `LogSpy`.
**Action:** Trigger the `.dropDestination` `perform` closure with `items = [mozartId]`.
**Expected:**
- The guard `source.id != vm.group.hostSpeaker.id` fails.
- The closure returns `false`.
- `vm.handleJoinDrop` is NOT called.
- `HapticEngineSpy` records no new haptics.
- `sessionVM.joinsInFlight` remains `[]`.
- `sessionVM.dropZoneActive` is not mutated by the perform closure (it is set by `isTargeted`, not by `perform`).
**Covers:** ADR §7 card contract #2; spec Error States "Drop occurs on the same speaker's own card (drop ID == host ID)"; design-spec §2.2 (self-drop is an invalid drop).

---

### TC-E59-A02

**ID:** TC-E59-A02
**Target:** `SpeakerCard` — unresolvable identifier rejected; returns false; no side effects
**ADR contract:** ADR §7 card contract #3 — "Unresolvable identifier (`resolveSpeaker` returns nil) returns false."
**Setup:** `sessionVM.discovery.groups` contains no speaker matching `unknownId`. Drop `unknownId` onto the card.
**Action:** Trigger `.dropDestination` `perform` with `items = [unknownId]`.
**Expected:**
- `vm.resolveSpeaker(unknownId)` returns nil.
- The guard fails.
- Closure returns `false`.
- `handleJoinDrop` NOT called.
- No state mutation.
**Covers:** ADR §7 card contract #3; ADR §8 CF-4 (race-window safe: unknown JID → reject drop); spec TR-3 drop handler guard.

---

### TC-E59-A03

**ID:** TC-E59-A03
**Target:** `SpeakerCard` — valid drop calls `handleJoinDrop` and returns true
**ADR contract:** ADR §7 card contract (inferred from §7 drop handler body) — "valid drop calls `handleJoinDrop(source:target:)` and returns `true`."
**Setup:** `sessionVM.discovery.groups` contains `sourceSpeaker` (distinct from the host). `sourceSpeaker.identifier = mozartId`. `hostSpeaker.id != sourceSpeaker.id`. Inject `LogSpy` to capture stub log.
**Action:** Trigger `.dropDestination` `perform` with `items = [mozartId]`.
**Expected:**
- `resolveSpeaker(mozartId)` returns `sourceSpeaker`.
- `source.id != hostSpeaker.id` passes (not a self-drop).
- `vm.handleJoinDrop(source: sourceSpeaker, target: hostSpeaker)` is called once.
- The closure returns `true`.
- `LogSpy.infoMessages` contains the stub log line (per TC-E59-U11 contract).
**Covers:** ADR §7 drop handler body; spec TR-3 happy path; US-80 AC-4 ("Releasing the ghost over a session card triggers the join...").

---

### TC-E59-A04

**ID:** TC-E59-A04
**Target:** `SpeakerCard` — `sessionVM == nil` → no `.dropDestination` modifier attached
**ADR contract:** ADR §7 card contract #1 — "`sessionVM == nil` → no `.dropDestination`, no gold-border overlay."
**Setup (static):** Code-review `SpeakerCard.swift`. Locate the conditional application of `.dropDestination`.
**Action:** Confirm the `.dropDestination` modifier is inside a conditional block or applied only when `sessionVM != nil`. Confirm existing call sites (e.g. `HomeView` idle card, Xcode previews) that pass no `sessionVM` continue to compile and do not receive a drop destination.
**Expected:** `.dropDestination` is absent when `sessionVM` is nil. Pre-E-59 call sites are unaffected (the `var sessionVM: SessionViewModel? = nil` default keeps them valid).
**Covers:** ADR §7 card contract #1; ADR §5 "default keeps pre-E-59 call sites valid".

---

### TC-E59-A05

**ID:** TC-E59-A05
**Target:** `SpeakerCard` gold border — visible only when `dropZoneActive == true && sessionVM != nil`
**ADR contract:** ADR §7 card contract overlay — "Gold-border: visible only when `dropZoneActive && sessionVM != nil`." Design-spec §3: `BeoColor.accent`, 1.5 pt lineWidth.
**Setup:** Construct `SpeakerCard` with `sessionVM` assigned. Inspect view tree in two states: `sessionVM.dropZoneActive = false` and `sessionVM.dropZoneActive = true`.
**Action (visual):** SwiftUI preview or simulator. Toggle `sessionVM.dropZoneActive`. Observe border visibility.
**Action (static):** Code-review `SpeakerCard.swift`. Confirm the `.overlay` reads: `RoundedRectangle(cornerRadius: Radius.card).stroke(BeoColor.accent, lineWidth: (sessionVM?.dropZoneActive == true) ? 1.5 : 0)`.
**Expected:** When `dropZoneActive == false` (or `sessionVM == nil`): `lineWidth == 0` (border invisible). When `dropZoneActive == true`: `lineWidth == 1.5`, color == `BeoColor.accent`. No conditional show/hide — the lineWidth is the toggle mechanism so SwiftUI can animate the transition via `withAnimation(BeoAnimation.spring)`.
**Covers:** ADR §7 card contract gold-border overlay; design-spec §3; US-80 AC-3 ("ghost over card → gold border appears").

---

### TC-E59-A06

**ID:** TC-E59-A06
**Target:** `SpeakerCard` `isTargeted` callback — fires `dragEnteredDropZone()` only on entry (isOver == true)
**ADR contract:** ADR §7 drop handler body — "`if isOver { HapticEngine.shared.dragEnteredDropZone() }`."
**Setup (static):** Code-review `SpeakerCard.swift` `.dropDestination` `isTargeted` closure body.
**Action:** Confirm `dragEnteredDropZone()` is called only when `isOver == true`, not on exit (`isOver == false`).
**Expected:** The haptic fires exactly once on entry, not on exit. Exit path only sets `dropZoneActive = false` (no haptic). This matches design-spec §6.2 "Ghost enters drop zone → `dragEnteredDropZone()`" with no "ghost exits" haptic.
**Covers:** ADR §7 drop handler `isTargeted` body; design-spec §6.2.

---

### TC-E59-A07

**ID:** TC-E59-A07
**Target:** `SpeakerCard` `isTargeted` — per-card independence (multi-card support per spec TR-8)
**ADR contract:** ADR §7 card contract #4 — "`dropZoneActive` transitions... per-card independence." Spec TR-8 — "Each card activates its own drop zone independently."
**Setup:** Two `SpeakerCard` instances, each with their own `SessionViewModel` instance. `cardVM1.dropZoneActive = false`, `cardVM2.dropZoneActive = false`.
**Action:** Simulate the `isTargeted` callback on `cardVM1` with `isOver = true`. Then check `cardVM2.dropZoneActive`.
**Expected:** `cardVM1.dropZoneActive == true`. `cardVM2.dropZoneActive == false` (unchanged). The two view models are independent; an `isTargeted` callback on one card does not affect sibling cards. Matches spec TR-8 and design-spec §6.5.
**Covers:** ADR §7 card contract #4; spec TR-8; epics T-5907.

---

### TC-E59-A08

**ID:** TC-E59-A08
**Target:** `SessionStripView` `sessionVMs` dictionary — stable across re-renders for same `group.id`
**ADR contract:** ADR §8 CF-3 — "`SessionViewModel` must be stable across ForEach re-renders for the same group." ADR §7 `SessionStripView` wiring — "`@State private var sessionVMs: [SpeakerGroup.ID: SessionViewModel] = [:]` keyed by `group.id`."
**Setup:** `SessionStripView` rendered with two groups (group A and group B). Reference `sessionVMs[groupA.id]` as `vmRef1`.
**Action:** Trigger a state update that causes `SessionStripView` to re-render (e.g. `groups` array receives a new value type with the same group IDs but updated `playbackState`). After re-render, read `sessionVMs[groupA.id]` as `vmRef2`.
**Expected:** `vmRef1 === vmRef2` (same object identity — Swift reference identity). The `@State` dictionary lookup pattern (`sessionVMs[group.id] ?? { create and store }()`) returns the same `SessionViewModel` instance on re-render. No new instance is created for an existing group ID.
**Covers:** ADR §8 CF-3; ADR §7 `SessionStripView` wiring; epics T-5905 note.

---

### TC-E59-A09

**ID:** TC-E59-A09
**Target:** `SessionStripView` `sessionVMs` dictionary — cleaned up when group is removed
**ADR contract:** ADR §7 `SessionStripView` wiring — "Clean up `sessionVMs` for groups that no longer exist: `.onChange(of: groups.map(\.id)) { _, newIds in let validIds = Set(newIds); sessionVMs = sessionVMs.filter { validIds.contains($0.key) }`."
**Setup:** `SessionStripView` rendered with two groups (A and B). `sessionVMs` contains entries for both.
**Action:** Remove group B from `groups`. Observe `sessionVMs` after the `.onChange` fires.
**Expected:** `sessionVMs` no longer contains the key for group B's ID. `sessionVMs.count == 1`. The cleaned-up `SessionViewModel` is released (no memory leak). Group A's entry is untouched.
**Covers:** ADR §7 `SessionStripView` cleanup; ADR §8 CF-3.

---

### TC-E59-A10

**ID:** TC-E59-A10
**Target:** `GroupingCoachMark` — shows when `hasEligiblePill == true && !hasSeen`
**ADR contract:** ADR §7 `GroupingCoachMark` contract #1 — "Shows when `hasEligiblePill && !hasSeen`."
**Setup:** `@AppStorage("hasSeenGroupingCoachMark")` set to `false`. Construct `GroupingCoachMark(hasEligiblePill: true, onDismiss: {})`.
**Action (visual):** Render in SwiftUI preview. Confirm the coach mark text is visible.
**Action (static):** Code-review `GroupingCoachMark.swift` — confirm the `body` renders the label when `hasEligiblePill && !hasSeen` and renders nothing (EmptyView or zero-height view) otherwise.
**Expected:** Label text `"Drag to join this session"` (EN) is visible. `allowsHitTesting(false)` is applied to the label. `.transition(.opacity)` is applied.
**Covers:** ADR §7 coach mark contract #1; spec TR-7; US-84 AC-1; design-spec §1.3.

---

### TC-E59-A11

**ID:** TC-E59-A11
**Target:** `GroupingCoachMark` — does NOT show when `hasEligiblePill == false`
**ADR contract:** ADR §7 contract #1 (converse case); US-84 AC-5 — "The coach mark does not appear if the user has only ineligible pills available."
**Setup:** `hasSeen = false`. `hasEligiblePill = false`.
**Action:** Render `GroupingCoachMark(hasEligiblePill: false, onDismiss: {})`.
**Expected:** Coach mark is not visible. No label rendered. This correctly handles the case where all speakers are already in groups.
**Covers:** ADR §7 contract #1 converse; US-84 AC-5.

---

### TC-E59-A12

**ID:** TC-E59-A12
**Target:** `GroupingCoachMark` — auto-dismisses after 3 seconds via `Task.sleep`
**ADR contract:** ADR §7 coach mark contract #2 — "Auto-dismisses after 3 seconds via `Task { try? await Task.sleep(for: .seconds(3)); onDismiss() }`."
**Setup (static):** Code-review `GroupingCoachMark.swift` — confirm the auto-dismiss `Task` is started when the coach mark becomes visible. Confirm it calls `onDismiss()` after exactly 3 seconds (`Task.sleep(for: .seconds(3))`).
**Action:** In a simulator test, render the coach mark and wait > 3 seconds. Observe that `onDismiss()` is invoked.
**Expected:** `onDismiss()` called exactly once, approximately 3 seconds after the coach mark appears. The `Task.sleep` uses `.seconds(3)` — not `.milliseconds(3000)` (both are equivalent but the `Duration`-based form is idiomatic in Swift 6 / iOS 26).
**Covers:** ADR §7 contract #2; US-84 AC-2 ("coach mark fades out automatically after 3 seconds").

---

### TC-E59-A13

**ID:** TC-E59-A13
**Target:** `GroupingCoachMark` — `onDismiss` sets `hasSeen = true` (persisted via `@AppStorage`)
**ADR contract:** ADR §7 coach mark contract #3 — "On dismiss: `hasSeen = true` (persisted)."
**Setup:** `hasSeen = false`. Coach mark is showing. Confirm `@AppStorage("hasSeenGroupingCoachMark")` key is used.
**Action (static):** Code-review `GroupingCoachMark.swift`. Confirm `@AppStorage("hasSeenGroupingCoachMark") private var hasSeen: Bool = false` is the storage declaration. Confirm `onDismiss()` or its internal body sets `hasSeen = true`. Confirm the key string matches `"hasSeenGroupingCoachMark"` exactly (case-sensitive).
**Action (integration):** After auto-dismiss (or explicit `onDismiss()`), read `UserDefaults.standard.bool(forKey: "hasSeenGroupingCoachMark")`. Confirm it is `true`.
**Expected:** `UserDefaults` key `"hasSeenGroupingCoachMark"` == `true` after any dismiss path. Once `hasSeen == true`, the coach mark never reappears (US-84 AC-4 / UQ-4 resolved).
**Covers:** ADR §7 contract #3; US-84 AC-4 ("'seen' state persists in `@AppStorage`"); spec TR-7 / spec UQ-4 resolved.

---

### TC-E59-A14

**ID:** TC-E59-A14
**Target:** `GroupingCoachMark` — does NOT show when `hasSeen == true` regardless of `hasEligiblePill`
**ADR contract:** ADR §7 contract #1 (persisted seen state blocks re-show); US-84 AC-4 — "Once true, the coach mark never appears again on this device."
**Setup:** `UserDefaults.standard.set(true, forKey: "hasSeenGroupingCoachMark")`. `hasEligiblePill = true`.
**Action:** Render `GroupingCoachMark(hasEligiblePill: true, onDismiss: {})`.
**Expected:** Coach mark is NOT visible. The `hasSeen == true` guard prevents any re-show. After a reinstall (or clearing UserDefaults), `hasSeen` reverts to `false` and the coach mark would reappear — this is correct per the "once per app lifetime" contract.
**Covers:** ADR §7 contract #1; US-84 AC-4; design-spec UQ-4.

---

### TC-E59-A15

**ID:** TC-E59-A15
**Target:** `GroupingCoachMark` — label has `.allowsHitTesting(false)`
**ADR contract:** ADR §7 coach mark contract #6 — "`.allowsHitTesting(false)` on the label."
**Setup (static):** Code-review `GroupingCoachMark.swift`.
**Action:** Confirm `.allowsHitTesting(false)` is applied to the coach mark label (the `Text` view or its container). Confirm it is NOT applied at a level that would block gestures on the pill below.
**Expected:** The label passes all touch events through. US-84 AC-5 ("The coach mark does not block any other interaction — the pill underneath remains draggable while the mark is showing") is satisfied.
**Covers:** ADR §7 contract #6; US-84 AC-5; design-spec §1.3.

---

### TC-E59-A16

**ID:** TC-E59-A16
**Target:** `GroupingStrings` — EN coach mark text is exactly `"Drag to join this session"`
**ADR contract:** ADR §7 `GroupingStrings` — "`var coachMark: String` — EN: `"Drag to join this session"`."
**Setup (static):** Code-review `GroupingStrings.swift`.
**Action:** Read `GroupingStrings.english.coachMark`.
**Expected:** `"Drag to join this session"` — exact string, correct capitalisation, no trailing period or spaces. Matches design-spec Appendix B `grouping.coachMark`.
**Covers:** ADR §7 `GroupingStrings` contract; design-spec Appendix B; ADR §8 CF-5 (strings via struct, not `.strings` file).

---

### TC-E59-A17

**ID:** TC-E59-A17
**Target:** `GroupingStrings` — DA coach mark text is exactly `"Træk for at tilslutte"`
**ADR contract:** ADR §7 — "DA: `"Træk for at tilslutte"`."
**Setup (static):** Code-review `GroupingStrings.swift`.
**Action:** Read `GroupingStrings.danish.coachMark`.
**Expected:** `"Træk for at tilslutte"` — correct Danish with `æ` character. Matches design-spec Appendix B.
**Covers:** ADR §7 `GroupingStrings` contract; design-spec Appendix B; ADR §8 CF-5.

---

### TC-E59-A18

**ID:** TC-E59-A18
**Target:** `GroupingStrings` follows `GroupChipStrings`/`DiscoveryStrings` pattern — NOT a `.strings` catalogue
**ADR contract:** ADR §8 CF-5 — "New strings follow the `GroupChipStrings`/`DiscoveryStrings` pattern: a new `GroupingStrings.swift` struct in `iOS/Voxio/Core/Strings/`."
**Setup (static):** Inspect the file system path `iOS/Voxio/Core/Strings/` and source file `GroupingStrings.swift`.
**Action:** Confirm `GroupingStrings` is a `struct` (not a class or enum) in `Core/Strings/`. Confirm there is NO corresponding entry in a `Localizable.strings` or `.xcstrings` file for `grouping.coachMark`. Confirm the struct has at least `static let english` and `static let danish` instances plus a `forLanguage(_:)` factory method (following the established pattern).
**Expected:** The codebase uses the struct-based strings pattern throughout. `GroupingStrings.swift` is consistent with `GroupChipStrings.swift` and `DiscoveryStrings.swift`. No `.strings` file entry created (epics T-5909 mentions `Localizable.strings` but ADR §8 CF-5 supersedes this with the struct pattern).
**Covers:** ADR §8 CF-5; CF-5 resolution.

---

## 7. Error States and Boundary Values

---

### TC-E59-E01

**ID:** TC-E59-E01
**Target:** Drop with empty `items` array — rejected silently
**Boundary:** `items.first` returns nil.
**Setup:** Trigger `.dropDestination` `perform` closure with `items = []` (empty array — SwiftUI should not produce this but it is a defensive boundary).
**Action:** Confirm the guard `guard let droppedId = items.first` fails. Closure returns `false`. No crash, no `handleJoinDrop` call.
**Expected:** `false` returned. No side effects. Defensive against SwiftUI sending an empty items array.
**Covers:** Defensive drop-destination boundary value.

---

### TC-E59-E02

**ID:** TC-E59-E02
**Target:** Drop with multiple items — only the first is processed
**Boundary:** `items.count > 1`.
**Setup:** Trigger `.dropDestination` `perform` with `items = [mozartId, aseId]` (two items).
**Action:** Confirm `items.first` returns `mozartId`. The second item (`aseId`) is ignored.
**Expected:** Only `mozartId` is processed. `handleJoinDrop` is called at most once (or not at all if self-drop). The SwiftUI drag-and-drop API is designed to carry one item from a `.draggable` source — this tests the defensive `first` extraction.
**Covers:** ADR §7 drop handler body (`items.first`).

---

### TC-E59-E03

**ID:** TC-E59-E03
**Target:** `isDraggable(_:)` — speaker in solo group (members.count == 1) IS draggable (boundary condition for multi-member check)
**Boundary:** `members.count == 1` (exactly solo, not multi-member).
**Setup:** `discoveryGroups` has one group `[targetSpeaker]` (`members.count == 1`). `targetSpeaker` is not the playing host of any other group. `joinsInFlightUnion = []`.
**Action:** Call `isDraggable(targetSpeaker)`.
**Expected:** Returns `true`. A solo speaker is eligible to be dragged. The check `members.count > 1` is strict-greater-than — solo groups do not trigger the non-draggable branch.
**Covers:** ADR §7 `isDraggable` contract (b) boundary; spec TR-2 ("member of any group with members.count > 1").

---

### TC-E59-E04

**ID:** TC-E59-E04
**Target:** `isDraggable(_:)` — speaker in 2-member group is NOT draggable (boundary condition)
**Boundary:** `members.count == 2`.
**Setup:** `discoveryGroups` has one group with `members = [host, targetSpeaker]` (`count == 2`).
**Action:** Call `isDraggable(targetSpeaker)`.
**Expected:** Returns `false`. The `count > 1` check is satisfied at exactly 2 members.
**Covers:** ADR §7 `isDraggable` contract (b) boundary (minimum non-draggable membership count).

---

### TC-E59-E05

**ID:** TC-E59-E05
**Target:** `SpeakerIdentifier` round-trip — JSON preserves `platform` enum raw value correctly
**Boundary:** `platform` field round-trip for both `.mozart` and `.ase` values.
**Setup:** Encode/decode `mozartId` (platform: `.mozart`) and `aseId` (platform: `.ase`).
**Action:** Confirm `decoded.platform == .mozart` for the Mozart fixture and `decoded.platform == .ase` for the ASE fixture.
**Expected:** Both platform raw values survive the `JSONEncoder` → `JSONDecoder` cycle. No silent fallback to a default platform. If `SpeakerPlatform` is an enum with `Codable`, each case maps to its raw string or integer value without loss.
**Covers:** ADR §7 contract #1 (all three fields equal); TC-E59-U01/U02 extension for platform field specifically.

---

### TC-E59-E06

**ID:** TC-E59-E06
**Target:** `GroupingCoachMark` — start condition race: becomes eligible AFTER `hasSeen` is already true
**Boundary:** `hasSeen = true` set before any eligible pill condition.
**Setup:** `UserDefaults` key `"hasSeenGroupingCoachMark"` set to `true` before any component mounts. `hasEligiblePill` transitions from `false` to `true` during app session.
**Action:** Observe `GroupingCoachMark` after `hasEligiblePill` becomes `true`.
**Expected:** Coach mark remains hidden. The `hasSeen == true` guard wins. The transition of `hasEligiblePill` to `true` does NOT re-show the mark once it has been seen.
**Covers:** US-84 AC-4 (once true, never reappears); ADR §7 contract #1 guard ordering.

---

### TC-E59-E07

**ID:** TC-E59-E07
**Target:** `SessionViewModel` construction — does not call `refreshGroups()` on init
**ADR contract:** ADR §5 — "E-59 must NOT call `refreshGroups()` — that is E-60's responsibility."
**Setup:** Construct `SessionViewModel(group: group, discovery: discoveryStub)`. `discoveryStub.refreshGroupsCallCount = 0`.
**Action:** After construction, read `discoveryStub.refreshGroupsCallCount`.
**Expected:** `refreshGroupsCallCount == 0`. No background network calls initiated on `SessionViewModel` construction.
**Covers:** ADR §5 forward-compat; E-60 boundary enforcement.

---

### TC-E59-E08

**ID:** TC-E59-E08
**Target:** `GroupChipRow.swift` — NOT modified by E-59; `.member`/`.overflow` switch exhaustive
**ADR contract:** ADR §5 / §8 CF-3 (from ADR-E53) — "E-59 must NOT touch `GroupChipRow.swift` at all. The exhaustive switch in `GroupChipRow.body` must remain exactly `.member` / `.overflow`."
**Setup (static):** Code-review `GroupChipRow.swift` after E-59 changes are applied.
**Action:** Confirm the file's git diff is empty (no lines changed). Confirm the `switch chipKind` statement covers only `.member` and `.overflow` cases with NO `@unknown default` added.
**Expected:** `GroupChipRow.swift` is bit-identical to its pre-E-59 state. Adding `@unknown default` in E-59 would suppress the compile-time break E-60 depends on when it adds `case loading` — this must not happen.
**Covers:** ADR §5 E-60 must-not-be-precluded; ADR-E53 §5 CF-3/CF-4 forward-compat.

---

### TC-E59-E09

**ID:** TC-E59-E09
**Target:** `ChipData` struct — NOT modified by E-59; `onTap` property absent
**ADR contract:** ADR §5 — "E-59 must not add any tap handling to chips. The existing `ChipData` struct must remain unchanged."
**Setup (static):** Code-review `ChipData` struct definition.
**Action:** Confirm `ChipData` does not have an `onTap` property. Confirm no `.onTapGesture` handling is added to chips by E-59.
**Expected:** `ChipData` is identical to its pre-E-59 form. E-61 (T-6101) is the owner of the `onTap` addition.
**Covers:** ADR §5 E-61 must-not-be-precluded.

---

## 8. Coverage Matrix (AC/ER → TC IDs)

| Requirement | Source | TC IDs |
|---|---|---|
| **ADR §7 `SpeakerIdentifier` contract #1** — round-trip equality on all three fields | ADR-E59 §7 | TC-E59-U01, TC-E59-U02, TC-E59-E05 |
| **ADR §7 `SpeakerIdentifier` contract #2** — `.id` never empty | ADR-E59 §7 | TC-E59-U04, TC-E59-U05 |
| **ADR §7 `SpeakerIdentifier` contract #3** — same JID → same `.id` regardless of host | ADR-E59 §7 | TC-E59-U03 |
| **ADR §7 `SessionViewModel` contract #1** — `resolveSpeaker` matches jid first, then host, nil for unknown | ADR-E59 §7 | TC-E59-U07, TC-E59-U08, TC-E59-U09 |
| **ADR §7 `SessionViewModel` contract #2** — mutations are `@MainActor` | ADR-E59 §7 | TC-E59-U14 |
| **ADR §7 stub log — `handleJoinDrop`** | ADR-E59 §7 | TC-E59-U11 |
| **ADR §7 stub log — `handleRemoveTap`** | ADR-E59 §7 | TC-E59-U12 |
| **ADR §7 `isDraggable` contract (a)** — playing host → false | ADR-E59 §7 | TC-E59-I01 |
| **ADR §7 `isDraggable` contract (b)** — multi-member group member → false | ADR-E59 §7 | TC-E59-I02, TC-E59-E03, TC-E59-E04 |
| **ADR §7 `isDraggable` contract (c)** — in `joinsInFlightUnion` → false | ADR-E59 §7 | TC-E59-I03 |
| **ADR §7 `isDraggable` → true otherwise** | ADR-E59 §7 | TC-E59-I04 |
| **ADR §7 pill opacity** — `0.5` non-draggable, `1.0` draggable | ADR-E59 §7 | TC-E59-I05 |
| **ADR §7 `.draggable` absent (not nil) for non-draggable** | ADR-E59 §7 | TC-E59-I06 |
| **ADR §7 `.draggable(speaker.identifier)` + ghost preview for draggable** | ADR-E59 §7 | TC-E59-I07 |
| **ADR §7 `joinsInFlightUnion` default `[]`** | ADR-E59 §7 | TC-E59-I08 |
| **ADR §7 `HapticEngine.dragLifted()` — `.medium` impact** | ADR-E59 §7 | TC-E59-I09 |
| **ADR §7 `HapticEngine.dragEnteredDropZone()` — `.light` impact** | ADR-E59 §7 | TC-E59-I10 |
| **ADR §7 `HapticEngine.dragCancelled()` — `.warning` notification** | ADR-E59 §7 | TC-E59-I11 |
| **ADR §7 `SpeakerCard` contract #1** — nil `sessionVM` → no drop destination | ADR-E59 §7 | TC-E59-A04 |
| **ADR §7 `SpeakerCard` contract #2** — self-drop → false, no side effects | ADR-E59 §7 | TC-E59-A01 |
| **ADR §7 `SpeakerCard` contract #3** — unresolvable id → false | ADR-E59 §7 | TC-E59-A02 |
| **ADR §7 `SpeakerCard` contract #4** — `isTargeted` per-card independence | ADR-E59 §7 | TC-E59-A07 |
| **ADR §7 `SpeakerCard` gold-border overlay** | ADR-E59 §7 | TC-E59-A05 |
| **ADR §7 `isTargeted` → `dragEnteredDropZone` only on entry** | ADR-E59 §7 | TC-E59-A06 |
| **ADR §7 valid drop → `handleJoinDrop` + return true** | ADR-E59 §7 | TC-E59-A03 |
| **ADR §7 `GroupingCoachMark` contract #1** — shows when eligible && !hasSeen | ADR-E59 §7 | TC-E59-A10, TC-E59-A11, TC-E59-A14 |
| **ADR §7 `GroupingCoachMark` contract #2** — auto-dismiss after 3 s | ADR-E59 §7 | TC-E59-A12 |
| **ADR §7 `GroupingCoachMark` contract #3** — `hasSeen = true` on dismiss | ADR-E59 §7 | TC-E59-A13 |
| **ADR §7 `GroupingCoachMark` contract #6** — `.allowsHitTesting(false)` | ADR-E59 §7 | TC-E59-A15 |
| **ADR §7 `SessionStripView` `sessionVMs` stable across re-renders** | ADR-E59 §7 CF-3 | TC-E59-A08 |
| **ADR §7 `SessionStripView` cleanup on group removal** | ADR-E59 §7 | TC-E59-A09 |
| **ADR §8 CF-1** — `SpeakerIdentifier.id` added alongside Transferable | ADR-E59 §8 CF-1 | TC-E59-U03, TC-E59-U04 |
| **ADR §8 CF-2** — `SpeakerCard` modifier order (drop destination before scale) | ADR-E59 §8 CF-2 | Deferred to §10 (device visual verification) |
| **ADR §8 CF-3** — `sessionVMs` stable via `@State` dict | ADR-E59 §8 CF-3 | TC-E59-A08 |
| **ADR §8 CF-4** — `resolveSpeaker` uses `groups.flatMap`, not `allSpeakers` | ADR-E59 §8 CF-4 | TC-E59-U10 |
| **ADR §8 CF-5** — strings via struct, not `.strings` file | ADR-E59 §8 CF-5 | TC-E59-A18 |
| **ADR §8 CF-6** — `dragCancelled` best-effort | ADR-E59 §8 CF-6 | TC-E59-I11, §10 |
| **ADR §8 CF-7** — `SpeakerCard.group` and `sessionVM.group` same instance | ADR-E59 §8 CF-7 | Deferred to §10 (device integration) |
| **US-80 AC-1** — long-press on eligible pill initiates drag; `dragLifted` fires | spec US-80 | TC-E59-I07, §10 (device) |
| **US-80 AC-2** — ineligible pill does not initiate drag; 0.5 opacity | spec US-80 | TC-E59-I01, TC-E59-I02, TC-E59-I03, TC-E59-I05, TC-E59-I06 |
| **US-80 AC-3** — ghost over card → gold border; leave card → returns to idle | spec US-80 | TC-E59-A05, TC-E59-A06 |
| **US-80 AC-4** — release over card → `handleJoinDrop` called | spec US-80 | TC-E59-A03 |
| **US-80 AC-5** — release outside any card → no state change; warning haptic | spec US-80 | TC-E59-I11, §10 (device) |
| **US-80 AC-6** — in-flight source pill at 0.5 opacity, non-draggable | spec US-80 | TC-E59-I03, TC-E59-I05 |
| **US-84 AC-1** — coach mark appears when first eligible pill present | spec US-84 | TC-E59-A10 |
| **US-84 AC-2** — auto-fades after 3 seconds | spec US-84 | TC-E59-A12 |
| **US-84 AC-4** — `hasSeen` persisted; mark never reappears | spec US-84 | TC-E59-A13, TC-E59-A14 |
| **US-84 AC-5** — mark not shown if no eligible pill; mark does not block gestures | spec US-84 | TC-E59-A11, TC-E59-A15 |
| **Forward-compat: `refreshGroups()` NOT called in E-59** | ADR §5 | TC-E59-U12, TC-E59-E07 |
| **Forward-compat: `GroupChipRow` NOT touched in E-59** | ADR §5 | TC-E59-E08 |
| **Forward-compat: `ChipData` unchanged; no `onTap` in E-59** | ADR §5 | TC-E59-E09 |
| **Transferable: `.data` UTI only; no secondary representation** | ADR §7 | TC-E59-U06 |
| **Existing `HapticEngine` methods unchanged** | ADR §7 | TC-E59-I12 |
| **`resolveSpeaker` nil-safe for unresolvable identifier** | ADR §8 CF-4 | TC-E59-U09, TC-E59-A02 |
| **English coach mark string exact value** | ADR §7 / design-spec Appendix B | TC-E59-A16 |
| **Danish coach mark string exact value** | ADR §7 / design-spec Appendix B | TC-E59-A17 |

---

## 9. Spec Gaps Discovered

The following gaps and inconsistencies were identified during preparation of this test plan. They do not block implementation but should be acknowledged.

### SG-1 — `resolveSpeaker` tie-break behaviour not specified when multiple speakers share a JID

ADR §7 contract #1 says "matches by `jid` first (when non-nil)" and ADR §8 CF-4 says "every speaker is assigned to at least a solo group by ADR-003's reconstruct algorithm." However, the contract is silent on what happens if two speakers in `discovery.groups.flatMap(\.members)` share the same `jid` (which should not occur in a correct B&O network, but could transiently during a discovery race). The implementation returns "the first match" implicitly via `first(where:)` semantics. TC-E59-U07 asserts this and documents the first-match behaviour. Recommend adding a contract note to `SessionViewModel.swift` inline: "Multiple JID matches are unexpected; `first(where:)` semantics mean the match closest to the front of `groups.flatMap(\.members)` wins."

### SG-2 — epics T-5909 references `Localizable.strings`; ADR §8 CF-5 supersedes it

`epics-and-tasks-multiroom-grouping.md T-5909` states: "Add string keys `grouping.coachMark.en` / `grouping.coachMark.da` to `iOS/Voxio/Resources/Localizable.strings`." This conflicts with ADR §8 CF-5, which mandates the `GroupingStrings.swift` struct pattern (no `.strings` file). The ADR supersedes the epics doc. TC-E59-A18 is the regression test. Recommend updating T-5909 to match the ADR so future implementers are not confused.

### SG-3 — `GroupingCoachMark` contract #4 (position above pill) has no automated test path

ADR §7 contract #4 states: "Position: overlay above first eligible pill, `Spacing.s8` above pill top." This positioning cannot be mechanically verified without a running layout engine and pixel measurements. It is acknowledged in this plan as a design-only contract verified by visual inspection. See §10 for deferral. No spec amendment needed — this is an inherent limitation of layout testing without a running device.

### SG-4 — `dragCancelled()` hookup path is unspecified when iOS 26 lacks a cancel callback

ADR §5 and §8 CF-6 acknowledge the `dragCancelled()` haptic is best-effort, but the fallback mechanism ("from a drag-end observer at the pill level" or "from the bottom-bar `onDrop(of:)` if the drop falls back to the bar's space") is left vague. T-5908 in the epics doc says to investigate on device. TC-E59-I11 covers only the `HapticEngine` method body itself; the call-site wiring is deferred to §10. Recommend that the implementer document the chosen hookup mechanism in the T-5908 PR description for traceability.

### SG-5 — `SessionViewModel.group` vs `SpeakerCard.group` same-instance requirement (CF-7) is untestable in isolation

ADR §8 CF-7 requires that both `SpeakerCard.group` and `SessionViewModel.group` receive the same `SpeakerGroup` instance from `SessionStripView`'s ForEach. This is a code-review and integration concern, not unit-testable. The TC is deferred to manual device verification in §10. No spec amendment needed.

### SG-6 — `GroupingCoachMark.onDismiss` vs internal `hasSeen` mutation — responsibility boundary unclear

ADR §7 shows `onDismiss: () -> Void` as a parameter, but also declares `@AppStorage("hasSeenGroupingCoachMark") private var hasSeen: Bool = false` as a stored property on the modifier itself. It is ambiguous whether `onDismiss()` is responsible for setting `hasSeen = true`, or whether the modifier sets `hasSeen = true` internally and then calls `onDismiss()` to notify the parent. TC-E59-A13 assumes the modifier owns the `hasSeen` write (because `hasSeen` is private). The `onDismiss` closure is for parent notification (e.g. E-60 T-6001 will use it to complete the coach-mark drop trigger path). Recommend ADR §7 add a clarifying note: "The modifier sets `hasSeen = true` internally on any dismiss path; `onDismiss` is a notification callback for parent components, not the persistence mechanism."

---

## 10. Tests Deferred to Manual Device Verification

The following items require a physical iPhone on iOS 26 and cannot be verified via static code review, SwiftUI previews, or simulator-only testing.

| Deferred Item | Rationale | Corresponding Task |
|---|---|---|
| Long-press lift haptic — physical feel of `UIImpactFeedbackGenerator(style: .medium)` on device | Haptic quality is subjective; `impactOccurred()` only produces haptic feedback on physical hardware | T-5904 |
| Ghost pill appearance and `1.06×` scale on real device during drag | Ghost rendering is a SwiftUI system behaviour, visually verified only during real drag interaction | T-5904 |
| Ghost cancel — SwiftUI default spring-return animation quality on iOS 26 | Cancel animation is SwiftUI system behaviour; ADR notes "iOS 26 availability unverified" | T-5908 |
| `dragCancelled()` haptic call-site wiring — whether a cancel callback exists on iOS 26 `.draggable` | ADR §5 CF-6: "SwiftUI's `.draggable` does not expose a cancel callback in iOS 16/17; iOS 26 availability unverified"; physical device required to test | T-5908 |
| `SpeakerCard` drop-zone gold border fade animation speed — "within one spring cycle" per design-spec §3 | Spring animation timing requires device-speed rendering to assess perceptually | T-5906 |
| `SpeakerCard` modifier order (CF-2) — drop destination geometry matches visible hit area after `scaleEffect` | Hit-test geometry verification requires a running device with a live drag interaction | T-5905, T-5906 |
| ADR §8 CF-7 — `SpeakerCard.group` and `sessionVM.group` are the same instance in `SessionStripView` ForEach | Requires live `SessionStripView` render with real groups; reference-identity check is integration-level | T-5905 |
| Coach mark visual position above first eligible pill — `Spacing.s8` gap | Layout position is verified by visual inspection on device; no mechanical test for view frame geometry | T-5909 |
| Multi-card drag — peeking card at edge activates gold border when ghost enters its bounds | Requires real drag with two cards partially visible; not reproducible in previews | T-5907 |
| End-to-end drag gesture: long-press → ghost follows finger → drop on card → `handleJoinDrop` stub log appears in Console | Full gesture requires real device; simulator drag-and-drop may behave differently | T-5910 |
| E-59 manual verification checklist (T-5910) items 1–7 — as listed in `epics-and-tasks-multiroom-grouping.md` | All require physical device with Mozart speakers on LAN; results documented in `test-notes-multiroom-grouping.md` | T-5910 |
