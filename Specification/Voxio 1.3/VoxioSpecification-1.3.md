# Voxio Specification — v1.3
**Version:** 1.3.3
**Status:** Draft
**Date:** 2026-05-04
**Platform:** iOS 26 (iPhone, portrait)
**References:** VoxioSpecification-1.2.md, Voice-Model-Improvements-Spec.md, CLAUDE.md
**Languages:** English (`en-US`) and Danish (`da-DK`) — both fully supported (unchanged from v1.2)

**Amendment history**

| Version | Date | Summary |
|---|---|---|
| 1.3.0 | 2026-05-04 | Initial draft. Feature 1: Voice model improvement — on-device personalisation (Flow B) and opt-in telemetry for retraining (Flow A). Further features to be added. |
| 1.3.1 | 2026-05-04 | Amendment: Feature 2 — Broadcast commands. New `VoiceCommand` cases and Stage 1 regex patterns for system-wide playback control ("stop everything", "volume down everywhere"). Executes in parallel across all active speakers. New US-56–US-59, E-37. |
| 1.3.2 | 2026-05-04 | Amendment: Streaming service integrations (Spotify, Deezer, Tidal) deferred to v1.4. Research docs moved to `Specification/Voxio 1.4/`. |
| 1.3.3 | 2026-05-04 | Amendment: Feature 3 — General UI improvements. First-boot onboarding screen, Settings sheet (hosts Flow A/B controls and language), and redesigned help screen with grouped command examples. New US-60–US-66, E-38–E-40. |
| 1.3.4 | 2026-05-04 | Amendment: Epic dependency blocks added to E-33–E-40. Alias deletion acceptance criteria strengthened in US-49; new T-3405 specifies deletion UX (swipe, confirmation, bulk delete, empty state). |

---

## Introduction

Voxio v1.3 builds on the speaker abstraction, widget, and voice pipeline shipped in v1.2. The primary workstream in this release is **voice model improvement**: making the command parser better over time through on-device personalisation and, for users who opt in, anonymised telemetry that feeds future retraining rounds.

The v1.3 spec is intentionally open-ended. Additional feature workstreams will be added as amendments. The voice model improvement feature is specified first because it touches the command-parsing pipeline that underpins every other planned feature.

What v1.3 changes:

1. **On-device personalisation (Flow B)** — users can create explicit aliases mapping personal phrases to intents, and the app implicitly learns from confirmed commands. Both stores are consulted before the Foundation Models or NLModel layers, short-circuiting the parse for known phrases. All data stays on device.
2. **Opt-in telemetry and retraining (Flow A)** — with explicit user consent, anonymised parse outcomes are buffered locally and uploaded in batches to a backend. The backend feeds a human labelling and retraining pipeline. Improved models ship in future releases, bundled in app updates. Off by default.
3. **Broadcast commands** — a new family of voice commands that operate on all active speakers simultaneously: "stop everything", "pause all", "volume down everywhere", "mute all", and their Danish equivalents. New `VoiceCommand` cases, new Stage 1 regex patterns, and parallel execution across the full speaker list.
4. **General UI improvements** — a first-boot onboarding screen introducing the app concept and trigger-word pattern; a Settings sheet hosting all voice model improvement and personalisation controls; and a redesigned help screen with elaborated, grouped command examples covering single-speaker, grouping, and system/broadcast actions.

### What is NOT changing in v1.3

- The three-tier voice command parsing pipeline structure — unchanged. New layers are inserted before or alongside the existing tiers, not replacing them.
- All existing single-speaker `VoiceCommand` cases and intent vocabulary — unchanged.
- The "Voxio" trigger word and orb state machine — unchanged.
- The auto-execute countdown confirmation flow — unchanged.
- The dark Liquid Glass visual layer — unchanged.
- The Mozart and BNR API integrations — unchanged.
- The `Group` abstraction and speaker join/leave — unchanged.
- The WidgetKit and Control Widget surfaces — unchanged.
- Language coverage — English and Danish only. No new languages in v1.3.
- Deployment target — iOS 26 (unchanged).
- Live Activity ("now playing") — deferred, was out of scope in v1.2, remains deferred.
- iPad layout and landscape orientation — out of scope (unchanged).

---

## Technical Context

| Decision | Choice | Rationale |
|---|---|---|
| Flow B storage | Core Data, scoped to app container. Two entities: `Alias` and `ConfirmedCommand`. | Core Data provides the schema migration, eviction, and query support needed for the LRU cap on `ConfirmedCommand`. SQLite direct is an alternative but adds more boilerplate. |
| Flow B sync | None in v1.3 — personalisation is per-device. | Would require an account system. Deferred. |
| Flow B parse layer position | New `PersonalisationParser` struct consulted in `CommandParserRouter.parse()` before Stage 1 regex. A hit short-circuits to the resolved intent immediately. | Aliases and confirmed-command entries are high-confidence and should be cheap to check. Checking before Stage 1 means even deterministic regex commands can be overridden by a user alias. |
| Flow B alias scope | Aliases are scoped per `Speaker.id`. | A phrase may mean different things on different speakers (e.g. "morning music" → Favorite 2 on the bedroom speaker, Favorite 5 on the kitchen speaker). |
| Flow B confirmed-command cap | 200 entries per speaker, LRU eviction. | Balances recall and storage. 200 entries × average ~50 bytes per entry ≈ 10 KB per speaker — negligible. |
| Flow A storage | Local `TelemetryBuffer` (Core Data or SQLite), separate from Flow B stores. | Telemetry and personalisation are independent concerns with different retention and upload lifecycles. |
| Flow A transport | HTTPS, batch upload, Wi-Fi only, no Low Power Mode. | Standard B&O privacy posture; matches the upload constraints recommended in Apple's background task documentation. |
| Flow A consent | Off by default; explicit `Settings > Voice control > Help improve voice control` toggle. First-time prompt shown after 50 commands. | Opt-in is the correct default for any data leaving the device. |
| Flow A audio | Never collected — transcription strings only. Favorite names hashed, speaker names stripped from transcription position. | Maintains the v1 privacy guarantee. |
| Flow A model update mechanism | New `.mlmodel` bundled with app releases. No over-the-air model swap in v1.3. | Over-the-air model swap adds infrastructure cost without proportional value at current user scale. |
| Flow A anonymous device ID | Randomly generated UUID, regenerated on personalisation clear or app reinstall. | Stable enough to support server-side deletion requests; not stable enough to correlate across reinstalls. |
| Telemetry event structure | `(transcriptionAnonymised, intent, slots, parserPath, outcome, appVersion, modelVersion, locale, timestamp, flags)` | See A-1 for full field spec. No audio, no raw favorite names, no raw speaker names. |
| Onboarding persistence | `@AppStorage("hasCompletedOnboarding")` boolean, set to `true` on dismiss. Replaces the existing `hasSeenHint` key. | Single flag; the onboarding screen subsumes the current `HintCardView` first-launch role. |
| Settings presentation | Modal `.sheet` anchored to an icon button in the `HomeView` toolbar. Full-height sheet, `DarkGlass` aesthetic. | Sheet is dismissible by swipe or a close button — consistent with `LanguagePickerSheet`. No separate navigation stack needed at this scale. |
| Help screen presentation | Full-height `.sheet`, triggered from both the existing `questionmark.circle` toolbar button and a row inside Settings. | Preserves the existing `questionmark.circle` UX while also making help accessible from Settings. |
| Help grouping | Three sections: (1) Single speaker, (2) Grouping, (3) System / broadcast. Each section shows a table of example phrases (EN + DA) side by side or switchable via the language setting. | Mirrors the three command categories in the voice pipeline. Keeps examples scannable at a glance. |

---

## Goals

- A user can teach the app a personal phrase ("play my morning playlist") that maps to a specific intent, and have it work immediately without using the app's default vocabulary.
- A confirmed command is remembered implicitly so the user does not have to repeat it the next time they use the same phrasing.
- The parser is faster for personalised phrases — alias and confirmed-command lookup adds ≤ 50 ms to the parse pipeline on a minimum-spec device.
- Flow B is visibly controllable: the user can view, edit, and delete all learned phrases and aliases from a settings screen.
- Flow A consent is unambiguous: the user can see exactly what is being collected, exactly what is not, and can revoke consent and request deletion at any time.
- When both flows are off, voice control behaviour is observably identical to v1.2.
- Privacy guarantee maintained: no voice audio, no raw favorite names, no raw speaker names ever leave the device.
- Combined personalisation and telemetry storage stays under 5 MB per user under typical usage.
- A first-time user understands the trigger-word pattern and can issue their first voice command within 60 seconds of first launch, without reading external documentation.
- All voice model improvement and personalisation controls are reachable from a single Settings sheet, 2 taps from the main screen.
- The help screen gives concrete, copy-ready example phrases for every major command category in both English and Danish.

---

## Out of Scope (v1.3 initial)

- **Cross-device sync of personalisation data** — requires an account system. Deferred.
- **On-device fine-tuning of `NLModel` or Foundation Models** — not currently supported by Apple's frameworks.
- **Real-time model updates outside app releases** — deferred; adds infrastructure cost without proportional value.
- **Sharing aliases between household members** — requires multi-user account model.
- **Automatic alias suggestion** ("looks like you say 'morning music' a lot — add as alias?") — possible v2 of this feature.
- **Live Activity / Dynamic Island now-playing card** — deferred from v1.2, remains deferred.
- **Favorite-selection in widget** — deferred from v1.2, remains deferred.
- **Skip / next-track control in widget** — deferred from v1.2, remains deferred.
- **Streaming service integrations (Spotify, Deezer, Tidal)** — deferred to v1.4. Research docs are in `Specification/Voxio 1.4/`.
- **Settings screen redesign** — now in scope as part of Feature 3 (General UI improvements). A new Settings sheet provides all controls needed for v1.3. A full redesign of app-level settings is not in scope.
- **Multi-page onboarding wizard** — Feature 3 introduces a single onboarding screen, not a multi-step wizard with account creation, hardware pairing, or advanced setup flows.
- **Interactive tutorial / guided first command** — the onboarding screen explains concepts; it does not walk the user through issuing a real command step by step.

---

## Feature 1 — Voice Model Improvement

*Full detail in `Voice-Model-Improvements-Spec.md`. This section summarises the feature at spec level and adds the implementation task breakdown.*

The v1 command parser ships with a fixed model. This feature adds two complementary layers that let the parser improve over time:

- **Flow B — On-Device Personalisation.** Immediate improvement, zero data leaves the device.
- **Flow A — Telemetry & Retraining.** Opt-in improvement that feeds future training rounds.

The two flows are independent. A user can opt out of Flow A entirely and still benefit from Flow B.

---

### User Stories

---

**US-49 — Alias creation**
> As a user, I want to teach the app that a phrase I commonly use means a specific action so that I don't have to use the app's default vocabulary.

**Acceptance criteria:**
- The user can open Settings and add an alias: a spoken phrase mapped to a target intent and slot.
- Alias targets in v1.3 cover: a specific favorite by name, a specific favorite by number, a specific speaker for join, and a fixed volume value.
- Aliases are scoped per addressed speaker.
- Aliases survive app restart and update; wiped on app deletion.
- Aliases can be edited and deleted from the alias management screen.
- Deleting an alias requires a confirmation prompt ("Delete alias?" with a destructive "Delete" action) — deletion is permanent and cannot be undone.
- A swipe-to-delete gesture triggers the same confirmation prompt as the explicit delete button.
- A "Delete all aliases for [Speaker]" bulk action is available per speaker group, with its own confirmation prompt naming the speaker and alias count ("Delete all 3 aliases for Beolab?").
- After all aliases for a speaker are deleted the speaker group is removed from the list; if no aliases remain, an empty-state illustration and "Add your first alias" prompt are shown.
- The parser checks aliases before invoking any other parsing layer; an alias hit short-circuits to the resolved intent.
- An alias hit routes through the same confirmation-before-execution step as any other command.

---

**US-50 — Confirmed-command memory**
> As a user, I want the app to remember when I successfully use a phrase that wasn't in its vocabulary so that I don't have to teach it the same phrase twice.

**Acceptance criteria:**
- After a command is confirmed and executed, the app stores the `(transcription, intent, slots)` tuple locally, scoped to the addressed speaker.
- The store is capped at 200 entries per speaker; LRU eviction applies.
- On subsequent commands, the store is checked before invoking Foundation Models or the fallback parser.
- A store hit still routes through the confirmation step — the user can say "no".
- A cancelled confirmation removes the offending entry from the store.
- The store is cleared on app deletion or explicit user action.

---

**US-51 — Personalisation visibility**
> As a user, I want to see what the app has learned about me so that I trust the system and can correct it.

**Acceptance criteria:**
- A "Learned phrases" section in Settings lists all confirmed-command store entries, grouped by speaker, showing phrase, resolved intent, and date last used.
- Each entry has a delete affordance.
- A "Clear all learned phrases" action wipes the store after a confirmation prompt.
- Aliases are shown as a separate section in the same settings area.

---

**US-52 — Disable personalisation**
> As a user, I want to turn off personalisation entirely so that the app behaves identically to the v1.2 baseline.

**Acceptance criteria:**
- A single toggle "Personalise voice control" controls both aliases and the confirmed-command store.
- When off, the parser ignores both stores entirely.
- Turning off does not delete data — only stops the parser consulting it.
- A separate "Clear all personalisation data" action permanently deletes both stores.

---

**US-53 — Telemetry consent**
> As a user, I want explicit control over whether anonymised voice data is shared so that I know exactly what I am agreeing to.

**Acceptance criteria:**
- "Help improve voice control" toggle in Settings is **off by default**.
- The toggle's description states: what is collected, what is not, where it goes, how to change it.
- A one-time prompt is shown after 50 commands; dismissed once, not shown again unless the user opens Settings.
- Turning off cancels any in-flight upload and stops all future uploads.
- Turning off offers a "Delete previously shared data" action that issues a server-side deletion request.

---

**US-54 — Respectful telemetry uploads**
> As a user, I want telemetry uploads to be silent, Wi-Fi only, and battery-respectful.

**Acceptance criteria:**
- Uploads are batched; upload only on Wi-Fi and outside Low Power Mode.
- Upload no more than once per 24 hours.
- No UI notification for uploads.
- Failed uploads retry with exponential backoff up to 24 hours; events are not removed from the local buffer until the server acknowledges receipt.

---

**US-55 — Telemetry transparency**
> As a user, I want to see what telemetry I have shared so that I can verify the stated privacy policy.

**Acceptance criteria:**
- A "Shared data" screen in Settings shows a count of events sent in the last 30 days.
- The screen explains, in plain language, what was sent and what was not, with a link to the privacy policy.
- The screen offers a "Stop sharing and delete" action combining toggle-off with the deletion request.

---

### Error States

| Scenario | Expected Behaviour |
|---|---|
| Alias creation fails (storage full or invalid input) | "Could not save alias. Please try again." — settings remains on alias edit screen |
| Confirmed-command store full | Oldest entries evicted silently; no user-facing notification |
| Telemetry buffer full | Oldest events evicted silently |
| Telemetry upload fails repeatedly | No user-facing notification; events remain in buffer until successful upload or eviction |
| Server-side deletion request fails | Toggle-off succeeds; "Shared data" screen shows pending deletion state and retries silently |
| User disables sharing during an in-flight upload | Upload cancelled; events retained in buffer unless consent also revoked |

---

### Implementation Epics and Tasks

#### E-33 — PersonalisationParser and Core Data schema

**Depends on:** v1.2 voice pipeline (shipped) — `CommandParserRouter`, `TwoStageFallbackParser`, existing Core Data stack.
**Unlocks:** E-34 (PersonalisationStore API must exist before the Settings UI can bind to it), E-35 (shared PersistenceController and Core Data container must be established before TelemetryBuffer entity is added).
**Runs in parallel with:** E-37, E-38, E-40.

| Task | Description |
|---|---|
| T-3301 | Define `Alias` and `ConfirmedCommand` Core Data entities. `Alias`: `id`, `speakerId`, `phrase`, `intent`, `slots` (JSON blob), `createdAt`. `ConfirmedCommand`: `id`, `speakerId`, `transcription`, `intent`, `slots` (JSON blob), `lastUsedAt`, `useCount`. |
| T-3302 | Implement `PersonalisationStore` — CRUD for both entities, LRU eviction (delete oldest `lastUsedAt` when `ConfirmedCommand` count per speaker exceeds 200). |
| T-3303 | Implement `PersonalisationParser` struct. `parse(_ text: String, speakerId: String) -> ParsedCommand?`. Checks aliases first (exact match, case-insensitive), then confirmed-command store (exact match). Returns `nil` on no match. |
| T-3304 | Insert `PersonalisationParser` into `CommandParserRouter.parse()` before Stage 1 regex. Log path as `"PersonalisationAlias"` or `"PersonalisationMemory"`. |
| T-3305 | After a command is confirmed and executed in `HomeView`, write the `(transcription, intent, slots)` tuple to the confirmed-command store if the entry does not already exist; increment `useCount` if it does. |
| T-3306 | On a cancelled confirmation, check if the cancellation removed a command that had a confirmed-command store entry and delete that entry. |

#### E-34 — Personalisation Settings UI

**Depends on:** E-33 (PersonalisationStore and PersonalisationParser must exist before Settings UI can bind to them).
**Unlocks:** E-39 T-3904 (Settings sheet wires "Aliases" and "Learned phrases" rows to screens built here).
**Runs in parallel with:** E-35, E-36, E-37, E-38, E-40.

| Task | Description |
|---|---|
| T-3401 | Add a "Voice control" section to Settings. Contains "Personalise voice control" toggle (default on), "Learned phrases" row, and "Aliases" row. |
| T-3402 | Implement "Aliases" list screen: aliases grouped by speaker, showing phrase and resolved intent for each entry. Add (`+` toolbar button) and edit (tap row) affordances. See design spec `design-spec-alias-management.md` for layout. |
| T-3403 | Implement "Learned phrases" screen: list of confirmed-command entries grouped by speaker, showing phrase, intent, date last used, delete affordance. "Clear all" action with confirmation prompt. |
| T-3404 | Wire "Personalise voice control" toggle to `PersonalisationStore.isEnabled`. When toggled off, `PersonalisationParser` returns `nil` for all inputs. |
| T-3405 | Implement alias deletion UX as specified in US-49: swipe-to-delete on each alias row triggers a confirmation alert ("Delete alias?" / destructive "Delete" / "Cancel"); tapping "Delete" calls `PersonalisationStore.deleteAlias(_:)`. Add a "Delete all aliases for [Speaker]" button at the bottom of each speaker section; this confirmation alert names the speaker and alias count. After deletion, collapse the speaker group if empty; show the empty-state view if no aliases remain at all. |

#### E-35 — Telemetry Buffer and Consent

**Depends on:** E-33 T-3301 (shared Core Data container must exist before `TelemetryBuffer` entity is added to it).
**Unlocks:** E-36 (Shared Data screen depends on `TelemetryUploader`), telemetry backend work (E-41+, separate repo).
**Runs in parallel with:** E-34, E-37, E-38, E-40.

| Task | Description |
|---|---|
| T-3501 | Define `TelemetryEvent` struct with fields: `transcriptionAnonymised`, `intent`, `slotsAnonymised` (JSON), `parserPath`, `outcome` (confirmed/cancelled/timedOut/unknown), `appVersion`, `modelVersion`, `locale`, `timestamp`, `flags` (likelyMisparse/recoverableUnknown). |
| T-3502 | Implement `TelemetryBuffer` — local Core Data entity, capped at 1,000 events, oldest-first eviction. Record an event after every parse outcome. |
| T-3503 | Implement anonymisation in `TelemetryBuffer.record()`: strip speaker-name tokens from transcription, hash favorite-name slot values with SHA-256 prefix (first 8 chars). |
| T-3504 | Implement misparse flagging: if a `cancelled` outcome is followed within 30 seconds by a `confirmed` outcome of a different intent on the same speaker, retroactively flag the cancelled event as `likelyMisparse`. |
| T-3505 | Add `TelemetryUploader` — batched HTTPS upload (up to 100 events per batch), Wi-Fi only, no Low Power Mode, once per 24 hours, exponential backoff on failure. Events not deleted from buffer until server returns 2xx. |
| T-3506 | Add "Help improve voice control" toggle to Settings (off by default). Wire to `TelemetryUploader.isEnabled`. Add first-time prompt shown after 50 confirmed commands. |
| T-3507 | Implement anonymous device ID: `UUID` stored in Keychain, regenerated on personalisation-data clear or app reinstall. Included in each upload batch header. |
| T-3508 | Implement "Delete previously shared data" — `DELETE /telemetry/{deviceId}` request to the backend. Show pending/success/failed state in the "Shared data" settings screen. |

#### E-36 — Shared Data Settings Screen

**Depends on:** E-35 (`TelemetryUploader.isEnabled` toggle and `DELETE` request from T-3508 must exist before this screen can bind to them).
**Unlocks:** E-39 T-3903 (Settings "Shared data" navigation row wires to the screen built here).
**Runs in parallel with:** E-34, E-37, E-38, E-40.

| Task | Description |
|---|---|
| T-3601 | Implement "Shared data" screen in Settings: event count (last 30 days), plain-language summary of what was collected, link to privacy policy. |
| T-3602 | Add "Stop sharing and delete" action that combines toggle-off with the `DELETE` request from T-3508. |

---

## Feature 2 — Broadcast Commands

A broadcast command targets all active speakers simultaneously rather than a single addressed speaker. It is triggered by explicit universal qualifiers in the utterance ("everything", "all", "everywhere" and their Danish equivalents). Existing single-speaker commands are unaffected — an utterance without a broadcast qualifier continues to route to the addressed speaker exactly as before.

**Supported broadcast intents (v1.3):**

| Intent | `VoiceCommand` case | What executes |
|---|---|---|
| Stop all | `.stopAll` | `stop()` on every speaker with `playbackState == .playing` |
| Pause all | `.pauseAll` | `pause()` on every speaker with `playbackState == .playing` |
| Resume all | `.resumeAll` | `resume()` on every speaker with `playbackState == .paused` |
| Volume up all | `.adjustVolumeAll(+delta)` | `adjustVolume(+delta)` on every active speaker |
| Volume down all | `.adjustVolumeAll(-delta)` | `adjustVolume(-delta)` on every active speaker |
| Mute all | `.muteAll` | `setMute(true)` on every active speaker |
| Unmute all | `.unmuteAll` | `setMute(false)` on every active speaker |

"Active speaker" is defined as any `Speaker` currently in the discovered speaker list, regardless of playback state, except where the intent table above narrows scope (stop/pause apply only to playing speakers; resume applies only to paused speakers).

---

### Broadcast trigger vocabulary

Stage 1 regex detects broadcast intent when a playback verb is combined with a universal qualifier:

**English triggers:**
- `stop everything` / `stop all` / `stop all speakers` / `stop the music everywhere`
- `pause everything` / `pause all` / `pause all speakers`
- `resume everything` / `resume all` / `play everywhere` / `play on all speakers`
- `volume down everywhere` / `turn down all speakers` / `lower everything` / `quieter everywhere` / `volume down on everything`
- `volume up everywhere` / `turn up all speakers` / `louder everywhere` / `volume up on everything`
- `mute everything` / `mute all` / `mute all speakers`
- `unmute everything` / `unmute all` / `unmute all speakers`

**Danish triggers:**
- `stop alt` / `stop alle højttalere` / `stop al musik`
- `pause alt` / `pause alle højttalere`
- `genoptag alt` / `spil overalt` / `spil på alle højttalere`
- `skru ned overalt` / `skru ned på alle højttalere` / `lavere overalt`
- `skru op overalt` / `skru op på alle højttalere` / `højere overalt`
- `slå lyden fra overalt` / `mute alt` / `mute alle`
- `slå lyden til overalt` / `unmute alt` / `unmute alle`

The universal qualifiers that alone signal broadcast (combined with any supported playback verb): `everything`, `all`, `all speakers`, `everywhere`, `on everything`, `alt`, `alle`, `alle højttalere`, `overalt`.

---

### Confirmation behaviour

Broadcast stop and pause execute immediately — no countdown confirmation. They are recoverable (the user can say "resume all" or tap play on any speaker). Adding a countdown to a "stop everything" command would feel like friction in the most common use case (someone leaving the room and wanting instant silence).

Broadcast volume and mute/unmute also execute immediately — consistent with how single-speaker volume and mute behave today.

---

### Execution model

`HomeView` (or a new `BroadcastCommandHandler`) iterates the current `SpeakerDiscoveryService.speakers` list, filters by the applicable scope, and fires the corresponding API call on each speaker using `async let` parallel tasks. Results are collected; partial failures are tolerated and logged at INFO level.

The UI shows a brief non-blocking toast naming how many speakers were affected: *"Stopped 3 speakers"* / *"Stoppede 3 højttalere"*. If all calls fail, the toast shows *"Could not reach any speaker"*.

---

### User Stories

---

**US-56 — Stop all active speakers**
> As a user, I want to say "stop everything" and have all speakers that are currently playing stop immediately, so I don't have to address each speaker by name.

**Acceptance criteria:**
- The phrase "stop everything" (and all trigger variants above) routes to `.stopAll`.
- Every speaker with `playbackState == .playing` at the moment the command is processed receives a `stop()` call.
- Speakers already stopped or paused are not affected.
- Execution is immediate — no countdown.
- A brief toast confirms how many speakers were stopped. If zero speakers were playing, the toast reads *"Nothing was playing"*.
- All calls are made in parallel; the command completes when all calls return or time out (5-second per-speaker timeout, matching existing `MozartClient` timeout).

---

**US-57 — Broadcast volume adjustment**
> As a user, I want to say "volume down everywhere" and have every active speaker turn down, so I can adjust the whole house at once.

**Acceptance criteria:**
- "volume down everywhere" and all volume variants route to `.adjustVolumeAll(-delta)`. Default delta is 10 (matching the single-speaker default).
- "volume down [number] everywhere" (e.g. "volume down 20 everywhere") applies the stated delta.
- Every speaker in the discovered list receives the volume adjustment, regardless of current playback state.
- Execution is immediate — no countdown.
- A brief toast confirms: *"Volume down on 3 speakers"*.

---

**US-58 — Broadcast mute / unmute**
> As a user, I want to say "mute everything" and instantly silence every speaker, so I can take a phone call without hunting for each speaker.

**Acceptance criteria:**
- "mute everything" and all mute variants route to `.muteAll`.
- "unmute everything" and all unmute variants route to `.unmuteAll`.
- Every active speaker receives the mute/unmute call in parallel.
- Execution is immediate — no countdown.
- A brief toast confirms: *"Muted 3 speakers"* / *"Unmuted 3 speakers"*.

---

**US-59 — No regression to single-speaker commands**
> As a user, I want single-speaker voice commands to behave exactly as before so that broadcast commands do not accidentally intercept my addressed commands.

**Acceptance criteria:**
- A command without a broadcast qualifier ("stop", "volume down", "mute") continues to route to the addressed speaker exactly as it does today.
- Stage 1 regex checks for broadcast triggers before the existing single-speaker patterns; if no broadcast qualifier is present, the existing patterns are applied unchanged.
- The broadcast qualifier detection is conservative: a partial word match (e.g. "altogether" containing "all") does not trigger broadcast intent. Only whole-word matches count (`\b` word boundaries in regex).

---

### Error States

| Scenario | Expected Behaviour |
|---|---|
| All API calls fail | Toast: *"Could not reach any speaker"* / *"Kunne ikke nå nogen højttalere"* |
| Some API calls fail | Toast names the count that succeeded: *"Stopped 2 of 3 speakers"*. Failed speakers are logged at INFO. |
| No speakers in scope (e.g. `.stopAll` when nothing is playing) | Toast: *"Nothing was playing"* / *"Intet spillede"* |
| Speaker list empty | Toast: *"No speakers found"* / *"Ingen højttalere fundet"* |
| Individual call times out | Speaker is excluded from the success count; treated as a failure for toast purposes. |

---

### Implementation Epics and Tasks

#### E-37 — Broadcast command parsing and execution

**Depends on:** v1.2 voice pipeline (shipped) — `CommandParserRouter`, `TwoStageFallbackParser`, `VoiceCommand` enum, `SpeakerDiscoveryService`.
**Unlocks:** nothing further in v1.3 (self-contained feature).
**Runs in parallel with:** all other v1.3 epics (E-33–E-36, E-38–E-40). No shared dependencies — can begin immediately.

| Task | Description |
|---|---|
| T-3701 | Add broadcast cases to `VoiceCommand`: `.stopAll`, `.pauseAll`, `.resumeAll`, `.adjustVolumeAll(Int)`, `.muteAll`, `.unmuteAll`. Update `CustomStringConvertible` conformance. |
| T-3702 | Add broadcast cases to `CommandIntent` in `ParsedCommand.swift`: `.stopAll`, `.pauseAll`, `.resumeAll`, `.volumeUpAll`, `.volumeDownAll`, `.muteAll`, `.unmuteAll`. |
| T-3703 | Add broadcast Stage 1 regex patterns to `TwoStageFallbackParser.parseStage1()`. Broadcast patterns must be checked **before** their single-speaker equivalents to ensure the universal-qualifier variants match first. Use `\b` word boundaries throughout. |
| T-3704 | Wire new `CommandIntent` broadcast cases through `CommandParserRouter.toVoiceCommand()`. |
| T-3705 | Implement `BroadcastCommandHandler` (or extend `HomeView.handleCommand()`) to detect `.stopAll` / `.pauseAll` / `.resumeAll` / `.adjustVolumeAll` / `.muteAll` / `.unmuteAll` and execute the corresponding call in parallel across the filtered speaker list using `async let` + `TaskGroup`. |
| T-3706 | Filter speaker scope per intent: stop/pause → `playbackState == .playing`; resume → `playbackState == .paused`; volume/mute/unmute → all discovered speakers. |
| T-3707 | Implement the result-count toast. Use a non-blocking `.overlay` or `.banner` pattern consistent with existing UI feedback (if any); otherwise a simple `@State` banner with a 3-second auto-dismiss. EN + DA strings. |
| T-3708 | Add corpus training examples for all broadcast trigger phrases (EN + DA) to `corpus-training.csv`. Retrain `VoxioCommandModel` and bundle the updated `.mlmodelc`. |
| T-3709 | Unit tests: `TwoStageFallbackParser` Stage 1 coverage for all broadcast trigger phrases and negative cases (single-speaker commands must not match broadcast patterns). |

---

## Feature 3 — General UI Improvements

Three related screens that make the app approachable for first-time users, surface the voice model improvement controls introduced in Feature 1, and give experienced users richer reference material.

- **Onboarding screen** — shown once on first launch. Explains the app concept and trigger-word pattern. Replaces the existing `HintCardView` first-launch role.
- **Settings sheet** — permanent home for voice model improvement (Flow A), personalisation (Flow B), language selection, and help access. Accessible from a toolbar icon.
- **Help screen** — replaces the current minimal `HintCardView` hint. A scrollable sheet with three grouped sections of example phrases (EN + DA): single speaker, grouping, and system/broadcast.

---

### User Stories

---

**US-60 — First-boot onboarding**
> As a new user, I want to see a brief introduction when I first open the app so that I understand what Voxio does and how to start using it before I try to speak a command.

**Acceptance criteria:**
- The onboarding screen is shown automatically the first time the app is launched and never again (persisted via `@AppStorage("hasCompletedOnboarding")`).
- The screen explains: what the app does (voice-control B&O speakers on the local network), the trigger-word pattern (`[Speaker name], [command]`), and that the app listens continuously via the microphone.
- The screen shows two to three concrete starter examples using placeholder speaker name "Beolab": *"Beolab, play"*, *"Beolab, volume up"*, *"Beolab, stop"*.
- A single `DarkGlassButton` "Get started" closes the screen and transitions to the main UI.
- If microphone and speech recognition permissions have not yet been granted, dismissing onboarding triggers the system permission prompts.
- The existing `hasSeenHint` `@AppStorage` key is migrated: if `hasSeenHint == true` on first launch after upgrade, `hasCompletedOnboarding` is set to `true` and the onboarding screen is not shown.
- Full EN + DA content.
- Respects Reduce Motion: no animated entrance beyond a simple `.opacity` fade.

---

**US-61 — Settings sheet access**
> As a user, I want quick access to all app settings from the main screen so that I can configure voice model options and personalisation without hunting through menus.

**Acceptance criteria:**
- A gear (`gear`) icon button is present in the `HomeView` toolbar alongside the existing language and help buttons.
- Tapping it opens a `SettingsView` as a `.sheet`.
- The sheet is dismissible by swipe or a close button in the sheet header.
- The sheet adopts the `DarkGlass` aesthetic consistent with the rest of the app.

---

**US-62 — Settings hosts voice model improvement controls**
> As a user who has been prompted to help improve voice control, I want to be able to find and change that setting easily so that I always know where to control my data sharing.

**Acceptance criteria:**
- Settings contains a "Voice model" section with:
  - "Help improve voice control" toggle (Flow A, default off). Tapping shows a one-sentence description of what is collected and what is not, with a link to open the "Shared data" sub-screen.
  - "Shared data" row — opens the Flow A transparency screen (US-55).
- The toggle state is the same control wired in E-35 (T-3506). Changing it here is the primary way to change consent.

---

**US-63 — Settings hosts personalisation controls**
> As a user, I want to manage my aliases and learned phrases from Settings so that I can see what the app knows about me and adjust it.

**Acceptance criteria:**
- Settings contains a "Personalisation" section with:
  - "Personalise voice control" toggle (Flow B, default on).
  - "Aliases" row — navigates to the alias management screen (US-49 / E-34).
  - "Learned phrases" row — navigates to the confirmed-command memory screen (US-51 / E-34).
- When "Personalise voice control" is off, the Aliases and Learned phrases rows are visually dimmed and non-interactive.

---

**US-64 — Settings hosts language selection**
> As a user, I want to change the recognition language from Settings so that I have one consistent place for all configuration.

**Acceptance criteria:**
- Settings contains a "Language" row that opens the existing `LanguagePickerSheet`.
- The current language is shown as a subtitle on the row (e.g. "English" / "Dansk").
- The standalone language button in the `HomeView` toolbar is retained so the language is also reachable directly from the main screen (two access paths).

---

**US-65 — Redesigned help screen with grouped examples**
> As a user, I want to see elaborated, grouped examples of all command types so that I can discover phrases I didn't know the app understood.

**Acceptance criteria:**
- The existing `questionmark.circle` toolbar button opens the new `HelpView` sheet instead of the `HintCardView`.
- Help is also accessible via a "Help" row in Settings.
- The `HelpView` sheet contains three named sections:

  **Section 1 — Single speaker actions** (uses placeholder `[Speaker]`):

  | Action | English | Danish |
  |---|---|---|
  | Play | *[Speaker], play* | *[Speaker], afspil* |
  | Pause | *[Speaker], pause* | *[Speaker], pause* |
  | Stop | *[Speaker], stop* | *[Speaker], stop* |
  | Resume | *[Speaker], resume* | *[Speaker], fortsæt* |
  | Volume absolute | *[Speaker], volume 50* | *[Speaker], lydstyrke 50* |
  | Volume up | *[Speaker], volume up* | *[Speaker], skru op* |
  | Volume up by amount | *[Speaker], volume up 20* | *[Speaker], skru op 20* |
  | Volume down | *[Speaker], volume down* | *[Speaker], skru ned* |
  | Mute | *[Speaker], mute* | *[Speaker], tavs* |
  | Unmute | *[Speaker], unmute* | *[Speaker], slå lyden til* |
  | Play favorite | *[Speaker], play favorite one* | *[Speaker], afspil favorit et* |
  | List favorites | *[Speaker], what are my favorites?* | *[Speaker], hvad er mine favoritter?* |

  **Section 2 — Grouping actions** (uses placeholders `[Speaker A]`, `[Speaker B]`):

  | Action | English | Danish |
  |---|---|---|
  | Join another speaker | *[Speaker A], join [Speaker B]* | *[Speaker A], tilslut [Speaker B]* |
  | Leave the group | *[Speaker A], leave the group* | *[Speaker A], forlad gruppen* |

  **Section 3 — System actions (all speakers)**:

  | Action | English | Danish |
  |---|---|---|
  | Stop all | *stop everything* | *stop alt* |
  | Pause all | *pause all* | *pause alle* |
  | Resume all | *resume all* | *genoptag alt* |
  | Volume down all | *volume down everywhere* | *skru ned overalt* |
  | Volume up all | *volume up everywhere* | *skru op overalt* |
  | Mute all | *mute everything* | *mute alt* |
  | Unmute all | *unmute everything* | *unmute alle* |

- The current app language (EN/DA) determines which column is shown by default; the other language is not hidden but shown in a secondary style or accessible via a toggle.
- If a speaker has been discovered, `[Speaker]` is replaced with the real first speaker name in the examples.
- The `HintCardView` is removed from the main UI flow. It is replaced entirely by the onboarding screen (first launch) and the help sheet (ongoing).

---

**US-66 — Re-show onboarding**
> As a user, I want to be able to re-read the introduction at any time so that I can refresh my memory.

**Acceptance criteria:**
- Settings contains a "Show introduction again" row that presents the onboarding screen as a sheet (rather than as a full-screen cover).
- Dismissing the sheet from Settings does not reset `hasCompletedOnboarding`.

---

### Error States

| Scenario | Expected Behaviour |
|---|---|
| Microphone permission denied at onboarding dismiss | Standard iOS permission denied state; no crash. App continues to Settings where the user can see a prompt to open System Settings and grant permission. |
| Settings sheet opened while a command countdown is in progress | Sheet is suppressed (not shown) while `coordinator.isPending == true`. The gear button is disabled during an active countdown. |

---

### Implementation Epics and Tasks

#### E-38 — First-boot onboarding screen

**Depends on:** none — standalone new screen against the existing app entry point.
**Unlocks:** E-39 T-3906 ("Show introduction again" row requires `OnboardingView` to exist).
**Runs in parallel with:** E-33–E-37, E-40. Can begin immediately.

| Task | Description |
|---|---|
| T-3801 | Implement `OnboardingView`: full-screen cover, dark background, Voxio wordmark or orb graphic, headline, body copy (2–3 sentences), 2–3 starter example rows, "Get started" `DarkGlassButton`. EN + DA strings. |
| T-3802 | Add `@AppStorage("hasCompletedOnboarding")` to `VoxioApp` or `HomeView`. Show `OnboardingView` as `.fullScreenCover` when `false`. |
| T-3803 | On onboarding dismiss, trigger microphone and speech recognition permission requests if not yet granted (move permission request logic here from wherever it currently fires). |
| T-3804 | Migrate existing `hasSeenHint`: on first run after upgrade, if `hasSeenHint == true`, write `hasCompletedOnboarding = true` so returning users skip onboarding. |
| T-3805 | Expose onboarding as a re-showable `.sheet` from Settings (US-66). |

#### E-39 — Settings sheet

**Depends on:** E-34 (alias and learned-phrases screens), E-36 (Shared Data screen), E-38 (`OnboardingView` re-show), E-40 (`HelpView`). Also depends on E-33/E-35 indirectly via the toggles wired in T-3903/T-3904. The sheet container (T-3901 + T-3902) can be scaffolded with stub rows early; individual rows cannot be fully wired until their target screens exist.
**Unlocks:** nothing further — this is the integration epic that ties all Feature 1 and Feature 3 screens together.
**Recommended order:** scaffold T-3901 + T-3902 first; complete T-3903–T-3907 after E-34, E-36, E-38, E-40 are done.

| Task | Description |
|---|---|
| T-3901 | Implement `SettingsView` as a SwiftUI `List` inside a `.sheet`. Sections: Voice model, Personalisation, Language, Help & About. Dark glass or system-adaptive list style. |
| T-3902 | Add gear (`gear`) toolbar button to `HomeView`. Disable during `coordinator.isPending`. |
| T-3903 | "Voice model" section: "Help improve voice control" toggle (wired to `TelemetryUploader.isEnabled` from T-3506) + description text + "Shared data" navigation row (US-55 screen). |
| T-3904 | "Personalisation" section: "Personalise voice control" toggle (wired to `PersonalisationStore.isEnabled` from T-3404) + "Aliases" and "Learned phrases" navigation rows (wired to E-34 screens). Dim rows when toggle is off. |
| T-3905 | "Language" row: shows current language label, opens `LanguagePickerSheet` on tap. |
| T-3906 | "Help" row: opens `HelpView` sheet. "Show introduction again" row: presents `OnboardingView` as a sheet. |
| T-3907 | "About" row: shows app version and build number. |

#### E-40 — Redesigned help screen

**Depends on:** none — standalone new screen.
**Unlocks:** E-39 T-3906 (Settings "Help" row requires `HelpView` to exist).
**Runs in parallel with:** all other v1.3 epics (E-33–E-39). Can begin immediately.

| Task | Description |
|---|---|
| T-4001 | Implement `HelpView`: scrollable `.sheet`, three `Section` groups matching the US-65 table. `DarkGlass` card per section or standard grouped list. |
| T-4002 | Single speaker section: 12 example rows as defined in US-65. Replace `[Speaker]` placeholder with first discovered speaker name if available. |
| T-4003 | Grouping section: 2 example rows as defined in US-65. Replace `[Speaker A]` / `[Speaker B]` with first two discovered speaker names if available. |
| T-4004 | System actions section: 7 example rows as defined in US-65. No speaker name substitution. |
| T-4005 | Language display: show the active language's phrases prominently; show the other language in `.secondary` style beneath each row. |
| T-4006 | Re-wire the existing `questionmark.circle` toolbar button in `HomeView` to open `HelpView`. Remove `HintCardView` from the main UI flow. |

---

## Open Questions

1. **Alias longest-match vs. first-match** — when two aliases share a substring ("morning" → Favorite 3, "morning music" → Favorite 5), which wins? Default assumption: longest phrase match. Needs UX validation.
2. **Alias vs. confirmed-command conflict** — if both match the same transcription, which wins? Default assumption: explicit aliases always take precedence over implicit confirmed-command entries.
3. **Telemetry rate cap** — should there be a per-day recording cap (not just upload cap)? A power user issuing 500 commands per day generates a large buffer. Default assumption: cap at 200 events recorded per day, drop the rest silently.
4. **Anonymous device ID rotation** — should the ID rotate monthly to limit cross-time correlation, or stay stable to support deletion requests? Default assumption: stable until the user clears data, then regenerate.
5. **Backend API design** — the upload endpoint, deletion endpoint, and batch format are not yet defined. App-side data structures (T-3501, T-3502) should be defined first; the backend spec follows.
6. **Streaming service integrations** — deferred to v1.4. See `Specification/Voxio 1.4/` for research docs.

---

## Resolved Decisions

| Question | Decision |
|---|---|
| Should Flow A be opt-in or opt-out? | Opt-in; off by default |
| Does Flow A ever collect audio? | No — transcription strings only, favorite and speaker names stripped or hashed |
| Does Flow B require any consent prompt? | No — local-only, adds nothing to a privacy review |
| Are aliases shared across speakers? | No — scoped per speaker |
| Does an alias bypass the confirmation step? | No — confirmation applies to alias hits the same as any other command |
| Are confirmed-command entries the same as aliases? | No — aliases are explicit/user-created; confirmed-command entries are implicit/learned |
| Does Flow A telemetry include any Flow B data? | No — Flow A records parse outcomes of real utterances, not the personalisation stores |
| Where do improved models ship from? | Bundled with app releases; no over-the-air model swap in v1.3 |
| Which Core Data stack approach? | Shared `PersistenceController` singleton used by both `PersonalisationStore` and `TelemetryBuffer`. Single container, two entity groups. |
| Do broadcast commands require confirmation? | No — stop, pause, volume, and mute/unmute all execute immediately. They are all recoverable actions. |
| Does "volume down" without a qualifier broadcast? | No — a command without an explicit broadcast qualifier routes to the addressed speaker. Implicit broadcast is not in scope for v1.3. |
| What is "active speaker" scope for volume/mute broadcast? | All discovered speakers, regardless of playback state. User said "all speakers playing" for stop/pause; for volume/mute the most useful behaviour is all-speakers since a muted idle speaker should still respond. |
| Are broadcast commands checked before or after personalisation (Flow B)? | After. A user alias can override a broadcast phrase if explicitly created. |
| Do broadcast commands appear in the telemetry buffer (Flow A)? | Yes — recorded as any other command outcome, with a `broadcast: true` flag in the event. |
| Is `HintCardView` kept alongside the new help screen? | No — `HintCardView` is removed. First-launch role transferred to `OnboardingView`; ongoing help transferred to `HelpView`. |
| Does Settings replace the existing language picker button in the toolbar? | No — the toolbar language button is retained. Settings is a second access path, not a replacement. |
| Should onboarding be a full-screen cover or a sheet? | Full-screen cover on first launch (no swipe-dismiss). Re-shown as a sheet from Settings (swipe-dismissible). |
| Is the gear icon added to the toolbar alongside the existing buttons? | Yes — gear added as a third toolbar icon alongside the existing language and help icons. |
