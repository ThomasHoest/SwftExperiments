# Epics & Tasks: Bang & Olufsen Voice Controller
**Version:** 1.0  
**Status:** Draft  
**Date:** 2026-04-28  
**References:** functional-spec-bo-voice-control v1.2, design-spec-bo-voice-control v1.0

---

## Overview

This document breaks the functional and design specifications into epics and their constituent tasks. Each epic maps to a coherent area of the product. Tasks are written at a level where a single developer can pick one up and complete it independently.

---

## Epic Index

| # | Epic | User Stories |
|---|---|---|
| E-01 | Project Foundation & Architecture | — |
| E-02 | Mozart API Integration | US-00 |
| E-03 | Voice Recognition & Command Parsing | US-00 through US-08 |
| E-04 | Speaker Addressing | US-00 |
| E-05 | Playback — Favorites | US-01, US-02, US-03 |
| E-06 | Playback — Stop, Pause & Resume | US-04, US-05 |
| E-07 | Volume Control | US-06, US-07, US-08 |
| E-08 | Confirmation & Feedback Loop | US-01 through US-08 |
| E-09 | Error Handling | All US |
| E-10 | UI — Home & Speaker Card | Design spec §Screen 1, 2, 4 |
| E-11 | UI — Confirmation Sheet | Design spec §Screen 3 |
| E-12 | UI — Toasts & Notifications | Design spec §Screen 5, 6 |
| E-13 | Accessibility | Design spec §Accessibility |
| E-14 | Polish — Animation & Haptics | Design spec §Interaction |

---

## E-01 — Project Foundation & Architecture

Establish the Xcode project, dependency structure, and architectural patterns that all other epics build on.

- [ ] **T-0101** Create Xcode project targeting iOS 26, Swift 6, minimum deployment iOS 25
- [ ] **T-0102** Set up folder structure: `Features/`, `Core/`, `DesignSystem/`, `Resources/`
- [ ] **T-0103** Define app architecture pattern (e.g. MVVM + Coordinator or TCA) and document the decision
- [ ] **T-0104** Add SwiftLint and configure rules file aligned to project conventions
- [ ] **T-0105** Configure light and dark mode support; verify system colour adaptation on launch
- [ ] **T-0106** Add design token file (`DesignTokens.swift`) with all spacing, radius, animation, and material constants from the design spec
- [ ] **T-0107** Add colour asset catalogue with all named colours from the design spec (`accent`, `bgPrimary`, `labelPrimary`, etc.) for both light and dark appearances
- [ ] **T-0108** Set up CI pipeline (e.g. Xcode Cloud or GitHub Actions) with build and test stages
- [ ] **T-0109** Configure app permissions in `Info.plist`: microphone usage description, local network usage description

---

## E-02 — Mozart API Integration

Build the networking layer that communicates with the Bang & Olufsen Mozart API for all speaker operations.

- [ ] **T-0201** Research and document the Mozart API endpoints required: list speakers, list favorites, play favorite, stop, pause, resume, get volume, set volume, mute, unmute
- [ ] **T-0202** Create `MozartAPIClient` — a single entry point for all API calls, configured with base URL and auth handling
- [ ] **T-0203** Implement `GET /speakers` — fetch available speakers; parse response into `Speaker` model
- [ ] **T-0204** Implement `GET /speakers/{id}/favorites` — fetch favorites for a given speaker; parse into `[Favorite]` model
- [ ] **T-0205** Implement `POST /speakers/{id}/play` — trigger playback of a named favorite
- [ ] **T-0206** Implement `POST /speakers/{id}/stop` — stop playback
- [ ] **T-0207** Implement `POST /speakers/{id}/pause` — pause playback
- [ ] **T-0208** Implement `POST /speakers/{id}/resume` — resume from paused position
- [ ] **T-0209** Implement `GET /speakers/{id}/volume` — read current volume level (integer 0–100)
- [ ] **T-0210** Implement `POST /speakers/{id}/volume` — set absolute volume level
- [ ] **T-0211** Implement `POST /speakers/{id}/mute` and `POST /speakers/{id}/unmute`
- [ ] **T-0212** Add timeout handling — surface a `MozartError.timeout` when the API does not respond within 5 seconds
- [ ] **T-0213** Add offline/unreachable detection — surface a `MozartError.unreachable` when the speaker cannot be reached
- [ ] **T-0214** Write unit tests for each API method using a mock URLSession; cover success and error cases
- [ ] **T-0215** Write integration tests against a local Mozart API stub or sandbox environment

---

## E-03 — Voice Recognition & Command Parsing

Implement the full pipeline from microphone input to a structured `VoiceCommand` value that other features can act on.

- [ ] **T-0301** Integrate `SFSpeechRecognizer` with the `en-US` locale; request microphone and speech recognition permissions on first launch
- [ ] **T-0302** Build `VoiceInputManager` — starts and stops a live `SFSpeechAudioBufferRecognitionRequest`; publishes real-time transcription strings
- [ ] **T-0303** Implement silence detection — finalise a recognition request after ~1.5 s of silence following speech
- [ ] **T-0304** Define `VoiceCommand` enum covering all intents: `.playNamed`, `.playDefault`, `.listFavorites`, `.stop`, `.pause`, `.resume`, `.setVolume`, `.adjustVolume`, `.mute`, `.unmute`, `.confirm`, `.cancel`, `.unknown`
- [ ] **T-0305** Build `CommandParser` — takes a raw transcription string, strips the leading speaker name token, and returns a `VoiceCommand`
- [ ] **T-0306** Implement intent matching for play commands: exact match and fuzzy match (Levenshtein distance ≤ 2) against known favorite names
- [ ] **T-0307** Implement intent matching for volume commands: parse absolute values ("set volume to 42") and relative values ("up 20", "louder")
- [ ] **T-0308** Implement intent matching for stop / pause / resume / mute / unmute commands
- [ ] **T-0309** Implement `.confirm` and `.cancel` recognition ("Yes", "No", "Cancel") for the confirmation step
- [ ] **T-0310** Handle `.unknown` — any transcription that does not match a known pattern returns `.unknown` with the raw string for error feedback
- [ ] **T-0311** Write unit tests for `CommandParser` covering all intents, edge cases, and partial matches
- [ ] **T-0312** Ensure voice recognition is fully stopped and deallocated when the app moves to background

---

## E-04 — Speaker Addressing

Enforce that every command begins with a recognised speaker name and route the command to the correct speaker.

- [ ] **T-0401** On app launch, call `GET /speakers` and populate a `SpeakerRegistry` with available speaker names and IDs
- [ ] **T-0402** Build `SpeakerNameMatcher` — given the first token(s) of a transcription, returns the best-matching `Speaker` or `nil`; uses case-insensitive fuzzy matching (Levenshtein distance ≤ 2)
- [ ] **T-0403** Integrate `SpeakerNameMatcher` as the first step in `CommandParser` — reject the command if no speaker match is found
- [ ] **T-0404** When no speaker name is recognised, trigger the "no speaker" error response: speak *"Please start your command with a speaker name"* and list available speakers
- [ ] **T-0405** Expose the active speaker through `SpeakerRegistry.activeSpeaker` — updated each time a command successfully addresses a speaker
- [ ] **T-0406** Handle the single-speaker case — still require the speaker name; no implicit default
- [ ] **T-0407** Write unit tests for `SpeakerNameMatcher` covering exact matches, case variants, minor mispronunciations, and unrecognised names

---

## E-05 — Playback — Favorites

Implement the three playback-from-favorites user stories end to end.

- [ ] **T-0501** Build `FavoritesService` — wraps `MozartAPIClient.fetchFavorites(for:)` and exposes a method to resolve a spoken name to a `Favorite` using fuzzy matching
- [ ] **T-0502** Implement `PlayNamedFavoriteUseCase` — receives `(speaker, favoriteName)`, fetches favorites, resolves the match, builds confirmation string *"Playing [favorite name] on [speaker name]"*, and returns it for confirmation
- [ ] **T-0503** On confirmation, call `MozartAPIClient.play(favorite:on:)` and verify playback begins within 3 seconds; surface a timeout error if not
- [ ] **T-0504** Implement "favorite not found" path — speak and display *"[Favorite name] was not found on [speaker name]. Available favorites are: [list]"*
- [ ] **T-0505** Implement `PlayDefaultFavoriteUseCase` — resolves the last-played favorite from local session state, or falls back to the first favorite in the Mozart API response; builds confirmation string *"Playing [resolved name] on [speaker name]"*
- [ ] **T-0506** Persist last-played favorite per speaker in `UserDefaults` scoped to the session; cleared on app termination
- [ ] **T-0507** Implement `ListFavoritesUseCase` — fetches favorites live from the Mozart API, builds a spoken list, and appends the prompt *"Say '[Speaker name], play [favorite name]' to start playing"*
- [ ] **T-0508** Write unit tests for `FavoritesService` fuzzy matching; cover exact, near-match, and no-match cases
- [ ] **T-0509** Write unit tests for all three use cases using mock API client and mock speaker registry

---

## E-06 — Playback — Stop, Pause & Resume

Implement stop, pause, and resume commands with full confirmation and error handling.

- [ ] **T-0601** Implement `StopPlaybackUseCase` — builds confirmation string *"Stopping playback on [speaker name]"*; on confirm calls `MozartAPIClient.stop(speaker:)`
- [ ] **T-0602** Handle "nothing playing" — if the API returns a not-playing status, speak *"[Speaker name] is not currently playing anything"* without showing the confirmation sheet
- [ ] **T-0603** Implement `PausePlaybackUseCase` — builds confirmation string *"Pausing [speaker name]"*; on confirm calls `MozartAPIClient.pause(speaker:)`
- [ ] **T-0604** Implement "pause not supported" path — if the Mozart API indicates the source does not support pause, speak *"[Speaker name] does not support pause for this source. Say '[Speaker name], stop' to stop instead"*
- [ ] **T-0605** Implement `ResumePlaybackUseCase` — builds confirmation string *"Resuming [speaker name]"*; on confirm calls `MozartAPIClient.resume(speaker:)`
- [ ] **T-0606** Write unit tests for all three use cases; cover success, nothing-playing, and pause-unsupported paths

---

## E-07 — Volume Control

Implement absolute volume, relative volume adjustment, mute, and unmute.

- [ ] **T-0701** Implement `SetVolumeUseCase` — validates input is 0–100; builds confirmation string *"Setting [speaker name] volume to [value]"*; on confirm calls `MozartAPIClient.setVolume(value:speaker:)`; on completion speaks *"[Speaker name] volume is now [value]"*
- [ ] **T-0702** Implement `AdjustVolumeUseCase` — fetches current volume via `MozartAPIClient.getVolume(speaker:)`; calculates new value (clamp 0–100); builds confirmation string *"Changing [speaker name] volume from [current] to [new value]"*
- [ ] **T-0703** Implement volume clamping — when the result hits 0 or 100 speak *"[Speaker name] is already at [maximum/minimum] volume"* and skip the confirmation sheet
- [ ] **T-0704** Implement default relative step of 10 when no amount is spoken; apply named increment when one is provided
- [ ] **T-0705** Implement `MuteUseCase` — fetches current volume; builds confirmation string *"Muting [speaker name] (currently at volume [value])"*; on confirm calls `MozartAPIClient.mute(speaker:)`; stores pre-mute volume in session state
- [ ] **T-0706** Implement idempotent mute — if already muted, speak *"[Speaker name] is already muted"* and skip confirmation sheet
- [ ] **T-0707** Implement `UnmuteUseCase` — reads stored pre-mute volume; builds confirmation string *"Unmuting [speaker name], restoring volume to [value]"*; on confirm calls `MozartAPIClient.unmute(speaker:)`
- [ ] **T-0708** Write unit tests for all volume use cases; cover boundary values (0, 1, 99, 100), default step, named step, already-muted, and already-at-limit paths

---

## E-08 — Confirmation & Feedback Loop

Implement the cross-cutting confirmation pattern shared by all commands — read-back, voice confirmation, and spoken completion.

- [ ] **T-0801** Build `ConfirmationCoordinator` — receives a confirmation string from any use case; speaks it aloud via `AVSpeechSynthesizer`; publishes `.pending` state to the UI; listens for `.confirm` or `.cancel` from `VoiceInputManager`
- [ ] **T-0802** Configure `AVSpeechSynthesizer` with `com.apple.voice.compact.en-US.Samantha` voice, speech rate 0.5; fall back to system default English if voice is unavailable
- [ ] **T-0803** Ensure voice recognition is paused while `AVSpeechSynthesizer` is speaking to prevent feedback loops; resume recognition immediately after speech ends
- [ ] **T-0804** Implement tap-to-confirm fallback — "Yes" and "No" buttons in the confirmation sheet trigger the same `.confirm` / `.cancel` path as voice
- [ ] **T-0805** Implement confirmation timeout — if neither voice nor tap confirmation is received within 10 seconds, auto-cancel and speak *"Action cancelled"*
- [ ] **T-0806** Implement post-action spoken completion feedback (e.g. *"[Speaker name] volume is now [value]"*) for use cases that specify it
- [ ] **T-0807** Write unit tests for `ConfirmationCoordinator`; cover confirm-by-voice, cancel-by-voice, confirm-by-tap, cancel-by-tap, and timeout paths

---

## E-09 — Error Handling

Centralise all error states and ensure every failure surfaces a clear, spoken, and visual response.

- [ ] **T-0901** Define `AppError` enum covering all error cases from the functional spec: `.noSpeakerSpoken`, `.speakerNotFound`, `.favoriteNotFound`, `.speakerUnreachable`, `.nothingPlaying`, `.volumeAtLimit`, `.pauseNotSupported`, `.alreadyMuted`, `.voiceNotRecognised`, `.apiTimeout`
- [ ] **T-0902** Build `ErrorResponseService` — maps each `AppError` to its exact spoken and display string from the functional spec
- [ ] **T-0903** Ensure all use cases surface errors through `ErrorResponseService` rather than ad-hoc strings
- [ ] **T-0904** Implement graceful API degradation — when `MozartError.timeout` or `MozartError.unreachable` is received, surface the appropriate `AppError` without crashing
- [ ] **T-0905** Ensure the app never crashes on network loss; write a test that simulates network unavailability mid-command
- [ ] **T-0906** Write unit tests for `ErrorResponseService`; verify every `AppError` maps to the correct string from the functional spec

---

## E-10 — UI — Home & Speaker Card

Build the primary screen: idle state, command recognition state, and now-playing state.

- [ ] **T-1001** Implement `HomeView` with full-bleed background showing the user's iOS wallpaper through a Liquid Glass layer; fall back to deep-charcoal gradient if wallpaper is unavailable
- [ ] **T-1002** Implement `SpeakerCard` — Liquid Glass rounded rect (corner radius 20 pt), horizontally inset 20 pt from screen edges; displays speaker name (SF Pro Display Semibold 34 pt) and playback status subtitle
- [ ] **T-1003** Implement idle waveform animation — five bars pulsing at ~1 Hz in accent gold (`#C8A97E`) when the app is listening; bars animate to voice amplitude in real time during speech
- [ ] **T-1004** Implement `SpeakerSelectorPill` — horizontally scrollable Liquid Glass pill row at the bottom of the screen, 12 pt above home indicator; active speaker highlighted with gold tint; snaps to centre on selection
- [ ] **T-1005** Implement connection status chip — compact Liquid Glass pill in the top trailing corner; green tint for online, gray for offline; uses SF Symbol `wifi.slash` for offline state
- [ ] **T-1006** Implement card expand animation for command recognition state — scale to 1.02 with spring (damping 0.7, response 0.4 s)
- [ ] **T-1007** Implement live transcription label below the card during command recognition — SF Pro Text 17 pt; fades in at 0.15 s; text updates with character-by-character reveal
- [ ] **T-1008** Implement now-playing inset panel within the speaker card — secondary Liquid Glass panel showing track/station name and three-bar animated playback indicator in accent gold
- [ ] **T-1009** Implement volume track below the card in now-playing state — horizontal Liquid Glass slider, accent gold fill, trailing volume label; display only, not interactive (voice-only control)
- [ ] **T-1010** Implement iOS 26 materialisation animation on app launch for the speaker card
- [ ] **T-1011** Implement specular highlight on the speaker card top edge responding to device tilt via CoreMotion
- [ ] **T-1012** Respect Dynamic Island — no UI elements overlap with the Dynamic Island area

---

## E-11 — UI — Confirmation Sheet

Build the bottom sheet that appears for every confirmation step.

- [ ] **T-1101** Implement `ConfirmationSheet` as a SwiftUI `.sheet` with `presentationDetents([.height(280)])`; no drag handle; drag-to-dismiss disabled
- [ ] **T-1102** Apply Liquid Glass material to the sheet surface with medium blur radius
- [ ] **T-1103** Implement sheet content layout: "About to:" label in `--label-secondary` (SF Pro Text 12 pt), action read-back text in SF Pro Display Regular 22 pt, "Yes" and "No" buttons full-width stacked
- [ ] **T-1104** Implement "Yes" button — filled Liquid Glass button with accent gold tint; triggers `ConfirmationCoordinator.confirm()`
- [ ] **T-1105** Implement "No" button — outlined Liquid Glass button; triggers `ConfirmationCoordinator.cancel()`
- [ ] **T-1106** Implement "or say Yes / No" mic indicator pill at the top of the sheet
- [ ] **T-1107** Implement sheet entry animation — slide up from below with spring (damping 0.75, response 0.5 s)
- [ ] **T-1108** Trigger `.medium` haptic impact when the sheet appears
- [ ] **T-1109** Trigger `.success` notification haptic on confirmation; dismiss the sheet and show a brief success toast
- [ ] **T-1110** Ensure all elements in the sheet respect bottom safe area insets

---

## E-12 — UI — Toasts & Notifications

Build the non-blocking toast system used for errors and volume limit notifications.

- [ ] **T-1201** Implement `ToastView` — Liquid Glass pill/banner that slides down from the top safe area with spring (damping 0.8); auto-dismisses after 4 seconds with fade + slide-up exit
- [ ] **T-1202** Implement error toast variant — icon (`exclamationmark.bubble` in `--label-secondary`), message text SF Pro Text 15 pt, using the exact string from `ErrorResponseService`
- [ ] **T-1203** Implement expandable list within the error toast for errors that include a list (e.g. available favorites); compact scrollable list beneath the message
- [ ] **T-1204** Implement volume limit toast variant — icon (`speaker.slash` or `speaker.wave.3`), accent tint on icon only, neutral label text
- [ ] **T-1205** Implement success toast — brief green-tinted pill after a confirmed action completes; auto-dismisses after 2 seconds
- [ ] **T-1206** Trigger `.error` notification haptic when an error toast appears; trigger `.warning` for volume limit toast
- [ ] **T-1207** Ensure toasts do not overlap the Dynamic Island; respect top safe area inset

---

## E-13 — Accessibility

Ensure the app is fully usable with VoiceOver, Dynamic Type, Reduce Motion, and Increase Contrast.

- [ ] **T-1301** Add `accessibilityLabel` to every interactive element: speaker card, speaker selector pills, confirm button, cancel button, connection status chip
- [ ] **T-1302** Ensure `ConfirmationSheet` posts a VoiceOver announcement when it appears, reading the full action read-back string
- [ ] **T-1303** Audit all text elements for Dynamic Type support; verify card height expands gracefully at the largest accessibility size
- [ ] **T-1304** Implement Reduce Motion path — detect `UIAccessibility.isReduceMotionEnabled`; replace all spring animations with 0.2 s cross-fades; replace waveform animation with static pulsing opacity
- [ ] **T-1305** Implement Increase Contrast path — reduce Liquid Glass blur; add 1 pt border in `--label-secondary` to all glass surfaces
- [ ] **T-1306** Audit colour usage — verify accent gold is never the sole differentiator for any state; every colour cue has a companion icon or label
- [ ] **T-1307** Verify all tappable elements meet the 44 × 44 pt minimum tap target
- [ ] **T-1308** Run the Accessibility Inspector against all six screens; resolve any reported issues

---

## E-14 — Polish — Animation & Haptics

Implement the full animation and haptic system as specified in the design spec.

- [ ] **T-1401** Implement `HapticEngine` wrapper around `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator`; expose named methods (`commandRecognised()`, `sheetAppeared()`, `actionConfirmed()`, `errorOccurred()`, `limitReached()`)
- [ ] **T-1402** Wire `HapticEngine.commandRecognised()` (`.light` impact) to the moment `CommandParser` returns a valid command
- [ ] **T-1403** Wire `HapticEngine.sheetAppeared()` (`.medium` impact) to `ConfirmationSheet` `onAppear`
- [ ] **T-1404** Wire `HapticEngine.actionConfirmed()` (`.success` notification) to the confirmation tap/voice path
- [ ] **T-1405** Wire `HapticEngine.errorOccurred()` (`.error` notification) to error toast presentation
- [ ] **T-1406** Wire `HapticEngine.limitReached()` (`.warning` notification) to volume limit toast presentation
- [ ] **T-1407** Implement shared element transition for all screen state changes anchored on the speaker card
- [ ] **T-1408** Implement iOS 26 materialisation animation for the speaker card on app launch
- [ ] **T-1409** Audit all animations against the Reduce Motion flag — confirm every animation has a cross-fade fallback (see T-1304)
- [ ] **T-1410** Profile animation performance on a minimum-spec supported device (iPhone with A15 chip); confirm 60 fps throughout all transitions

---

## Task Summary

| Epic | Tasks | Notes |
|---|---|---|
| E-01 Foundation | 9 | Prerequisite for all other epics |
| E-02 Mozart API | 15 | Prerequisite for E-05 through E-07 |
| E-03 Voice Recognition | 12 | Prerequisite for E-04 through E-08 |
| E-04 Speaker Addressing | 7 | Prerequisite for E-05 through E-07 |
| E-05 Playback — Favorites | 9 | Depends on E-02, E-03, E-04, E-08 |
| E-06 Playback — Stop/Pause/Resume | 6 | Depends on E-02, E-03, E-04, E-08 |
| E-07 Volume Control | 8 | Depends on E-02, E-03, E-04, E-08 |
| E-08 Confirmation & Feedback | 7 | Depends on E-03 |
| E-09 Error Handling | 6 | Depends on E-02, E-03 |
| E-10 UI — Home & Speaker Card | 12 | Depends on E-01 |
| E-11 UI — Confirmation Sheet | 10 | Depends on E-08, E-10 |
| E-12 UI — Toasts | 7 | Depends on E-09, E-10 |
| E-13 Accessibility | 8 | Depends on E-10, E-11, E-12 |
| E-14 Animation & Haptics | 10 | Depends on E-10, E-11, E-12 |
| **Total** | **126** | |
