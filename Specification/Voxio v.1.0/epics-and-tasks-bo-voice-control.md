# Epics & Tasks: Bang & Olufsen Voice Controller
**Version:** 1.3  
**Status:** Draft  
**Date:** 2026-04-29  
**References:** functional-spec-bo-voice-control v1.3, design-spec-bo-voice-control v1.0, spec-command-parser-bo-voice-control v1.1  
**Languages:** English (`en-US`) and Danish (`da-DK`) — both fully supported

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
| E-15 | AI-Powered Command Recognition | US-00 through US-08 |
| E-16 | Gen AI Service Authentication | — |
| E-17 | Danish & Multilingual Support | All US |
| E-18 | Robust Command Parsing (Foundation Models + NLModel) | US-00 through US-08 |
| E-19 | Usability Enhancements | US-09 through US-12 |

---

## E-01 — Project Foundation & Architecture

Establish the Xcode project, dependency structure, and architectural patterns that all other epics build on.

- [x] **T-0101** Create Xcode project targeting iOS 26, Swift 6, minimum deployment iOS 25
- [x] **T-0102** Set up folder structure: `Features/`, `Core/`, `DesignSystem/`, `Resources/`
- [ ] **T-0103** Define app architecture pattern (e.g. MVVM + Coordinator or TCA) and document the decision
- [ ] **T-0104** Add SwiftLint and configure rules file aligned to project conventions
- [x] **T-0105** Configure light and dark mode support; verify system colour adaptation on launch
- [x] **T-0106** Add design token file (`DesignTokens.swift`) with all spacing, radius, animation, and material constants from the design spec
- [x] **T-0107** Add colour asset catalogue with all named colours from the design spec (`accent`, `bgPrimary`, `labelPrimary`, etc.) for both light and dark appearances
- [ ] **T-0108** Set up CI pipeline (e.g. Xcode Cloud or GitHub Actions) with build and test stages
- [x] **T-0109** Configure app permissions in `Info.plist`: microphone usage description, local network usage description

---

## E-02 — Mozart API Integration

Build the networking layer that communicates with the Bang & Olufsen Mozart API for all speaker operations.

- [x] **T-0201** Research and document the Mozart API endpoints required: list speakers, list favorites, play favorite, stop, pause, resume, get volume, set volume, mute, unmute
- [x] **T-0202** Create `MozartAPIClient` — a single entry point for all API calls, configured with base URL and auth handling
- [ ] **T-0203** Implement `GET /speakers` — fetch available speakers; parse response into `Speaker` model
- [x] **T-0204** Implement `GET /speakers/{id}/favorites` — fetch favorites for a given speaker; parse into `[Favorite]` model
- [x] **T-0205** Implement `POST /speakers/{id}/play` — trigger playback of a named favorite
- [x] **T-0206** Implement `POST /speakers/{id}/stop` — stop playback
- [x] **T-0207** Implement `POST /speakers/{id}/pause` — pause playback
- [x] **T-0208** Implement `POST /speakers/{id}/resume` — resume from paused position
- [x] **T-0209** Implement `GET /speakers/{id}/volume` — read current volume level (integer 0–100)
- [x] **T-0210** Implement `POST /speakers/{id}/volume` — set absolute volume level
- [x] **T-0211** Implement `POST /speakers/{id}/mute` and `POST /speakers/{id}/unmute`
- [x] **T-0212** Add timeout handling — surface a `MozartError.timeout` when the API does not respond within 5 seconds
- [x] **T-0213** Add offline/unreachable detection — surface a `MozartError.unreachable` when the speaker cannot be reached
- [ ] **T-0214** Write unit tests for each API method using a mock URLSession; cover success and error cases
- [ ] **T-0215** Write integration tests against a local Mozart API stub or sandbox environment

---

## E-03 — Voice Recognition & Command Parsing

Implement the full pipeline from microphone input to a structured `VoiceCommand` value that other features can act on. The recogniser locale is determined by `LanguageService` (E-17); both `en-US` and `da-DK` are supported.

- [x] **T-0301** Integrate `SFSpeechRecognizer` with the `en-US` locale; request microphone and speech recognition permissions on first launch
- [x] **T-0302** Build `VoiceInputManager` — starts and stops a live `SFSpeechAudioBufferRecognitionRequest`; publishes real-time transcription strings
- [x] **T-0303** Implement silence detection — finalise a recognition request after ~1.5 s of silence following speech
- [x] **T-0304** Define `VoiceCommand` enum covering all intents: `.playNamed`, `.playDefault`, `.listFavorites`, `.stop`, `.pause`, `.resume`, `.setVolume`, `.adjustVolume`, `.mute`, `.unmute`, `.confirm`, `.cancel`, `.unknown`
- [x] **T-0305** Build `CommandParser` — takes a raw transcription string, strips the leading speaker name token, and returns a `VoiceCommand`
- [x] **T-0306** Implement intent matching for play-favorite commands: recognise the phrase "play favorite [one|two|three|four]" / "afspil favorit [en|to|tre|fire]" (spoken number words only, no digits) and resolve to a 1-based index 1–4. Each speaker exposes exactly 4 favorites; if the resolved index exceeds the speaker's favorite count, treat as not-found. No fuzzy matching required.
- [x] **T-0307** Implement intent matching for volume commands: parse absolute values ("set volume to 42") and relative values ("up 20", "louder" / "skru op", "højere")
- [x] **T-0308** Implement intent matching for stop / pause / resume / mute / unmute commands (English and Danish keywords)
- [x] **T-0309** Implement `.confirm` and `.cancel` recognition — English: "Yes", "No", "Cancel"; Danish: "Ja", "Jo", "Nej", "Annuller"
- [x] **T-0310** Handle `.unknown` — any transcription that does not match a known pattern returns `.unknown` with the raw string for error feedback
- [ ] **T-0311** Write unit tests for `CommandParser` covering all intents, edge cases, and partial matches
- [x] **T-0312** Ensure voice recognition is fully stopped and deallocated when the app moves to background

---

## E-04 — Speaker Addressing

Discover speakers on the local network via mDNS, maintain a live `SpeakerRegistry`, and route voice commands to the correct speaker. A command may address a speaker explicitly by name or implicitly when exactly one speaker is actively playing.

- [x] **T-0401** On app launch start an mDNS browser for the `_bangolufsen._tcp.` service type (reusing `MdnsDiscovery`); for each resolved IPv4 address call `Speaker.initialize()` and add the speaker to `SpeakerRegistry` on success; remove it if initialisation throws
- [ ] **T-0402** Keep `SpeakerRegistry` live — re-run the mDNS scan on a 15-second interval; add newly appeared speakers and remove speakers whose IPv4 address is no longer resolved
- [x] **T-0403** Build `SpeakerNameMatcher` — given the first token(s) of a transcription, returns the best-matching `Speaker` from the registry or `nil`; uses case-insensitive prefix and fuzzy matching (Levenshtein distance ≤ 2) against each speaker's `friendlyName`
- [x] **T-0404** Implement implicit active-session addressing — if no speaker name token is found at the head of the transcript AND exactly one speaker in the registry has `isPlaying == true`, route the command to that speaker and set it as `activeSpeaker`; if zero or more than one speaker is playing, fall through to the explicit-name-required error path
- [x] **T-0405** Integrate speaker resolution as the first step in the command dispatch pipeline — after resolving the speaker, strip the name token (if present) from the transcript before passing the remainder to `CommandParser`
- [x] **T-0406** When no speaker can be resolved (no name match and no unambiguous active speaker), speak *"Please start your command with a speaker name"* and list discovered speaker names; do not dispatch the command
- [x] **T-0407** Expose `SpeakerRegistry.activeSpeaker: Speaker?` — set to the last successfully addressed speaker; used by the implicit active-session path as a secondary fallback when no speaker is playing but one was recently addressed (within the current app session)
- [ ] **T-0408** Write unit tests for `SpeakerNameMatcher` covering exact match, case variants, minor mispronunciation (distance ≤ 2), distance > 2 (no match), and empty registry
- [ ] **T-0409** Write unit tests for the implicit active-session path covering: one playing speaker (routes correctly), zero playing speakers (falls through), two playing speakers (falls through), and recently-addressed fallback

---

## E-05 — Playback — Favorites

Implement the three playback-from-favorites user stories end to end.

- [x] **T-0501** Build `FavoritesService` — wraps `MozartAPIClient.fetchFavorites(for:)` and exposes a method to resolve a spoken name to a `Favorite` using fuzzy matching
- [ ] **T-0502** Implement `PlayNamedFavoriteUseCase` — receives `(speaker, favoriteName)`, fetches favorites, resolves the match, builds confirmation string *"Playing [favorite name] on [speaker name]"*, and returns it for confirmation
- [ ] **T-0503** On confirmation, call `MozartAPIClient.play(favorite:on:)` and verify playback begins within 3 seconds; surface a timeout error if not
- [ ] **T-0504** Implement "favorite not found" path — speak and display *"[Favorite name] was not found on [speaker name]. Available favorites are: [list]"*
- [x] **T-0505** Implement `PlayDefaultFavoriteUseCase` — resolves the last-played favorite from local session state, or falls back to the first favorite in the Mozart API response; builds confirmation string *"Playing [resolved name] on [speaker name]"*
- [ ] **T-0506** Persist last-played favorite per speaker in `UserDefaults` scoped to the session; cleared on app termination
- [x] **T-0507** Implement `ListFavoritesUseCase` — fetches favorites live from the Mozart API, builds a spoken list, and appends the prompt *"Say '[Speaker name], play [favorite name]' to start playing"*
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

- [x] **T-0801** Build `ConfirmationCoordinator` — receives a confirmation string from any use case; speaks it aloud via `AVSpeechSynthesizer`; publishes `.pending` state to the UI; listens for `.confirm` or `.cancel` from `VoiceInputManager`
- [x] **T-0802** Configure `AVSpeechSynthesizer` with `com.apple.voice.compact.en-US.Samantha` voice (English) or the best available `da-DK` system voice (Danish), speech rate 0.5; fall back to the system default voice for the active language if the preferred identifier is unavailable
- [x] **T-0803** Ensure voice recognition is paused while `AVSpeechSynthesizer` is speaking to prevent feedback loops; resume recognition immediately after speech ends
- [x] **T-0804** Implement tap-to-confirm fallback — "Yes" and "No" buttons in the confirmation sheet trigger the same `.confirm` / `.cancel` path as voice
- [x] **T-0805** Implement confirmation timeout — if neither voice nor tap confirmation is received within 10 seconds, auto-cancel and speak *"Action cancelled"*
- [x] **T-0806** Implement post-action spoken completion feedback (e.g. *"[Speaker name] volume is now [value]"*) for use cases that specify it
- [ ] **T-0807** Write unit tests for `ConfirmationCoordinator`; cover confirm-by-voice, cancel-by-voice, confirm-by-tap, cancel-by-tap, and timeout paths

---

## E-09 — Error Handling

Centralise all error states and ensure every failure surfaces a clear, spoken, and visual response.

- [x] **T-0901** Define `AppError` enum covering all error cases from the functional spec: `.noSpeakerSpoken`, `.speakerNotFound`, `.favoriteNotFound`, `.speakerUnreachable`, `.nothingPlaying`, `.volumeAtLimit`, `.pauseNotSupported`, `.alreadyMuted`, `.voiceNotRecognised`, `.apiTimeout`
- [x] **T-0902** Build `ErrorResponseService` — maps each `AppError` to its exact spoken and display string from the functional spec; returns the string in the active language (English or Danish)
- [x] **T-0903** Ensure all use cases surface errors through `ErrorResponseService` rather than ad-hoc strings
- [x] **T-0904** Implement graceful API degradation — when `MozartError.timeout` or `MozartError.unreachable` is received, surface the appropriate `AppError` without crashing
- [ ] **T-0905** Ensure the app never crashes on network loss; write a test that simulates network unavailability mid-command
- [ ] **T-0906** Write unit tests for `ErrorResponseService`; verify every `AppError` maps to the correct string from the functional spec

---

## E-10 — UI — Home & Speaker Card

Build the primary screen: idle state, command recognition state, and now-playing state.

- [x] **T-1001** Implement `HomeView` with full-bleed background showing the user's iOS wallpaper through a Liquid Glass layer; fall back to deep-charcoal gradient if wallpaper is unavailable
- [x] **T-1002** Implement `SpeakerCard` — Liquid Glass rounded rect (corner radius 20 pt), horizontally inset 20 pt from screen edges; displays speaker name (SF Pro Display Semibold 34 pt) and playback status subtitle
- [x] **T-1003** Implement idle waveform animation — five bars pulsing at ~1 Hz in accent gold (`#C8A97E`) when the app is listening; bars animate to voice amplitude in real time during speech
- [x] **T-1004** Implement `SpeakerSelectorPill` — horizontally scrollable Liquid Glass pill row at the bottom of the screen, 12 pt above home indicator; active speaker highlighted with gold tint; snaps to centre on selection
- [x] **T-1005** Implement connection status chip — compact Liquid Glass pill in the top trailing corner; green tint for online, gray for offline; uses SF Symbol `wifi.slash` for offline state
- [x] **T-1006** Implement card expand animation for command recognition state — scale to 1.02 with spring (damping 0.7, response 0.4 s)
- [x] **T-1007** Implement live transcription label below the card during command recognition — SF Pro Text 17 pt; fades in at 0.15 s; text updates with character-by-character reveal
- [x] **T-1008** Implement now-playing inset panel within the speaker card — secondary Liquid Glass panel showing track/station name and three-bar animated playback indicator in accent gold
- [x] **T-1009** Implement volume track below the card in now-playing state — horizontal Liquid Glass slider, accent gold fill, trailing volume label; display only, not interactive (voice-only control)
- [x] **T-1010** Implement iOS 26 materialisation animation on app launch for the speaker card
- [x] **T-1011** Implement specular highlight on the speaker card top edge responding to device tilt via CoreMotion
- [x] **T-1012** Respect Dynamic Island — no UI elements overlap with the Dynamic Island area

---

## E-11 — UI — Confirmation Sheet

Build the bottom sheet that appears for every confirmation step.

- [x] **T-1101** Implement `ConfirmationSheet` as a SwiftUI `.sheet` with `presentationDetents([.height(280)])`; no drag handle; drag-to-dismiss disabled
- [x] **T-1102** Apply Liquid Glass material to the sheet surface with medium blur radius
- [x] **T-1103** Implement sheet content layout: "About to:" label in `--label-secondary` (SF Pro Text 12 pt), action read-back text in SF Pro Display Regular 22 pt, "Yes" and "No" buttons full-width stacked
- [x] **T-1104** Implement "Yes" button — filled Liquid Glass button with accent gold tint; triggers `ConfirmationCoordinator.confirm()`
- [x] **T-1105** Implement "No" button — outlined Liquid Glass button; triggers `ConfirmationCoordinator.cancel()`
- [x] **T-1106** Implement mic indicator pill at the top of the sheet — "or say Yes / No" in English, "eller sig Ja / Nej" in Danish
- [x] **T-1107** Implement sheet entry animation — slide up from below with spring (damping 0.75, response 0.5 s)
- [x] **T-1108** Trigger `.medium` haptic impact when the sheet appears
- [x] **T-1109** Trigger `.success` notification haptic on confirmation; dismiss the sheet and show a brief success toast
- [x] **T-1110** Ensure all elements in the sheet respect bottom safe area insets

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

## E-15 — AI-Powered Command Recognition

Replace the rule-based `CommandParser` with a cloud gen AI backend that understands natural, varied speech — including follow-up commands, ambiguous phrasing, and multi-intent utterances. The iOS client never calls the gen AI provider directly; all LLM calls are proxied through a backend service that holds the provider credentials.

- [ ] **T-1501** Define the backend NLU service API contract: `POST /nlu/parse` accepts `{ transcript, context[] }` and returns `{ command, confidence, rawIntent }` where `command` maps to the `VoiceCommand` JSON schema
- [ ] **T-1502** Build `NLUClient` in iOS — sends the raw transcript and conversation context window to the backend; deserialises the response into a `VoiceCommand`; 5-second timeout with `URLError.timedOut` on failure
- [ ] **T-1503** Design the backend NLU system prompt: enumerate all `VoiceCommand` cases and their expected JSON shape; instruct the model to return a confidence score 0.0–1.0 and to prefer `.unknown` over guessing when confidence is below 0.7
- [ ] **T-1504** Implement the backend NLU endpoint — validate and sanitise the incoming transcript; call the gen AI provider API; parse the structured JSON response; return it to the iOS client
- [ ] **T-1505** Implement local fallback — if `NLUClient` times out or returns a network error, transparently fall back to the local `CommandParser` and log the degraded mode at INFO level
- [ ] **T-1506** Implement conversation context window — send the last 5 finalised transcripts with each request so the model can resolve follow-up commands (e.g. "play the second one" after listing favorites)
- [ ] **T-1507** Implement client-side transcript caching — identical transcripts within a 30-second window return the cached `VoiceCommand` without a network round-trip
- [ ] **T-1508** Implement confidence gating — if the returned confidence is below 0.7, return `.unknown` and surface the "voice not recognised" error path; log the raw intent for debugging
- [ ] **T-1509** Add consent-aware logging — log NLU request latency and command type at INFO level; never log raw transcript content to any external service without explicit user consent (see E-16 privacy settings)
- [ ] **T-1510** Write integration tests against a mock NLU backend; verify each `VoiceCommand` case round-trips correctly and that the fallback path triggers on timeout

---

## E-16 — Gen AI Service Authentication

Provide UI and account management for the online gen AI backend. Users must authenticate before AI-powered recognition is active; the local `CommandParser` remains available as an unauthenticated fallback.

- [ ] **T-1601** Build `AuthService` — manages the lifecycle of the user's backend credential (API key or OAuth token); exposes `isAuthenticated: Bool` and async `signIn(credential:)` / `signOut()` methods
- [ ] **T-1602** Implement keychain storage for the auth credential using `Security.framework`; credential is stored under a namespaced service key and never written to `UserDefaults` or logs
- [ ] **T-1603** Build `SignInView` — full-screen onboarding screen presented modally on first launch when no credential is stored; contains a branded header, a secure text field for the API key or token, a "Connect" primary button, and a "Use without AI" secondary link
- [ ] **T-1604** Implement credential validation on sign-in — call `POST /auth/validate` on the backend before persisting; show an inline error if validation fails; never store an unvalidated credential
- [ ] **T-1605** Implement sign-out — clear the keychain entry; reset `AuthService.isAuthenticated` to `false`; navigate back to `SignInView`; AI-powered recognition deactivates immediately
- [ ] **T-1606** Implement token refresh — if the backend returns HTTP 401, attempt a silent token refresh; if refresh fails, sign the user out and present `SignInView` with a "Session expired, please sign in again" banner
- [ ] **T-1607** Surface auth state in the connection status chip (E-10 T-1005) — add a distinct AI indicator icon (`sparkles`) alongside the WiFi status; gold tint when AI is authenticated, gray with slash when not
- [ ] **T-1608** Add an "AI Service" row to the app settings screen — shows the connected account identifier (masked), a "Disconnect" button, and a toggle to enable/disable AI recognition while staying signed in
- [ ] **T-1609** Implement privacy settings — a toggle that controls whether raw transcripts may be sent to the backend at all; when off, force local `CommandParser` regardless of auth state; default to off on first launch
- [ ] **T-1610** Write unit tests for `AuthService` covering sign-in success, sign-in failure (invalid credential), sign-out, silent token refresh success, and refresh failure paths

---

## E-17 — Danish & Multilingual Support

Add full Danish (`da-DK`) support alongside English (`en-US`) across the entire voice pipeline — recognition, command parsing, TTS feedback, error strings, and UI labels. Language selection follows the device's primary language by default with a user-accessible override.

Danish command keywords:
- **Play:** *afspil*, *spil*
- **Play favorite N:** *afspil favorit [en|to|tre|fire]*, *spil favorit [en|to|tre|fire]*
- **Stop:** *stop* (same)
- **Pause:** *pause* (same)
- **Resume:** *fortsæt*, *genoptag*
- **Volume up:** *skru op*, *højere*
- **Volume down:** *skru ned*, *lavere*
- **Mute:** *slå lyden fra*, *tavs*
- **Unmute:** *slå lyden til*
- **List favorites:** *list favoritter*, *vis favoritter*
- **Confirm:** *ja*, *jo*
- **Cancel:** *nej*, *annuller*

Danish error strings (spoken and display):
- `noSpeakerSpoken` → *"Start din kommando med et højttalernavn. Tilgængelige højttalere er: [liste]"*
- `speakerNotFound` → *"[navn] blev ikke fundet. Tilgængelige højttalere er: [liste]"*
- `favoriteNotFound` → *"[navn] blev ikke fundet på [højttaler]. Tilgængelige favoritter er: [liste]"*
- `speakerUnreachable` → *"[højttaler] kunne ikke nås. Kontroller at højttaleren er tændt og forbundet til netværket"*
- `nothingPlaying` → *"[højttaler] afspiller ikke noget i øjeblikket"*
- `volumeAtLimit` → *"[højttaler] er allerede ved [maksimal|minimal] lydstyrke"*
- `pauseNotSupported` → *"[højttaler] understøtter ikke pause for denne kilde. Sig [højttaler], stop for at stoppe i stedet"*
- `alreadyMuted` → *"[højttaler] er allerede slået fra"*
- `voiceNotRecognised` → *"Undskyld, jeg forstod ikke det. Gentag venligst din kommando"*
- `apiTimeout` → *"Kunne ikke nå Bang & Olufsen servicen. Prøv venligst igen"*

- [ ] **T-1701** Build `LanguageService` — exposes `activeLanguage: Language` (`.english` / `.danish`); determines the default from `Locale.preferredLanguages` (first `da` or `da-DK` entry activates Danish); persists user override to `UserDefaults`
- [ ] **T-1702** Update `AVService` to instantiate `SFSpeechRecognizer` with the locale from `LanguageService`; reinitialise the recogniser (stop current request, create new instance, restart) when `activeLanguage` changes
- [ ] **T-1703** Extend `CommandParser` to accept a `Language` parameter; add Danish keyword mappings for all command intents using the keyword table above
- [ ] **T-1704** Add Danish spoken-number words (`en`, `to`, `tre`, `fire`) to the play-favorite number map in `CommandParser`
- [ ] **T-1705** Update `ConfirmationCoordinator` to select the `da-DK` system TTS voice when Danish is active (`AVSpeechSynthesisVoice(language: "da-DK")`); fall back to any available Danish voice; apply the same speech rate (0.5)
- [ ] **T-1706** Extend `ErrorResponseService` to return Danish strings for all `AppError` cases when `LanguageService.activeLanguage == .danish`; use the Danish strings listed above
- [ ] **T-1707** Translate all confirmation and completion message strings in `HomeView` (`confirmationMessage(for:speaker:)`, `completionMessage(for:speaker:)`) to Danish; select the correct language via `LanguageService`
- [ ] **T-1708** Translate all static UI strings to Danish via `String(localized:)`: ConfirmationSheet labels ("About to:" → "Er ved at:", "eller sig Ja / Nej"), `HomeView` status messages ("Listening…" → "Lytter…", "Looking for speakers…" → "Leder efter højttalere…", "Microphone access denied" → "Mikrofonadgang nægtet")
- [ ] **T-1709** Add `da` to `Info.plist` `CFBundleLocalizations`; add Danish variants to `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` in `Localizable.strings`
- [ ] **T-1710** Expose language toggle in app settings (long-press on the connection status chip or a dedicated settings screen row); switching language restarts the recogniser and updates all spoken feedback immediately without requiring an app restart
- [ ] **T-1711** Write unit tests for `CommandParser` in Danish mode: cover all intents, spoken number words, confirm/cancel keywords, and mixed Danish/English edge cases
- [ ] **T-1712** Write unit tests for `ErrorResponseService` in Danish mode: verify every `AppError` maps to the correct Danish string

---

## E-18 — Robust Command Parsing (Foundation Models + NLModel)

Replace the rule-based `CommandParser` from E-03 with a two-path architecture that handles natural language variation without an enumerated phrase list. On Apple Intelligence-capable devices (A17 Pro / M1+, iOS 26+) a `FoundationModelParser` runs on-device inference via `LanguageModelSession`. On all other devices a `TwoStageFallbackParser` uses deterministic Swift `Regex` patterns first, then a bundled `NLModel` classifier. A `CommandParserRouter` selects the appropriate path at runtime. `SpeakerNameMatcher` (E-04) remains the mandatory pipeline entry point — neither parser is invoked until a speaker is resolved.

**Depends on:** E-03 (T-0304 `VoiceCommand` enum, T-0312 background stop), E-04 (T-0403 `SpeakerNameMatcher`), E-05 (T-0501 `FavoritesService` for slot resolution)  
**Supersedes:** E-03 T-0305–T-0311 (existing `CommandParser`; those tasks remain complete in history)

### Task dependency chain

```
T-1801 (ParsedCommand types)
  ├── T-1802 (FoundationModelParser) ──► T-1809 (integration tests)
  │       └── T-1804 (Router)
  └── T-1803 (TwoStageFallbackParser) ──► T-1808 (unit tests)
          └── T-1804 (Router)
T-1806 (Train NLModel) ──► T-1803
                       └── T-1807 (CI accuracy gate)
T-1804 (Router) + T-0403 ──► T-1805 (pipeline integration) ──► T-1810 (voice pause test)
```

- [ ] **T-1801** Define `ParsedCommand` `@Generable` struct and `CommandIntent` / `VolumeDirection` enums; place in `Core/CommandParsing/ParsedCommand.swift`; all types must conform to `Generable`, `Codable`, and `Equatable`
  *No E-18 dependencies. Prerequisite for T-1802, T-1803.*

- [ ] **T-1802** Build `FoundationModelParser` — create and hold a `LanguageModelSession` with a system-instructions template that injects the active speaker name and favorites list; expose `parse(_:speaker:) async throws -> ParsedCommand` and `warmUp()` for pre-loading; call `warmUp()` from app launch after speaker list loads (aligns with T-0401)
  *Depends on: T-1801, T-0501. Prerequisite for T-1804, T-1809.*

- [ ] **T-1803** Build `TwoStageFallbackParser` — Stage 1: Swift `Regex` patterns for all 13 intents as specified in the command parser spec; Stage 2: `NLModel` loaded from the bundled `.mlmodel` (produced by T-1806) with confidence threshold 0.65; returns `ParsedCommand(intent: .unknown, ...)` when both stages fail
  *Depends on: T-1801, T-1806 (`.mlmodel` artifact). Prerequisite for T-1804, T-1808.*

- [ ] **T-1804** Build `CommandParserRouter` — check `SystemLanguageModel.availability` at init; instantiate `FoundationModelParser` only when available; `parse(_:addressedSpeaker:) async throws` delegates to the appropriate parser; does not catch-and-reroute errors
  *Depends on: T-1802, T-1803. Prerequisite for T-1805.*

- [ ] **T-1805** Integrate `SpeakerNameMatcher` as mandatory pipeline entry point — wire into `VoiceInputManager` so the raw transcription is passed to `SpeakerNameMatcher` first; on `nil` result surface `.noSpeakerSpoken` and halt; on success pass `(remainder, speaker)` to `CommandParserRouter`
  *Depends on: T-1804, T-0403. Prerequisite for T-1810.*

- [ ] **T-1806** Train and bundle `NLModel` classifier — create training corpus at `Resources/CommandClassifier/TrainingData.json` with ≥ 200 examples per intent covering canonical phrasings, word-order variants, ASR noise forms, and numeric vs. word-form numbers; compile to `.mlmodel`; check both files into the repository
  *No E-18 dependencies. Prerequisite for T-1803, T-1807.*

- [ ] **T-1807** Add classifier accuracy gate to CI pipeline — load the bundled `NLModel`, run inference against the held-out validation set, fail the build with a non-zero exit code if accuracy drops below 85%; run on every PR that touches `TrainingData.json` or the `.mlmodel`; output per-intent accuracy breakdown
  *Depends on: T-1806.*

- [ ] **T-1808** Unit tests for `TwoStageFallbackParser` — one positive + one negative test per Stage 1 regex pattern; volume boundary tests (0, 1, 99, 100, out-of-range); one canonical example per Stage 2 intent class; confirm and cancel variants ("yeah", "never mind"); all tests must pass on the CI simulator without Apple Intelligence
  *Depends on: T-1803.*

- [ ] **T-1809** Integration tests for `FoundationModelParser` — gated behind `SystemLanguageModel.availability == .available`; cover: playNamed with exact favorite, playNamed with paraphrased name, volumeUp with spoken number, stop, confirm, unknown utterance; assert `intent` and slot values
  *Depends on: T-1802.*

- [ ] **T-1810** Verify voice recognition pauses during `AVSpeechSynthesizer` output — `VoiceInputManager` suspends `SFSpeechAudioBufferRecognitionRequest` while `AVSpeechSynthesizer.isSpeaking`; resumes within 200 ms of speech end; no self-triggered parse events in the test harness
  *Depends on: T-1805, T-0803.*

---

## E-19 — Usability Enhancements

Close four first-launch and day-to-day usability gaps: explicit language selection at startup with persistent choice, spoken feedback when a command is not understood, a dismissible getting-started hint card using real speaker names, and consistent auto-clearing of the voice transcript. None of these tasks change the existing command grammar, Mozart API integration, or design system.

**References:** functional-spec-usability-enhancements v1.1 (US-09–US-12)  
**Depends on:** E-03 (T-0303 silence detection), E-08 (T-0801 `ConfirmationCoordinator`), E-09 (T-0901 `AppError`, T-0902 `ErrorResponseService`), E-17 (T-1701 `LanguageService`, T-1702 `AVService.setLocale`), E-18 (T-1801 `ParsedCommand`/`CommandIntent`)

### Task dependency chain

```
T-1901 (LanguageService flag)
  └── T-1902 (LanguagePickerSheet UI)
        └── T-1903 (HomeView wiring — defer mic until chosen)

T-1904 (voiceNotRecognised on .unknown) ── no dependencies within E-19

T-1905 (HintCardView)
  └── T-1906 (? button in statusBar)

T-1907 (clearTranscriptAfterDelay on all paths)
  └── T-1908 (suppress clear while confirmation pending)

T-1909 (unit tests) ── depends on T-1901–T-1908
```

- [ ] **T-1901** Add `hasExplicitlyChosen: Bool` to `LanguageService` — persisted under key `com.voxio.activeLanguage.hasExplicitlyChosen` in `UserDefaults`; set to `true` inside `setLanguage(_:)` after persisting; defaults to `false` when the key is absent. No other `LanguageService` behaviour changes.
  *No E-19 dependencies. Prerequisite for T-1902, T-1903.*

- [ ] **T-1902** Build `LanguagePickerSheet` — a SwiftUI `View` presented as a `.sheet` with `interactiveDismissDisabled(true)` and `presentationDetents([.height(280)])`; matches `ConfirmationSheet` Liquid Glass material and design tokens; contains two full-width tappable rows: "English" and "Dansk"; each row calls `LanguageService.shared.setLanguage(_:)` then dismisses the sheet; VoiceOver announcement on appear: "Choose your command language." (EN) / "Vælg dit kommandosprog." (DA); both rows are at least 44 × 44 pt; Dynamic Type text scales correctly at all sizes.
  *Depends on: T-1901. Prerequisite for T-1903.*

- [ ] **T-1903** Wire `LanguagePickerSheet` into `HomeView` — present the sheet on `HomeView.onAppear` when `!languageService.hasExplicitlyChosen`; do not call `voiceToText.start()` or begin the mDNS scan until the sheet has been dismissed (sheet dismissal is the trigger for mic and discovery initialisation); the picker must appear within 500 ms of `onAppear`; on every subsequent launch the sheet is not presented and the existing startup flow is unchanged.
  *Depends on: T-1902.*

- [ ] **T-1904** Announce `voiceNotRecognised` on `.unknown` command intent — in the E-18 dispatch path in `HomeView` (the `switch parsed.intent` block), add `coordinator.announce(errorService.spoken(.voiceNotRecognised))` to the `.unknown` case; the existing `clearTranscriptAfterDelay()` call in that branch remains; spoken feedback must begin within 500 ms of the final transcript delivering `.unknown`; voice recognition is paused while speaking (existing `onSpeechWillStart` / `onSpeechDidEnd` hooks are authoritative and require no changes).
  *No E-19 dependencies.*

- [ ] **T-1905** Build `HintCardView` — a SwiftUI `View` rendered inside the `voiceFeedback` `VStack` (`HomeView.swift:155–177`); shows three example command phrases in the active language using `speakers.first?.friendlyName` (or a placeholder if no speaker has been discovered yet); EN copy: "Try saying:" + `"<Name>, play"` + `"<Name>, pause"` + `"<Name>, volume 50"`; DA copy: "Prøv at sige:" + `"<Navn>, afspil"` + `"<Navn>, pause"` + `"<Navn>, lydstyrke 50"`; placeholder copy when no speaker is discovered yet: "Looking for speakers… Once one is found you can say e.g. 'Beolab, play'" / "Leder efter højttalere… Når en er fundet kan du f.eks. sige 'Beolab, afspil'"; a "Got it" / "OK" button sets `@AppStorage("hasSeenHint") = true` and hides the card; auto-hides (without setting `hasSeenHint`) when `transcript` becomes non-empty; must not appear while `coordinator.isPending == true` or while `AVSpeechSynthesizer.isSpeaking`; Reduce Motion: entry/exit uses `.opacity` cross-fade only; Dynamic Type: all text scales to the user's preferred size; dismiss control `accessibilityLabel`: "Dismiss hint" / "Afvis tip".
  *No E-19 dependencies. Prerequisite for T-1906.*

- [ ] **T-1906** Add "?" button to `statusBar` — place a `Button` on the leading edge of the `statusBar` HStack in `HomeView`, 20 pt horizontal and 8 pt top inset (mirroring `ConnectionStatusChip` alignment at the trailing edge); tapping toggles a `@State var showHintManually: Bool`; `HintCardView` is visible when `showHintManually == true` OR when `hasSeenHint == false && speakers.isNotEmpty`; tapping "?" while the card is visible hides it (sets `showHintManually = false`); `accessibilityLabel`: "Show getting-started hint" / "Vis kom-godt-i-gang-tip"; button uses SF Symbol `questionmark.circle` at the same point size as `ConnectionStatusChip`'s icon.
  *Depends on: T-1905.*

- [ ] **T-1907** Call `clearTranscriptAfterDelay()` on all remaining final-transcript paths in `HomeView` — audit every branch reached after `onFinalTranscript` fires and confirm `clearTranscriptAfterDelay()` is called on: successful command (confirmed and dispatched), cancelled command (user said "no", tapped Cancel, or confirmation timed out), and API error paths (`.speakerUnreachable`, `.favoriteNotFound`, `.nothingPlaying`, etc.) and `.noSpeakerSpoken`; the `.unknown` path already calls it and must not be changed; the timer starts from the moment each branch's handler returns; if a new transcription arrives before any timer fires, the new transcription replaces the old one and its own 5-second timer supersedes the previous one (cancel the old `Task` before scheduling the new one).
  *No E-19 dependencies. Prerequisite for T-1908.*

- [ ] **T-1908** Suppress `clearTranscriptAfterDelay()` while confirmation is pending — inside the existing `clearTranscriptAfterDelay()` method (`HomeView.swift:368`), after the `Task.sleep` wakes, check `coordinator.isPending`; if `true`, reschedule the same 5-second sleep instead of writing `transcript = ""`; repeat until `coordinator.isPending == false`; this requires no new timer primitive and no changes to `ConfirmationCoordinator`.
  *Depends on: T-1907.*

- [ ] **T-1909** Write unit tests — (a) `LanguageService.hasExplicitlyChosen` is `false` when the UserDefaults key is absent and `true` after `setLanguage(_:)` is called; (b) `LanguagePickerSheet` is presented on first launch and absent on subsequent launches; (c) `voiceNotRecognised` is announced when `parsed.intent == .unknown` and not announced for any other intent; (d) `clearTranscriptAfterDelay()` does not clear `transcript` while `coordinator.isPending == true` and does clear it after `isPending` becomes `false`; (e) `HintCardView` renders with a real speaker name when one is discovered and with placeholder copy when none is; (f) `hasSeenHint` is set to `true` only on explicit dismissal, not on auto-hide.
  *Depends on: T-1901–T-1908.*

---

## Task Summary

| Epic | Tasks | Notes |
|---|---|---|
| E-01 Foundation | 9 | Prerequisite for all other epics |
| E-02 Mozart API | 15 | Prerequisite for E-05 through E-07 |
| E-03 Voice Recognition | 12 | Prerequisite for E-04 through E-08 |
| E-04 Speaker Addressing | 9 | Prerequisite for E-05 through E-07 |
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
| E-15 AI-Powered Command Recognition | 10 | Depends on E-03, E-16; enhances E-05 through E-08 |
| E-16 Gen AI Service Authentication | 10 | Prerequisite for E-15 |
| E-17 Danish & Multilingual Support | 12 | Depends on E-03, E-08, E-09, E-11 |
| E-18 Robust Command Parsing | 10 | Depends on E-03, E-04, E-05; supersedes E-03 T-0305–T-0311 |
| E-19 Usability Enhancements | 9 | Depends on E-03, E-08, E-09, E-17, E-18; US-09–US-12 |
| **Total** | **179** | |
