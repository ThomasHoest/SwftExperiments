# Functional Specification: Voxio Usability Enhancements
## Bang & Olufsen Voice Controller

**Version:** 1.1
**Status:** Draft
**Date:** 2026-04-29
**References:** functional-spec-bo-voice-control v1.3, design-spec-bo-voice-control v1.0, spec-command-parser-bo-voice-control v1.1, epics-and-tasks-bo-voice-control v1.2
**Languages:** English (`en-US`) and Danish (`da-DK`) — both fully supported

---

## Overview

This specification defines four small but high-value usability enhancements layered on top of the shipped Voxio iOS app. Each enhancement closes a known gap in first-launch onboarding, command failure feedback, transcript hygiene, and language preference persistence. None of the four features change the existing voice command grammar, the Mozart API integration, or the design system. The purpose of this version is to make the app self-explanatory on first run, less silent when it fails to understand the user, and tidier between commands. Backend changes, new Mozart endpoints, and new commands are explicitly out of scope.

---

## Technical Context

| Decision | Choice | Rationale |
|---|---|---|
| Persistence layer for language preference | `UserDefaults` via `LanguageService` (already in place) | `LanguageService.shared` already persists `activeLanguage` to `UserDefaults` under `com.voxio.activeLanguage`; the new "has user explicitly chosen" flag piggy-backs on the same store |
| Persistence layer for hint dismissal | `@AppStorage("hasSeenHint")` in `HomeView` | Single Boolean, view-local, no service needed; matches SwiftUI conventions used elsewhere in the app |
| Picker presentation pattern | SwiftUI `.sheet` from `HomeView` | `HomeView` already uses `.sheet` for `ConfirmationSheet`; keeps the navigation model uniform |
| Hint placement | Dismissible card inside the existing `voiceFeedback` area | The voice feedback area is empty when `transcript.isEmpty`; reusing it avoids new layout primitives |
| Failure feedback for `.unknown` intents | Reuse `errorService.spoken(.voiceNotRecognised)` | The `AppError.voiceNotRecognised` case already exists in `iOS/Voxio/Core/AppError.swift`; the EN/DA strings already exist in `ErrorStrings`, and the case is already wired through `coordinator.announce` for both spoken and visual surfacing |
| Unknown-intent signal | `ParsedCommand.intent == .unknown` (E-18 pipeline) | Confirmed: `CommandIntent.unknown` is the last case of the enum in `iOS/Voxio/Core/CommandParsing/ParsedCommand.swift`; `ParsedCommand.unknown(_ text:)` is the static factory used by the parser routes |
| Transcript clear timing | Existing `clearTranscriptAfterDelay()` (5 s `Task.sleep`) | Already implemented and used on the `.unknown` path; this version applies it consistently to every final-transcript code path |
| Recogniser locale switching on language change | Existing `voiceToText.setLanguage(_:)` via `HomeView.onChange(of: langService.activeLanguage)` | Already wired; switches `SFSpeechRecognizer` instance at runtime via `AVService.setLocale(_:)` |
| iOS deployment target | Unchanged (iOS 25 minimum, iOS 26 preferred) | All four features use APIs already in use elsewhere in the app |

---

## Goals

- A user opening Voxio for the first time chooses their command language explicitly (English or Dansk) before the microphone starts; the chosen language is then remembered for every subsequent launch
- A user who says something Voxio cannot parse hears an immediate spoken explanation rather than silence
- A user on first launch with at least one discovered speaker sees a single concrete example of how to phrase a command, using a real speaker name from their network
- The transcription text shown below the waveform clears within 5 seconds of every final transcription, regardless of whether the command succeeded, failed, was cancelled, or was unrecognised
- A user can re-show the getting-started hint on demand from the main screen at any time

---

## Out of Scope (this version)

- New voice commands or grammar changes (no new intents, no new keywords)
- Changes to the confirmation sheet layout or behaviour
- Changes to the Mozart API client, mDNS discovery, or speaker registry
- Languages beyond English and Danish (e.g. German, French) — deferred to a future version
- A full Settings screen — language change after first launch is still handled via the long-press / settings affordance defined in E-17 T-1710 and is not redesigned here
- Onboarding screens beyond the language picker and the hint card (no carousel, no permissions walkthrough)
- Tutorial videos or animated demonstrations
- Telemetry or analytics on first-launch flow

---

## User Stories

### US-09 — Choose command language on first launch

> As a new Voxio user, I want to pick my command language the first time I open the app, so that the speech recogniser and all spoken feedback use the language I expect from the very first command.

**Acceptance criteria:**

- On first launch, before the microphone is initialised, the app presents a modal language picker showing two options: "English" and "Dansk"
- The picker is non-dismissible by drag, swipe-down, or tap-outside; the user must tap one of the two options to proceed
- Tapping "English" sets `LanguageService.activeLanguage = .english`, persists the choice, and sets the new "has explicitly chosen" flag to `true`
- Tapping "Dansk" sets `LanguageService.activeLanguage = .danish`, persists the choice, and sets the new "has explicitly chosen" flag to `true`
- After the picker is dismissed, the speech recogniser starts using the chosen locale (`en-US` or `da-DK`) without requiring an app restart
- On every subsequent launch (after the flag is `true`), the picker does not appear; the persisted language is used
- If the user uninstalls and reinstalls the app, the picker appears again (clean slate)
- The picker uses the existing Liquid Glass material and design tokens; visual styling matches `ConfirmationSheet`

### US-10 — Hear an explanation when a command is not understood

> As a Voxio user, I want the app to tell me out loud when it didn't understand my command, so that I know to try again rather than wondering if the microphone failed.

**Acceptance criteria:**

- When the parsed command's `intent` is `.unknown`, the app speaks the existing `voiceNotRecognised` string in the active language: *"Sorry, I didn't catch that. Please repeat your command"* (EN) / *"Undskyld, jeg forstod ikke det. Gentag venligst din kommando"* (DA)
- The same string is also surfaced visually via the existing `coordinator.announce(_:)` path (no new toast or label is introduced)
- The existing transcript-clear behaviour still fires, so the unrecognised text disappears within 5 seconds (US-12)
- Spoken feedback uses the same TTS voice configuration as confirmations (E-08 T-0802)
- Voice recognition is paused while the feedback is being spoken (existing `coordinator.onSpeechWillStart` / `onSpeechDidEnd` pause/resume hooks remain authoritative)
- The behaviour fires for both the confirmation-pending path (when the user says something other than confirm/cancel during a confirmation) and the regular command path; today only the regular command path is silent — see Open Question 2

### US-11 — See a getting-started hint on first launch

> As a first-time Voxio user with at least one discovered speaker, I want a single concrete example of how to phrase a command, so that I know what to say without having to read documentation.

**Acceptance criteria:**

- After the language picker is dismissed AND at least one speaker has been discovered AND the user has not previously dismissed the hint (`hasSeenHint == false`), the app shows a hint card inside the voice feedback area
- The hint card uses the name of the first discovered speaker (e.g. "Beolab 28") and shows three concrete example phrases in the active language; suggested copy:
    - **English:** "Try saying:", followed by `"<Speaker name>, play"`, `"<Speaker name>, pause"`, `"<Speaker name>, volume 50"`
    - **Danish:** "Prøv at sige:", followed by `"<Højttalernavn>, afspil"`, `"<Højttalernavn>, pause"`, `"<Højttalernavn>, lydstyrke 50"`
- The card is dismissible: tapping a "Got it" / "OK" affordance sets `hasSeenHint = true` and hides the card
- The card auto-hides as soon as the user starts speaking (i.e. when `transcript` becomes non-empty); auto-hiding does NOT set `hasSeenHint = true` so the card returns on the next launch if the user has not explicitly dismissed it — see Open Question 3
- A small "?" button in `statusBar` (next to `ConnectionStatusChip`) lets the user re-show the hint at any time, regardless of `hasSeenHint`; tapping the "?" while the hint is visible toggles it off
- When `hasSeenHint == true`, the hint does not appear automatically on launch; only the "?" button can summon it
- The hint card does not appear while a confirmation sheet is presented or while the app is reading back a spoken response
- The hint card respects Reduce Motion (cross-fade only) and Dynamic Type (text scales with the user's preference)

### US-12 — See the transcript auto-clear after every command

> As a Voxio user, I want the text of my last spoken command to clear from the screen a few seconds after each command, so that the screen does not look stale and I am not unsure whether the app heard the next thing I said.

**Acceptance criteria:**

- After the final transcription is delivered (`voiceToText.onFinalTranscript`), the visible `transcript` clears 5 seconds later regardless of branch:
    - Successful command (confirmed and dispatched, e.g. play favorite, set volume)
    - Cancelled command (user said "no" or tapped Cancel, or confirmation timed out)
    - Failed command (e.g. `.speakerUnreachable`, `.favoriteNotFound`, `.nothingPlaying`)
    - Unrecognised command (`.unknown` intent — already covered today)
    - No-speaker-resolved path (`.noSpeakerSpoken` error)
- The 5-second timer starts from the moment the final-transcript handler returns; if a new transcription arrives before the timer fires, the new transcription replaces the old text and the timer is restarted (no flicker between old and empty before the new one shows)
- The clear is animated using the existing `.transition(.opacity)` / `.animation(.easeIn(duration: 0.15), value: transcript)` modifiers on the transcript label — no new animation primitives
- The clear must NOT fire while a confirmation sheet is on screen; the timer is paused for the duration of the sheet and resumes (or restarts at 5 s) once the sheet is dismissed — see Open Question 4
- Implementation reuses the existing `clearTranscriptAfterDelay()` method; no new utility is added

---

## Error States

| Scenario | Expected Behaviour |
|---|---|
| User taps neither button in the language picker and backgrounds the app | App stays in pre-language state; on relaunch the picker is shown again. No language is persisted. |
| Language picker is somehow dismissed without a selection (defensive) | Treat as if `hasExplicitlyChosen == false`; on next foregrounding, present the picker again. Microphone is not started until a language is chosen. |
| Command parses to `.unknown` intent | Speak and display *"Sorry, I didn't catch that. Please repeat your command"* (EN) / *"Undskyld, jeg forstod ikke det. Gentag venligst din kommando"* (DA). Transcript clears within 5 s. |
| Command parses to `.unknown` intent during a pending confirmation | Behaviour during confirmation-pending is decided per Open Question 2; default until resolved is to keep current behaviour (silent ignore other than the existing confirm/cancel parse). |
| Hint card requested via "?" but no speakers are discovered yet | Show the hint card with placeholder copy: "Looking for speakers… Once one is found you can say e.g. 'Beolab, play'." (EN) / "Leder efter højttalere… Når en er fundet kan du f.eks. sige 'Beolab, afspil'." (DA). Replace with a real speaker name as soon as discovery resolves one. |
| Hint shown automatically (first launch) but user backgrounds the app before dismissing | On next foreground, show the hint again (since `hasSeenHint == false`). Same logic as initial launch. |
| Transcript clear timer fires while confirmation sheet is on screen | Timer is suppressed; transcript remains visible. After sheet dismissal, the timer is started fresh from 0 with a new 5-second window. |
| Transcript clear timer fires while a new transcription is already showing | The newer transcription wins; the existing timer for the older transcription is cancelled and a new 5-second timer is started for the new transcription. |
| User changes language via the existing settings affordance after first launch | No language picker is shown. `LanguageService.setLanguage(_:)` updates the recogniser as it does today; `hasExplicitlyChosen` remains `true`. |

---

## Non-Functional Requirements

- **Latency — language picker:** Picker appears within 500 ms of `HomeView.onAppear` on first launch; no microphone setup or mDNS scan happens until the user has chosen.
- **Latency — unknown-command feedback:** Spoken feedback begins within 500 ms of the final transcription delivering an `.unknown` intent.
- **Latency — transcript clear:** The fixed 5-second delay defined by `clearTranscriptAfterDelay()` must not vary by more than ±200 ms.
- **Privacy:** No new data leaves the device. Language preference, hint-dismissal flag, and transcript values are all local-only (`UserDefaults` and in-memory state).
- **Accessibility — language picker:** Both options are at least 44 × 44 pt tap targets; VoiceOver reads each option's label; the picker posts a VoiceOver announcement on appear stating "Choose your command language." / "Vælg dit kommandosprog."
- **Accessibility — hint card:** Hint copy is fully VoiceOver-readable; the dismiss control has an explicit `accessibilityLabel`; "?" button has label "Show getting-started hint" / "Vis kom-godt-i-gang-tip".
- **Accessibility — Reduce Motion:** All new animations (picker presentation, hint card appear/dismiss) honour `UIAccessibility.isReduceMotionEnabled` (cross-fade fallback); see E-13 T-1304.
- **Accessibility — Dynamic Type:** Picker option labels and hint card text scale with the user's preferred size; layout must remain legible at the largest accessibility size.
- **Localization:** All new user-facing strings exist in both English and Danish at ship time; no string falls back to English for a Danish user (see E-17 conventions).
- **Persistence durability:** Language preference and hint-dismissal flag persist across app launches and OS restarts; they are cleared only on app uninstall (standard `UserDefaults` lifetime).
- **Resource usage:** No additional background tasks, timers, or observers beyond the existing 5-second `Task.sleep` used by `clearTranscriptAfterDelay()`.

---

## Open Questions

1. **Does `LanguageService` need to expose a separate `hasExplicitlyChosen` flag, or should the existence of any value at the `com.voxio.activeLanguage` UserDefaults key be treated as "user has chosen"?** — Owner: architect. Default assumption: introduce an explicit `hasExplicitlyChosen: Bool` flag stored under `com.voxio.activeLanguage.hasExplicitlyChosen` so that future device-locale-derived defaults remain distinguishable from explicit user choices. The current `LanguageService` writes to `UserDefaults` only when `setLanguage(_:)` is called, so the existence of the key is itself a decent proxy — but the explicit flag is more robust against future refactors.

2. **When `intent == .unknown` is received during a pending confirmation (i.e. the user says something that is neither "yes" nor "no"), should we (a) keep current behaviour and silently ignore, (b) speak `voiceNotRecognised` and continue waiting, or (c) speak something more specific like "Please say yes or no"?** — Owner: product. Default assumption: option (b) — speak `voiceNotRecognised` and remain in pending state until the existing 10-second confirmation timeout elapses. This is consistent with US-10's intent. Option (c) would require a new string in both languages, which extends scope.

3. **Does auto-hide of the hint card (when the user starts speaking) mark the hint as "seen", or only an explicit tap on "Got it"?** — Owner: product. Default assumption: only an explicit dismissal sets `hasSeenHint = true`. Auto-hide just hides the current view; the hint returns on the next launch until the user explicitly dismisses it. This protects users who accidentally trigger the recogniser before they have read the hint.

4. **When the confirmation sheet is on screen, is the transcript timer paused or simply suppressed?** — Owner: architect. Default assumption: suppressed — the existing `clearTranscriptAfterDelay()` schedules a `Task.sleep` and unconditionally writes `transcript = ""` when it wakes; we change it to check `coordinator.isPending` at wake-time and, if true, reschedule itself for another 5 seconds. This is one extra branch and avoids introducing a true pause/resume mechanism.

5. **Hint copy review and translation sign-off.** — Owner: product (copy) + Danish reviewer (translation). Default assumption: ship with the copy proposed in US-11 acceptance criteria above. Final translations should be reviewed by a native Danish speaker for tone consistency with the existing UI strings in `UIStrings.danish`.

6. **Where exactly does the "?" button live in `statusBar`?** — Owner: design. Default assumption: leading edge of `statusBar`, mirroring `ConnectionStatusChip` on the trailing edge. Both elements share the same vertical alignment and padding (20 pt horizontal, 8 pt top — matches `HomeView.swift:114–115`). A separate design review may want to revisit placement.

7. **Should the language picker also be reachable post-first-launch via the same "?" affordance, or stay reserved for first launch?** — Owner: product. Default assumption: stay reserved for first launch. Language change after first launch continues to use the existing E-17 T-1710 settings affordance (long-press on `ConnectionStatusChip` or a dedicated row). Conflating the picker with the hint button risks accidental language switches.

---

## Resolved Decisions

| Question | Decision |
|---|---|
| Reuse the existing `voiceNotRecognised` string for `.unknown` intent feedback, or introduce a new "I didn't understand" string? | Reuse existing. Both EN and DA strings already exist in `ErrorStrings`; no new copy is needed. |
| Does `AppError.voiceNotRecognised` already exist? | Yes — confirmed in `iOS/Voxio/Core/AppError.swift` (line 12 of the enum). No new error case needs to be added. |
| Is `ParsedCommand.intent == .unknown` the correct E-18 signal for unrecognised commands? | Yes — confirmed in `iOS/Voxio/Core/CommandParsing/ParsedCommand.swift`. `CommandIntent.unknown` is the last enum case; `ParsedCommand.unknown(_ text:)` is the static factory used by both parser paths. |
| Surface the unknown-command feedback as a toast or via the existing announce path? | Use existing `coordinator.announce(_:)` path — same pipeline as every other error today. Avoids introducing a new UI primitive. |
| Use `@AppStorage` or `LanguageService` for the language preference? | Use `LanguageService` — it already exists, already persists to `UserDefaults`, already has `setLanguage(_:)`, and is observed throughout the app via `@ObservedObject`. Adding `@AppStorage` would create two sources of truth. |
| Use `@AppStorage` or a dedicated service for the hint-dismissal flag? | Use `@AppStorage("hasSeenHint")` directly in `HomeView`. The flag is view-local, single Boolean, never read from anywhere else; a service would be overkill. |
| Show the hint as a sheet, an overlay, or in the voice feedback area? | In the voice feedback area. The area is empty when no transcript is showing; reusing it avoids introducing a new layer. |
| Build a new "PleaseTryAgain"-style error case or reuse `voiceNotRecognised`? | Reuse `voiceNotRecognised`. (Same reasoning as above.) |
| Add a new utility for transcript auto-clearing or reuse `clearTranscriptAfterDelay()`? | Reuse. The method already exists at `HomeView.swift:368` and is correct; the gap is just in where it is called from. |
| Should the language picker offer a "Detect from device" option in addition to the two explicit choices? | No. The current `Language.fromLocale()` behaviour is the silent default; the picker exists to make the choice explicit. Adding a third option re-introduces the ambiguity the picker is meant to resolve. |
| Should the picker block app launch entirely (full-screen) or present as a sheet? | Sheet, non-dismissible. Matches the rest of the app's modal patterns; a full-screen onboarding flow is over-engineering for two buttons. |
| When the user changes language post-first-launch, should the hint reappear in the new language? | No. `hasSeenHint` persists across language changes. The hint is a one-time-by-default "what is this app" prompt, not a per-language tutorial. (Re-show via the "?" button is always available.) |

---

## Glossary

- **First launch:** The first time the app runs after install (or after the user uninstalls and reinstalls), determined by the absence of the persisted language-chosen flag in `UserDefaults`.
- **Active language:** `LanguageService.shared.activeLanguage` — drives speech recognition locale, TTS voice, command keywords, and all UI strings.
- **Final transcript:** The string delivered by `voiceToText.onFinalTranscript` after `SFSpeechRecognizer` finalises a recognition request (after ~1.5 s of silence following speech, per E-03 T-0303).
- **Voice feedback area:** The `voiceFeedback` `VStack` in `HomeView.swift:155–177` — contains the waveform, the live transcript label, and the mic status line.
- **`.unknown` intent:** `ParsedCommand.intent == .unknown` (E-18) or `VoiceCommand == .unknown` (E-03 legacy path); both represent a transcription that did not match any recognised pattern.
