# Specification Additions: Multi-Room Grouping & Favorites-by-Number
## Bang & Olufsen Voice Controller

**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-01
**Extends:** `functional-spec-bo-voice-control.md` v1.2, `spec-command-parser-bo-voice-control.md` v1.0, `epics-and-tasks-bo-voice-control.md` v1.0

---

## Overview

The training corpus introduced three intents that are not yet covered by the functional spec:

- `playFavoriteByNumber` — start a favorite by its slot number rather than its name
- `joinSpeaker` — group the addressed speaker with another speaker for synchronised playback
- `leaveSpeaker` — remove the addressed speaker from a group

These intents are common B&O Mozart-supported behaviours and the corpus contains 1,500 labelled examples across them. This document defines the user stories, acceptance criteria, error states, and parser additions required to bring the v1 functional spec, design spec, and parser spec in line.

The intents are additive — none of them changes existing v1 behaviour.

---

## Functional Spec Additions

### New User Stories

#### US-09 — Play a favorite by its slot number

> As a user, I want to say a favorite's number after the speaker name so that I can start it without having to remember its name.

**Acceptance criteria:**

- Command formats: *"[Speaker name], play favorite [N]"*, *"[Speaker name], play favorite number [N]"*, *"[Speaker name], play number [N]"*
- `[N]` accepts integer values 1–10 in either digit form ("3") or word form ("three" / "tre")
- Before executing, the app reads back: *"Playing favorite [N]: [favorite name] on [speaker name]"* — the favorite name is resolved from the live favorites list at request time
- User must confirm before playback starts
- If the slot number is empty (no favorite assigned to that slot), the app responds: *"Favorite [N] is empty on [speaker name]"*
- If the spoken number is outside 1–10, the app responds: *"Favorite numbers go from 1 to 10. You said [N]"*

---

#### US-10 — Group the addressed speaker with another speaker

> As a user, I want to say a join command after the speaker name so that the addressed speaker plays in sync with another room.

**Acceptance criteria:**

- Command formats: *"[Speaker name], join [other speaker]"*, *"[Speaker name], group with [other speaker]"*, *"[Speaker name], play together with [other speaker]"*
- `[other speaker]` is matched against the same `SpeakerRegistry` used for the addressed speaker (case-insensitive, fuzzy match, Levenshtein distance ≤ 2)
- Before executing, the app reads back: *"Joining [addressed speaker] with [other speaker]"*
- User must confirm before the join is sent
- After confirmation, both speakers play the same content. The content source is whatever the **other speaker** is currently playing — joining always pulls the addressed speaker into the group, never the other way around
- If `[other speaker]` is not recognised, the app responds: *"[spoken name] was not found. Available speakers are: [list]"*
- If the other speaker is not currently playing, the app responds: *"[other speaker] is not currently playing anything to join"*
- If the addressed speaker is already grouped with the named other speaker, the app responds: *"[addressed speaker] is already grouped with [other speaker]"*
- If `[other speaker]` is omitted (e.g. *"Beosound, join the group"*), the app pulls the addressed speaker into whatever group is currently active. If no group is active, it responds: *"There is no active group to join. Say '[Speaker name], join [other speaker]' to start a group"*

---

#### US-11 — Remove the addressed speaker from its group

> As a user, I want to say a leave command after the speaker name so that the addressed speaker stops playing in sync with the others.

**Acceptance criteria:**

- Command formats: *"[Speaker name], leave the group"*, *"[Speaker name], disconnect"*, *"[Speaker name], play alone"*, *"[Speaker name], ungroup"*
- Before executing, the app reads back: *"Removing [speaker name] from the group"*
- User must confirm before the leave is sent
- After confirmation, the addressed speaker stops playing the group's content. The remaining speakers in the group continue playing as before
- If the addressed speaker is not currently in a group, the app responds: *"[speaker name] is not currently in a group"*

---

### Updated Voice Command Reference

Add these rows to the existing table in `functional-spec-bo-voice-control.md` §Voice Command Reference:

| Intent | Example Commands |
|---|---|
| Address speaker + play favorite by number | "Beosound, play favorite 3", "Beosound, play favorite number three" |
| Address speaker + join another speaker | "Beosound, join the kitchen", "Beosound, group with bedroom" |
| Address speaker + leave group | "Beosound, leave the group", "Beosound, play alone" |

---

### Updated Error States

Add these rows to the existing table in `functional-spec-bo-voice-control.md` §Error States:

| Scenario | Expected Behaviour |
|---|---|
| Favorite slot is empty | *"Favorite [N] is empty on [speaker name]"* |
| Favorite number out of range | *"Favorite numbers go from 1 to 10. You said [N]"* |
| Other speaker name not recognised on join | *"[spoken name] was not found. Available speakers are: [list]"* |
| Other speaker not playing on join | *"[other speaker] is not currently playing anything to join"* |
| Already grouped with named speaker | *"[addressed speaker] is already grouped with [other speaker]"* |
| Join issued without an active group | *"There is no active group to join. Say '[Speaker name], join [other speaker]' to start a group"* |
| Leave issued when not in a group | *"[speaker name] is not currently in a group"* |

---

## Parser Spec Additions

### Updated `CommandIntent` enum

Add three cases to `CommandIntent` in `spec-command-parser-bo-voice-control.md` §Shared Output Type:

```swift
@Generable
enum CommandIntent: String, CaseIterable {
    // ... existing cases ...
    case playFavoriteByNumber  // "[Speaker], play favorite 3"
    case joinSpeaker           // "[Speaker], join the kitchen"
    case leaveSpeaker          // "[Speaker], leave the group"
}
```

### Updated `ParsedCommand` struct

Add two slot fields:

```swift
@Generable
struct ParsedCommand {
    // ... existing fields ...
    let favoriteNumber: Int?     // 1–10 for playFavoriteByNumber
    let otherSpeakerName: String? // unresolved spoken name for joinSpeaker
}
```

The `otherSpeakerName` is unresolved at the parser stage — like `favoriteName`, it's resolved against `SpeakerRegistry` downstream. This keeps the parser's output language-agnostic and avoids coupling parsing to registry state.

### Updated Stage 1 regex patterns

Add to the table in `spec-command-parser-bo-voice-control.md` §Stage 1 — Deterministic Regex Parser:

| Intent | Pattern (Swift `Regex`) | Slots Extracted |
|---|---|---|
| `playFavoriteByNumber` | `\b(?:play\|start)\s+(?:favou?rite\s+(?:number\s+)?\|number\s+\|preset\s+)(\d{1,2})\b` | `favoriteNumber` = capture group 1 |
| `leaveSpeaker` | `\b(leave(?:\s+the)?\s+group\|disconnect\|ungroup\|play\s+alone\|forlad\s+gruppen\|frakobl\|spil\s+alene)\b` | — |
| `joinSpeaker` (no other speaker named) | `\b(join\s+the\s+group\|join\s+the\s+others\|tilslut\s+gruppen\|join\s+gruppen)\b` | — |

For `joinSpeaker` **with** an explicit other speaker name, Stage 1 is not reliable — the room name varies too widely. Stage 2 (NLModel) handles this case, and `otherSpeakerName` is extracted by trailing-phrase heuristic: `(?:join|group with|sync with|connect to|tilslut|forbind med|grupper med)\s+(?:the\s+)?(.+)$`.

### Updated Foundation Models system instructions

Append to the instruction template in `spec-command-parser-bo-voice-control.md` §Session Configuration:

```
- For playFavoriteByNumber, extract the integer favoriteNumber (1–10).
  Accept both digit and word forms in English and Danish.
- For joinSpeaker with a named other speaker ("join the kitchen"),
  set otherSpeakerName to the spoken name verbatim. The downstream
  SpeakerRegistry will resolve it against the available speakers.
- For joinSpeaker without a named other speaker ("join the group"),
  set intent to joinSpeaker with otherSpeakerName nil — this is the
  "join the active group" case.
- For leaveSpeaker, no slots are required.
```

---

## Epics & Tasks Additions

The following tasks should be added to `epics-and-tasks-bo-voice-control.md`. Two existing epics are extended (E-02 Mozart API, E-03 Voice Recognition); two new epics are added.

### E-02 additions — Mozart API endpoints for grouping

- [ ] **T-0216** Implement `POST /speakers/{id}/play-favorite/{number}` — trigger playback of the favorite at the given slot number on the addressed speaker
- [ ] **T-0217** Implement `GET /speakers/{id}/favorite/{number}` — read the favorite metadata for the given slot (used to resolve the favorite name for confirmation read-back)
- [ ] **T-0218** Implement `POST /speakers/{id}/join` with body `{ "otherSpeakerId": "..." }` — group the addressed speaker with another speaker
- [ ] **T-0219** Implement `POST /speakers/{id}/leave` — remove the addressed speaker from its current group
- [ ] **T-0220** Implement `GET /speakers/{id}/group-status` — fetch current group membership (used to detect "already grouped" and "not in a group" error states)

### E-03 additions — Parser

- [ ] **T-0313** Add `playFavoriteByNumber`, `joinSpeaker`, `leaveSpeaker` to `CommandIntent`
- [ ] **T-0314** Extend `TwoStageFallbackParser` Stage 1 regex table with the three new patterns from the parser spec additions
- [ ] **T-0315** Extend `FoundationModelParser` system instructions with the three new intent rules
- [ ] **T-0316** Add unit tests covering favorite-number parsing in both digit and word form, both languages

### E-15 — Playback by Favorite Number (new epic)

Implements US-09 end to end.

- [ ] **T-1501** Build `PlayFavoriteByNumberUseCase` — receives `(speaker, favoriteNumber)`; calls `MozartAPIClient.fetchFavorite(number:on:)` to resolve the favorite name; builds confirmation string *"Playing favorite [N]: [favorite name] on [speaker name]"*; on confirm calls `MozartAPIClient.playFavoriteByNumber(number:on:)`
- [ ] **T-1502** Implement "favorite slot empty" path — if the API returns no favorite for that slot, speak *"Favorite [N] is empty on [speaker name]"* without showing the confirmation sheet
- [ ] **T-1503** Implement "out of range" path — if `favoriteNumber` is outside 1–10, speak *"Favorite numbers go from 1 to 10. You said [N]"*
- [ ] **T-1504** Write unit tests covering: valid number with assigned favorite, valid number with empty slot, out-of-range number, both digit and word input forms

### E-16 — Multi-Room Grouping (new epic)

Implements US-10 and US-11 end to end.

- [ ] **T-1601** Build `JoinSpeakerUseCase` — receives `(addressedSpeaker, otherSpeakerName)`; resolves `otherSpeakerName` via `SpeakerNameMatcher` against `SpeakerRegistry`; builds confirmation string *"Joining [addressed speaker] with [other speaker]"*; on confirm calls `MozartAPIClient.join(speaker:withOther:)`
- [ ] **T-1602** Implement "other speaker not found" path — surface `AppError.speakerNotFound` with the spoken name and available speaker list
- [ ] **T-1603** Implement "other speaker not playing" path — call `MozartAPIClient.getGroupStatus(speaker:)` for the other speaker; if not playing, speak *"[other speaker] is not currently playing anything to join"*
- [ ] **T-1604** Implement "already grouped" idempotent path — check current group membership before issuing the join; if already grouped with the named speaker, speak *"[addressed speaker] is already grouped with [other speaker]"* without confirmation
- [ ] **T-1605** Implement "no active group" path for unspecified-other-speaker case — if `otherSpeakerName` is nil and no group is active anywhere on the network, speak *"There is no active group to join..."*
- [ ] **T-1606** Build `LeaveSpeakerUseCase` — receives `(addressedSpeaker)`; checks group membership via `MozartAPIClient.getGroupStatus(speaker:)`; if not in a group, speaks *"[speaker name] is not currently in a group"*; otherwise builds confirmation *"Removing [speaker name] from the group"* and on confirm calls `MozartAPIClient.leave(speaker:)`
- [ ] **T-1607** Add `AppError.favoriteSlotEmpty(Int)`, `.favoriteNumberOutOfRange(Int)`, `.otherSpeakerNotPlaying(String)`, `.alreadyGrouped(String, String)`, `.noActiveGroup`, `.notInGroup(String)` to the `AppError` enum (E-09)
- [ ] **T-1608** Update `ErrorResponseService` (T-0902) with spoken/display strings for all six new error cases
- [ ] **T-1609** Write unit tests for both use cases covering the full matrix of paths

---

## Design Spec Notes

The new intents do not require new screens. They reuse the existing surfaces:

- **Confirmation sheet**: the new read-back strings (*"Playing favorite 3: Jazz Radio on Beosound"*, *"Joining Beosound with the kitchen"*, *"Removing Beosound from the group"*) fit the existing 22 pt SF Pro Display action read-back pattern. No layout change needed.
- **Error toast**: the seven new error strings use the existing toast template. The "speaker list" expansion variant (already specified for `speakerNotFound`) is reused for the join error case.
- **Now Playing state**: the speaker card subtitle should reflect group membership when the speaker is in a group. Suggestion: append *" — grouped with [other speaker]"* to the subtitle. This is a minor design spec extension and should be confirmed before implementation.

---

## Open Questions

1. **Owner of group state** — Mozart API may expose group status from any speaker in the group, or only from a designated leader. The `getGroupStatus` design assumes any speaker can report the group it belongs to. Verify against Mozart API docs before T-0220.
2. **Group leader semantics** — when speaker A joins speaker B, who controls subsequent playback commands ("Beosound, pause" — does it pause just Beosound or the whole group)? Default assumption: a command addressed to one speaker affects only that speaker's contribution to the group, but Mozart API behaviour should be confirmed.
3. **Favorite slot count** — the spec assumes 1–10. B&O speakers expose the slot count via Mozart API; we should read the actual maximum at runtime rather than hard-coding 10. Defer to implementation.
4. **`leaveSpeaker` ambiguity** — *"Beosound, leave"* is short enough to be confused with stop or cancel by ASR. The corpus mitigates this through training, but worth a confirmation-sheet test case during QA.

---

## Resolved Decisions

| Question | Decision |
|---|---|
| Should favorite-by-number be a separate intent or a slot variant of `playNamed`? | Separate intent — keeps Stage 1 regex deterministic and avoids ambiguity between named and numbered favorites |
| Should join always make the addressed speaker follow the other speaker, or vice versa? | Addressed speaker follows the other — matches the natural language ("Beosound, join the kitchen" = Beosound joins what's playing in the kitchen) |
| Should `leaveSpeaker` require a group name? | No — the addressed speaker can only be in one group at a time, so the target is unambiguous |
| Should grouping commands respect the same confirmation-before-execution rule as v1 commands? | Yes — no exemption. State changes always confirm first |
