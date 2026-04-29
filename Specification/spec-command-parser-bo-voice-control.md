# Technical Specification: Robust Command Parsing
## Bang & Olufsen Voice Controller

**Version:** 1.0  
**Status:** Draft  
**Date:** 2026-04-28  
**References:** functional-spec-bo-voice-control v1.2, epics-and-tasks-bo-voice-control v1.0

---

## Overview

This specification replaces the `CommandParser` design proposed in E-03 (tasks T-0305 through T-0311) of the epics-and-tasks document. It addresses the inherent fragility of the original Levenshtein-distance rule-based approach and defines a more robust two-path architecture: a Foundation Models-powered semantic parser for Apple Intelligence-capable devices, with a deterministic + probabilistic fallback for older hardware.

---

## Problem Statement

The original `CommandParser` design (T-0305–T-0311) relies on:

- Stripping the leading speaker name token from the raw transcription
- Matching the remainder against a fixed set of known phrase patterns
- Using Levenshtein distance ≤ 2 as a fuzzy-match tolerance

This approach fails in practice across several predictable failure modes:

| Failure Mode | Example | Why It Breaks |
|---|---|---|
| Numeric vs. word form | "volume up twenty" vs. "volume up 20" | Edit distance >> 2 despite identical meaning |
| ASR filler words | "uh Beosound play the jazz radio" | Filler shifts token positions; prefix strip breaks |
| Word reordering | "play on Beosound Jazz Radio" | Pattern match expects fixed word order |
| Natural variation | "can you stop" vs. "stop" | Out-of-vocabulary phrasing returns `.unknown` |
| Slot + intent conflation | "set volume to forty-two" | Edit distance can't simultaneously match intent and extract the value `42` |
| Scale | 11 intents × real-world phrasing variation | Enumerable pattern lists cannot cover the surface form space |

Additionally, `SFSpeechRecognizer` produces raw transcription output that frequently includes inconsistent capitalisation, dropped articles, and partial words mid-utterance — none of which the original design accounts for.

---

## Design Goals

1. Handle natural language variation without maintaining an enumerated phrase list
2. Separate intent classification from slot extraction cleanly
3. Work on every device in the supported range (iOS 25+)
4. Respect the privacy requirement: no audio or transcription data leaves the device
5. Meet the 3-second end-to-end latency budget defined in the functional spec
6. Remain testable without requiring Apple Intelligence hardware

---

## Architecture

The revised `CommandParser` is replaced by a three-component system: a `SpeakerNameMatcher` (unchanged from the original spec), a `CommandParserRouter` that selects the appropriate parsing strategy based on device capability, and two concrete parser implementations.

```
SFSpeechRecognizer (ASR)
        │
        ▼ raw transcription string
┌───────────────────┐
│ SpeakerNameMatcher│  ← fast prefix scan; unchanged from E-04
└───────────────────┘
        │
        ├─ no match → .noSpeakerSpoken error; stop pipeline
        │
        ▼ (speaker resolved, remainder string isolated)
┌──────────────────────┐
│ CommandParserRouter  │  ← checks SystemLanguageModel.availability
└──────────────────────┘
        │                          │
        │ Apple Intelligence        │ Fallback
        │ available                 │ (older device / AI disabled)
        ▼                          ▼
┌─────────────────────┐   ┌────────────────────────┐
│ FoundationModel     │   │ TwoStageFallbackParser  │
│ Parser              │   │                        │
│                     │   │  Stage 1: Regex         │
│ LanguageModelSession│   │  (deterministic)        │
│ @Generable output   │   │                        │
│                     │   │  Stage 2: NLModel       │
│                     │   │  (probabilistic)        │
└─────────────────────┘   └────────────────────────┘
        │                          │
        └──────────┬───────────────┘
                   ▼
            ParsedCommand
         (intent + slots, typed)
```

---

## Shared Output Type

All parsers produce a single `ParsedCommand` value. This is the only type that the rest of the application (use cases, confirmation coordinator, error handler) depends on.

```swift
@Generable
struct ParsedCommand {
    let intent: CommandIntent
    let speakerID: String?        // resolved speaker ID from SpeakerRegistry
    let speakerName: String?      // display name for confirmation strings
    let favoriteName: String?     // spoken favorite name, unresolved
    let volumeValue: Int?         // absolute target, 0–100
    let volumeDelta: Int?         // relative adjustment, signed; nil = use default step
    let volumeDirection: VolumeDirection?
}

@Generable
enum CommandIntent: String, CaseIterable {
    case playNamed        // "[Speaker], play Jazz Radio"
    case playDefault      // "[Speaker], play music"
    case listFavorites    // "[Speaker], what are my favorites?"
    case stop
    case pause
    case resume
    case setVolume        // "[Speaker], set volume to 50"
    case volumeUp         // "[Speaker], volume up [amount]" / "louder"
    case volumeDown       // "[Speaker], volume down [amount]" / "quieter"
    case mute
    case unmute
    case confirm          // "Yes"
    case cancel           // "No" / "Cancel"
    case unknown          // no match; raw string preserved for error feedback
}

@Generable
enum VolumeDirection: String {
    case up, down
}
```

`@Generable` conformance is required for the Foundation Models path. The `TwoStageFallbackParser` produces the same type directly, bypassing the LLM.

---

## Path A: FoundationModelParser

### When It Is Used

`CommandParserRouter` selects this path when `SystemLanguageModel.availability == .available`. This implies the device supports Apple Intelligence (A17 Pro or M1 chip minimum) and the user has Apple Intelligence enabled.

### Session Configuration

A single `LanguageModelSession` is created and held by the parser. Its system instructions are set once at initialisation and updated whenever the addressed speaker changes (i.e., when the active speaker's favorites list changes).

```swift
LanguageModelSession(instructions: """
    You are a command parser for a Bang & Olufsen speaker voice control app.
    Your only job is to extract a structured command from a spoken utterance.
    Do not answer questions. Do not generate explanations.

    Available speakers: \(speakerNames.joined(separator: ", "))
    Addressed speaker: \(activeSpeakerName)
    Favorites on \(activeSpeakerName): \(favoriteNames.joined(separator: ", "))

    Rules:
    - If the utterance contains no recognised speaker name, set intent to unknown.
    - For playNamed, set favoriteName to the closest match from the favorites list
      above, preserving the user's spoken form in case of no match.
    - For setVolume, volumeUp, volumeDown: extract the integer value if spoken.
      If no value is given for up/down, leave volumeDelta nil (default step applies).
    - "Yes", "yeah", "correct", "do it" → confirm.
    - "No", "cancel", "stop that", "never mind" → cancel.
""")
```

### Invocation

```swift
let result = try await session.respond(
    to: remainderTranscription,  // transcription with speaker token already stripped
    generating: ParsedCommand.self
)
return result.content
```

### Latency Management

- The session is pre-warmed on app launch, immediately after `GET /speakers` completes (aligns with T-0401). The first `respond` call after launch benefits from a loaded model.
- Session instructions are updated (not recreated) when the active speaker changes; this is cheaper than creating a new session.
- The 4,096-token context window is sufficient for this use case: system instructions + a favorites list of up to ~50 items + one user utterance comfortably fit within the limit. If a speaker has an unusually large favorites list, truncate to the 40 most recently played items.

### Privacy

All inference runs on-device. No transcription text, speaker names, or favorite names are transmitted to any external service. This satisfies the functional spec's privacy requirement without additional measures.

---

## Path B: TwoStageFallbackParser

Used when Foundation Models are unavailable. Implements a deterministic-first, probabilistic-second pipeline — the industry standard pattern for on-device NLU.

### Stage 1 — Deterministic Regex Parser

Handles high-confidence, structurally unambiguous commands. If a pattern matches, a `ParsedCommand` is returned immediately without proceeding to Stage 2.

Patterns operate on the post-speaker-strip remainder string, lowercased, with leading/trailing whitespace removed.

| Intent | Pattern (Swift `Regex`) | Slots Extracted |
|---|---|---|
| `stop` | `\b(stop\|stop music\|stop playing)\b` | — |
| `pause` | `\bpause\b` | — |
| `resume` | `\b(resume\|continue playing\|unpause)\b` | — |
| `mute` | `\bmute\b` | — |
| `unmute` | `\bunmute\b` | — |
| `setVolume` | `\b(set volume to\|volume)\s+(\d{1,3})\b` | `volumeValue` = capture group 2 |
| `volumeUp` (with amount) | `\b(volume up\|louder by)\s+(\d{1,3})\b` | `volumeDelta` = capture group 2 |
| `volumeDown` (with amount) | `\b(volume down\|quieter by)\s+(\d{1,3})\b` | `volumeDelta` = capture group 2, negated |
| `volumeUp` (default step) | `\b(volume up\|louder)\b` | `volumeDelta` = nil |
| `volumeDown` (default step) | `\b(volume down\|quieter)\b` | `volumeDelta` = nil |
| `listFavorites` | `\b(what are my favorites?\|list favorites?\|show favorites?)\b` | — |
| `confirm` | `^(yes\|yeah\|correct\|do it\|confirm)$` | — |
| `cancel` | `^(no\|cancel\|stop that\|never mind\|nope)$` | — |

Volume values are clamped to 0–100 at parse time; out-of-range values produce a `ParsedCommand` with `intent = .unknown` so the error handler can surface a clear message.

### Stage 2 — Probabilistic NLModel Classifier

Used when Stage 1 finds no match — primarily for play commands and less-structured utterances.

- Model type: `NLModel` (Apple's `NaturalLanguage` framework), text classification
- Training data: ~200 labelled examples per intent, covering common phrasings, ASR noise variants, and partial sentences
- Intents classified: `playNamed`, `playDefault`, `listFavorites`, `stop`, `pause`, `resume`, `volumeUp`, `volumeDown`, `mute`, `unmute`, `unknown`
- Slot extraction after classification:
    - `playNamed`: extract the spoken favorite name using a trailing-phrase heuristic (`play\s+(.+)$`), then pass to `FavoritesService` for fuzzy resolution against the live favorites list
    - `volumeUp` / `volumeDown`: attempt secondary regex for numeric amount; if absent, `volumeDelta` is nil
- Confidence threshold: if the classifier's top prediction scores below 0.65, return `intent = .unknown`

### Training and Maintenance

- Training corpus lives in `Resources/CommandClassifier/TrainingData.json`; format is `[{ "text": "...", "label": "playNamed" }, ...]`
- Model is compiled to a `.mlmodel` and bundled with the app; it does not update at runtime
- When new command variants are discovered through testing, add examples to the training corpus and rebuild the model
- CI pipeline runs a classification accuracy check against a held-out validation set on every build; build fails if accuracy drops below 85%

---

## SpeakerNameMatcher (Unchanged)

The first step in the pipeline remains as specified in E-04. It operates on the full raw transcription before any intent parsing. It is the same for both parser paths.

- Case-insensitive prefix scan against all speaker names from `SpeakerRegistry`
- Levenshtein distance ≤ 2 on the first 1–3 tokens
- Returns `(speaker: Speaker, remainderString: String)` or `nil`
- On `nil`: surface `.noSpeakerSpoken` error; do not invoke either parser

The Levenshtein-distance tolerance is appropriate here because speaker names are a small, known, closed set (typically 1–5 names). The failure modes that apply to open-ended intent matching do not apply to this bounded lookup.

---

## CommandParserRouter

```swift
final class CommandParserRouter {

    private let foundationModelParser: FoundationModelParser?
    private let fallbackParser: TwoStageFallbackParser

    init(speakerRegistry: SpeakerRegistry) {
        self.fallbackParser = TwoStageFallbackParser()
        if SystemLanguageModel.availability == .available {
            self.foundationModelParser = FoundationModelParser(
                speakerRegistry: speakerRegistry
            )
        } else {
            self.foundationModelParser = nil
        }
    }

    func parse(_ remainder: String, addressedSpeaker: Speaker) async throws -> ParsedCommand {
        if let fmp = foundationModelParser {
            return try await fmp.parse(remainder, speaker: addressedSpeaker)
        }
        return try fallbackParser.parse(remainder, speaker: addressedSpeaker)
    }
}
```

The router does not retry across paths on failure. If `FoundationModelParser` throws (e.g. context overflow, model unavailable mid-session), the error propagates to the call site, which surfaces a `.voiceNotRecognised` error to the user. This is preferable to a silent fallback that might produce a misclassified command.

---

## Revised Task List (Replaces T-0305–T-0311)

The following tasks replace the original T-0305 through T-0311 block in E-03.

---

### T-0305a — Define ParsedCommand and CommandIntent types

Define the `ParsedCommand` `@Generable` struct and `CommandIntent` / `VolumeDirection` enums as specified above. Both types must conform to `Generable`, `Codable`, and `Equatable`. Place in `Core/CommandParsing/ParsedCommand.swift`.

**Acceptance criteria:**
- `@Generable` macro compiles without warnings on Xcode 26
- All intent cases from the functional spec are present
- `ParsedCommand` is `Equatable` to support unit test assertions

---

### T-0305b — Build FoundationModelParser

Implement `FoundationModelParser` as described in Path A above.

**Acceptance criteria:**
- Session is initialised with the system instructions template; speaker name and favorites list are injected at init and updated via `updateContext(speaker:favorites:)`
- `parse(_:speaker:)` calls `session.respond(generating: ParsedCommand.self)` and returns the result
- Returns `ParsedCommand(intent: .unknown, ...)` rather than throwing when the model produces a low-confidence or malformed output
- Pre-warm method `warmUp()` triggers a no-op prompt to load the model into memory; called from the app launch sequence after speaker list loads

---

### T-0305c — Build TwoStageFallbackParser

Implement `TwoStageFallbackParser` as described in Path B above.

**Acceptance criteria:**
- Stage 1 regex patterns cover all intents listed in the Stage 1 table; patterns compile with Swift `Regex` literal syntax
- Volume values parsed from regex are clamped 0–100 at parse time
- Stage 2 uses `NLModel` loaded from the bundled `.mlmodel`; confidence threshold of 0.65 enforced
- If both stages fail or confidence is below threshold, returns `ParsedCommand(intent: .unknown, rawText: remainder)`
- No network calls; runs entirely on-device

---

### T-0305d — Build CommandParserRouter

Implement `CommandParserRouter` as specified above.

**Acceptance criteria:**
- `SystemLanguageModel.availability` is checked at init; `FoundationModelParser` is only instantiated when available
- `parse(_:addressedSpeaker:)` delegates to the appropriate parser
- Does not catch and re-route errors from `FoundationModelParser`; errors propagate to the call site

---

### T-0305e — Integrate SpeakerNameMatcher as pipeline entry point

Wire `SpeakerNameMatcher` (E-04, T-0402) as the mandatory first step before `CommandParserRouter`. Neither parser is invoked if `SpeakerNameMatcher` returns `nil`.

**Acceptance criteria:**
- `VoiceInputManager` passes raw transcription to `SpeakerNameMatcher` first
- On `nil` result, `ErrorResponseService.handle(.noSpeakerSpoken)` is called; neither parser is invoked
- On successful match, `remainder` string and resolved `Speaker` are passed to `CommandParserRouter.parse(_:addressedSpeaker:)`

---

### T-0305f — Train and bundle NLModel classifier

Create the training corpus, train the `NLModel`, and bundle the compiled `.mlmodel` with the app.

**Acceptance criteria:**
- Training corpus contains ≥ 200 examples per intent in `Resources/CommandClassifier/TrainingData.json`
- Corpus covers: canonical phrasings, word-order variants, ASR noise forms (missing articles, filler words), numeric vs. word-form numbers
- Compiled model achieves ≥ 85% accuracy on the held-out validation split
- Model is checked into the repository as a compiled `.mlmodel`; source corpus JSON is also versioned

---

### T-0305g — Add classifier accuracy gate to CI pipeline

Add a build step that loads the `NLModel` and runs inference against the validation set, failing the build if accuracy drops below 85%.

**Acceptance criteria:**
- CI step runs on every pull request that modifies `TrainingData.json` or the `.mlmodel` file
- Build output includes a per-intent accuracy breakdown
- Failing accuracy threshold causes a non-zero exit code and blocks merge

---

### T-0305h — Unit tests for TwoStageFallbackParser

Write unit tests covering all Stage 1 patterns and Stage 2 classification. These tests run without Apple Intelligence hardware.

**Acceptance criteria:**
- Every Stage 1 regex pattern has at least one positive test (correct match + slot extraction) and one negative test (should not match)
- Volume boundary values tested: 0, 1, 99, 100, and an out-of-range value (e.g. 150)
- Stage 2 tests cover one canonical example per intent class
- Confirm and cancel variants ("yeah", "never mind") tested explicitly
- All tests pass on the CI simulator target (no Apple Intelligence required)

---

### T-0305i — Integration tests for FoundationModelParser

Write integration tests that exercise `FoundationModelParser` on a device or simulator with Apple Intelligence enabled.

**Acceptance criteria:**
- Tests are gated behind `SystemLanguageModel.availability == .available`; they are skipped gracefully on unsupported hardware
- Cover: playNamed with exact favorite name, playNamed with paraphrased name, volumeUp with spoken number, stop, confirm, unknown utterance
- Assert that `ParsedCommand.intent` matches the expected value for each case
- Assert that slot values (favoriteName, volumeValue, volumeDelta) are extracted correctly where applicable

---

### T-0305j — Verify voice recognition pauses during AVSpeechSynthesizer output

Ensure the parsing pipeline is not triggered by the app's own spoken confirmations.

**Acceptance criteria:**
- `VoiceInputManager` suspends the `SFSpeechAudioBufferRecognitionRequest` while `AVSpeechSynthesizer.isSpeaking == true`
- Recognition resumes within 200 ms of `AVSpeechSynthesizer` finishing
- No self-triggered parse events occur in the test harness when the confirmation string is read back

---

## Context Window Budget (FoundationModelParser)

The Foundation Models on-device model has a 4,096-token context window covering input and output combined. The table below estimates token usage for a typical session turn.

| Component | Estimated Tokens |
|---|---|
| System instructions (template) | ~180 |
| Speaker name list (5 speakers avg.) | ~25 |
| Addressed speaker name | ~10 |
| Favorites list (20 items avg.) | ~120 |
| User utterance (one command) | ~20 |
| Generated ParsedCommand (JSON) | ~60 |
| **Total** | **~415** |

This leaves substantial headroom. Even with 50 favorites, the budget remains well within the limit. If a speaker's favorites list exceeds 40 items, truncate to the 40 most recently played, ordered by last-played timestamp.

---

## Dependency Map

| Component | Depends On |
|---|---|
| `FoundationModelParser` | `FoundationModels` framework (iOS 26+), `SpeakerRegistry`, `FavoritesService` |
| `TwoStageFallbackParser` | `NaturalLanguage` framework, bundled `.mlmodel`, `FavoritesService` |
| `CommandParserRouter` | `FoundationModelParser` (optional), `TwoStageFallbackParser` |
| `SpeakerNameMatcher` | `SpeakerRegistry` |
| `VoiceInputManager` | `SpeakerNameMatcher`, `CommandParserRouter` |

---

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Foundation Models cold-start latency exceeds 3 s budget | Medium | Pre-warm session on app launch (T-0305b); first user command is never the first model call |
| On-device model misclassifies ambiguous commands | Low–Medium | Confirmation step before every action catches misclassification before it causes an effect |
| NLModel accuracy degrades as command vocabulary grows | Low | CI accuracy gate (T-0305g) catches regressions; corpus is versioned and can be extended |
| User's device does not support Apple Intelligence | Medium | `TwoStageFallbackParser` covers all supported devices down to iOS 25 |
| Favorites list grows large enough to exceed context budget | Low | Truncation to 40 most-recently-played items; documented limit |

---

## Out of Scope

- Multi-turn conversational context (each command is a single independent utterance)
- Language support beyond English (deferred to v2 per functional spec)
- Fine-tuning or adapter training on the Foundation Models on-device model (not supported by the framework)
- Cloud-based NLU services (excluded by the privacy requirement)
