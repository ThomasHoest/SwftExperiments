# Functional Specification: Voice Model Improvement
## Bang & Olufsen Voice Controller

**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-02
**Extends:** `functional-spec-bo-voice-control.md` v1.2, `spec-command-parser-bo-voice-control.md` v1.0

---

## Overview

The v1 command parser ships with a fixed model — the bundled `NLModel` and the Foundation Models system instructions don't change after release. This means the app cannot improve as users find phrasings the corpus didn't anticipate, and it cannot adapt to individual users' habits.

This specification defines two complementary flows that address this:

- **Flow A — Telemetry & Retraining.** Anonymised parse outcomes are collected on-device and, with explicit user consent, shipped to a backend for use in the next training round. Users see improvement on each app release.
- **Flow B — On-Device Personalisation.** The app learns and remembers per-user phrases — both explicit aliases the user creates and implicit patterns from confirmed commands. Users see improvement immediately, on their device, with no data leaving it.

The two flows are independent. A user can opt out of Flow A entirely and still benefit from Flow B. Flow B requires no backend and ships first.

---

## Technical Context

| Decision | Choice |
|---|---|
| Flow B storage | Local only — Core Data or SQLite, scoped to the app |
| Flow B sync | None in v1 — personalisation is per-device |
| Flow A storage | Local buffer first, backend upload on user opt-in |
| Flow A transport | HTTPS, batch upload, Wi-Fi only |
| Flow A consent | Off by default; explicit settings toggle required |
| Flow A audio | Never collected — transcription strings only |
| Model update mechanism | New `.mlmodel` bundled with app releases |

---

## Goals

- Let the parser improve over time without users having to adjust their phrasing to match what the model expects
- Respect the v1 privacy guarantee: voice audio is never stored or transmitted
- Give users immediate, visible benefit through Flow B before any telemetry-driven improvement is available
- Provide a clear, granular consent model — Flow A is opt-in, off by default, and can be disabled at any time
- Keep the v1 user experience unchanged when both flows are disabled

---

## Out of Scope (v1 of this spec)

- Cross-device sync of personalisation data (deferred — would require account system)
- On-device fine-tuning of `NLModel` or Foundation Models (not currently supported by Apple's frameworks)
- Real-time model updates outside app releases (deferred — adds infrastructure cost without proportional value)
- Sharing aliases between household members
- Automatic alias suggestion ("looks like you say 'morning music' a lot — should that be Favorite 3?") — possible v2

---

## Flow B — On-Device Personalisation

Flow B improves the parser's behaviour for an individual user, on their device, without any data leaving the device.

### B-1 Aliases

> As a user, I want to teach the app that a phrase I commonly use means a specific action so that I don't have to use the app's default vocabulary.

**Acceptance criteria:**

- The user can open a settings screen and add an alias mapping a spoken phrase to a target intent and slot
- Alias targets in v1 cover: a specific favorite by name, a specific favorite by number, a specific other speaker for join, and a fixed volume value
- Aliases are scoped per addressed speaker: an alias *"morning music"* on Beosound can map to a different favorite than the same phrase on a Beolab
- Aliases are stored locally; they survive app restart and update but are wiped on app deletion
- Aliases can be edited and deleted from the same settings screen
- The parser checks aliases before invoking either Foundation Models or the fallback parser; an alias hit short-circuits to the resolved intent
- An alias hit follows the same confirmation-before-execution rule as any other command

---

### B-2 Confirmed-Command Memory

> As a user, I want the app to remember when I successfully use a phrase that wasn't in its vocabulary so that I don't have to teach it the same phrase twice.

**Acceptance criteria:**

- After a command is confirmed and executed, the app stores the parsed `(transcription, intent, slots)` tuple locally
- The store is per addressed speaker, capped at a fixed number of entries (e.g. 200 per speaker), with least-recently-used eviction
- On subsequent commands, the parser checks this store before invoking Foundation Models or the fallback parser
- A store hit short-circuits to the cached intent, but still routes through the confirmation step — the user can still say "no" if the cached interpretation isn't what they want this time
- A cancelled confirmation removes the offending entry from the store
- The store is cleared when the user signs out, deletes the app, or explicitly clears it from settings

---

### B-3 Personalisation Visibility

> As a user, I want to see what the app has learned about me so that I trust the system and can correct it.

**Acceptance criteria:**

- A "Learned phrases" section in settings lists every entry from the confirmed-command store, grouped by speaker
- Each entry shows: the phrase, the resolved intent and slot, the date last used
- Each entry has a delete affordance
- A "Clear all learned phrases" action wipes the store after a confirmation prompt
- The aliases list (B-1) is shown as a separate section in the same settings area for clarity

---

### B-4 Disabling Personalisation

> As a user, I want to turn off personalisation entirely so that the app behaves identically to the v1 baseline.

**Acceptance criteria:**

- A single settings toggle "Personalise voice control" controls both aliases (B-1) and the confirmed-command store (B-2)
- When the toggle is off, the parser ignores both stores and behaves exactly as the v1 baseline parser
- Turning the toggle off does not delete the stored data — it only stops the parser from consulting it
- A separate "Clear all personalisation data" action permanently deletes both stores

---

## Flow A — Telemetry & Retraining

Flow A collects anonymised parse outcomes from consenting users, ships them to a backend, and uses them to train improved models that ship in subsequent app releases.

### A-1 Local Telemetry Buffer

> As a user, I want to know that any data the app collects about my voice commands stays on my device until I explicitly agree to share it.

**Acceptance criteria:**

- After every parse outcome (confirmed, cancelled, timed out, or `.unknown`), the app records a structured event to a local buffer
- Each event contains: anonymised transcription (with speaker name position marked but value stripped), parsed intent, parsed slots (favorite names hashed, not raw), parser path used, outcome, app version, model version, locale, timestamp
- Each event explicitly does **not** contain: audio, raw favorite names, raw speaker names, household identifiers, account identifiers, location
- The local buffer is capped (e.g. 1,000 events); oldest entries are evicted when the cap is reached
- The buffer exists regardless of consent state — it allows Flow A to start uploading immediately if the user opts in later, without losing recent events

---

### A-2 Consent and Opt-In

> As a user, I want explicit, granular control over whether anonymised voice data is shared.

**Acceptance criteria:**

- The "Help improve voice control" toggle in settings is **off by default**
- The toggle's description states clearly: what is collected, what is not collected, where it goes, and how to change the choice
- A first-time prompt is shown after a configurable usage threshold (e.g. 50 commands) — once dismissed, the prompt is not shown again unless the user opens the related settings screen
- The toggle can be turned off at any time; turning it off cancels any in-flight upload and stops future uploads
- Turning the toggle off offers a "Delete previously shared data" action that issues a server-side deletion request for all events associated with the user's anonymous device ID
- The consent state and any associated identifiers are stored locally and cleared if the app is deleted

---

### A-3 Upload

> As a user, I want telemetry uploads to be respectful of my battery, my data plan, and my time.

**Acceptance criteria:**

- Uploads are batched: events are held in the local buffer and uploaded in batches of up to N events
- Uploads happen only on Wi-Fi and only when the device is not in Low Power Mode
- Uploads happen no more than once per 24 hours
- Uploads are silent — there is no UI prompt and no notification
- A failed upload retries with exponential backoff up to a maximum delay of 24 hours; events are not removed from the local buffer until the server acknowledges receipt
- An anonymous, randomly generated device identifier is included with each upload so that server-side deduplication and deletion requests work; this identifier is regenerated if the user clears personalisation data or reinstalls the app

---

### A-4 Disagreement Signals

> As a user, I want the app to learn most from cases where it got something wrong so that the next release fixes those cases first.

**Acceptance criteria:**

- The telemetry event records the outcome explicitly: `confirmed`, `cancelled`, `timedOut`, or `unknown`
- A `cancelled` outcome followed within a configurable window (e.g. 30 seconds) by a successful command of a different intent on the same speaker is flagged in the event as `likelyMisparse` — this is the highest-value signal for retraining
- An `unknown` outcome followed by a successful command of any intent on the same speaker is flagged as `recoverableUnknown`
- Flagged events are not treated differently in transit — they are uploaded with the same consent and same transport as any other event — but the flag lets the labelling pipeline prioritise them

---

### A-5 Backend Labelling and Retraining (out of app, summarised here)

The backend pipeline is out of scope for the app spec but is summarised so the app side can be designed to fit:

- Incoming events are reviewed by a human labelling tool that surfaces flagged events first
- Reviewers add high-quality (transcription, intent) pairs to the training corpus
- A new `NLModel` is trained per release; the CI accuracy gate from T-0305g still applies
- A regression set is maintained: previously failed examples that have been fixed must not regress
- New models ship with the next app release; there is no over-the-air model swap in v1

The app side does not need to know any of this — it only needs to ship clean, labelled, anonymised events.

---

### A-6 Transparency

> As a user, I want to be able to see exactly what telemetry the app has sent, in plain language.

**Acceptance criteria:**

- A "Shared data" screen in settings shows a count of events sent in the last 30 days
- The screen explains, in plain language, what was sent and what was not — with a link to the privacy policy
- The screen offers a "Stop sharing and delete" action that combines the toggle-off with the deletion request from A-2

---

## Interaction Between Flow A and Flow B

The two flows operate on different data and at different layers:

- Flow B reads and writes the local **personalisation stores** (aliases and confirmed-command memory). These never leave the device.
- Flow A reads and writes the local **telemetry buffer**. Aliases and confirmed-command entries are **not** included in telemetry events. The telemetry event records only the parse outcome of the actual user utterance.

When a Flow B alias short-circuits a parse, the telemetry event still records that this happened — the parser path field includes a `.aliasHit` value. This lets the backend distinguish between cases where the model parsed correctly and cases where the user's personalisation saved a parse the model would have got wrong. It does not capture the alias content itself.

---

## Error States

| Scenario | Expected Behaviour |
|---|---|
| Alias creation fails (storage full or invalid input) | *"Could not save alias. Please try again."* — settings remains on the alias edit screen |
| Confirmed-command store full | Oldest entries are evicted silently; no user-facing notification |
| Telemetry buffer full | Oldest events evicted silently |
| Telemetry upload fails repeatedly | No user-facing notification; events remain in buffer until either successful upload or buffer eviction |
| Server-side deletion request fails | The local toggle-off succeeds anyway; a banner in the "Shared data" screen indicates deletion is pending and will retry |
| User clears personalisation while an upload is in flight | Upload is cancelled; events for that batch are retained in the buffer for next attempt unless consent has also been revoked |

---

## Non-Functional Requirements

- **No regression of v1 behaviour:** when both flows are disabled, voice control is observably identical to v1
- **Privacy:** no audio, no raw favorite names, no raw speaker names ever leave the device under Flow A
- **Performance:** alias and confirmed-command lookup adds no more than 50 ms to the parse pipeline on a minimum-spec device
- **Storage:** combined personalisation and telemetry storage stays under 5 MB per user under typical usage
- **Battery:** Flow A uploads are scheduled to align with system background-task windows; no active polling or wake-locks
- **Resilience:** turning Flow A off mid-upload does not corrupt the local buffer
- **Auditability:** the user can always view, edit, or delete their personalisation data and request deletion of their shared telemetry data

---

## Open Questions

1. **Alias collisions** — what happens when two aliases on the same speaker resolve to different intents but share a substring (alias *"morning"* → Favorite 3, alias *"morning music"* → Favorite 5)? Default assumption: longest match wins; needs UX validation.
2. **Confirmed-command store and aliases conflict resolution** — if a user has both an alias and a confirmed-command entry that match the same transcription, which wins? Default assumption: explicit aliases always win over implicit memory.
3. **Telemetry rate limiting** — should there be a per-day cap on events recorded (not just uploaded)? A power user issuing 500 commands per day generates a large buffer. Default assumption: cap recording at 200 events per day, drop the rest silently.
4. **Anonymous device ID rotation** — should the ID rotate periodically (e.g. monthly) to limit cross-time correlation, or stay stable to support deletion requests? Default assumption: stable until the user clears data, then regenerate.
5. **Family-sharing households** — should aliases be marked as "shared" vs "personal" in anticipation of multi-user scenarios? Default assumption: no marking in v1; revisit when a household account model exists.
6. **Crash and error events** — should parser exceptions and Mozart API failures be included in telemetry alongside parse outcomes? Useful for backend reliability but expands the scope. Default assumption: in scope, but flagged separately so they can be filtered out of training data.

---

## Resolved Decisions

| Question | Decision |
|---|---|
| Should Flow A be opt-in or opt-out? | Opt-in; off by default |
| Does Flow A ever collect audio? | No — transcription strings only, with favorite and speaker names stripped or hashed |
| Does Flow B require any consent prompt? | No — it's local-only and adds nothing to a privacy review |
| Are aliases shared across speakers? | No — aliases are scoped per addressed speaker |
| Does an alias bypass the confirmation step? | No — confirmation-before-execution applies to alias hits the same as any other command |
| Are confirmed-command entries the same as aliases? | No — aliases are explicit and user-created; confirmed-command entries are implicit and learned. They share storage scope but not creation path |
| Does Flow A telemetry include any Flow B data? | No — Flow A records parse outcomes of real utterances, not the personalisation stores themselves |
| Where do new models ship from? | Bundled with app releases; no over-the-air model swap in v1 |