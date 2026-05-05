# Epics & Tasks: Voxio v1.3 — Command Parsing Pipeline v2
**Version:** 1.3.0-iOS-pipeline
**Status:** Draft
**Date:** 2026-05-05
**References:** ADR E-41 (`iOS/docs/adr/E-41-command-parsing-pipeline-v2.md`), ADR E-33 (PersonalisationParser), ADR E-37 (Broadcast intercept), `HomeView.swift` lines 388–544, `CommandParserRouter.swift`, `PersonalisationStore.swift`, `SpeakerNameMatcher.swift`, CLAUDE.md
**Languages:** English (`en-US`) and Danish (`da-DK`) — both fully supported

---

## Overview

This document covers a single iOS-track epic — **E-41: Command Parsing
Pipeline v2** — which restructures the voice-command dispatch flow in
`HomeView` from a speaker-name-first pipeline into an intent-first
utterance-classification pipeline. The change resolves the architectural
gap that caused alias phrases without a speaker name (e.g. "musik til
arbejdet") to be rejected by `SpeakerNameMatcher` before the alias store
was consulted.

The full design is in ADR E-41. This document breaks the work into nine
implementable tasks (T-4101 through T-4109).

### Numbering note

A separate spec document (telemetry backend) also begins at **E-41 / T-4101**
in its own namespace. The two are tracked in different documents and on
different boards; the namespaces do not collide. iOS pipeline work uses
this document.

---

## Epic Index

| # | Epic | Tasks | Feature Area |
|---|---|---|---|
| E-41 | Command Parsing Pipeline v2 | T-4101 – T-4109 | iOS — voice command dispatch refactor |

---

## E-41 — Command Parsing Pipeline v2

Replace the broadcast pre-check + speaker resolution gate + parse + post-parse
broadcast intercept block in `HomeView` with a single classification step
followed by a `switch` on `UtteranceClass`. Introduce
`UtteranceClassifier` as a `@MainActor` struct in
`iOS/Voxio/Core/CommandParsing/`. Promote
`PersonalisationStore.matchPersonalisedCommandAcrossAllSpeakers` from a
HomeView workaround to the official backing API for the `.personalised`
classification path. Add a focused-speaker fallback so utterances with no
speaker name and no alias hit fall back to the currently selected speaker
in the UI.

The three-tier parser internals (Stage 1 regex, Foundation Models, NLModel)
are not changed. `VoiceCommand`, `ParsedCommand`, and `CommandIntent` are
not changed. `SpeakerNameMatcher` is reused inside the classifier.

**Depends on:** E-33 (PersonalisationStore exists), E-37 (broadcast intent
cases exist on `VoiceCommand`).
**Unlocks:** future work on conversational follow-ups, multi-turn dialogue,
cross-speaker grouping voice commands.

### Acceptance criteria for the epic as a whole

- A user who has saved the alias "musik til arbejdet" → (speaker A,
  `playDefault`) can say "musik til arbejdet" and the command dispatches
  to speaker A — no speaker name in the transcript.
- "Stop alle" / "Stop everything" continues to broadcast across all
  speakers (no regression of E-37).
- Saying "yes" / "no" during a pending countdown still confirms / cancels
  (no regression of the existing system-command path).
- After commanding speaker A successfully, saying "pause" with no speaker
  name pauses speaker A (the focused speaker).
- Saying a command with no speaker name, no alias hit, and no focused
  speaker still surfaces `.noSpeakerSpoken` to the user.
- Saying a speaker name followed by a command continues to work
  identically to today.

---

### Task list

- [ ] **T-4101** Create `iOS/Voxio/Core/CommandParsing/UtteranceClassifier.swift`.
  Define the `UtteranceClassifier.Outcome` enum (four classification cases plus
  `.unresolved`) and the `UtteranceClassifier` struct itself. The struct is
  `@MainActor`, value-type, holds references to
  `SpeakerDiscoveryService`, `PersonalisationStore`, `CommandParserRouter`,
  and a `focusedSpeaker: () -> Speaker?` closure. Add a top-level typealias
  `UtteranceClass = UtteranceClassifier.Outcome`. Implement `classify(_ text: String) -> Outcome`
  as a stub that returns `.unresolved` for everything; later tasks fill in
  the cases. Mirror the public surface in ADR E-41 exactly.

  Note: there is **no `.system` case** — confirm/cancel are UI-only (OQ-1
  resolved 2026-05-05).

  **Files added:** `iOS/Voxio/Core/CommandParsing/UtteranceClassifier.swift`.
  **Files changed:** none.
  **Acceptance criteria:**
  - File compiles with Swift 6 strict concurrency under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
  - `UtteranceClassifier(...).classify("anything")` returns `.unresolved`.
  - The `Outcome` enum has exactly five cases: `.broadcast`, `.personalised`, `.addressed`, `.focused`, `.unresolved`.
  - The typealias `UtteranceClass` is referenceable from outside the file (e.g. `UtteranceClass.broadcast(.stopAll)`).

  *No dependencies. Prerequisite for T-4103 – T-4106.*

- [ ] **T-4103** Refactor broadcast classification into
  `UtteranceClassifier`. The classifier's branch 2 calls the existing
  `CommandParserRouter.parseBroadcast(_:)` (no change to its signature
  or body) and, on a non-nil result, returns `.broadcast(cmd)`. Do not
  remove the broadcast pre-check from HomeView in this task — that is
  T-4107's responsibility — but the classifier must produce the same
  outcomes for every broadcast utterance.

  **Files changed:**
  - `iOS/Voxio/Core/CommandParsing/UtteranceClassifier.swift` — wire branch 2.

  **Acceptance criteria:**
  - `classify("stop alle")` returns `.broadcast(.stopAll)`.
  - `classify("pause everything")` returns `.broadcast(.pauseAll)`.
  - `classify("skru op for alt 20")` returns `.broadcast(.adjustVolumeAll(20))`.
  - `classify("stop")` does NOT match `.broadcast` — it has no qualifier; falls through.
  - The order is: `.system` is checked first (T-4102), `.broadcast` second.

  *Depends on: T-4101, T-4102.*

- [ ] **T-4104** Implement cross-speaker alias + confirmed-command
  classification. Branch 3 of the classifier checks
  `personalisationStore.isEnabled`, then calls
  `personalisationStore.matchPersonalisedCommandAcrossAllSpeakers(phrase: text)`.
  If a hit is returned, the classifier looks up the speaker in
  `discovery.groups.flatMap(\.members)` by `speakerId` (matching
  `Speaker.id.uuidString`). If the speaker is found, return
  `.personalised(speaker:, command:)`. If the speaker is **not** found
  (e.g. powered off, removed from discovery), the classifier falls
  through to the next branch — do not surface `.unresolved` from this
  branch. Log at info level both the hit and the speaker-missing
  fall-through.

  **Files changed:**
  - `iOS/Voxio/Core/CommandParsing/UtteranceClassifier.swift` — wire branch 3.
  - `iOS/Voxio/Core/Personalisation/PersonalisationStore.swift` — add a doc comment on `matchPersonalisedCommandAcrossAllSpeakers` noting it is the official backing API for the `.personalised` classification path (no code change).

  **Acceptance criteria:**
  - With an alias saved as `("speaker-A-uuid", "musik til arbejdet", .playDefault)` and speaker A in `discovery.groups`, `classify("musik til arbejdet")` returns `.personalised(speaker: A, command: ParsedCommand(intent: .playDefault, ...))`.
  - With the same alias but speaker A absent from `discovery.groups`, `classify("musik til arbejdet")` does NOT return `.personalised` — it falls through.
  - With `personalisationStore.isEnabled == false`, this branch is skipped entirely.
  - Confirmed commands (entries in `ConfirmedCommand`) match the same way as aliases — both are exposed by `matchPersonalisedCommandAcrossAllSpeakers`.

  *Depends on: T-4101.*

- [ ] **T-4105** Implement speaker-name classification. Branch 4 lowercases
  and tokenises `text`, then calls `discovery.resolve(words:)` (which wraps
  `SpeakerNameMatcher`). On match, return
  `.addressed(speaker: matched, remainder: remainingWords.joined(separator: " "))`.
  If `remainingWords` is empty, return
  `.addressed(speaker: matched, remainder: text)` — the remainder is the
  original text, deferring the "bare speaker name" handling to
  `CommandParserRouter.parse`, which already returns `.unknown` for empty
  command text after speaker stripping.

  **Files changed:**
  - `iOS/Voxio/Core/CommandParsing/UtteranceClassifier.swift` — wire branch 4.

  **Acceptance criteria:**
  - With speakers `["Stue", "Køkken"]`, `classify("stue play")` returns `.addressed(speaker: Stue, remainder: "play")`.
  - With the same speakers, `classify("stue")` returns `.addressed(speaker: Stue, remainder: "stue")` (remainder falls back to original).
  - With the same speakers, `classify("køkken pause")` returns `.addressed(speaker: Køkken, remainder: "pause")`.
  - The Levenshtein-2 fuzzy match is preserved (existing `SpeakerNameMatcher` behaviour).

  *Depends on: T-4101.*

- [ ] **T-4106** Implement focused-speaker fallback. Branch 5: if branches
  1–4 all fall through, call `focusedSpeaker()`. If the closure returns a
  non-nil `Speaker`, return `.focused(speaker:, text:)`. If it returns
  `nil`, return `.unresolved`. Do not perform any speaker lookup in
  `discovery` — the closure is the source of truth.

  **Files changed:**
  - `iOS/Voxio/Core/CommandParsing/UtteranceClassifier.swift` — wire branches 5 and 6 (`.focused` and `.unresolved`).

  **Acceptance criteria:**
  - With `focusedSpeaker = { Stue }` and an utterance "play favourite one" that does not match system / broadcast / alias / speaker-name, `classify(...)` returns `.focused(speaker: Stue, text: "play favourite one")`.
  - With `focusedSpeaker = { nil }` and the same input, `classify(...)` returns `.unresolved`.
  - The `text` argument passed back in `.focused` is the original input verbatim (lowercased only if the upstream parse pipeline expects lowercase — match HomeView's current behaviour, which lowercases inside the parser).

  *Depends on: T-4101, T-4102, T-4103, T-4104, T-4105.*

- [ ] **T-4107** Refactor `HomeView` dispatch to switch on `UtteranceClass`.
  Replace the block from lines 401 to 460 (broadcast pre-check + speaker
  resolution `if/else if/else` chain + speaker-resolved dispatch + post-parse
  broadcast intercept) with:

  1. Construct an `UtteranceClassifier` inside `handleFinalTranscript`,
     capturing `discovery`, `personalisationStore`, `commandRouter`, and
     `{ selectedSpeaker }`.
  2. `let outcome = classifier.classify(text)`.
  3. `switch outcome { … }` covering all six cases per the ADR's pseudo-code.

  Remove the inline `personalisationStore.matchPersonalisedCommandAcrossAllSpeakers`
  call from HomeView (the workaround). Remove the post-parse `isBroadcast(command)`
  intercept — broadcasts are now classified up-front and cannot reach the
  single-speaker dispatch path.

  Preserve all existing side effects:
  - `HapticEngine.shared.commandRecognised()` fires on every non-`.unresolved`,
    non-`.unknown` outcome.
  - `selectedSpeaker = speaker` is set on `.personalised`, `.addressed`, and `.focused`.
  - `transcriptController.clearAfterCommand()` is called on every terminal path.
  - The confirmation-coordinator path (`coordinator.startCountdown`),
    telemetry recording, `confirmedCommandCount` increment, and
    `showTelemetryPrompt` logic remain unchanged — they apply to `.personalised`,
    `.addressed`, and `.focused` outcomes.

  Extract a private helper `dispatchWithConfirmationIfNeeded(command:to:commandText:) async`
  that encapsulates the existing `confirmationMessage / preflightError / coordinator.startCountdown / dispatch`
  flow, called by the three dispatchable cases.

  **Files changed:**
  - `iOS/Voxio/Features/Home/HomeView.swift` — replace the block; add the helper.

  **Acceptance criteria:**
  - The current "musik til arbejdet" failure log line (`[HomeView] no speaker resolved for: Musik til arbejdet`) no longer appears for any saved alias — instead the alias dispatches.
  - "Stop alle" continues to broadcast (regression test in T-4108).
  - "Yes" / "Nej" continue to confirm / cancel a pending countdown.
  - HomeView no longer references `matchPersonalisedCommandAcrossAllSpeakers` (grep verifies zero hits in `Features/`).
  - The `parseBroadcast` call site in HomeView is removed (the classifier owns it now); `parseBroadcast` itself remains in `CommandParserRouter` and is called from inside the classifier.
  - Line count of the transcript handler drops by ≥ 30 lines.

  *Depends on: T-4106.*

- [ ] **T-4108** Write unit tests for `UtteranceClassifier` covering all
  five paths plus `.unresolved`. Place tests in
  `iOS/VoxioTests/UtteranceClassifierTests.swift`. Use an in-memory
  `PersistenceController.preview` for the store, a fake
  `SpeakerDiscoveryService` with a fixed speaker list, a real
  `CommandParserRouter` (no Foundation Models dependency required for the
  classifier's synchronous paths), and a closure-controlled
  `focusedSpeaker`.

  Test cases (one per outcome, plus regression cases):
  - `broadcast_stop_all` — "stop alle" → `.broadcast(.stopAll)`.
  - `broadcast_volume_up_all_with_amount` — "skru op for alt 20" → `.broadcast(.adjustVolumeAll(20))`.
  - `personalised_alias_no_speaker_name` — alias "musik til arbejdet" saved for speaker A, utterance "musik til arbejdet" → `.personalised(A, ...)`.
  - `personalised_speaker_offline_falls_through` — alias saved for speaker B, but speaker B not in discovery → falls through to `.unresolved` (no other branch can match the phrase).
  - `addressed_simple` — "stue play" with speaker "Stue" present → `.addressed(Stue, "play")`.
  - `addressed_fuzzy` — "stu play" (Levenshtein 1) with speaker "Stue" → `.addressed(Stue, "play")`.
  - `addressed_bare_speaker_name` — "stue" → `.addressed(Stue, "stue")`.
  - `focused_fallback_used` — "pause" with no name match, no alias, `focusedSpeaker = Stue` → `.focused(Stue, "pause")`.
  - `unresolved_no_focused_speaker` — "pause" with no name match, no alias, `focusedSpeaker = nil` → `.unresolved`.
  - `personalisation_disabled_skips_branch` — alias exists but `personalisationStore.isEnabled = false` → does NOT return `.personalised`.
  - `system_wins_over_alias` — alias saved with phrase "yes" (hypothetical) → still classified as `.system(.confirm)` because branch 1 wins.
  - `broadcast_wins_over_alias` — alias saved with phrase "stop alle" → still classified as `.broadcast(.stopAll)` because branch 2 wins over branch 3.

  **Files added:** `iOS/VoxioTests/UtteranceClassifierTests.swift`.

  **Acceptance criteria:**
  - All listed test cases pass.
  - Tests run in < 1 second total (no Foundation Models warm-up; no real Core Data file — use in-memory).
  - The test file compiles under Swift 6 strict concurrency.

  *Depends on: T-4101 – T-4106.*

- [ ] **T-4109** Integration test — verify "musik til arbejdet"-style
  aliases work end-to-end. Place test in
  `iOS/VoxioTests/CommandPipelineIntegrationTests.swift`. The test:

  1. Constructs a real `PersonalisationStore` backed by an in-memory
     Core Data context (via `PersistenceController.preview`).
  2. Saves an alias `("speaker-A-uuid", "musik til arbejdet", .playDefault, [:])`.
  3. Constructs a `CommandParserRouter` with that store.
  4. Constructs an `UtteranceClassifier` with a fake discovery containing
     a `Speaker` whose `id.uuidString == "speaker-A-uuid"`, and
     `focusedSpeaker = { nil }`.
  5. Calls `classifier.classify("musik til arbejdet")`.
  6. Asserts the outcome is `.personalised(speaker: A, command: <intent: .playDefault>)`.

  Add a second test case verifying confirmed-command memory dispatch:
  save a confirmed-command record `("speaker-B-uuid", "tænd musikken", .resume, [:])`,
  utter "tænd musikken" with no speaker name, expect
  `.personalised(speaker: B, command: <intent: .resume>)`.

  Add a third test case verifying that the same utterance with no alias
  saved and no focused speaker returns `.unresolved`.

  **Files added:** `iOS/VoxioTests/CommandPipelineIntegrationTests.swift`.

  **Acceptance criteria:**
  - All three integration cases pass.
  - The first case fails before T-4104 / T-4107 ship (proves the test catches the original bug).
  - The test does not depend on Foundation Models (the `.personalised` path skips the parser entirely).

  *Depends on: T-4101 – T-4107.*

---

## Dependency graph

T-4102 is removed (system-command classification — OQ-1 resolved: UI only).

```
T-4101 ─┬─> T-4103 ─> T-4106 ─> T-4107 ─> T-4108 ─> T-4109
        ├─> T-4104 ─┘              ▲
        └─> T-4105 ────────────────┘
```

T-4108 (unit tests) can be developed in parallel with T-4101 – T-4106 (TDD)
but cannot pass until T-4106 lands. T-4109 (integration) cannot pass until
T-4107 lands.

---

## Out of scope (this epic)

- The three-tier parser internals (Stage 1 regex / Foundation Models /
  NLModel / Stage 2). They are reused unchanged.
- New `VoiceCommand` cases or new `CommandIntent` cases.
- Multi-turn dialogue ("play music… louder… pause") — the focused-speaker
  fallback is a single-utterance follow-up; multi-turn state lives outside
  the classifier.
- A separate "last commanded speaker" field — `selectedSpeaker` already
  serves that role and is updated by the dispatch path. Splitting them is
  a future epic.
- Voice-driven editing of aliases / personalisation — out of scope.
- Telemetry-pipeline changes — the classifier path already records via the
  existing `telemetryBuffer.record` calls; no schema changes.

---

## Open questions

All open questions resolved. See Resolved Decisions table below.

---

## Resolved decisions

| Question | Decision |
|---|---|
| Where does the classifier live? | New file `iOS/Voxio/Core/CommandParsing/UtteranceClassifier.swift`; auto-compiled via `PBXFileSystemSynchronizedRootGroup`. |
| Should the classifier be `@MainActor`? | Yes — it accesses `PersonalisationStore` (`@MainActor`) and `SpeakerDiscoveryService`. |
| Is `parseBroadcast` removed from `CommandParserRouter`? | No — it is still called, but only from inside the classifier. The HomeView call site is removed. |
| Is the workaround `matchPersonalisedCommandAcrossAllSpeakers` deleted? | No — it becomes the official backing API for `.personalised`. |
| Is `UtteranceClassifier` a class or a struct? | Struct. Value type, stateless beyond captured references, constructed per transcript. |
| What is "focused speaker"? | The current value of `HomeView.selectedSpeaker`, exposed to the classifier via a closure. No new state field is added. |
| Order of classification branches? | Locked: broadcast → personalised → addressed → focused → unresolved. |
| Does `.focused` consult the alias store? | No — alias lookup is branch 2, before `.focused`. If an alias matches, it wins. |
| Does the classifier run the full three-tier parser? | No. It runs only Stage 1 broadcast patterns and exact-string lookups (personalised). The full parse is delegated to `CommandParserRouter.parse` for `.addressed` and `.focused` from inside HomeView. |
| OQ-1: Voice confirm/cancel | **Removed.** Confirm and cancel are UI-button only. Voice input ignored during active countdown. Confirm/cancel Stage 1 regex deleted from `TwoStageFallbackParser`. No `.system` case in classifier. |
| OQ-2: Alias vs fuzzy speaker-name precedence | **Alias wins.** `.personalised` (branch 2) runs before `.addressed` (branch 3). Exact alias always beats fuzzy speaker-name match. |
| OQ-3: focusedSpeaker persistence across launches | **No persistence.** `selectedSpeaker` resets to nil on cold launch. Focused-speaker fallback is within-session only. |
