# Voxio Specification — v1.1
**Version:** 1.1.3
**Status:** Draft
**Date:** 2026-04-29
**Platform:** iOS 26
**References:** design-spec-bo-voice-control v1.1, functional-spec-bo-voice-control v1.3, epics-and-tasks-bo-voice-control v1.3 (E-01–E-19), epics-and-tasks-voxio-1.1 (E-20–E-26), ADR-001-v1.1-visual-layer, CLAUDE.md
**Languages:** English (`en-US`) and Danish (`da-DK`) — both fully supported (unchanged from v1.0)

**Amendment history**

| Version | Date | Summary |
|---|---|---|
| 1.1.0 | 2026-04-29 | Initial draft. |
| 1.1.1 | 2026-04-29 | Applied 5 amendments from `ADR-001-v1.1-visual-layer.md`: (1) BeoColor naming reconciled to `text` / `muted` + new prerequisite **T-2100**; (2) `.glassEffect` API authoritative (no DIY `ultraThinMaterial`) — see §Decision-Audit Note; (3) `Capsule()` shape change documented as deliberate, snapshot tests verify against `ButtonLookAndFeel.png`; (4) T-2105 / T-2106 haptic wording disambiguated — `DarkGlassButton` itself emits no haptics; (5) `HintCardView` button shape change explicitly noted in T-2109. |
| 1.1.2 | 2026-04-29 | Added **E-24 Three-Tier Voice Command Parsing** (US-20, US-21, US-22, US-23) following research-driven solution selection. Three-tier architecture: Foundation Models (A17 Pro+, iOS 26) → retrained NLModel (primary floor for A15/A16) → existing keyword `CommandParser` (safety net, unchanged). Bilingual (en + da) NLU corpus required. **Supersedes the rendering of E-18 task IDs T-1801 through T-1810** — those task IDs are retired in favour of T-2401 through T-2419; the existing keyword `CommandParser` shipped under E-18 remains in place as Tier 3. Intro section §What is NOT changing in v1.1 was previously accurate but is now amended: the parsing pipeline IS being replaced by E-24. |
| 1.1.3 | 2026-04-29 | Added **E-25 Auto-Execute Confirmation with Countdown Cancel** (US-24, US-25) and **E-26 "Voxio" Trigger Word** (US-26, US-27). E-25 replaces the Yes/No confirmation pattern with a 3-second countdown and a single Cancel control (button or voice "cancel"/"no"/"nej"/"annuller"); **supersedes T-1104 (Yes button), T-1108 (sheet-appear haptic wiring), T-0805 (10-second timeout)**. E-26 replaces the always-listening recogniser with a "Voxio" wake-word activation model and a passive/active orb state machine; **supersedes T-0301, T-0302, T-0303**. New tasks T-2501–T-2510 and T-2601–T-2610. Five new open questions Q20–Q24 (keyword-spotting API availability is Q20). Several v1.0 §What is NOT changing entries are amended below — confirmation flow logic (E-08), animation/haptic system (E-14), and the always-on speech-recognition entry path (E-03) ARE changing in v1.1. Epics and tasks split out to a sibling document `epics-and-tasks-voxio-1.1.md`; this spec retains everything except the epic / task breakdown. |

---

## Introduction

Voxio v1.1 is a focused release covering four parallel workstreams: a visual-layer refresh (E-20 through E-23), a voice command parsing improvement (E-24), an auto-execute countdown confirmation flow (E-25), and a "Voxio" trigger-word activation model (E-26). The intent set in `VoiceCommand.swift`, the Mozart API integration, language coverage, and accessibility behaviours otherwise remain as shipped in v1.0 (E-01 through E-19) — but several v1.0 interaction patterns are deliberately replaced this release: the Yes/No confirmation buttons (E-25) and the always-on speech recognition entry path (E-26).

What v1.1 changes:

1. **Fixed `AppBackground.png`** — a custom dark navy / blue-teal-green orb image replaces the deep-charcoal gradient (and supersedes the iOS-wallpaper-through-glass approach previously specified by **T-1001**). The background no longer adapts to the user's wallpaper or system light/dark setting.
2. **Dark Liquid Glass pill button system** — every interactive button in the app is rebuilt as a single reusable `DarkGlassButton` SwiftUI view that wraps the iOS 26 native `.glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: Capsule())` API with a hairline white specular border. This replaces the mixed button styles introduced in E-11 (`T-1104` filled-gold "Yes", `T-1105` outlined "No") and any other ad-hoc button styling elsewhere in the codebase.
3. **Dark-mode-only visual layer** — the app is intentionally dark-only. `.preferredColorScheme(.dark)` already sits on `WindowGroup`, but `.sheet()`-presented content (`LanguagePickerSheet`, `ConfirmationSheet`) reverts to system appearance unless its own root explicitly enforces dark mode. v1.1 closes that gap and, in the same pass, adds a SwiftUI-native `@Environment(\.colorSchemeContrast)` reactive Increase Contrast border path. (No legacy `UIAccessibility.isContrastEnabled` call sites exist in `iOS/Voxio/`; T-2204 verifies this and closes as N/A.)
4. **Three-tier voice command parsing** — replace the v1.0 keyword/regex-only `CommandParser` (E-18) with a three-tier classifier that significantly improves natural-language paraphrase recognition while preserving full offline operation, full privacy, and bilingual (English + Danish) coverage. Tier 1 uses Apple's iOS 26 Foundation Models framework on capable devices (A17 Pro+); Tier 2 is a retrained `NLModel` intent classifier that serves as the primary floor for all supported devices (A15/A16+); Tier 3 is the existing keyword `CommandParser` retained as a deterministic safety net. See E-24.
5. **Auto-execute confirmation with countdown cancel** — replace the Yes/No two-button confirmation pattern with an auto-execute model. After the spoken read-back finishes, a visible countdown ("Cancelling in 3… 2… 1…") runs for 3 seconds, surfacing a single destructive-role `DarkGlassButton` for cancel. The user cancels by tapping the button or by saying "cancel" / "no" / "nej" / "annuller" during the countdown; otherwise the action fires automatically. **Supersedes T-1104 (Yes button), T-1108 (sheet-appear haptic wiring), T-0805 (10-second confirmation timeout).** See E-25.
6. **"Voxio" trigger word** — replace the always-listening model with a wake-word activation model. The orb has two states: **passive** (small slow pulse — listening for the trigger word "Voxio" only) and **active** (full amplitude animation — listening for a command). After a command is captured (silence detection) or after ~5 seconds of post-activation silence with no speech, the app returns to passive. The trigger word may be spoken alone ("Voxio" then a command) or in the same utterance as the command ("Voxio, Beosound play"). **Supersedes T-0301 (always-on `SFSpeechRecognizer`), T-0302 (`VoiceInputManager` start/stop), T-0303 (silence detection entry point).** See E-26.

### Why these three visual changes, together

The three visual changes are coupled by a single design intent: produce a consistent, cinematic, brand-controlled canvas that does not depend on the user's wallpaper or system appearance. The fixed background sets the stage; the dark glass buttons are the only style that reads correctly on top of that stage; and dark-mode-only enforcement makes sure the stage and the buttons remain consistent across every presentation surface (main window, sheets, popovers, system-rendered chrome). Shipping any one of these in isolation would produce visible mismatches between the home screen and the sheets, or between the main window and a system-presented view.

### Why the parsing change, in this same release

E-19 usability work (shipped) widened the surface area of phrasings users actually attempt. Field reports and the v1.0 acceptance criteria for E-18 confirm that the keyword/regex parser, while reliable for canonical phrasings, falls back to `.unknown` on natural-language paraphrases such as "could you turn it down a bit", "let's pause for a sec", or "play my second favourite". Improving recognition for these phrasings without sacrificing privacy, offline operation, latency, or bilingual coverage requires moving from pattern-matching to a learned classifier. The three-tier design lets us adopt the strongest available technology on each device class while keeping a deterministic floor.

### Why the countdown confirmation, in this same release

The Yes/No two-button pattern from E-11 forces the user to confirm every parsed command — even unambiguous ones like "pause" or "next favourite". Field observation showed that users develop a habit of tapping Yes immediately, which makes the confirmation step pure friction. The auto-execute model preserves the safety property of v1.0 (an irreversible action does not fire without the user having a chance to stop it) while removing the redundant tap. The countdown is short enough to feel responsive and long enough to be cancellable by voice or touch. Cancel-by-voice ("cancel" / "no" / "nej" / "annuller") preserves bilingual symmetry and lets the user keep their hands free.

### Why the trigger word, in this same release

The v1.0 always-on `SFSpeechRecognizer` consumes the microphone continuously while the app is foregrounded, draining battery and producing false-positive transcripts when the user is talking to someone else in the room. A wake-word model makes the listening-vs-acting boundary explicit and visible (passive vs. active orb states), reduces battery drain, and reduces accidental commands. "Voxio" was chosen as the trigger because it matches the product name and is unlikely to occur in casual speech. The trigger phase remains fully on-device — no audio leaves the phone for trigger detection any more than for command parsing.

### What is NOT changing in v1.1

- Voice command intents (E-03 intent set unchanged; the `VoiceCommand` enum is unchanged — E-24 only changes how transcripts are mapped to those existing intents)
- Mozart API integration (E-02 unchanged)
- Speaker discovery and addressing (E-04 unchanged)
- Use-case handlers for play / stop / pause / volume / mute (E-05, E-06, E-07 unchanged)
- Error semantics and strings (E-09 unchanged)
- Toast structure and triggers (E-12 unchanged) — only their button styling changes
- Accessibility behaviours (E-13 unchanged) — VoiceOver, Dynamic Type, Reduce Motion semantics; only the Increase Contrast path is added (additive, not a replacement). VoiceOver gains new announcements for the countdown and for trigger-word state transitions; these are additive.
- Language coverage (E-17 unchanged — both English and Danish, no new languages)
- Usability enhancements shipped in E-19 (T-1901–T-1909 unchanged)
- The existing keyword `CommandParser` shipped under E-18 is **kept**, not deleted — it serves as Tier 3 of the new router. The E-18 epic itself is otherwise unchanged; only its v1.0 task IDs T-1801 through T-1810 are retired by E-24 (the rendering of those tasks is replaced — see Resolved Decisions).

**What IS changing that v1.0 listed under "not changing":** confirmation flow logic (E-08) is reshaped by E-25 — the `ConfirmationCoordinator.confirm()` / `.cancel()` API is replaced by `.startCountdown()` / `.cancelCountdown()`, and the 10-second confirmation timeout from T-0805 is replaced by the 3-second auto-execute. Animation and haptic system (E-14) gains new countdown-related animations and a `.error` notification haptic on cancel; existing sheet-appear and confirm-success haptics from T-1108 / T-1109 are re-wired (T-1108 sheet-appear `.medium` impact moves to "countdown start", T-1109 `.success` moves to "auto-execute fire"). The always-on speech recognition entry path (T-0301/T-0302/T-0303) is replaced by E-26's wake-word state machine.

### Decision-audit note

The design spec (`design-spec-bo-voice-control.md` §Button Style) prose says buttons should "use `.ultraThinMaterial` with a `Color.black.opacity(0.45)` overlay". This is legacy wording from a pre-iOS-26 draft. The native iOS 26 `.glassEffect` API is authoritative for v1.1 (see §Technical Context and §Resolved Decisions). The design team has been asked to refresh the design spec prose accordingly (open question Q11 below); the engineering implementation in this document is the source of truth.

---

## Technical Context

| Decision | Choice | Rationale |
|---|---|---|
| Background asset | `Assets.xcassets/AppBackground.imageset/AppBackground.png` (642 × 1077, portrait) | Confirmed by design spec v1.1 §Background; portrait-only matches v1.0 §Out of Scope (no landscape, no iPad) |
| Background pattern | `Image("AppBackground").resizable().scaledToFill().ignoresSafeArea()` as first child of root `ZStack` | Researcher-confirmed iOS 26 idiom; matches the gradient pattern already in `HomeView`; no new safe-area caveats |
| Button material | `.glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: Capsule())` | iOS 26 native API; codebase already targets iOS 26 (uses `.glassEffect(in:)` on toast / emptyState). Authoritative over the design-spec prose mentioning `ultraThinMaterial`. |
| Button border | `.overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))` | `strokeBorder` (not `stroke`) keeps the hairline inside the capsule clip — no bleed past the edge |
| Button shape | `Capsule()` — fully-rounded pill | Replaces the v1.0 `RoundedRectangle(cornerRadius: 12)` ad-hoc shape used in `ConfirmationSheet`, `LanguagePickerSheet`, and `HintCardView`. Visible design change; verified against `ButtonLookAndFeel.png` reference image during E-23 snapshot tests. |
| Button reusability | Single `DarkGlassButton` SwiftUI view in `DesignSystem/` | Matches existing `BeoColor` / `DesignTokens` organisation; mandated for all buttons in app |
| Token name reconciliation | `BeoColor.text` (primary label) and `BeoColor.muted` (secondary label) are the canonical names in the codebase. The design-spec tokens `--label-primary` / `--label-secondary` map to these. **T-2100** adds aliases `BeoColor.labelPrimary` / `BeoColor.labelSecondary` so future code can use either name without breaking. | Design spec uses `--label-primary` / `--label-secondary`; codebase uses `text` / `muted`. Aliases unblock `DarkGlassButton` from compile-time naming conflict. |
| Dark mode | Existing `.preferredColorScheme(.dark)` on `WindowGroup` + new explicit modifier on every `.sheet` content root | Sheets create presentation boundaries that intercept the WindowGroup preference; verified by researcher and ADR-001 |
| Increase Contrast detection | `@Environment(\.colorSchemeContrast)` (SwiftUI) — reactive | Researcher-recommended SwiftUI-native API. No `UIAccessibility.isContrastEnabled` references exist in the current codebase; T-2204 confirms by audit. |
| Light mode | Disallowed | Background image is intrinsically dark; light-mode rendering would wash out glass surfaces |
| Deployment target | iOS 26 (unchanged) | `.glassEffect` is iOS 26+; codebase already requires iOS 26 |
| Token additions | `appBackground` asset constant + `DarkGlassButton.{overlayColor, borderColor, borderWidth, paddingV, paddingH, iconGap, iconOnlySize, pressedScale, pressSpringResponse, pressSpringDamping}` in `DesignTokens.swift` | Mirrors v1.1 design-token reference §Design Tokens Reference |
| Parsing architecture | Three-tier router: Tier 1 Foundation Models `LanguageModelSession` (when available), Tier 2 retrained `NLModel`, Tier 3 keyword `CommandParser`. Tier selection is computed once at app session start. | On-device, offline, private; matches research recommendation Rank 1 (Option A + B). NLModel is the **primary floor** that must work for all supported devices; Foundation Models is an enhancement, not a requirement. |
| Tier 1 availability gate | `SystemLanguageModel.default.availability == .available` (Foundation Models framework, iOS 26) | Apple's recommended availability check; covers A17 Pro+ devices with Apple Intelligence enabled. Devices that do not satisfy this gate skip Tier 1 entirely. |
| Tier 1 structured output | `@Generable` Swift type with `@Guide(.anyOf([...]))` constraining the model output to one of the 13 `VoiceCommand` cases plus required slots (volume delta/level, favorite index 1–4) | Guided generation eliminates free-text post-processing and tightens latency to a constrained classification call (~100–400 ms prewarmed per Apple WWDC25 benchmarks). Pre-warm session at app launch. |
| Tier 2 model | Retrained `NLModel` (Create ML `MLTextClassifier`) shipped as a `.mlmodel` bundled in the app | Direct successor to the existing E-18 NLModel slot. <5 ms inference, runs on all iOS 26 devices, no device gating. Validation accuracy target ≥ 92 % on a held-out test set per language. |
| Tier 2 corpus strategy | Hybrid: open-source NLU/intent corpora adapted to the Voxio intent set + generated utterances to fill coverage gaps. Bilingual: English and Danish utterance examples both required. Target 300–500 utterances per intent per language. | Research-confirmed approach; raw open-source datasets do not match the 13-intent set so adaptation is unavoidable. Generated utterances cover paraphrases that public datasets miss (e.g. confirm/cancel in a music-playback context, favourite-by-position phrasing). |
| Tier 3 model | Existing keyword `CommandParser` shipped under E-18, unchanged | Deterministic, ~0 ms, always available. Acts as a safety net when Tiers 1 and 2 both return low confidence or `.unknown`. Also handles the canonical phrasings that benefit nobody to round-trip through a model. |
| Confidence handling | Tier 1 emits a structured intent with implicit high confidence (guided generation); Tier 2 emits `(intent, confidence)` and falls through to Tier 3 below a threshold (default 0.55, tunable per T-2410); Tier 3 either matches a keyword pattern or returns `.unknown(transcript)` | Threshold tuned during corpus training; recorded in the model card alongside the model artifact. |
| Router location | New `CommandParserRouter` (extending the existing router introduced by commit `63467c0` per recent codebase changes) wraps all three tiers behind the same async API surface that `VoiceToText` calls | Single seam in the codebase; the parsing call site in `VoiceToText.swift:50` becomes async-aware. |
| Async surface | Router exposes `func parse(_ transcript: String) async -> VoiceCommand` | Foundation Models calls are async; NLModel is sync but wrapping it in async keeps the API uniform. The call site in `VoiceToText.swift` (currently main-thread synchronous) updates to dispatch the parse on a Task and deliver the result on the main actor before invoking `onCommand`. |
| Privacy posture | All three tiers run on-device. No transcript leaves the device. Matches v1.0 privacy NFR exactly. | Non-negotiable — same posture as the existing `CommandParser`. |
| Foundation Models API stability | iOS 26 framework; researcher noted a beta-stage API stability caveat from WWDC25. Risk accepted: proceed with implementation, gated by `SystemLanguageModel.availability` so any runtime regression on non-Apple-Intelligence devices is invisible (those devices land on Tier 2). | See open question Q13. If the framework is withdrawn or breaks at GA, Tier 2 carries the entire load with no functional regression. |
| Locale routing | Tier 1 and Tier 2 are both passed the active language at session/router init time; Tier 2 ships separate `.mlmodel` files per language (English and Danish) selected by `LanguageService.shared.activeLanguage` | Per-language NLModels outperform a single multilingual model on this small intent set; cost is two ~50–200 KB model files instead of one. |
| Confirmation pattern | Auto-execute after a 3-second countdown, with a single Cancel control (button or voice) and no Confirm button. The countdown begins after the spoken read-back (TTS) completes. | Removes redundant Yes-tap friction observed in v1.0 field use; preserves cancel safety. Replaces the 10 s timeout from T-0805 (where a missing decision *cancelled* the action) with a 3 s timeout where a missing decision *executes* the action — this is the inversion of v1.0 behaviour and is deliberate. |
| Countdown duration | 3 seconds, fixed | Long enough to react and cancel by voice; short enough to feel responsive. Not user-configurable in v1.1. See open question Q21. |
| Countdown UI | A SwiftUI view rendering "Cancelling in 3… 2… 1…" (localised) above a single `DarkGlassButton(role: .cancel)` labeled "Cancel" / "Annuller". The numeric value updates each second. | Single-control surface; matches the visual system from E-21. The countdown text is not animated (no scale/opacity transitions per second) — the digit substitution is the only change. |
| Countdown TTS interaction | TTS playback (the spoken read-back) completes before the countdown timer starts. The countdown does NOT begin during read-back. | Prevents the user from being asked to react before they've heard what the action is. Read-back text is unchanged from v1.0 (T-1102 / T-1106). |
| Voice cancel grammar | Trigger words during countdown: `cancel`, `no`, `nej`, `annuller`. Case-insensitive. Match is on whole-word presence in the active recognition session. | Reuses the existing v1.0 cancel-grammar tokens (`no`, `nej`) plus explicit `cancel` / `annuller`. No NLModel call for the cancel decision — keyword match is sufficient and ~0 ms. |
| Coordinator API change | `ConfirmationCoordinator.confirm()` / `.cancel()` are replaced by `.startCountdown(action:)` / `.cancelCountdown()`. The countdown owns the timer; on expiry it invokes the bound action. | Single seam for the new flow. The downstream call sites for the actual commands (play / pause / volume etc) are unchanged — only the *reach* path through the coordinator changes. |
| Trigger-word approach | Use `SFSpeechRecognizer` in a continuous on-device recognition mode for trigger detection, with a possible upgrade to a dedicated keyword-spotting API if iOS 26 exposes one (see open question Q20). The default implementation uses `SFSpeechRecognizer`. | Keeps the existing speech-recognition stack and avoids a third-party SDK. Battery cost is the dominant trade-off — see NFR §Battery and Q20 for the keyword-spotting investigation. |
| Trigger word | "Voxio" (case-insensitive). Matched on whole-word boundary in the partial transcript stream. | Matches the product name; unlikely to occur in casual speech; stable phonetics in both en-US and da-DK. |
| Trigger-word state machine | Two states: `passive` (continuous low-cost recognition; orb shows small slow pulse animation) and `active` (full speech recognition pipeline; orb shows full amplitude animation). Transition `passive → active` on detecting "Voxio". Transition `active → passive` on (a) silence detection firing after a captured command, or (b) ~5 s of post-activation silence with no further speech. | Explicit visible boundary between listening-for-trigger and listening-for-command. The 5 s safety timeout prevents the app from staying in active state after a stray "Voxio" with no follow-on command. |
| Trigger-in-utterance | A single utterance containing both the trigger and the command ("Voxio, Beosound play") is captured in active state and parsed normally; the leading "Voxio" token is stripped from the transcript before parsing. | Avoids forcing the user into a two-utterance pattern. Stripping is a simple prefix-match on whitespace-bounded "Voxio" / "voxio". |
| Trigger-word privacy | The trigger-word listening phase runs on-device only. No audio buffer, partial transcript, or any other data leaves the device. The same on-device speech-recognition guarantee that v1.0 relied on continues to hold. | Non-negotiable; matches v1.0 privacy NFR. Verified by network audit (T-2609). |
| Mic permission string | `NSMicrophoneUsageDescription` updated to: "Voxio listens for the wake word 'Voxio' so you can control your speakers by voice." (English; Danish translation per `LanguageService`). All processing happens on-device. | The previous v1.0 string assumed always-on listening for any speech. The new string explains the wake-word model. |
| First-launch order | `LanguagePickerSheet` continues to appear on first launch BEFORE trigger-word listening begins. Mic / speech-recognition permissions are still requested before any listening starts. | Preserves the v1.0 first-launch flow. Trigger-word state machine activates only after permissions are granted and a language is selected. |
| Hint copy | `HintCardView` example phrases are updated to include the trigger word: "Try saying: Voxio, Beosound play" / "Prøv at sige: Voxio, Beosound spil". Existing hint behaviour (T-1905 auto-hide and `hasSeenHint` persistence) is unchanged. | Teaches the wake-word pattern at first contact. |

---

## Goals

- A consistent, brand-controlled visual canvas: every screen, sheet, and toast in v1.1 sits on top of `AppBackground.png` in dark mode, regardless of system setting or user wallpaper.
- A single reusable `DarkGlassButton` view used by every button in the app — the language-picker rows, hint dismissal, the trigger-word state hint, and the countdown Cancel control are all rendered through it.
- Sheets (`LanguagePickerSheet`, `ConfirmationSheet`) render in dark mode in 100 % of cases, including when the system is in light mode and when Increase Contrast is enabled.
- Increase Contrast handling is reactive — toggling the system setting while the app is foregrounded re-renders affected views without an app restart.
- Visual parity with the design spec v1.1 button reference image (`ButtonLookAndFeel.png`) is verifiable by side-by-side screenshot review.
- **Parsing accuracy:** measured intent-classification accuracy on a held-out bilingual test set of natural paraphrases improves from the v1.0 keyword baseline to ≥ 92 % (Tier 2 alone) and ≥ 96 % when Tier 1 is available.
- **Parsing privacy:** zero transcripts leave the device. Verified by network audit (T-2417).
- **Parsing latency:** median end-to-end command latency (transcript final → `VoiceCommand` delivered) ≤ 500 ms on Tier 1 (prewarmed) and ≤ 50 ms on Tier 2. The v1.0 functional spec NFR (voice command to action under 3 s on a normal home network) is preserved with margin.
- **Parsing graceful degradation:** if Tier 1 or Tier 2 is unavailable for any reason at runtime, the router transparently falls through to the next tier; the user sees no error and no behavioural difference.
- **Friction reduction at confirmation:** unambiguous parsed commands fire automatically after a 3-second cancellable countdown — no Yes-tap is required. The action-cancel path remains accessible by tap or by voice in both languages.
- **Cancel safety:** any in-flight countdown can be cancelled within the 3-second window by tapping Cancel or by saying "cancel" / "no" / "nej" / "annuller". A successful cancel does not fire the action and does not re-prompt.
- **Battery and listening posture:** the always-on speech recogniser is replaced by a passive trigger-word state. While the app is foregrounded but not actively processing a command, mic-driven CPU/audio cost is materially lower than v1.0 (target: ≥ 30 % reduction in mic-related power draw measured via Instruments Energy gauge over a 5-minute idle session — see NFR §Battery).
- **Trigger reliability:** "Voxio" is detected from a normal speaking distance (≤ 2 m) at conversational volume in a quiet room with ≥ 95 % recall and ≤ 1 false-activation per hour of foregrounded idle time in a household environment with background music or TV at low volume. See US-26 acceptance.
- **Trigger privacy:** the trigger-word listening phase generates no outbound network traffic. Verified by network audit alongside parsing privacy (T-2609 reuses T-2417's harness).
- Zero regression to functional behaviour for v1.0 surfaces NOT explicitly amended: Mozart API, speaker discovery, use-case handlers, error semantics, toast structure, accessibility, animation tokens beyond the new countdown additions, and E-19 usability.

---

## Out of Scope (v1.1)

- **Light mode variant.** The app is intentionally dark-only. System light-mode setting does not change the background, button surfaces, or text colours. Deferred indefinitely.
- **iPad layout / landscape orientation.** v1.1 remains portrait-only on iPhone; the background asset is portrait-only.
- **Animated background.** `AppBackground.png` is a static asset. No CoreMotion-driven parallax or video background.
- **Per-speaker theming.** No accent colour customisation; the warm gold accent (`#C8A97E`) remains the single accent token everywhere.
- **New iconography.** SF Symbols 6 baseline unchanged from v1.0.
- **New voice commands.** v1.1 does not add new intents; the `VoiceCommand` enum is unchanged.
- **New language coverage.** v1.1 does not add languages beyond English and Danish.
- **Settings screen redesign.** Out of scope; settings UI was already deferred in v1.0. **In particular:** the countdown duration is not user-configurable in v1.1 (see Q21); the trigger word is not user-configurable (see Q23).
- **Replacement of the iOS-26-only `.glassEffect` API with a pre-iOS-26 fallback.** Deployment target stays at iOS 26.
- **Renaming `BeoColor.text` / `BeoColor.muted` to `labelPrimary` / `labelSecondary` across the codebase.** T-2100 adds aliases; a full rename is deferred to a future cleanup.
- **Cloud-backed NLU (Wit.ai, Dialogflow, OpenAI, Claude, AWS Lex, Azure CLU).** Eliminated by privacy and offline requirements.
- **CoreML transformer (BERT/distilBERT) parser.** Researcher Rank 3 fallback; deferred unless Tier 2 NLModel cannot meet ≥ 92 % validation accuracy after retraining (see open question Q14).
- **Slot extraction beyond the existing slots** (volume delta/level, favorite index). Tier 1 and Tier 2 produce only the slots already present in `VoiceCommand`. No new slots in v1.1.
- **Adding intents that exist in popular open-source NLU corpora but are not in `VoiceCommand`** (e.g. timer, alarm, smart-home device control). The corpus is filtered down to the existing 13-intent set.
- **Continuous on-device learning / personalisation.** The shipped NLModel is static. Telemetry collection for future retraining is deferred (see open question Q15).
- **Confirm-by-voice during the countdown.** The countdown is silent on confirm — if the user does nothing, the action fires. There is no "yes" / "ja" voice token that fires the action early. (Saying "yes" during countdown is a no-op; the timer continues.) See Q22.
- **Variable countdown duration per intent class.** Destructive intents (e.g. `.stop`) and non-destructive intents (e.g. `.adjustVolume(-5)`) both use the same 3-second countdown in v1.1. See Q21.
- **Skipping the countdown for "safe" intents.** All confirmable intents go through the countdown in v1.1. The set of confirmable intents (defined by the v1.0 `ConfirmationCoordinator`) is unchanged.
- **A second wake word or wake-word personalisation.** The trigger word is fixed to "Voxio". No multi-word triggers, no per-user training, no UI to change it. See Q23.
- **Background / locked-screen wake-word listening.** The wake-word state machine operates only while the app is foregrounded. v1.0 already paused recognition on backgrounding (T-0312); v1.1 keeps this behaviour. Background trigger detection is deferred indefinitely.
- **Audio cue on activation.** Transitioning from passive to active state is signalled visually by the orb animation only; no chime, no haptic. See Q24.
- **Push-to-talk fallback.** No tap-the-orb-to-activate alternative is shipped. The wake word is the only activation path. (If trigger detection fails, the user repeats "Voxio".)
- **Custom keyword-spotting model trained on "Voxio".** The default implementation uses Apple's existing speech-recognition stack. Training a bespoke keyword model is deferred (see Q20).

---

## User Stories

### Design change 1 — Fixed `AppBackground.png`

**US-13 — A consistent dark backdrop on every screen**
> As a user, I want the app to look the same to me as it does to anyone else, regardless of my iOS wallpaper or my Light/Dark Mode preference, so that the experience feels like a deliberate Bang & Olufsen product rather than a skin over my phone.

**Acceptance criteria:**
- The home screen displays `AppBackground.png` full-bleed behind all content, on every launch, on every device the app supports.
- The background extends behind the Dynamic Island, the home indicator, the status bar, and the keyboard area when present.
- The background does not change when the user switches the system between Light Mode and Dark Mode while the app is foregrounded.
- The background does not change when the user changes their iOS wallpaper.
- The image is rendered at native resolution without visible scaling artefacts on iPhone widths from 375 pt (iPhone SE) to 430 pt (Pro Max). Cropping (`scaledToFill`) is permitted; the orb composition remains visually balanced at every supported width.
- Foreground content respects safe-area insets — the background extends into the safe area, but text, cards, and the speaker selector pill do not.
- Keyboard avoidance for any text input continues to work; the background does not push content under the keyboard.

---

**US-14 — The background does not interfere with glass surfaces**
> As a user, I want speaker cards, sheets, and buttons floating over the background to remain readable so that I can always see the speaker name, the current track, and the action the app is about to take.

**Acceptance criteria:**
- The speaker card (`systemMaterial` Liquid Glass) reads as visibly frosted, not transparent, against the dark base of the image. The speaker name is readable at the v1.0 typography sizes without an additional scrim.
- The dark glass pill buttons (US-15) read as buttons, not as flat dark rectangles — the specular hairline edge is visible against the orb regions of the background image.
- The confirmation sheet read-back text remains readable in all sheet positions.
- The live transcription label (during command recognition) remains readable when displayed over any region of the background image.

---

### Design change 2 — Dark Liquid Glass pill button system

**US-15 — A single, recognisable button style throughout the app**
> As a user, I want every button to look and behave the same — same shape, same colour, same press feedback — so that I always know what is tappable and what is not.

**Acceptance criteria:**
- Every interactive button in the app is rendered through a single reusable `DarkGlassButton` view (or its `DarkGlassIconButton` icon-only variant) located in `iOS/Voxio/DesignSystem/`.
- The button is a fully-rounded capsule shape (`Radius.pill = 100`). This replaces the v1.0 `RoundedRectangle(cornerRadius: 12)` shape used by the existing Yes / No / language-picker rows. The shape change is deliberate; `ButtonLookAndFeel.png` from the design team is the visual source of truth.
- The button surface uses the iOS 26 `.glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: Capsule())` API.
- A 0.5 pt `Capsule().strokeBorder(Color.white.opacity(0.15))` overlay is rendered on top of the surface on every instance.
- Default labels render in the `--label-primary` text colour (`BeoColor.text`, aliased as `BeoColor.labelPrimary` after T-2100) at SF Pro Text Medium 15 pt.
- A leading SF Symbol icon, when present, is white by default and sits 6 pt before the label.
- Vertical padding is 10 pt, horizontal padding is 16 pt; icon-only variant is a 36 × 36 pt circle in the same dark glass surface.
- Pressing the button animates a `scaleEffect(0.95)` with spring response 0.3 s, damping 0.7. The `.interactive()` glass-effect modifier provides additional native press feedback (subtle bounce / shimmer); both are present.
- Disabled buttons render at surface opacity 0.4 and do not respond to taps.
- `DarkGlassButton` itself emits no haptics. Haptic feedback remains the responsibility of the call site.

---

**US-16 — The single Cancel button feels destructive without breaking the style system**
> As a user, I want the Cancel control during the countdown to feel obviously destructive (red cue) without the button looking unfamiliar against the rest of the app.

**Acceptance criteria:**
- The `Cancel` variant uses the dark glass pill surface; both the label ("Cancel"/"Annuller") and the leading `xmark` SF Symbol render in system red (`Color.red`) — not a hex value, so the colour adapts to system accessibility rendering.
- The variant shares the exact same shape, padding, border, press animation, and disabled treatment as the default `DarkGlassButton`.
- The Cancel button rendered inside the countdown surface (E-25) and any other future destructive surface uses the same `role: .cancel` rendering — no per-call-site overrides.
- Note: the v1.0 `Confirm` variant (Yes button, gold-tinted checkmark) is no longer rendered anywhere in v1.1 because the Yes button is removed by E-25. The `.confirm` role on `DarkGlassButton` is retained in the source for forward compatibility but has no call sites in v1.1; T-2110 documents this as a deliberate exception.

---

**US-17 — Button hit areas remain ≥ 44 × 44 pt**
> As a user with motor impairments or a large finger size, I want every button — including the icon-only "?" hint button and the language-picker rows — to be reliably tappable.

**Acceptance criteria:**
- Every `DarkGlassButton` instance has an effective hit area of at least 44 × 44 pt, including the icon-only 36 × 36 pt variant (which uses `.frame(minWidth: 44, minHeight: 44)` on the `Button` wrapper to extend the hit area to 44 × 44 pt without changing the visual size).
- The "?" hint button in `HomeView`'s status bar (T-1906) is at least 44 × 44 pt.
- The language-picker rows in `LanguagePickerSheet` (T-1902) are at least 44 × 44 pt.
- The Cancel button in the countdown surface (E-25) is at least 44 × 44 pt.
- The Accessibility Inspector reports no tap-target violations on any screen after v1.1 lands.

---

### Design change 3 — Dark-mode-only visual layer

**US-18 — Sheets stay dark, always**
> As a user with a light-mode iPhone, I want the language picker and the confirmation surface to look exactly like the rest of the app — never to flash as a light-mode panel — so that the experience is uninterrupted.

**Acceptance criteria:**
- When the system is in Light Mode and the user opens the app, the home screen is dark (already true in v1.0 via `WindowGroup.preferredColorScheme(.dark)`).
- When the `LanguagePickerSheet` is presented for the first time on a light-mode device, the sheet content (rows, labels, separators) renders in dark mode. There is no visible flash of light mode at any point during sheet presentation or dismissal.
- When the countdown surface (E-25) is presented after a parsed voice command on a light-mode device, the sheet content renders in dark mode. There is no visible flash of light mode at any point during sheet presentation or dismissal.
- Toggling the system between Light Mode and Dark Mode while the app is foregrounded does not change the appearance of any in-app surface (main window, sheets, toasts, hint card).
- System-rendered alerts (microphone permission, speech recognition permission, local network permission) are governed by iOS and may render in light mode; this is acceptable and out of scope for v1.1. Voxio-rendered surfaces — anything inside the app's `WindowGroup` — must be dark.

---

**US-19 — Increase Contrast is honoured reactively**
> As a user with Increase Contrast enabled in iOS Accessibility settings, I want the dark glass surfaces to gain a stronger border so they remain readable, and I want that change to take effect the moment I toggle the setting — not on next app launch.

**Acceptance criteria:**
- When the user enables Increase Contrast in Settings → Accessibility while the Voxio app is running and foregrounded, all dark glass surfaces (`DarkGlassButton`, speaker card, countdown surface, language picker sheet, toasts, hint card) re-render within 1 second to apply the high-contrast variant. The user does not need to background and re-foreground the app.
- The high-contrast variant of `DarkGlassButton` increases the border width to 1.0 pt (from 0.5 pt) and uses `BeoColor.muted` (aliased as `BeoColor.labelSecondary` after T-2100) for the border colour instead of `white.opacity(0.15)`.
- The high-contrast variant of the speaker card adds a 1 pt border in `BeoColor.muted` to its rounded-rect surface.
- Increase Contrast detection is implemented via `@Environment(\.colorSchemeContrast)` in SwiftUI view code. T-2204 audits the codebase for any `UIAccessibility.isContrastEnabled` references and confirms zero hits before closing as N/A.
- Increase Contrast does not change the background image, the typography sizes, the colour palette, or the haptic / animation system. Only border treatments and blur intensity change, per design spec v1.1 §Accessibility.
- VoiceOver, Dynamic Type, and Reduce Motion behaviour is unaffected by this change.

---

### Voice command parsing improvement

**US-20 — Natural-language paraphrases are recognised**
> As a user, I want the app to understand commands the way I'd naturally say them — "could you turn it down a bit", "let's pause for a sec", "play my second favourite" — not just the canonical phrasings, so that I don't have to memorise an exact script.

**Acceptance criteria:**
- The released app correctly classifies at least 92 % of utterances in the held-out bilingual paraphrase test set (T-2415) into the correct `VoiceCommand` case.
- "could you turn it down a bit" → `.adjustVolume(-10)` (volume delta uses the existing `defaultVolumeStep`).
- "let's pause for a sec" → `.pause`.
- "play my second favourite" / "spil min anden favorit" → `.playFavorite(index: 2)`.
- "shut it" / "vær stille" → `.mute`.
- Unrecognised input (e.g. "what's the weather") returns `.unknown(transcript)`, with no false-positive routing into `.playDefault` or any other intent.
- All canonical phrasings that the v1.0 `CommandParser` already handles continue to be classified correctly. No regression on the existing v1.0 test corpus (T-2416 enforces this).

---

**US-21 — Parsing works on every supported device**
> As a user on any iPhone the app supports, I want voice commands to work reliably regardless of whether my device has Apple Intelligence — I should not see a degraded experience on an older phone.

**Acceptance criteria:**
- On a device without Apple Intelligence available (any iPhone running iOS 26 below A17 Pro, or with Apple Intelligence disabled), Tier 2 NLModel classification operates as the primary parser. Field testing on iPhone 13 (A15) and iPhone 14 (A15) shows no functional difference in command outcomes versus an iPhone 15 Pro (A17 Pro) running with Tier 1 active, on the canonical phrasings used in v1.0 acceptance.
- On a device with Apple Intelligence available, Tier 1 (Foundation Models) operates as the primary parser. The user perceives no difference except improved paraphrase recognition.
- The tier in use is recorded at app session start in the log at INFO level (`Log.info("[CommandParserRouter] tier=… language=…")`).
- Switching active language at runtime (via `LanguagePickerSheet`) re-initialises the router with the appropriate Tier 2 model and Tier 1 prompt context within 1 second.

---

**US-22 — Parsing is private and offline**
> As a user, I want every voice command I issue to be processed entirely on my phone — nothing about what I say should leave the device.

**Acceptance criteria:**
- A network packet capture taken during a sustained command session (10 commands across both languages) shows zero outbound traffic from the parsing pipeline. The only network traffic observed is the existing Mozart REST/WebSocket traffic already covered by E-02.
- The app continues to classify commands with full accuracy when the device is in Airplane Mode (with WiFi/Bluetooth re-enabled to keep the LAN speaker connection alive).
- No third-party SDK that performs cloud NLU is added to the build (audited per T-2417).

---

**US-23 — Parsing latency does not regress the 3-second NFR**
> As a user, I want the system to react to my command at least as quickly as v1.0 did — the move to a smarter parser should not make the app feel slower.

**Acceptance criteria:**
- Median time from `isFinal` transcript to `onCommand` callback is ≤ 500 ms on Tier 1 (Foundation Models, prewarmed) and ≤ 50 ms on Tier 2 (NLModel) on the minimum-spec device (iPhone 13, A15).
- 95th percentile time from `isFinal` transcript to `onCommand` callback is ≤ 1.5 s on Tier 1 and ≤ 200 ms on Tier 2.
- The v1.0 functional spec NFR — total voice command to action under 3 s on a normal home network — continues to hold with margin (≥ 1 s headroom for the Mozart REST round-trip).
- Tier 1 session is pre-warmed at app launch (during the existing mic / permission setup phase in `VoxioApp` startup) so the first command after launch does not pay a cold-start cost.

---

### Auto-execute confirmation with countdown cancel

**US-24 — Confirmation runs without an explicit Yes tap**
> As a user, I want the app to act on what I just said without making me tap "Yes" every time, so that voice control stays voice-first.

**Acceptance criteria:**
- After a command is parsed and the spoken read-back (TTS) completes, a countdown surface appears showing "Cancelling in 3… 2… 1…" (localised: "Annullerer om 3… 2… 1…").
- The countdown decrements once per second; the displayed digit updates exactly at each whole-second boundary.
- If 3 seconds elapse without cancellation, the parsed action fires automatically (the same `Use-Case Handler` call path that v1.0 fired on Yes-tap).
- There is no Yes button visible at any point during the countdown. Tapping the dismissed area below the countdown surface does NOT trigger the action.
- The countdown surface contains exactly one button — the Cancel control.
- The visual countdown surface uses the dark Liquid Glass styling from E-21 (Capsule, hairline border, dark mode).
- The Cancel button uses `DarkGlassButton(role: .cancel)` per US-16.
- VoiceOver: the surface announces "Action will execute in 3 seconds. Say cancel to stop." at countdown start. VoiceOver does not re-announce on each tick.
- Haptics: a `.medium` impact fires when the countdown starts (re-wired from T-1108 sheet-appear). A `.success` notification fires when the action auto-executes (re-wired from T-1109 confirm-tap). On cancel, a `.error` notification fires.
- The countdown surface dismisses immediately on auto-execute or on cancel; it does not linger after either resolution.
- If the parsed command is `.unknown`, no countdown is shown — the existing v1.0 unknown-command behaviour from E-09 fires instead.

---

**US-25 — Cancel is reliably reachable by tap or by voice**
> As a user who said something the app misheard, I want to stop the action before it happens — by tapping Cancel or by simply saying "cancel" — without needing to fight the UI.

**Acceptance criteria:**
- Tapping the Cancel button at any point during the 3-second countdown cancels the action. The bound action is NOT invoked, the countdown surface dismisses, and a `.error` notification haptic fires.
- Saying "cancel" (en) or "annuller" (da) or "no" (en) or "nej" (da) at any point during the 3-second countdown cancels the action. Match is case-insensitive on whole-word boundary in the active speech-recognition transcript stream.
- A cancel command spoken before the read-back completes (i.e. before the countdown starts) does NOT cancel — there is nothing to cancel yet. The user must speak after read-back. (This matches v1.0 behaviour where Yes/No buttons were not visible during read-back.)
- After a successful cancel, the app returns to the trigger-word passive state (E-26) — the user does NOT need to re-trigger or re-issue the cancel.
- After an auto-execute (no cancel within 3 s), the app returns to the trigger-word passive state.
- A cancel that arrives in the same audio buffer as the auto-execute timer expiry resolves to **cancel** (cancellation wins ties). The bound action is not fired.
- VoiceOver users: tapping the Cancel button reads "Cancelled" before dismissing (announced via `UIAccessibility.post(.announcement, ...)`).
- The countdown is visible to assistive technologies (VoiceOver focus, Switch Control). The Cancel button receives focus on countdown appear so a Switch Control user can confirm-cancel by activating the focused element.
- Reduce Motion: the countdown digit substitution is instantaneous (no scale/opacity transition). The countdown remaining duration is unchanged. The `.medium` haptic on countdown start still fires.

---

### "Voxio" trigger word

**US-26 — The app listens passively until I say "Voxio"**
> As a user with the app open in the foreground, I want the app to wait quietly for me to say "Voxio" before it pays attention to my words, so that incidental conversation doesn't trigger unwanted commands.

**Acceptance criteria:**
- On app launch, after permissions are granted and the language has been chosen (or pre-existing language selection has been read), the orb enters the **passive** state. The orb renders a small slow pulse animation distinct from the v1.0 active animation.
- In passive state, the app's speech-recognition pipeline is engaged in a low-cost continuous mode that scans for the trigger word "Voxio" only. No transcript is delivered to the parser.
- When "Voxio" is detected (case-insensitive, whole-word match in the partial transcript), the orb transitions to the **active** state within 250 ms. The orb animation switches to the full-amplitude v1.0 listening animation.
- In active state, the app captures the next utterance for parsing exactly as it did in v1.0 (the `silenceTimeout` and final-transcript path are unchanged).
- A single utterance that contains both the trigger and the command ("Voxio, Beosound play") activates the app and is captured for parsing in the same active session. The leading "Voxio" / "voxio" token (and any directly following comma or whitespace) is stripped from the transcript before it is handed to the parser.
- Trigger-word recognition runs on-device (verified by T-2609 packet capture).
- The trigger word is detected at a normal speaking distance (≤ 2 m) and conversational volume in a quiet room with ≥ 95 % recall in a 50-utterance test (T-2607).
- False-activation rate is ≤ 1 per hour during a 1-hour foregrounded idle test in a household environment with low-volume background music or TV (T-2608).
- The trigger word is detected in both English and Danish locales — pronunciation `/ˈvɒk.si.oʊ/` works regardless of active language.
- VoiceOver: when the orb transitions passive → active, an announcement "Listening" is posted. When the orb transitions active → passive, "Stopped listening" is posted.

---

**US-27 — The orb tells me which state I'm in**
> As a user, I want to see at a glance whether the app is waiting for "Voxio" or actively listening for a command, so that I never mistake one state for the other.

**Acceptance criteria:**
- The passive-state orb is visibly different from the active-state orb at a glance: smaller scale (≤ 70 % of active scale), slower pulse cycle (≥ 2 s per cycle vs active's responsive amplitude), and a less saturated colour treatment per the design tokens.
- The transition between passive and active is animated (≤ 250 ms). Reduce Motion replaces the animation with a cross-fade.
- The active-state orb continues to behave exactly as in v1.0 — its scale and glow respond to the live RMS audio level from the mic.
- After ~5 seconds of post-activation silence with no captured speech, the orb returns to passive. (This safety timeout exists to recover from a stray "Voxio" with no follow-on command.)
- After a captured command's silence-detection finalises, the orb returns to passive once the command has been parsed and either auto-executed or cancelled (E-25 resolution).
- The home screen status text reflects the state in plain language: "Say 'Voxio' to start" in passive; "Listening…" in active. Localised in both languages.
- The hint card (T-1905, updated by T-2604) shows trigger-word example phrases on first launch: "Try saying: Voxio, Beosound play" / "Prøv at sige: Voxio, Beosound spil".
- When the app moves to the background (existing v1.0 T-0312 behaviour), the orb stops both pulsing and animating and the recogniser stops. On returning to foreground, the orb resumes in passive state.
- The state is recorded in the log on every transition: `Log.info("[TriggerWord] state passive→active")` and `… active→passive reason=silence|command`.

---

## Error States

All scenarios below are visual-layer regressions caught during v1.1, plus parsing-layer error scenarios introduced by E-24, plus countdown- and trigger-word error scenarios introduced by E-25 / E-26. Each maps to an explicit observable behaviour. No new spoken error strings are introduced — voice and error semantics from v1.0 §E-09 are unchanged.

| Scenario | Expected Behaviour |
|---|---|
| `AppBackground.png` asset missing from `Assets.xcassets` | App fails the build (Xcode asset-catalog warning escalated to error in CI). No runtime fallback to gradient. |
| Image fails to render at runtime (corrupted asset) | Show a flat `Color(hex: "#0A0E1A")` (deep navy) as the background fallback, log `Logger.error("AppBackground render failed")`. App does not crash. |
| `.glassEffect` is unavailable at runtime (theoretical: build deployed to a sub-iOS-26 device) | Build is rejected by App Store / Xcode at upload time; no runtime path required because deployment target is iOS 26. |
| `LanguagePickerSheet` presented in light mode without local `.preferredColorScheme(.dark)` | The sheet renders as a light panel (regression). v1.1 acceptance: this state must not occur. Verified by snapshot test (T-2304). |
| Countdown surface presented in light mode without local `.preferredColorScheme(.dark)` | Same as above; verified by snapshot test (T-2502). |
| Increase Contrast toggled while app is foregrounded | All `DarkGlassButton` instances and the speaker card re-render with high-contrast borders within one display frame of the SwiftUI environment update. No manual notification handling. |
| `DarkGlassButton` used inside a non-dark presentation boundary (e.g. a future popover) | Button still renders correctly because its tint, border, and label colours are not derived from the colour scheme — they are explicit token values. No regression expected. |
| Hit area smaller than 44 × 44 pt on icon-only `DarkGlassIconButton` | Build-time SwiftUI preview test (T-2210) verifies `.frame(minWidth: 44, minHeight: 44)` is applied. CI snapshot regression test catches violations. |
| Background does not extend behind Dynamic Island | Visual regression; verified by snapshot test on iPhone 15 Pro / 16 Pro frame (T-2104). |
| `DarkGlassButton` references `BeoColor.labelPrimary` before T-2100 ships | Compile error. T-2100 must merge before T-2102 (the component) builds. The dependency graph in E-21 makes this explicit. |
| `DarkGlassButton` accidentally fires a haptic on tap | Regression — would result in double-haptic during the countdown flow (countdown-start `.medium` impact + a third unwanted haptic from the component). T-2503 acceptance forbids this. |
| Foundation Models framework is unavailable at runtime (Apple Intelligence disabled, A15/A16 device, or model not yet downloaded) | Router records Tier 1 unavailable at session start; falls through to Tier 2 NLModel. User sees no error and no behavioural difference. Logged at INFO. |
| Foundation Models call returns `.unknown` or fails (timeout, model busy, transient error) | Router falls through to Tier 2 for that single utterance. Logged at INFO. The next utterance retries Tier 1 normally. No retry storm. |
| Tier 1 latency exceeds 1.5 s for a single utterance | Router does not interrupt the call (cancellation would corrupt the structured-output state). The call completes; the result is delivered. Latency exceedance is recorded in a rolling counter for telemetry (T-2418). If three consecutive Tier 1 calls exceed 1.5 s within a session, the router downgrades to Tier 2 for the remainder of the session and logs `Log.info("[CommandParserRouter] downgrade tier=2 reason=latency")`. |
| Tier 2 NLModel produces low-confidence prediction (below the per-language threshold from T-2410) | Router falls through to Tier 3 keyword `CommandParser`. If Tier 3 returns `.unknown`, the user-visible result is `.unknown(transcript)` exactly as in v1.0. No silent misclassification. |
| Tier 2 NLModel asset missing from the bundle for the active language | Build fails at link time (model file is a build resource). No runtime fallback — both English and Danish models must ship. |
| Tier 2 NLModel returns an intent slot value out of range (e.g. `.playFavorite(index: 7)`) | Router rejects the prediction and falls through to Tier 3. Index range is fixed at 1–4 per the existing v1.0 contract. Logged at INFO. |
| Active language switched mid-utterance (e.g. user opens picker while command is being processed) | The in-flight utterance completes against the language that was active when the transcript was finalised. The next utterance uses the new language. No cross-language routing of a single utterance. |
| Tier 1 session not yet prewarmed when the first command arrives | Router awaits the prewarm task (it starts at app launch); first-command latency may extend to ~600–800 ms instead of ~400 ms. Subsequent commands are at the prewarmed latency. Acceptable per T-2418 observation budget. |
| Network packet capture detects outbound traffic from the parsing pipeline | Test failure (T-2417). Spec acceptance forbids any non-Mozart outbound traffic from the parsing path. |
| Read-back TTS still playing when the 3-second timer would otherwise fire | The countdown does not start until TTS completes. If TTS overruns its expected duration, the countdown also delays. The combined (TTS + countdown) duration may exceed the v1.0 3-second total NFR — acceptable, because v1.0 already had unbounded TTS as a precondition for confirmation. |
| User taps Cancel after the auto-execute has already fired | The tap is a no-op. The countdown surface has already dismissed; there is no Cancel target on screen. (This is a tie-breaker for a sub-display-frame edge case; the action has already gone to the use-case handler.) |
| User says "cancel" simultaneously with the timer expiry | Cancellation wins ties. The bound action is not invoked. `.error` haptic fires; `.success` does not. Logged at INFO `[Countdown] tie cancel` for diagnostics. |
| User says "cancel" before read-back completes | No-op. The countdown has not yet started; there is nothing to cancel. The read-back continues to completion, the countdown then starts normally, and a *fresh* "cancel" said during the countdown will then cancel. (This is a deliberate constraint — see Q22 alternative.) |
| `.unknown` parsed command reaches the confirmation pipeline | No countdown is shown. Existing v1.0 unknown-command behaviour from E-09 fires (toast or read-back of "Sorry, I didn't catch that"). |
| Countdown surface dismissed by an OS-level event (e.g. incoming call interrupts the foreground app) | The countdown is cancelled (treated as if the user had cancelled). The bound action does not fire. The user must re-issue the command after the interruption. Logged at INFO `[Countdown] cancelled reason=interruption`. |
| Trigger-word recogniser fails to start (microphone permission revoked at runtime, or speech-recognition authorisation revoked) | Status text shows the existing v1.0 mic/speech permission denied string (UIStrings `micAccessDenied`). Orb stops animating. The user must grant permissions in Settings to recover. |
| Trigger-word recogniser drops audio buffers under system pressure | The state remains passive; the user re-saying "Voxio" recovers normally. Buffer drops are logged at VERBOSE; not surfaced to the UI. |
| User says "Voxio" while orb is already in active state | No-op. The active session continues to capture the utterance; the leading "Voxio" is stripped from the transcript before parsing per US-26. |
| 5-second silence timeout fires while orb is in active state with no captured speech | Orb returns to passive. Status text reverts to "Say 'Voxio' to start". No error surfaced. Logged at INFO `[TriggerWord] active→passive reason=silence`. |
| User backgrounds the app during the countdown | The countdown is cancelled (per the OS-interruption row above). On returning to foreground, the orb resumes in passive state. |
| Network packet capture detects outbound traffic from the trigger-word pipeline | Test failure (T-2609). Spec acceptance forbids any outbound traffic from the trigger-word path. |
| Bonjour / mDNS discovery interruption while in active state | Unrelated to the trigger-word path; existing v1.0 behaviour from E-04 applies. The trigger-word state machine is independent of speaker discovery. |

---

## Non-Functional Requirements

- **Performance:** Background image render adds no measurable frame-rate cost on iPhone 12 (A14) or newer; 60 fps maintained during sheet present/dismiss and during command-recognition card scale animation. Re-verify with the v1.0 60 fps target from T-1410.
- **Memory:** `AppBackground.png` is loaded once and cached by SwiftUI's `Image` view; no per-frame decoding. Asset peak memory ≤ 5 MB. Tier 2 NLModel files (per language) ≤ 200 KB each on disk; loaded into memory at router init and held for the session. The trigger-word recogniser holds at most one rolling audio buffer of ≤ 1 s; total memory cost ≤ 2 MB while in passive state.
- **Asset size:** `AppBackground.png` ≤ 600 KB shipped (PNG, optimised; design spec dimensions 642 × 1077 px). Combined Tier 2 NLModel assets ≤ 500 KB shipped (both languages).
- **Latency:**
  - No regression to the v1.0 functional spec NFR — voice command to action under 3 s on a normal home network. Note: the auto-execute countdown ADDS 3 s between the parsed command and the action firing, which is intentional and outside the v1.0 NFR's measurement scope (the v1.0 NFR measures *intent → speaker reacts* assuming a Yes-tap; v1.1 trades the Yes-tap for the countdown).
  - Tier 1 parsing: median ≤ 500 ms, p95 ≤ 1.5 s (prewarmed).
  - Tier 2 parsing: median ≤ 50 ms, p95 ≤ 200 ms.
  - Tier 3 parsing: ≤ 5 ms (unchanged from v1.0).
  - Trigger-word detection: median time from the `o` of "Voxio" reaching the mic to the orb showing the active animation ≤ 250 ms.
  - Countdown digit update: each whole-second decrement renders within one display frame of its scheduled time (≤ 16.67 ms drift on a 60 Hz display).
- **Accessibility:**
  - Minimum tap target 44 × 44 pt, including icon-only buttons (US-17) and the countdown Cancel button.
  - Increase Contrast reactive within 1 s of toggling system setting (US-19).
  - VoiceOver, Dynamic Type, Reduce Motion behaviours preserved exactly per v1.0 §E-13. New VoiceOver announcements: countdown-start ("Action will execute in 3 seconds. Say cancel to stop."), countdown-cancel ("Cancelled"), state transitions ("Listening" / "Stopped listening"). Reduce Motion: countdown digit substitution is instantaneous; orb passive↔active transition is a cross-fade rather than a scale animation.
- **Privacy:** Unchanged from v1.0. All parsing tiers and the trigger-word recogniser run on-device; no transcript or audio leaves the device. Verified by network audit (T-2417 + T-2609).
- **Localisation:** All button labels (`Cancel`/`Annuller`, `Got it`/`OK`) continue to flow through the existing `LanguageService` and `String(localized:)` paths from E-17. No new localisation infrastructure. Tier 1 is given an English/Danish prompt template per active language; Tier 2 uses per-language `.mlmodel` files. New strings introduced in v1.1: "Cancelling in {n}…" / "Annullerer om {n}…", "Action will execute in 3 seconds. Say cancel to stop." / "Handlingen udføres om 3 sekunder. Sig annuller for at stoppe.", "Say 'Voxio' to start" / "Sig 'Voxio' for at starte", "Try saying: Voxio, Beosound play" / "Prøv at sige: Voxio, Beosound spil".
- **Testability:** Every screen has a snapshot test in dark mode, in dark + Increase Contrast mode, and at the smallest and largest Dynamic Type sizes. The parsing pipeline has a unit test corpus covering ≥ 50 paraphrases per intent per language with a held-out 10 % test split. The countdown has unit tests covering the auto-execute, button-cancel, voice-cancel, tie-resolution, and OS-interruption paths. The trigger-word state machine has unit tests covering passive→active, active→passive (silence), active→passive (command resolved), and the trigger-in-utterance prefix-strip.
- **Haptic preservation and reassignment:** v1.0 haptics from T-1108 (sheet-appear `.medium` impact) and T-1109 (confirm-tap `.success` notification) are **re-wired** in v1.1 — not lost. T-1108 `.medium` now fires on countdown start (T-2503). T-1109 `.success` now fires on auto-execute (T-2504). A new `.error` notification fires on cancel (T-2505). `DarkGlassButton` itself emits no haptics.
- **Parsing accuracy floor:** Tier 2 NLModel must achieve ≥ 92 % validation accuracy per language on the held-out test split before being shipped. Tier 1 (when active) is expected to add 4–6 percentage points but is not gated on a fixed minimum; Tier 2 carries the contractual floor.
- **Parsing robustness:** Tier 1 unavailability, Tier 1 timeout, Tier 2 low confidence, and Tier 2 missing-model conditions all degrade gracefully without a user-visible error message; behaviour collapses cleanly to Tier 3 (keyword) → `.unknown` exactly as in v1.0.
- **Battery (trigger-word power posture):** While foregrounded and idle in passive state, the trigger-word recogniser draws materially less power than v1.0's always-on full speech recognition. Target: ≥ 30 % reduction in mic-attributed energy use measured via Xcode Instruments Energy gauge over a 5-minute idle session on iPhone 13 (A15). Method and result documented in `Specification/Voxio 1.1/parsing/battery-report.md`. If the default `SFSpeechRecognizer`-based implementation does not hit this target, T-2603 directs investigation of the iOS 26 keyword-spotting API per Q20 before ship.
- **Trigger-word reliability:** Recall ≥ 95 % at conversational distance and volume in a quiet room across a 50-utterance bilingual test set (T-2607). False-activation rate ≤ 1 per hour during a 1-hour foregrounded idle test in a household environment (T-2608).
- **Countdown safety:** Ties between an arriving cancel (touch or voice) and the timer expiry resolve to **cancel**. Verified by unit test (T-2509).

---

## Epics and Tasks

Epics and tasks are broken down in `epics-and-tasks-voxio-1.1.md`.

---

## Open Questions

1. **AppBackground.png delivery format** — Owner: Design team. Default assumption: design provides a single 642 × 1077 px PNG with @1x, @2x, @3x scales pre-exported, ≤ 600 KB optimised. Question: is a vector / SVG source available in case future iPad layouts re-open the asset?
2. **Confirm role icon tint colour token name** — Owner: Design team. Default assumption: re-use the existing `BeoColor.accent` (`#C8A97E`) token from v1.0. Question: should v1.1 introduce a dedicated `confirmIconTint` token for future flexibility, or stay coupled to `accent`? (Note: the `.confirm` role has no v1.1 call sites because the Yes button is removed by E-25; the question is about the role definition being kept in source for forward compatibility.)
3. **Cancel role label/icon colour token** — Owner: Design team. Default assumption: use `Color.red` (system adaptive red), matching design spec v1.1 and ADR-001-v1.1-visual-layer §Implementation Notes. Question: should this be tokenised as `BeoColor.destructive` to align with the v1.1 design tokens reference (`--destructive`)?
4. **Increase Contrast border colour** — Owner: Design team. Default assumption: `BeoColor.muted` (alias `labelSecondary`, hex `#A09488`) at 1.0 pt width per design spec §Accessibility. Question: confirm the spec means `--label-secondary` and not a dedicated high-contrast token.
5. **System alerts in light mode** — Owner: Engineering / Product. Default assumption: out of scope for v1.1; system-rendered permission alerts (microphone, speech, local network) follow iOS appearance and are accepted. Question: should we add `window.overrideUserInterfaceStyle = .dark` via a UIKit scene delegate to also dark-mode system alerts, accepting the cost of a UIKit shim?
6. **Existing `UIAccessibility.isContrastEnabled` call sites** — Owner: Engineering. Default assumption: the codebase is SwiftUI-first and contains zero references; T-2204 closes as N/A. Question: confirm by grep before T-2204 is closed.
7. **Speaker selector pill (T-1004) consistency** — Owner: Design team. Default assumption: the speaker selector pill keeps its v1.0 style (gold-tinted active state, Liquid Glass surface) and is explicitly excluded from `DarkGlassButton` adoption (T-2110 lists it as an exception). Question: confirm the design intent — should the selector pill be migrated to `DarkGlassButton` in a future release?
8. **Snapshot testing infrastructure** — Owner: Engineering. Default assumption: `swift-snapshot-testing` (Point-Free) is added if not already present, configured to write reference images to `iOS/VoxioTests/__Snapshots__/`. Question: confirm the snapshot library choice and whether new test target wiring is required.
9. **`scaledToFill` cropping risk on SE-class devices** — Owner: Design team. Default assumption: the orb composition tolerates ~5–10 % horizontal crop without losing visual balance. Question: provide a safe-area indicator on the source asset or confirm the crop tolerance.
10. **Asset-missing fallback colour** — Owner: Design team. Default assumption: `Color(hex: "#0A0E1A")` deep navy used as the runtime fallback (T-2006) if the image asset fails to render. Question: confirm the fallback hex value.
11. **Design spec §Button Style prose refresh** — Owner: Design team. Default assumption: the design spec's legacy prose mentioning `.ultraThinMaterial` is refreshed to reference the iOS 26 `.glassEffect` API, matching this functional spec's Technical Context table. Question: confirm timeline for the design-spec edit so engineering and design references stay in sync. Identified by ADR-001-v1.1-visual-layer §Conflict 2.
12. **`BeoColor` rename vs. alias strategy** — Owner: Engineering. Default assumption: aliases via T-2100 (`labelPrimary` / `labelSecondary` mapped to `text` / `muted`). A full rename is deferred to a future cleanup. Question: schedule the full rename, or accept the aliases indefinitely?
13. **Foundation Models API stability at iOS 26 GA** — Owner: Engineering. Default assumption: the Foundation Models framework remains as documented at WWDC25; if the API changes between Xcode 26 beta and Xcode 26 GA, the Tier 1 implementation absorbs the change inside `FoundationModelsParser` without affecting Tier 2 or Tier 3. Risk accepted. Question: monitor Apple release notes through ship; if Tier 1 is withdrawn, document the decision and ship with Tier 2 as the maximum tier.
14. **NLModel accuracy floor fallback to CoreML transformer** — Owner: ML / Engineering. Default assumption: Tier 2 NLModel achieves ≥ 92 % validation accuracy after corpus tuning; if it does not, the spec's escalation path is to swap Tier 2 for a fine-tuned distilBERT (researcher Rank 3 path) — a separate epic, deferred. Question: trigger a CoreML-transformer epic only if T-2409 evaluation falls below the floor after two retraining rounds.
15. **On-device telemetry for future retraining** — Owner: Engineering / Product. Default assumption: no telemetry collection in v1.1; corpus is static. Question: should v1.2 add an opt-in mechanism to capture failed-classification transcripts (with explicit user consent) for offline retraining?
16. **Open-source corpus licence audit** — Owner: ML / Legal. Default assumption: only corpora with redistribution-permissive licences (MIT, Apache 2.0, CC-BY) are included; share-alike (CC-BY-SA) corpora are excluded to avoid downstream obligations on the trained model. Question: confirm the legal review and document the exact licences chosen in `corpus-sources.md` (T-2401).
17. **Tier 1 prompt engineering** — Owner: Engineering. Default assumption: per-language system prompts are concise (a few sentences each) describing the speaker context and the 13-intent menu, leveraging guided generation rather than few-shot examples to keep token cost low. Question: do we need few-shot examples to handle Danish edge cases the model is weaker on?
18. **Latency budget when Apple Intelligence model is downloading** — Owner: Engineering. Default assumption: if the Foundation Models on-device model is not yet downloaded (a state Apple exposes via availability), Tier 1 is treated as unavailable for the session and the router operates as Tier 2 + Tier 3 only; the user sees no error. Question: confirm the availability API surfaces this distinct "downloading" state and that we treat it as unavailability.
19. **Slot ambiguity ("turn it down a bit") default delta** — Owner: Engineering / Product. Default assumption: "a bit" with no number maps to the existing `defaultVolumeStep = 10` from the v1.0 `CommandParser`. Question: keep `10`, or make it configurable per language?
20. **iOS 26 dedicated keyword-spotting API** — Owner: Engineering. Default assumption: the default implementation of `TriggerWordDetector` uses `SFSpeechRecognizer` in continuous on-device mode (T-2601). T-2603 investigates whether iOS 26 exposes a lower-power alternative (a dedicated keyword-spotting primitive in `Speech.framework` or `AudioToolbox`). Decision rule: adopt the dedicated API if it exists and is at least 30 % more power-efficient than the default, otherwise keep the default and accept the battery cost. Question: complete T-2603 before T-2606 begins so the implementation choice is settled.
21. **Countdown duration tunability** — Owner: Engineering / Product. Default assumption: 3 seconds, fixed, the same for every confirmable intent in v1.1. Question: should v1.2 offer a Settings toggle (e.g. 2 / 3 / 5 s) or a per-intent duration (e.g. shorter for safe intents like volume-down, longer for destructive intents like stop)?
22. **Confirm-by-voice during countdown** — Owner: Product. Default assumption: there is no "yes" / "ja" voice token that fires the action early during the countdown — the user simply does nothing and waits. Question: should saying "yes" fire the action immediately (skipping the remaining countdown), or should the silence-only model be retained for simplicity?
23. **Trigger-word personalisation** — Owner: Product. Default assumption: the trigger word is fixed to "Voxio". No multi-word triggers, no per-user training, no Settings UI to change it. Question: should v1.2 let the user change the trigger word, or train a personalised acoustic model on the user's voice?
24. **Audio cue on activation** — Owner: Design / Product. Default assumption: passive→active is signalled visually only (the orb animation change in T-2606); no chime, no haptic. Question: should we add a soft chime or a `.light` haptic on activation, accepting the privacy/UX cost (audible cue may bother nearby people; haptic increases mic-vibration coupling risk)?

---

## Resolved Decisions

| Question | Decision |
|---|---|
| Background source for v1.1? | Fixed `AppBackground.png`; not user wallpaper, not a gradient. Supersedes T-1001. |
| Light-mode variant? | Out of scope. Dark-mode only at the visual layer. |
| Button material API? | iOS 26 native `.glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: Capsule())`. **Authoritative over the design-spec §Button Style prose mentioning `ultraThinMaterial`** (legacy wording, design team to refresh — see Q11). |
| Button border? | 0.5 pt `Capsule().strokeBorder(Color.white.opacity(0.15))`. Use `strokeBorder`, not `stroke`. |
| Button shape? | `Capsule()` — fully-rounded pill. **Replaces v1.0's `RoundedRectangle(cornerRadius: 12)` ad-hoc shape.** Visible design change verified against `ButtonLookAndFeel.png` reference image during T-2304 snapshot tests. |
| `HintCardView` button shape? | Capsule, same as every other `DarkGlassButton`. **Replaces the v1.0 `RoundedRectangle(cornerRadius: Radius.sheet)` (16 pt) shape used by the hint dismiss button.** The hint card itself remains `RoundedRectangle(cornerRadius: Radius.card)` — only the button inside changes shape. See T-2109. |
| Where does `DarkGlassButton` live? | `iOS/Voxio/DesignSystem/DarkGlassButton.swift`, alongside `BeoColor.swift` and `DesignTokens.swift`. |
| How is the Confirm action visually distinguished? | The `.confirm` role retains the gold-tinted checkmark + white label rendering in source for forward compatibility, but **has no call sites in v1.1** because the Yes button is removed by E-25. |
| How is the Cancel action visually distinguished? | Same dark glass pill; both label and icon in `Color.red` (system adaptive — not a hex value). Used in v1.1 as the countdown Cancel control. |
| Sheet dark mode? | Each sheet body root explicitly applies `.preferredColorScheme(.dark)` in addition to the `WindowGroup`-level modifier. Includes the new countdown surface (T-2203). |
| Increase Contrast detection API? | SwiftUI `@Environment(\.colorSchemeContrast)`. T-2204 audits for any `UIAccessibility.isContrastEnabled` references (expected zero) and closes as N/A. |
| Increase Contrast effect on `DarkGlassButton`? | Border width increases to 1.0 pt and border colour becomes `BeoColor.muted` (alias `labelSecondary`). Shape, padding, and animation unchanged. |
| Pre-iOS-26 fallback for `.glassEffect`? | None. Deployment target stays at iOS 26. |
| `GlassEffectContainer` required for buttons? | No. Required only when multiple glass surfaces should visually merge — single buttons render correctly without it. |
| Hit area policy? | Minimum 44 × 44 pt for every interactive element, including the visually 36 × 36 pt icon-only variant which uses `.frame(minWidth: 44, minHeight: 44)` on the outer `Button` wrapper. |
| Animation system changes? | Additive only beyond v1.0. v1.0 spring tokens (`BeoAnimation.spring`, `cardExpand`, `toast`) remain authoritative. New tokens added under `OrbState` (T-2606) for the passive/active orb transition. The countdown digit substitution is instantaneous (no animation). |
| Haptics in `DarkGlassButton`? | **None.** The component does not call `UIImpactFeedbackGenerator` or `UINotificationFeedbackGenerator`. Haptics live at call sites: T-2503 countdown-start `.medium` impact (re-wiring of v1.0 T-1108); T-2504 auto-execute `.success` notification (re-wiring of v1.0 T-1109); T-2505 cancel `.error` notification (new in v1.1). |
| `BeoColor` naming? | Codebase uses `text` and `muted`. T-2100 adds aliases `labelPrimary` and `labelSecondary` so v1.1 code can use either name. No rename in v1.1. |
| New tokens added in v1.1? | `appBackground` asset constant; `DarkGlassButton.{overlayColor, borderColor, borderWidth, paddingV, paddingH, iconGap, iconOnlySize, pressedScale, pressSpringResponse, pressSpringDamping}`; `BeoColor.labelPrimary` / `BeoColor.labelSecondary` aliases; `OrbState.{passiveScale, passivePulseDuration, transitionDuration}`. |
| Are any v1.0 tasks removed? | No tasks are *deleted* from v1.0. Superseded by v1.1: T-1001 (E-20), T-1104 (E-25 — Yes button removed entirely), T-1105 (E-25 — No button replaced by countdown Cancel), T-1108 (E-25 — haptic re-wired to countdown start), T-1109 (E-25 — haptic re-wired to auto-execute), T-0805 (E-25 — 10 s timeout replaced by 3 s auto-execute), T-0301, T-0302, T-0303 (E-26 — always-on listening replaced by trigger-word state machine), T-1801 through T-1810 (E-24 — keyword-only parsing replaced by three-tier router). All v1.0 task IDs remain in v1.0 history. |
| Are any v1.1 task IDs retired? | T-2105 and T-2106 are retired in v1.1.3. They were defined in v1.1.2 to migrate the v1.0 Yes/No buttons into `DarkGlassButton` 1:1; in v1.1.3 the Yes button is deleted entirely (E-25) and the cancel control is built fresh against the countdown surface (T-2502), so a 1:1 migration no longer applies. The IDs are not reused. |
| Parsing architecture for v1.1? | Three-tier: Tier 1 Foundation Models (when `SystemLanguageModel.availability == .available`), Tier 2 retrained per-language `NLModel` (primary floor, all supported devices), Tier 3 existing keyword `CommandParser` (safety net, unchanged). |
| Device floor for parsing? | A15/A16 — Tier 2 NLModel must work as the primary parser on every supported device. Tier 1 Foundation Models is an enhancement on capable devices, not a requirement. |
| Cloud NLU? | Excluded. All parsing runs on-device for privacy and offline operation. Wit.ai, Dialogflow CX, OpenAI, Claude, AWS Lex, Azure CLU all eliminated. |
| Parsing language coverage? | Both English and Danish at every tier. Per-language NLModel artifacts; per-language Foundation Models prompt templates. |
| Corpus strategy? | Hybrid: open-source NLU corpora adapted to the Voxio 13-intent set + generated utterances to fill gaps. ≥ 300 utterances per intent per language. Bilingual. Static corpus; no live LLM in the shipped app. |
| Intent set changes? | None. The 13 cases of `VoiceCommand` are unchanged. E-24 changes only how transcripts are mapped to those intents. |
| Slot extraction? | Tier 1 emits slots via guided generation. Tier 2 emits intent only; the router post-processes the transcript with regex/keyword logic to fill slots, falling through to Tier 3 if extraction fails. |
| Async parsing API? | Yes — `CommandParserRouter.parse(_:)` becomes `async`. The call site in `VoiceToText.swift:50` dispatches a `Task` and delivers the result on the main actor. Ordering between `onFinalTranscript` and `onCommand` is preserved from v1.0. |
| Tier 1 prewarming? | Yes — `LanguageModelSession` is prewarmed at app launch during the existing mic/permission setup phase. First-command latency benefits; first-command does not pay cold-start. |
| Tier 1 unavailability handling? | Router falls through to Tier 2 silently; user sees no error. Logged at INFO. |
| Tier 2 confidence threshold? | Per-language, derived empirically in T-2410. Default starting point 0.55. Below threshold falls through to Tier 3. |
| Regression policy? | All v1.0 canonical phrasings classify identically to v1.0. Enforced by T-2419 regression pass against `corpus-regression.jsonl` (T-2406). 100 % pass rate required. |
| Foundation Models API stability risk? | Acknowledged. Spec proceeds; if the framework is withdrawn or breaks at GA, Tier 2 carries the entire load with no functional regression. See open question Q13. |
| Legal posture on open-source corpora? | Only redistribution-permissive licences. Share-alike corpora excluded. Audit documented per T-2401 / Q16. |
| Confirmation pattern in v1.1? | Auto-execute after a 3-second cancellable countdown. No Yes button. Single Cancel control (button + voice). Replaces v1.0 Yes/No two-button flow. |
| Countdown duration? | 3 seconds, fixed. Not user-configurable in v1.1 (see Q21). |
| Voice-cancel grammar? | `cancel`, `no`, `nej`, `annuller` (case-insensitive whole-word). Detected by a lightweight keyword matcher (T-2506), not routed through the `CommandParserRouter`. |
| Confirm-by-voice during countdown? | Not in v1.1. Saying "yes" / "ja" during the countdown is a no-op. See Q22. |
| Countdown-TTS interaction? | TTS read-back completes before the countdown timer starts. The countdown does NOT begin during read-back. |
| Coordinator API change? | `ConfirmationCoordinator.confirm()` / `.cancel()` removed. Replaced by `.startCountdown(action:readBack:onResolved:)` and `.cancelCountdown(reason:)`. The 10 s confirmation timeout from T-0805 is removed. |
| Tie resolution between voice-cancel and timer expiry? | Cancellation wins ties. The bound action is not invoked. `.error` haptic fires; `.success` does not. |
| Trigger-word activation in v1.1? | Yes — wake word is "Voxio" (case-insensitive). Replaces always-on `SFSpeechRecognizer` from T-0301. Two orb states: passive (small slow pulse, listening for trigger only) and active (full v1.0 animation, listening for command). |
| Trigger-word implementation? | Default: `SFSpeechRecognizer` in continuous on-device mode scanning for "Voxio" (T-2601). T-2603 investigates the iOS 26 keyword-spotting API and may swap the implementation under the same callback surface if it is at least 30 % more power-efficient. |
| Trigger-word privacy? | All listening on-device. No outbound traffic. Verified by T-2609 packet capture. Mic permission string updated by T-2604 to explain the wake-word model. |
| Trigger-in-utterance handling? | Supported. "Voxio, Beosound play" activates the app and the leading "Voxio" token is stripped before parsing (T-2605). |
| Trigger-word state-machine timeouts? | After ~5 s of post-activation silence with no captured speech, return to passive. After captured-command resolution (E-25 auto-execute or cancel), return to passive. |
| Background trigger detection? | Not in v1.1. Existing v1.0 background-pause behaviour from T-0312 is preserved. |
| Audio cue on passive→active transition? | Not in v1.1 — visual orb change only. See Q24. |
| Trigger-word personalisation? | Not in v1.1. Trigger is fixed to "Voxio". See Q23. |

---

## References

- `epics-and-tasks-voxio-1.1.md` — sibling document; v1.1 epic and task breakdown (E-20–E-26, tasks T-2001–T-2610).
- `Specification/Voxio 1.0/functional-spec-bo-voice-control.md` — v1.0 functional specification (US-00–US-12).
- `Specification/Voxio 1.0/epics-and-tasks-bo-voice-control.md` — v1.0 epics and tasks (E-01–E-19, T-0101–T-1909).
- `Specification/Design Specification/design-spec-bo-voice-control.md` — v1.1 design specification (Liquid Glass, dark Liquid Glass pill button, fixed `AppBackground.png`).
- `Specification/Voxio 1.1/ADR-001-v1.1-visual-layer.md` — Architecture decision record for the v1.1 visual layer (token reconciliation, `.glassEffect` API, Capsule shape change).
- `CLAUDE.md` — project-level architectural notes (iOS folder structure, Mozart API, deployment target).
