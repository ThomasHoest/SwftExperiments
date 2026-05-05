# ADR E-37 — Broadcast Command Parsing and Execution

**Status:** Accepted
**Date:** 2026-05-05
**Epic:** E-37 (Voxio 1.3, Feature 2)

---

## Decision

Broadcast `VoiceCommand` and `CommandIntent` cases are added inline to the existing enums. Broadcast Stage 1 regex patterns are prepended to `TwoStageFallbackParser.parseStage1()` before all single-speaker patterns. Execution is handled by a new free-standing `BroadcastCommandHandler` struct (not by extending `HomeView.dispatch()`) so that the parallel fan-out logic stays testable in isolation. `HomeView.startListening()` is extended with a pre-dispatch intercept that detects broadcast commands and routes them to `BroadcastCommandHandler` before the single-speaker path runs.

---

## Context

- The v1.2 voice pipeline is the canonical dependency: `CommandParserRouter` → `TwoStageFallbackParser` (Stage 1 regex → Stage 2 NLModel) → `toVoiceCommand()` → `HomeView.dispatch()`.
- `CommandParserRouter.parse()` runs Stage 1 first on all devices. A Stage 1 hit short-circuits Foundation Models and NLModel entirely.
- `HomeView` is `@MainActor`; all API calls on `Speaker` are `async throws`.
- `SpeakerDiscoveryService.groups` is the authoritative discovered speaker list.
- `Toast` / `ToastView` / `showToast()` are already wired in `HomeView`.
- Broadcast commands execute immediately — no countdown confirmation (resolved decision in spec).
- T-3708 (corpus training + `.mlmodelc` rebundle) is a **manual training step** — out of scope for automated implementation.

---

## Options Considered

**Option A — Extend `HomeView.dispatch()` directly**

- Pro: minimal new files.
- Con: `dispatch()` takes a single `Speaker`; semantically wrong for broadcast. Fan-out + `TaskGroup` inside a view function is untestable without a live `HomeView`. Rejected.

**Option B — New `BroadcastCommandHandler` struct (chosen)**

A new `@MainActor` struct holds a reference to `SpeakerDiscoveryService`. It exposes `handle(_ command: VoiceCommand) async -> BroadcastResult`. `HomeView` intercepts broadcast commands before the single-speaker path.

- Pro: fully unit-testable; `HomeView` stays thin; speaker-scope filtering is co-located with execution.
- Con: one additional file; `HomeView` must check for broadcast cases.

---

## Rationale

The broadcast intercept must happen before the single-speaker `dispatch()` path because broadcast commands intentionally ignore the resolved `speaker` argument. Keeping fan-out logic in a dedicated struct makes T-3709 unit tests straightforward — the struct can be tested with a stub list of speakers without any view machinery.

---

## Consequences

- `VoiceCommand`, `CommandIntent`, and `CommandStrings` gain new cases — all callers with exhaustive `switch` statements must be updated (compiler will flag omissions).
- The `NLModel` will not recognise broadcast intents until T-3708 is completed manually. Until then, utterances that miss Stage 1 return `.unknown` — acceptable because Stage 1 covers all specified broadcast trigger phrases.
- Partial failures in the fan-out are tolerated and logged; the toast reflects the success count.

---

## File-Level Plan

### New files

| Path | Purpose |
|---|---|
| `iOS/Voxio/Core/CommandParsing/BroadcastCommandHandler.swift` | T-3705/T-3706 — parallel execution, speaker filtering, returns `BroadcastResult` |

### Modified files

| Path | Tasks |
|---|---|
| `iOS/Voxio/Core/Models/VoiceCommand.swift` | T-3701 — add 6 broadcast cases + `CustomStringConvertible` arms |
| `iOS/Voxio/Core/CommandParsing/ParsedCommand.swift` | T-3702 — add 7 broadcast `CommandIntent` cases + `description` arms |
| `iOS/Voxio/Core/CommandParsing/TwoStageFallbackParser.swift` | T-3703 — prepend broadcast regex blocks before existing single-speaker checks |
| `iOS/Voxio/Core/CommandParsing/CommandParserRouter.swift` | T-3704 — add broadcast arms to `toVoiceCommand()` |
| `iOS/Voxio/Features/Home/HomeView.swift` | T-3705/T-3707 — broadcast intercept guard; call `BroadcastCommandHandler.handle()`; show result toast |
| `iOS/Voxio/Core/Strings/CommandStrings.swift` | T-3707 — add broadcast toast strings (EN + DA) |

---

## Public Interface Contract

### New `VoiceCommand` cases

```swift
case stopAll
case pauseAll
case resumeAll
case adjustVolumeAll(Int)   // positive = up, negative = down; default ±10
case muteAll
case unmuteAll
```

### New `CommandIntent` cases

```swift
case stopAll
case pauseAll
case resumeAll
case volumeUpAll
case volumeDownAll
case muteAll
case unmuteAll
```

### `BroadcastCommandHandler`

```swift
struct BroadcastResult {
    let successCount: Int
    let totalCount: Int
    let intent: VoiceCommand
}

@MainActor
struct BroadcastCommandHandler {
    let discovery: SpeakerDiscoveryService
    func handle(_ command: VoiceCommand) async -> BroadcastResult
}
```

`handle()` uses `withTaskGroup(of: Bool.self)` for parallel fan-out. Speaker scope:
- `.stopAll` / `.pauseAll` → speakers where `playbackState == .playing`
- `.resumeAll` → speakers where `playbackState == .paused`
- `.adjustVolumeAll` / `.muteAll` / `.unmuteAll` → all discovered speakers

### HomeView intercept

```swift
// After `let command = await commandRouter.parse(...)`
if isBroadcast(command) {
    let result = await broadcastHandler.handle(command)
    showToast(broadcastToast(result, cs))
    transcriptController.clearAfterCommand()
    return
}
// existing single-speaker path continues unchanged
```

---

## Conflicts Flagged

1. **T-3708 is a manual training step.** The Implementer must append EN+DA broadcast trigger phrases to `corpus-training.csv`, retrain `VoxioCommandModel`, and replace the bundled `.mlmodelc`. Until complete, Stage 2 returns `.unknown` for unmatched broadcast utterances — safe because Stage 1 covers all specified phrases.

2. **`CommandParserRouter.toVoiceCommand()` switch becomes non-exhaustive.** All seven new `CommandIntent` cases must be mapped; `volumeUpAll` → `.adjustVolumeAll(+(parsed.volumeDelta ?? 10))`, `volumeDownAll` → `.adjustVolumeAll(-(parsed.volumeDelta ?? 10))`.

3. **`HomeView.confirmationMessage()` and `preflightError()` switches must add broadcast arms** — return `nil` for all six broadcast `VoiceCommand` values (no countdown, no preflight per spec).

4. **Speaker list access:** use `discovery.groups.flatMap(\.members)` — not a `.speakers` property.
