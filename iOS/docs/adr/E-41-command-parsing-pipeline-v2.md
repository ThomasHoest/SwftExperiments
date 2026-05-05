# ADR E-41 — Command Parsing Pipeline v2 (Intent-First Utterance Classification)

**Status:** Proposed
**Date:** 2026-05-05
**Epic:** E-41 (Voxio 1.3, iOS pipeline track)

---

## Decision

Replace the current speaker-name-first dispatch flow in `HomeView` with an
**intent-first, utterance-classification pipeline**. A new `@MainActor` struct
`UtteranceClassifier` is introduced in `iOS/Voxio/Core/CommandParsing/`. It
exposes a single synchronous entry point:

```swift
func classify(_ text: String) -> UtteranceClass
```

`UtteranceClass` is a five-case enum that captures the *kind* of utterance
before any speaker resolution is performed:

```swift
enum UtteranceClass {
    case system(VoiceCommand)                                    // confirm / cancel
    case broadcast(VoiceCommand)                                 // stopAll / pauseAll / …
    case personalised(speaker: Speaker, command: ParsedCommand)  // alias / confirmed-command hit (any speaker)
    case addressed(speaker: Speaker, remainder: String)          // speaker name appears in transcript
    case focused(speaker: Speaker, text: String)                 // no speaker name; uses currently focused speaker
    case unresolved                                              // no classification possible
}
```

`HomeView` becomes a thin dispatch layer that switches on `UtteranceClass`
exactly once per final transcript. The current "broadcast pre-check + speaker
resolution gate + parse + post-parse broadcast intercept" pattern is replaced
by a single switch over the classifier output. The hard speaker-name gate is
removed.

The cross-speaker alias workaround
(`PersonalisationStore.matchPersonalisedCommandAcrossAllSpeakers`) is **kept**
as the implementation backing the `.personalised` case. The HomeView call
site, however, is removed: the classifier owns the lookup.

---

## Context

A failure in the current pipeline exposed an architectural gap:

```
[SpeakerMatcher] no match for words=["musik", "til", "arbejdet"]
[HomeView] no speaker resolved for: Musik til arbejdet
```

"Musik til arbejdet" is a saved alias for (speaker A, `.playDefault`). The
phrase contains **no speaker name**. Under the current pipeline:

1. `parseBroadcast()` runs first — no broadcast pattern match.
2. `discovery.resolve(words:)` runs next — `SpeakerNameMatcher` fails (no
   token within Levenshtein 2 of any speaker).
3. The `else` arm calls `handleError(.noSpeakerSpoken)` and returns. The
   alias store is **never consulted**.

A workaround was patched into HomeView: after `discovery.resolve` fails, a
fallback call to `PersonalisationStore.matchPersonalisedCommandAcrossAllSpeakers`
is made, and if it hits, the alias's `speakerId` is used. This is a symptom,
not a fix. The deeper problem is that the pipeline is structured around
speaker-name resolution as a hard precondition for every other classification.

The architectural problems, enumerated:

1. **Speaker-name resolution is a hard gate.** Every command — including
   commands that don't need a speaker (confirm/cancel) and broadcast commands
   (which need *all* speakers, not one) — has to either pass the matcher or
   match a special-cased pre-check.
2. **Aliases that span no speaker name fail.** The alias store is reached
   from `CommandParserRouter.parse()`, which runs *after* speaker resolution.
   No speaker → no parse → no alias lookup.
3. **No focused-speaker fallback.** If the user has just commanded speaker A
   and follows up with a bare command ("pause"), the matcher fails and the
   utterance is rejected. The `selectedSpeaker` UI state is ignored.
4. **Confirmed commands have the same gate problem.** The same bug applies to
   learned phrases — they require the spoken speaker name to be re-spoken.
5. **System commands (confirm/cancel) leak into the speaker path.** They
   don't need a speaker. They are handled correctly during a pending
   countdown but otherwise compete with speaker-name matching.
6. **The broadcast pre-check is a bolted-on special case.** `parseBroadcast`
   was added specifically because "stop alle" causes `SpeakerNameMatcher` to
   consume "stop" (Levenshtein 2 from "Stue"), leaving "alle" as the command
   text. The pre-check works but signals that the order of operations is
   inverted.

The right fix is to invert the order: **classify the utterance first; resolve
the speaker only when the classification demands it.** Phase 1 (classification)
is cheap and synchronous. Phase 2 (speaker resolution, if needed) and Phase 3
(three-tier parsing) follow.

---

## Options Considered

### Option A — `UtteranceClassifier` struct, five-case `UtteranceClass` enum (chosen)

A new `@MainActor struct UtteranceClassifier` owns Phase 1. It is constructed
with references to `SpeakerDiscoveryService`, `PersonalisationStore`,
`CommandParserRouter`, and a `focusedSpeakerProvider: () -> Speaker?` closure.
`classify(_:)` returns one of the five cases above; HomeView's transcript
handler switches on it.

- Pro: classification logic is testable in isolation (inject mock store /
  mock discovery / mock focused-speaker provider).
- Pro: HomeView shrinks to a `switch` — no nested guards, no "pre-check"
  comments, no `else if` arms doing fallback resolution.
- Pro: the workaround (`matchPersonalisedCommandAcrossAllSpeakers`) is
  preserved as the `.personalised` backing call — no behavioural regression.
- Pro: the broadcast pre-check moves from a HomeView side-channel into a
  named, documented classification path (`.broadcast`).
- Con: HomeView gains one more `@State` member (the classifier). Minor.

### Option B — Re-order the existing pipeline inside `CommandParserRouter.parse()`

Make `parse()` take the full transcript (no speaker stripping), have it
consult aliases across all speakers first, then internally do speaker name
matching, etc.

- Pro: no new file.
- Con: `parse()` currently returns `VoiceCommand`, which carries no speaker
  identity. To return both speaker and command, the return type must change
  — a much larger blast radius than introducing a classifier.
- Con: breaks the "router parses speaker-stripped text" contract that other
  callers (e.g. `parseBroadcast`) rely on.
- Con: doesn't fit a focused-speaker fallback cleanly — that's a UI-state
  concern, not a parser concern.

### Option C — Move classification into `SpeakerDiscoveryService`

`discovery.resolve(words:)` could be expanded to return a richer enum.

- Con: `SpeakerDiscoveryService` is platform-specific (mDNS, peers graph,
  group assembly). Adding alias lookup and confirm/cancel pattern matching
  to it conflates discovery with intent classification.
- Con: doesn't reduce HomeView complexity — HomeView still needs to handle
  the five outcomes.

**Option A is chosen.** It cleanly separates Phase 1 (classification, pure
logic, synchronous) from Phase 2 (speaker resolution, which only some paths
need) and Phase 3 (the existing three-tier parser, untouched).

---

## Rationale

The classifier-first design enforces a single principle: **decide what kind
of utterance this is before deciding which speaker it targets.** That
principle dissolves all six listed problems:

- System commands have their own classification (`.system`); they never see
  the speaker matcher.
- Broadcast commands have their own classification (`.broadcast`); the
  pre-check stops being a "pre-check" and becomes a first-class branch.
- Aliases that span no speaker name have their own classification
  (`.personalised`); the cross-speaker store lookup is the natural,
  unconditional way to resolve them.
- Focused-speaker fallback has its own classification (`.focused`); when no
  speaker name is present and no alias hits, the currently focused speaker
  is used.
- The speaker-name path has its own classification (`.addressed`); it is now
  one branch among five, not the gate that all others must pass through.

The three-tier parser internals (Stage 1 regex, Foundation Models, NLModel
fallback) are not changed. The classifier delegates command parsing to
`CommandParserRouter.parse(text:speakerId:)` for `.addressed` and `.focused`,
just as HomeView does today.

---

## Consequences

- `HomeView` loses ≈ 40 lines of dispatch code; gains a single `switch`.
- `PersonalisationStore.matchPersonalisedCommandAcrossAllSpeakers` becomes a
  documented, first-class API rather than a workaround.
- A new "focused speaker" concept is introduced. It is the speaker last
  selected in the UI (`selectedSpeaker`), or `nil` if none. The classifier
  receives it via a closure so HomeView's `@State` can drive it without the
  classifier holding a SwiftUI binding.
- The `.unresolved` case is the only one that surfaces `noSpeakerSpoken` to
  the user. All other classifications produce a dispatchable outcome.
- Existing unit tests for `CommandParserRouter` are unaffected — the router's
  public surface does not change.
- New unit tests for `UtteranceClassifier` cover all five paths.
- One integration test covers the original failing scenario ("musik til
  arbejdet" with no speaker name).

---

## File-Level Plan

### New files

| Path | Purpose |
|---|---|
| `iOS/Voxio/Core/CommandParsing/UtteranceClassifier.swift` | `UtteranceClass` enum + `UtteranceClassifier` struct. Phase 1 owner. |
| `iOS/VoxioTests/UtteranceClassifierTests.swift` | Unit tests, one per `UtteranceClass` case + `.unresolved`. |
| `iOS/VoxioTests/CommandPipelineIntegrationTests.swift` | End-to-end test: alias save → speak phrase with no speaker name → command dispatched to alias's speaker. |

### Modified files

| Path | Change |
|---|---|
| `iOS/Voxio/Features/Home/HomeView.swift` | Replace the broadcast pre-check / speaker resolution / parse / post-parse broadcast intercept block (lines 401–460) with a single `switch await classifier.classify(text)`. Remove the local `matchPersonalisedCommandAcrossAllSpeakers` call (lines 427–432). Add a `@State private var classifier: UtteranceClassifier`. |
| `iOS/Voxio/Core/CommandParsing/CommandParserRouter.swift` | Add `parseSystem(_ text: String) -> VoiceCommand?` returning `.confirm` / `.cancel` / `nil`. The existing `parseBroadcast(_:)` is unchanged. |
| `iOS/Voxio/Core/Personalisation/PersonalisationStore.swift` | No code change. The existing `matchPersonalisedCommandAcrossAllSpeakers(phrase:)` is now documented as the supported backing API for the `.personalised` classification. |

### Untouched (out of scope)

- `TwoStageFallbackParser` (Stage 1 / Stage 2 internals).
- `FoundationModelParser` (Tier 1 internals).
- `PersonalisationParser` (Tier 0 — still runs inside `CommandParserRouter.parse`
  for `.addressed` / `.focused`).
- `SpeakerNameMatcher` (still used inside the classifier; behaviour unchanged).
- `VoiceCommand` enum cases.

---

## Public Interface Contract

```swift
// iOS/Voxio/Core/CommandParsing/UtteranceClassifier.swift

@MainActor
struct UtteranceClassifier {

    /// All possible classification outcomes. Exactly one is returned per call.
    enum Outcome {
        case system(VoiceCommand)                                    // .confirm / .cancel
        case broadcast(VoiceCommand)                                 // .stopAll / .pauseAll / .resumeAll / .adjustVolumeAll / .muteAll / .unmuteAll
        case personalised(speaker: Speaker, command: ParsedCommand)  // alias or confirmed-command hit (any speaker)
        case addressed(speaker: Speaker, remainder: String)          // SpeakerNameMatcher consumed leading tokens
        case focused(speaker: Speaker, text: String)                 // no speaker name; using last focused speaker
        case unresolved                                              // no classification possible
    }

    init(
        discovery: SpeakerDiscoveryService,
        personalisationStore: PersonalisationStore,
        router: CommandParserRouter,
        focusedSpeaker: @escaping () -> Speaker?
    )

    /// Classifies the utterance. Synchronous: all five paths are cheap lookups.
    /// The full three-tier parse is NOT performed here — only Stage 1 patterns
    /// for system/broadcast and an exact-string lookup for personalised.
    func classify(_ text: String) -> Outcome
}
```

A typealias `UtteranceClass = UtteranceClassifier.Outcome` is provided at file
scope so call sites can write `UtteranceClass.system(...)` without nesting.

```swift
// iOS/Voxio/Core/CommandParsing/CommandParserRouter.swift  (additions)

extension CommandParserRouter {
    /// Returns `.confirm` / `.cancel` if `text` matches a Stage 1 system pattern,
    /// otherwise `nil`. Does not consult personalisation, Foundation Models, or NLModel.
    func parseSystem(_ text: String) -> VoiceCommand?
}
```

### Updated HomeView dispatch (pseudo-code)

```swift
let outcome = classifier.classify(text)
switch outcome {

case .system(let cmd):
    // confirm / cancel — dispatched to the active confirmation coordinator.
    // If no countdown is pending, .cancel is a no-op; .confirm is a no-op.
    handleSystemCommand(cmd)
    transcriptController.clearAfterCommand()

case .broadcast(let cmd):
    HapticEngine.shared.commandRecognised()
    let result = await broadcastHandler.handle(cmd)
    showToast(result.totalCount == 0
        ? cs.broadcastNothingInScope
        : cs.broadcastExecuted(result.successCount, result.totalCount))
    transcriptController.clearAfterCommand()

case .personalised(let speaker, let parsed):
    HapticEngine.shared.commandRecognised()
    selectedSpeaker = speaker
    let cmd = commandRouter.toVoiceCommand(parsed)
    await dispatchWithConfirmationIfNeeded(command: cmd, to: speaker, commandText: text)

case .addressed(let speaker, let remainder):
    selectedSpeaker = speaker
    let cmd = await commandRouter.parse(remainder, speakerId: speaker.id.uuidString)
    if case .unknown = cmd { } else { HapticEngine.shared.commandRecognised() }
    await dispatchWithConfirmationIfNeeded(command: cmd, to: speaker, commandText: remainder)

case .focused(let speaker, let text):
    selectedSpeaker = speaker
    let cmd = await commandRouter.parse(text, speakerId: speaker.id.uuidString)
    if case .unknown = cmd { } else { HapticEngine.shared.commandRecognised() }
    await dispatchWithConfirmationIfNeeded(command: cmd, to: speaker, commandText: text)

case .unresolved:
    let available = discovery.groups.flatMap(\.members).map(\.name)
    handleError(.noSpeakerSpoken(available: available))
    transcriptController.clearAfterCommand()
}
```

### Internal classification order (locked)

The classifier evaluates the cases in this exact order. Earlier branches
short-circuit:

1. **`.system`** — `router.parseSystem(text)` returns `.confirm` / `.cancel`.
   No speaker-name search is done first; system commands win unconditionally.
2. **`.broadcast`** — `router.parseBroadcast(text)` returns a broadcast
   `VoiceCommand`. Runs before alias lookup so saved aliases cannot hide
   broadcast intent (e.g. a user who saved the phrase "stop alle" as an
   alias still gets broadcast behaviour).
3. **`.personalised`** — `personalisationStore.isEnabled` and
   `matchPersonalisedCommandAcrossAllSpeakers(phrase:)` returns a hit.
   The classifier looks up the speaker by `speakerId` in
   `discovery.groups.flatMap(\.members)`; if the speaker is no longer
   reachable (e.g. powered off), the classifier falls through to the
   next case.
4. **`.addressed`** — `discovery.resolve(words:)` (which wraps
   `SpeakerNameMatcher`) succeeds. Returns the matched speaker and the
   tokens that remain after stripping the name. If `remainder` is empty,
   the classifier still emits `.addressed` with the original text as
   `remainder` — `CommandParserRouter.parse` handles bare speaker names by
   returning `.unknown`.
5. **`.focused`** — none of the above; the `focusedSpeaker()` closure
   returns a non-nil `Speaker`. Classifier returns `.focused(speaker, text)`.
6. **`.unresolved`** — fall-through. HomeView surfaces `.noSpeakerSpoken`.

---

## Conflicts Flagged

**CONFLICT 1 — Workaround retention (PersonalisationStore)**

`PersonalisationStore.matchPersonalisedCommandAcrossAllSpeakers(phrase:)` was
introduced as a workaround. **Do not delete it.** It is the supported backing
implementation for the `.personalised` classification. The existing call site
in `HomeView` (lines 427–432) **must** be removed during T-4107 — keeping it
duplicates the lookup once classifier-driven dispatch is in place.

**CONFLICT 2 — `selectedSpeaker` state ownership**

The `.focused` fallback requires `UtteranceClassifier` to read
HomeView's `@State private var selectedSpeaker: Speaker?`. SwiftUI `@State`
cannot be passed by reference into a non-View struct. The classifier
therefore receives a `focusedSpeaker: @escaping () -> Speaker?` closure at
init. HomeView constructs the classifier inside its `init()` and captures
`{ [weak self] in self?.selectedSpeaker }` — but `HomeView` is a value type,
so the closure captures a `Binding`-like accessor instead. The simplest
working pattern is:

```swift
// HomeView body, before the transcript handler is wired:
let classifier = UtteranceClassifier(
    discovery: discovery,
    personalisationStore: personalisationStore,
    router: commandRouter,
    focusedSpeaker: { selectedSpeaker }   // captured by reference via @State's projected value
)
```

Because `selectedSpeaker` is `@State`, the closure must be re-created
inside `body` (or inside `startListening()`) where the current value is
visible. Storing the classifier in `@State` is acceptable as long as the
closure it holds is refreshed whenever `selectedSpeaker` changes — or,
preferably, the classifier is constructed lazily per transcript inside the
final-transcript handler (cheap; no allocations beyond the struct itself).

**Decision:** construct the classifier **per final transcript** inside
`handleFinalTranscript`. The struct is value-type and stateless beyond its
captured references; per-call allocation is negligible and avoids the
SwiftUI state-capture problem entirely.

**CONFLICT 3 — Focus tracking semantics**

This ADR adopts a minimal definition of "focused speaker": **the current
value of `HomeView.selectedSpeaker`**, which is already updated to the most
recently commanded speaker by every successful classification path.
A separate "last commanded speaker" field is **not** added — it would
duplicate `selectedSpeaker` semantics. If a future epic distinguishes
"selected via UI tap" from "selected via voice", the closure parameter is
the extension point.

**CONFLICT 4 — Epic numbering with telemetry backend**

A separate spec document numbers the telemetry backend epic at E-41 in its
own namespace. This ADR uses E-41 for the iOS pipeline epic. The two
namespaces do not collide — they live in different documents
(`iOS/docs/adr/` vs the backend specs) — but reviewers should be aware that
"E-41" disambiguates by document context. Tasks for this epic begin at
T-4101 to mirror the epic number; the backend epic uses the same range in
its own document. iOS work and backend work are tracked on separate boards.
