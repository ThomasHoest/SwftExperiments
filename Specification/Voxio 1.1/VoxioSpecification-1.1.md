# Voxio Specification — v1.1
**Version:** 1.1.2
**Status:** Draft
**Date:** 2026-04-29
**Platform:** iOS 26
**References:** design-spec-bo-voice-control v1.1, functional-spec-bo-voice-control v1.3, epics-and-tasks-bo-voice-control v1.3 (E-01–E-19), ADR-001-v1.1-visual-layer, CLAUDE.md
**Languages:** English (`en-US`) and Danish (`da-DK`) — both fully supported (unchanged from v1.0)

**Amendment history**

| Version | Date | Summary |
|---|---|---|
| 1.1.0 | 2026-04-29 | Initial draft. |
| 1.1.1 | 2026-04-29 | Applied 5 amendments from `ADR-001-v1.1-visual-layer.md`: (1) BeoColor naming reconciled to `text` / `muted` + new prerequisite **T-2100**; (2) `.glassEffect` API authoritative (no DIY `ultraThinMaterial`) — see §Decision-Audit Note; (3) `Capsule()` shape change documented as deliberate, snapshot tests verify against `ButtonLookAndFeel.png`; (4) T-2105 / T-2106 haptic wording disambiguated — `DarkGlassButton` itself emits no haptics; (5) `HintCardView` button shape change explicitly noted in T-2109. |
| 1.1.2 | 2026-04-29 | Added **E-24 Three-Tier Voice Command Parsing** (US-20, US-21, US-22, US-23) following research-driven solution selection. Three-tier architecture: Foundation Models (A17 Pro+, iOS 26) → retrained NLModel (primary floor for A15/A16) → existing keyword `CommandParser` (safety net, unchanged). Bilingual (en + da) NLU corpus required. **Supersedes the rendering of E-18 task IDs T-1801 through T-1810** — those task IDs are retired in favour of T-2401 through T-2419; the existing keyword `CommandParser` shipped under E-18 remains in place as Tier 3. Intro section §What is NOT changing in v1.1 was previously accurate but is now amended: the parsing pipeline IS being replaced by E-24. |

---

## Introduction

Voxio v1.1 is a focused release covering two parallel workstreams: a visual-layer refresh (E-20 through E-23) and a voice command parsing improvement (E-24). It does not add, remove, or change any voice command intent, Mozart API integration, language support, or accessibility behaviour beyond the parsing accuracy improvement in E-24. The functional surface area defined in the v1.3 functional spec and delivered through E-01 through E-19 in v1.0 remains otherwise as shipped.

What v1.1 changes:

1. **Fixed `AppBackground.png`** — a custom dark navy / blue-teal-green orb image replaces the deep-charcoal gradient (and supersedes the iOS-wallpaper-through-glass approach previously specified by **T-1001**). The background no longer adapts to the user's wallpaper or system light/dark setting.
2. **Dark Liquid Glass pill button system** — every interactive button in the app is rebuilt as a single reusable `DarkGlassButton` SwiftUI view that wraps the iOS 26 native `.glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: Capsule())` API with a hairline white specular border. This replaces the mixed button styles introduced in E-11 (`T-1104` filled-gold "Yes", `T-1105` outlined "No") and any other ad-hoc button styling elsewhere in the codebase.
3. **Dark-mode-only visual layer** — the app is intentionally dark-only. `.preferredColorScheme(.dark)` already sits on `WindowGroup`, but `.sheet()`-presented content (`LanguagePickerSheet`, `ConfirmationSheet`) reverts to system appearance unless its own root explicitly enforces dark mode. v1.1 closes that gap and, in the same pass, adds a SwiftUI-native `@Environment(\.colorSchemeContrast)` reactive Increase Contrast border path. (No legacy `UIAccessibility.isContrastEnabled` call sites exist in `iOS/Voxio/`; T-2204 verifies this and closes as N/A.)
4. **Three-tier voice command parsing** — replace the v1.0 keyword/regex-only `CommandParser` (E-18) with a three-tier classifier that significantly improves natural-language paraphrase recognition while preserving full offline operation, full privacy, and bilingual (English + Danish) coverage. Tier 1 uses Apple's iOS 26 Foundation Models framework on capable devices (A17 Pro+); Tier 2 is a retrained `NLModel` intent classifier that serves as the primary floor for all supported devices (A15/A16+); Tier 3 is the existing keyword `CommandParser` retained as a deterministic safety net. See E-24.

### Why these three visual changes, together

The three visual changes are coupled by a single design intent: produce a consistent, cinematic, brand-controlled canvas that does not depend on the user's wallpaper or system appearance. The fixed background sets the stage; the dark glass buttons are the only style that reads correctly on top of that stage; and dark-mode-only enforcement makes sure the stage and the buttons remain consistent across every presentation surface (main window, sheets, popovers, system-rendered chrome). Shipping any one of these in isolation would produce visible mismatches between the home screen and the sheets, or between the main window and a system-presented view.

### Why the parsing change, in this same release

E-19 usability work (shipped) widened the surface area of phrasings users actually attempt. Field reports and the v1.0 acceptance criteria for E-18 confirm that the keyword/regex parser, while reliable for canonical phrasings, falls back to `.unknown` on natural-language paraphrases such as "could you turn it down a bit", "let's pause for a sec", or "play my second favourite". Improving recognition for these phrasings without sacrificing privacy, offline operation, latency, or bilingual coverage requires moving from pattern-matching to a learned classifier. The three-tier design lets us adopt the strongest available technology on each device class while keeping a deterministic floor.

### What is NOT changing in v1.1

- All voice command intents and language coverage (E-03, E-17 unchanged; the intent set in `VoiceCommand.swift` is unchanged — E-24 only changes how transcripts are mapped to those existing intents)
- Mozart API integration (E-02 unchanged)
- Speaker discovery and addressing (E-04 unchanged)
- Use-case handlers for play / stop / pause / volume / mute (E-05, E-06, E-07 unchanged)
- Confirmation flow logic (E-08 unchanged) — only the visual rendering of the sheet changes
- Error semantics and strings (E-09 unchanged)
- Toast structure and triggers (E-12 unchanged) — only their button styling changes
- Accessibility behaviours (E-13 unchanged) — VoiceOver, Dynamic Type, Reduce Motion semantics; only the Increase Contrast path is added (additive, not a replacement)
- Animation and haptic system (E-14 unchanged) — `DarkGlassButton` emits no haptics of its own; existing T-1108 sheet-appear `.medium` impact and T-1109 confirm-tap `.success` notification continue to fire from their existing call sites
- Usability enhancements shipped in E-19 (T-1901–T-1909 unchanged)
- The existing keyword `CommandParser` shipped under E-18 is **kept**, not deleted — it serves as Tier 3 of the new router. The E-18 epic itself is otherwise unchanged; only its v1.0 task IDs T-1801 through T-1810 are retired by E-24 (the rendering of those tasks is replaced — see Resolved Decisions).

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

---

## Goals

- A consistent, brand-controlled visual canvas: every screen, sheet, and toast in v1.1 sits on top of `AppBackground.png` in dark mode, regardless of system setting or user wallpaper.
- A single reusable `DarkGlassButton` view used by every button in the app — confirm, cancel, language-picker rows, hint dismissal, future sheet actions.
- Sheets (`LanguagePickerSheet`, `ConfirmationSheet`) render in dark mode in 100 % of cases, including when the system is in light mode and when Increase Contrast is enabled.
- Increase Contrast handling is reactive — toggling the system setting while the app is foregrounded re-renders affected views without an app restart.
- Zero regression to functional behaviour: all v1.0 acceptance criteria for E-01 through E-19 still pass after v1.1 ships. In particular, the v1.0 haptic behaviours from T-1108 (`.medium` sheet-appear) and T-1109 (`.success` confirm-tap) survive the migration.
- Visual parity with the design spec v1.1 button reference image (`ButtonLookAndFeel.png`) is verifiable by side-by-side screenshot review.
- **Parsing accuracy:** measured intent-classification accuracy on a held-out bilingual test set of natural paraphrases improves from the v1.0 keyword baseline to ≥ 92 % (Tier 2 alone) and ≥ 96 % when Tier 1 is available.
- **Parsing privacy:** zero transcripts leave the device. Verified by network audit (T-2417).
- **Parsing latency:** median end-to-end command latency (transcript final → `VoiceCommand` delivered) ≤ 500 ms on Tier 1 (prewarmed) and ≤ 50 ms on Tier 2. The v1.0 functional spec NFR (voice command to action under 3 s on a normal home network) is preserved with margin.
- **Parsing graceful degradation:** if Tier 1 or Tier 2 is unavailable for any reason at runtime, the router transparently falls through to the next tier; the user sees no error and no behavioural difference.

---

## Out of Scope (v1.1)

- **Light mode variant.** The app is intentionally dark-only. System light-mode setting does not change the background, button surfaces, or text colours. Deferred indefinitely.
- **iPad layout / landscape orientation.** v1.1 remains portrait-only on iPhone; the background asset is portrait-only.
- **Animated background.** `AppBackground.png` is a static asset. No CoreMotion-driven parallax or video background.
- **Per-speaker theming.** No accent colour customisation; the warm gold accent (`#C8A97E`) remains the single accent token everywhere.
- **New iconography.** SF Symbols 6 baseline unchanged from v1.0.
- **New voice commands.** v1.1 does not add new intents; the `VoiceCommand` enum is unchanged.
- **New language coverage.** v1.1 does not add languages beyond English and Danish.
- **Settings screen redesign.** Out of scope; settings UI was already deferred in v1.0.
- **Replacement of the iOS-26-only `.glassEffect` API with a pre-iOS-26 fallback.** Deployment target stays at iOS 26.
- **Renaming `BeoColor.text` / `BeoColor.muted` to `labelPrimary` / `labelSecondary` across the codebase.** T-2100 adds aliases; a full rename is deferred to a future cleanup.
- **Cloud-backed NLU (Wit.ai, Dialogflow, OpenAI, Claude, AWS Lex, Azure CLU).** Eliminated by privacy and offline requirements.
- **CoreML transformer (BERT/distilBERT) parser.** Researcher Rank 3 fallback; deferred unless Tier 2 NLModel cannot meet ≥ 92 % validation accuracy after retraining (see open question Q14).
- **Slot extraction beyond the existing slots** (volume delta/level, favorite index). Tier 1 and Tier 2 produce only the slots already present in `VoiceCommand`. No new slots in v1.1.
- **Adding intents that exist in popular open-source NLU corpora but are not in `VoiceCommand`** (e.g. timer, alarm, smart-home device control). The corpus is filtered down to the existing 13-intent set.
- **Continuous on-device learning / personalisation.** The shipped NLModel is static. Telemetry collection for future retraining is deferred (see open question Q15).

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
- `DarkGlassButton` itself emits no haptics. Haptic feedback remains the responsibility of the call site (e.g. `ConfirmationSheet.onAppear` for the `.medium` sheet-appear haptic, the confirm-tap handler for the `.success` notification haptic).

---

**US-16 — Confirm and Cancel buttons feel different without breaking the style system**
> As a user, I want the Confirm action to feel positive (warm gold cue) and the Cancel action to feel destructive (red cue) without the buttons looking like two completely different components.

**Acceptance criteria:**
- The `Confirm` variant uses the dark glass pill surface, label "Yes" (or "Ja") in white, and a leading `checkmark` SF Symbol tinted with `--accent` (`#C8A97E`).
- The `Cancel` variant uses the dark glass pill surface; both the label ("No"/"Nej") and the leading `xmark` SF Symbol render in system red (`Color.red`) — not a hex value, so the colour adapts to system accessibility rendering.
- The two variants share the exact same shape, padding, border, press animation, and disabled treatment as the default `DarkGlassButton`.
- The two-button stack in `ConfirmationSheet` (T-1103, T-1104, T-1105) renders Confirm-on-top, Cancel-on-bottom, full-width, with 12 pt vertical spacing between them. v1.0 functional behaviour (T-1104 / T-1105) is preserved — only the rendering changes.

---

**US-17 — Button hit areas remain ≥ 44 × 44 pt**
> As a user with motor impairments or a large finger size, I want every button — including the icon-only "?" hint button and the language-picker rows — to be reliably tappable.

**Acceptance criteria:**
- Every `DarkGlassButton` instance has an effective hit area of at least 44 × 44 pt, including the icon-only 36 × 36 pt variant (which uses `.frame(minWidth: 44, minHeight: 44)` on the `Button` wrapper to extend the hit area to 44 × 44 pt without changing the visual size).
- The "?" hint button in `HomeView`'s status bar (T-1906) is at least 44 × 44 pt.
- The language-picker rows in `LanguagePickerSheet` (T-1902) are at least 44 × 44 pt.
- The Accessibility Inspector reports no tap-target violations on any screen after v1.1 lands.

---

### Design change 3 — Dark-mode-only visual layer

**US-18 — Sheets stay dark, always**
> As a user with a light-mode iPhone, I want the language picker and the confirmation sheet to look exactly like the rest of the app — never to flash as a light-mode panel — so that the experience is uninterrupted.

**Acceptance criteria:**
- When the system is in Light Mode and the user opens the app, the home screen is dark (already true in v1.0 via `WindowGroup.preferredColorScheme(.dark)`).
- When the `LanguagePickerSheet` is presented for the first time on a light-mode device, the sheet content (rows, labels, separators) renders in dark mode. There is no visible flash of light mode at any point during sheet presentation or dismissal.
- When the `ConfirmationSheet` is presented after a parsed voice command on a light-mode device, the sheet content renders in dark mode. There is no visible flash of light mode at any point during sheet presentation or dismissal.
- Toggling the system between Light Mode and Dark Mode while the app is foregrounded does not change the appearance of any in-app surface (main window, sheets, toasts, hint card).
- System-rendered alerts (microphone permission, speech recognition permission, local network permission) are governed by iOS and may render in light mode; this is acceptable and out of scope for v1.1. Voxio-rendered surfaces — anything inside the app's `WindowGroup` — must be dark.

---

**US-19 — Increase Contrast is honoured reactively**
> As a user with Increase Contrast enabled in iOS Accessibility settings, I want the dark glass surfaces to gain a stronger border so they remain readable, and I want that change to take effect the moment I toggle the setting — not on next app launch.

**Acceptance criteria:**
- When the user enables Increase Contrast in Settings → Accessibility while the Voxio app is running and foregrounded, all dark glass surfaces (`DarkGlassButton`, speaker card, confirmation sheet, language picker sheet, toasts, hint card) re-render within 1 second to apply the high-contrast variant. The user does not need to background and re-foreground the app.
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

## Error States

All scenarios below are visual-layer regressions caught during v1.1, plus parsing-layer error scenarios introduced by E-24. Each maps to an explicit observable behaviour. No new spoken or written error strings are introduced — voice and error semantics are unchanged from v1.0.

| Scenario | Expected Behaviour |
|---|---|
| `AppBackground.png` asset missing from `Assets.xcassets` | App fails the build (Xcode asset-catalog warning escalated to error in CI). No runtime fallback to gradient. |
| Image fails to render at runtime (corrupted asset) | Show a flat `Color(hex: "#0A0E1A")` (deep navy) as the background fallback, log `Logger.error("AppBackground render failed")`. App does not crash. |
| `.glassEffect` is unavailable at runtime (theoretical: build deployed to a sub-iOS-26 device) | Build is rejected by App Store / Xcode at upload time; no runtime path required because deployment target is iOS 26. |
| `LanguagePickerSheet` presented in light mode without local `.preferredColorScheme(.dark)` | The sheet renders as a light panel (regression). v1.1 acceptance: this state must not occur. Verified by snapshot test (T-2304). |
| `ConfirmationSheet` presented in light mode without local `.preferredColorScheme(.dark)` | Same as above; verified by snapshot test (T-2304). |
| Increase Contrast toggled while app is foregrounded | All `DarkGlassButton` instances and the speaker card re-render with high-contrast borders within one display frame of the SwiftUI environment update. No manual notification handling. |
| `DarkGlassButton` used inside a non-dark presentation boundary (e.g. a future popover) | Button still renders correctly because its tint, border, and label colours are not derived from the colour scheme — they are explicit token values. No regression expected. |
| Hit area smaller than 44 × 44 pt on icon-only `DarkGlassIconButton` | Build-time SwiftUI preview test (T-2210) verifies `.frame(minWidth: 44, minHeight: 44)` is applied. CI snapshot regression test catches violations. |
| Background does not extend behind Dynamic Island | Visual regression; verified by snapshot test on iPhone 15 Pro / 16 Pro frame (T-2104). |
| `DarkGlassButton` references `BeoColor.labelPrimary` before T-2100 ships | Compile error. T-2100 must merge before T-2102 (the component) builds. The dependency graph in E-21 makes this explicit. |
| `DarkGlassButton` accidentally fires a haptic on tap | Regression — would result in double-haptic when used inside `ConfirmationSheet` (sheet-appear `.medium` impact + confirm-tap `.success` notification + a third unwanted haptic from the component). T-2105 acceptance forbids this. |
| Foundation Models framework is unavailable at runtime (Apple Intelligence disabled, A15/A16 device, or model not yet downloaded) | Router records Tier 1 unavailable at session start; falls through to Tier 2 NLModel. User sees no error and no behavioural difference. Logged at INFO. |
| Foundation Models call returns `.unknown` or fails (timeout, model busy, transient error) | Router falls through to Tier 2 for that single utterance. Logged at INFO. The next utterance retries Tier 1 normally. No retry storm. |
| Tier 1 latency exceeds 1.5 s for a single utterance | Router does not interrupt the call (cancellation would corrupt the structured-output state). The call completes; the result is delivered. Latency exceedance is recorded in a rolling counter for telemetry (T-2418). If three consecutive Tier 1 calls exceed 1.5 s within a session, the router downgrades to Tier 2 for the remainder of the session and logs `Log.info("[CommandParserRouter] downgrade tier=2 reason=latency")`. |
| Tier 2 NLModel produces low-confidence prediction (below the per-language threshold from T-2410) | Router falls through to Tier 3 keyword `CommandParser`. If Tier 3 returns `.unknown`, the user-visible result is `.unknown(transcript)` exactly as in v1.0. No silent misclassification. |
| Tier 2 NLModel asset missing from the bundle for the active language | Build fails at link time (model file is a build resource). No runtime fallback — both English and Danish models must ship. |
| Tier 2 NLModel returns an intent slot value out of range (e.g. `.playFavorite(index: 7)`) | Router rejects the prediction and falls through to Tier 3. Index range is fixed at 1–4 per the existing v1.0 contract. Logged at INFO. |
| Active language switched mid-utterance (e.g. user opens picker while command is being processed) | The in-flight utterance completes against the language that was active when the transcript was finalised. The next utterance uses the new language. No cross-language routing of a single utterance. |
| Tier 1 session not yet prewarmed when the first command arrives | Router awaits the prewarm task (it starts at app launch); first-command latency may extend to ~600–800 ms instead of ~400 ms. Subsequent commands are at the prewarmed latency. Acceptable per T-2418 observation budget. |
| Network packet capture detects outbound traffic from the parsing pipeline | Test failure (T-2417). Spec acceptance forbids any non-Mozart outbound traffic from the parsing path. |

---

## Non-Functional Requirements

- **Performance:** Background image render adds no measurable frame-rate cost on iPhone 12 (A14) or newer; 60 fps maintained during sheet present/dismiss and during command-recognition card scale animation. Re-verify with the v1.0 60 fps target from T-1410.
- **Memory:** `AppBackground.png` is loaded once and cached by SwiftUI's `Image` view; no per-frame decoding. Asset peak memory ≤ 5 MB. Tier 2 NLModel files (per language) ≤ 200 KB each on disk; loaded into memory at router init and held for the session.
- **Asset size:** `AppBackground.png` ≤ 600 KB shipped (PNG, optimised; design spec dimensions 642 × 1077 px). Combined Tier 2 NLModel assets ≤ 500 KB shipped (both languages).
- **Latency:**
  - No regression to the v1.0 functional spec NFR — voice command to action under 3 s on a normal home network.
  - Tier 1 parsing: median ≤ 500 ms, p95 ≤ 1.5 s (prewarmed).
  - Tier 2 parsing: median ≤ 50 ms, p95 ≤ 200 ms.
  - Tier 3 parsing: ≤ 5 ms (unchanged from v1.0).
- **Accessibility:**
  - Minimum tap target 44 × 44 pt, including icon-only buttons (US-17).
  - Increase Contrast reactive within 1 s of toggling system setting (US-19).
  - VoiceOver, Dynamic Type, Reduce Motion behaviours preserved exactly per v1.0 §E-13.
- **Privacy:** Unchanged from v1.0. All parsing tiers run on-device; no transcript leaves the device. Verified by network audit.
- **Localisation:** All button labels (`Yes`/`Ja`, `No`/`Nej`, `Got it`/`OK`) continue to flow through the existing `LanguageService` and `String(localized:)` paths from E-17. No new localisation infrastructure. Tier 1 is given an English/Danish prompt template per active language; Tier 2 uses per-language `.mlmodel` files.
- **Testability:** Every screen has a snapshot test in dark mode, in dark + Increase Contrast mode, and at the smallest and largest Dynamic Type sizes. The parsing pipeline has a unit test corpus covering ≥ 50 paraphrases per intent per language with a held-out 10 % test split.
- **Haptic preservation:** v1.0 haptics from T-1108 (sheet-appear `.medium` impact) and T-1109 (confirm-tap `.success` notification) continue to fire from their existing call sites. `DarkGlassButton` itself emits no haptics.
- **Parsing accuracy floor:** Tier 2 NLModel must achieve ≥ 92 % validation accuracy per language on the held-out test split before being shipped. Tier 1 (when active) is expected to add 4–6 percentage points but is not gated on a fixed minimum; Tier 2 carries the contractual floor.
- **Parsing robustness:** Tier 1 unavailability, Tier 1 timeout, Tier 2 low confidence, and Tier 2 missing-model conditions all degrade gracefully without a user-visible error message; behaviour collapses cleanly to Tier 3 (keyword) → `.unknown` exactly as in v1.0.

---

## Epics and Tasks

The v1.1 release adds five epics (E-20 through E-24), continuing the numbering from v1.0's E-19. Tasks are numbered T-2001 onwards, continuing from v1.0's T-1909. E-24 task IDs begin at T-2401 and continue from E-23's T-2309.

### Epic Index (v1.1)

| # | Epic | User Stories |
|---|---|---|
| E-20 | Fixed App Background | US-13, US-14 |
| E-21 | Dark Liquid Glass Button System | US-15, US-16, US-17 |
| E-22 | Dark-Mode-Only Visual Layer | US-18, US-19 |
| E-23 | v1.1 Visual QA & Regression Hardening | All v1.1 visual US |
| E-24 | Three-Tier Voice Command Parsing | US-20, US-21, US-22, US-23 |

---

### E-20 — Fixed App Background

Replace the deep-charcoal gradient (and the original v1.0 plan to render the user's iOS wallpaper through a glass layer) with a fixed `AppBackground.png` asset rendered full-bleed behind every screen. **Supersedes T-1001** from v1.0; that task remains in v1.0 history but its rendered behaviour is no longer the spec.

**Depends on:** none (purely additive at the visual layer)
**Supersedes:** v1.0 T-1001

- [ ] **T-2001** Add `AppBackground.imageset` to `iOS/Voxio/Assets.xcassets` containing `AppBackground.png` (642 × 1077 px, portrait, ≤ 600 KB optimised). Configure the imageset for universal device support; provide @1x, @2x, @3x scales as supplied by the design team. No localisation variants.
  *No dependencies. Prerequisite for T-2002.*

- [ ] **T-2002** Replace the `LinearGradient.ignoresSafeArea()` background in `HomeView` with `Image("AppBackground").resizable().scaledToFill().ignoresSafeArea()` as the first child of the root `ZStack`. Do not move `.ignoresSafeArea()` to the `ZStack` itself. Remove the gradient definition entirely if it has no other call sites.
  *Depends on: T-2001.*

- [ ] **T-2003** Verify foreground content layout is unchanged after the swap — the speaker card, status bar, speaker selector pill, and hint card retain their existing safe-area insets. Run the existing snapshot fixtures from E-10 / E-19 against the new background; confirm only the bottom layer changes.
  *Depends on: T-2002.*

- [ ] **T-2004** Add `appBackground = "AppBackground"` constant to `DesignTokens.swift` (a new `BeoAsset` enum or appended to an existing tokens file). Update `HomeView` and any future call sites to reference the constant rather than the literal string.
  *Depends on: T-2002.*

- [ ] **T-2005** Test the background on iPhone SE (375 pt), iPhone 15 (393 pt), iPhone 15 Pro (393 pt with Dynamic Island), iPhone 15 Pro Max (430 pt), and iPhone 16 Pro Max simulators. Confirm the orb composition remains visually balanced and `scaledToFill` does not crop important visual elements off-screen on the narrowest device.
  *Depends on: T-2002.*

- [ ] **T-2006** Implement the asset-missing fallback — if `Image("AppBackground")` fails to render (verified via `UIImage(named:)` precheck at view init), display `Color(hex: "#0A0E1A")` and `Logger.error("AppBackground render failed")`. Do not crash. Do not silently fall back to the gradient.
  *Depends on: T-2002.*

- [ ] **T-2007** Verify keyboard avoidance — present a hypothetical text-input flow (or a simulated `.sheet` with a `TextField`); confirm content shifts above the keyboard and that the background remains anchored full-bleed.
  *Depends on: T-2002.*

- [ ] **T-2008** Update `iOS/Voxio/Features/Home/ContentView.swift` (if a separate view exists) and any preview providers that reference the gradient. Ensure all SwiftUI previews render the new background.
  *Depends on: T-2002.*

---

### E-21 — Dark Liquid Glass Button System

Build the single reusable dark-glass pill button as a SwiftUI view in `DesignSystem/`. Replace every existing button rendering (Confirm, Cancel, language-picker rows, hint dismissal, "?" hint trigger) with this view. The two distinct visual variants required by v1.0 (Confirm = filled gold, Cancel = outlined) are unified under a single component with role-based icon/label tinting.

**Depends on:** none (additive design-system work)
**Supersedes:** v1.0 T-1104, T-1105 (rendering only — `ConfirmationCoordinator` confirm/cancel logic from T-0801, T-0804 unchanged)

#### Compile-blocker prerequisite

- [ ] **T-2100** Reconcile `BeoColor` naming so v1.1 token references compile. Add the following aliases to `iOS/Voxio/DesignSystem/BeoColor.swift`:
  ```swift
  static let labelPrimary   = BeoColor.text
  static let labelSecondary = BeoColor.muted
  ```
  Do not rename `text` or `muted`; existing v1.0 call sites continue to use those names. Both pairs (the originals and the aliases) must compile and resolve to the same `Color` asset. This task must merge before T-2102 begins, otherwise `DarkGlassButton` will fail to compile. Identified by ADR-001-v1.1-visual-layer §Conflict 1.
  *No dependencies. Prerequisite for T-2102, T-2205, T-2206.*

#### Component build

- [ ] **T-2101** Add v1.1 button design tokens to `DesignTokens.swift` — append a `DarkGlassButton` enum (or extend an existing tokens enum) with: `overlayColor = Color.black.opacity(0.45)`, `borderColor = Color.white.opacity(0.15)`, `borderWidth: CGFloat = 0.5`, `paddingV: CGFloat = 10`, `paddingH: CGFloat = 16`, `iconGap: CGFloat = 6`, `iconOnlySize: CGFloat = 36`, `pressedScale: CGFloat = 0.95`, `pressSpringResponse: Double = 0.3`, `pressSpringDamping: Double = 0.7`. Mirror the design spec v1.1 §Design Tokens Reference exactly.
  *No dependencies. Prerequisite for T-2102.*

- [ ] **T-2102** Build `DarkGlassButton` SwiftUI view in `iOS/Voxio/DesignSystem/DarkGlassButton.swift`. API: `init(label: String, systemImage: String? = nil, role: Role = .default, action: @escaping () -> Void)`. `Role` enum cases: `.default`, `.confirm`, `.cancel`, `.disabled`. Body composes a `Button` with `.glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: Capsule())`, `.overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))`, content `HStack { icon; label }`, padding from tokens, and the `scaleEffect(0.95)` press animation via `ButtonStyle`. **The component must not call `UIImpactFeedbackGenerator` or `UINotificationFeedbackGenerator`** — haptics remain the responsibility of the call site.
  *Depends on: T-2100, T-2101.*

- [ ] **T-2103** Implement `DarkGlassButton.Role` rendering rules:
  - `.default` — label `BeoColor.labelPrimary` (alias for `BeoColor.text`), icon white
  - `.confirm` — label `BeoColor.labelPrimary`, icon `BeoColor.accent` (`#C8A97E`)
  - `.cancel` — label and icon both `Color.red` (system adaptive red — not a hex value, so the colour follows iOS's accessibility rendering)
  - `.disabled` — entire button at `.opacity(0.4)` and `.disabled(true)`
  Each role must produce visually distinct output but share shape, padding, border, and press animation.
  *Depends on: T-2102.*

- [ ] **T-2104** Build `DarkGlassIconButton` icon-only variant in the same file — circular pill, 36 × 36 pt visual size (via an inner `.frame(width: 36, height: 36)` on the visual capsule), `.frame(minWidth: 44, minHeight: 44)` on the outer `Button` wrapper for the hit area, single SF Symbol centred. Same role enum and same press animation as `DarkGlassButton`. The component must not emit haptics. API: `init(systemImage: String, role: Role = .default, accessibilityLabel: String, action: @escaping () -> Void)`.
  *Depends on: T-2102, T-2103.*

#### Call-site replacements

- [ ] **T-2105** Replace the v1.0 `Yes` button rendering in `ConfirmationSheet` (currently the filled-gold `RoundedRectangle(cornerRadius: 12)` from T-1104) with `DarkGlassButton(label: confirmLabel, systemImage: "checkmark", role: .confirm, action: confirm)`. Do not change the call site for `ConfirmationCoordinator.confirm()`. **Haptic preservation:** verify both haptics that bracket the confirmation flow continue to fire — (a) the T-1108 `UIImpactFeedbackGenerator(style: .medium)` invoked in `ConfirmationSheet.onAppear` when the sheet appears, and (b) the T-1109 `UINotificationFeedbackGenerator().notificationOccurred(.success)` invoked when the confirm action fires. Both haptics live at the `ConfirmationSheet` call site, not inside `DarkGlassButton`. The component itself emits no haptics. Identified by ADR-001-v1.1-visual-layer §Conflict 4.
  *Depends on: T-2103.*

- [ ] **T-2106** Replace the v1.0 `No` button rendering in `ConfirmationSheet` (currently the outlined `RoundedRectangle(cornerRadius: 12)` from T-1105) with `DarkGlassButton(label: cancelLabel, systemImage: "xmark", role: .cancel, action: cancel)`. Do not change the call site for `ConfirmationCoordinator.cancel()`. **Haptic preservation:** the T-1108 sheet-appear `.medium` impact and any cancel-path haptic at the call site must continue to fire from their existing locations; `DarkGlassButton` itself emits no haptics.
  *Depends on: T-2103.*

- [ ] **T-2107** Replace the language-picker row rendering in `LanguagePickerSheet` (T-1902) with two `DarkGlassButton` instances — one per language. Labels: "English" and "Dansk", role: `.default`. The existing `setLanguage(_:)` and dismiss behaviour from T-1902 / T-1903 is unchanged. **Visible shape change:** rows that were `RoundedRectangle(cornerRadius: 12)` become `Capsule()`; deliberate per ADR-001-v1.1-visual-layer §Conflict 3 and verified against `ButtonLookAndFeel.png` in T-2304.
  *Depends on: T-2103.*

- [ ] **T-2108** Replace the "?" hint button rendering in `HomeView`'s status bar (T-1906) with `DarkGlassIconButton(systemImage: "questionmark.circle", accessibilityLabel: hintButtonAccessibilityLabel, action: toggleHint)`. The existing `accessibilityLabel` localisation logic from T-1906 must continue to work. Visible change: the previously bare `Button { Image(systemName:) }` gains a 36 × 36 pt dark glass capsule surface with the standard hairline border.
  *Depends on: T-2104.*

- [ ] **T-2109** Replace the "Got it" / "OK" hint dismissal button rendering in `HintCardView` (T-1905) with `DarkGlassButton(label: dismissLabel, role: .default, action: dismissHint)`. Auto-hide behaviour and `hasSeenHint` persistence from T-1905 unchanged. **Visible shape change:** the dismiss button moves from `RoundedRectangle(cornerRadius: Radius.sheet)` (16 pt corner radius) to `Capsule()`. Deliberate per ADR-001-v1.1-visual-layer §Conflict 5; verified in T-2304. The hint card itself remains `RoundedRectangle(cornerRadius: Radius.card)` — only the button inside it changes shape.
  *Depends on: T-2103.*

- [ ] **T-2110** Audit `iOS/Voxio/` for any remaining `Button { … }` definitions that render visible interactive controls and replace each with `DarkGlassButton` or `DarkGlassIconButton`. Acceptable exceptions: (a) speaker selector pills (a separate component, T-1004, retains its existing pill style), (b) `accessibilityElement` decorative wrappers, (c) gesture-target views without a visible button surface. Document each exception in a code comment referencing this task.
  *Depends on: T-2103, T-2104.*

#### Component verification

- [ ] **T-2111** Add SwiftUI previews for `DarkGlassButton` and `DarkGlassIconButton` rendering all four roles in dark mode and dark + Increase Contrast mode. Each preview is a standalone `#Preview` block in the same file.
  *Depends on: T-2102, T-2104.*

- [ ] **T-2112** Verify hit areas — every `DarkGlassButton` and `DarkGlassIconButton` instance reports a tap target of at least 44 × 44 pt via the Accessibility Inspector. Add a snapshot test that fails if the button's `.frame` falls below that minimum.
  *Depends on: T-2102, T-2104.*

---

### E-22 — Dark-Mode-Only Visual Layer

Enforce dark mode at every presentation boundary: the main window, every `.sheet`, every `.popover` (none currently shipped, but defensive), and every system-rendered surface that sits inside the app's `WindowGroup`. Add the SwiftUI `@Environment(\.colorSchemeContrast)` reactive Increase Contrast border path. Audit for any legacy `UIAccessibility.isContrastEnabled` references; close as N/A if none are found.

**Depends on:** none

- [ ] **T-2201** Audit `iOS/Voxio/` for every `.sheet`, `.fullScreenCover`, `.popover`, and `.alert` modifier. Build a list of sheet content roots (`LanguagePickerSheet.body`, `ConfirmationSheet.body`, plus any future sheets). Document the list as a code comment in `VoxioApp.swift`.
  *No dependencies. Prerequisite for T-2202.*

- [ ] **T-2202** Add `.preferredColorScheme(.dark)` to the body root of `LanguagePickerSheet`. Verify on a light-mode simulator that the sheet renders dark on first present, on dismissal, and on re-present. Place the modifier as the last modifier on the outermost view in `body`, after layout/frame modifiers and before any presentation modifiers.
  *Depends on: T-2201.*

- [ ] **T-2203** Add `.preferredColorScheme(.dark)` to the body root of `ConfirmationSheet`. Verify on a light-mode simulator that the sheet renders dark on present, on dismissal, and on re-present immediately after a parsed command. Same placement convention as T-2202.
  *Depends on: T-2201.*

- [ ] **T-2204** Audit `iOS/Voxio/` for any reference to `UIAccessibility.isContrastEnabled`. If any are found, replace them with `@Environment(\.colorSchemeContrast)` reads. The expected outcome (per ADR-001-v1.1-visual-layer §Context, item 4) is zero hits — the codebase is SwiftUI-first. Document the audit result in a code comment in `BeoColor.swift` or the project's accessibility-related file and close the task. Do **not** remove `UIAccessibility.post(notification:)` VoiceOver announcements such as the one in `LanguagePickerSheet.onAppear` — those are accessibility announcements, not contrast detection.
  *No dependencies.*

- [ ] **T-2205** Add `@Environment(\.colorSchemeContrast) private var contrast` to `DarkGlassButton` and `DarkGlassIconButton` (T-2102, T-2104). When `contrast == .increased`, render the border at 1.0 pt width and use `BeoColor.muted` (aliased as `BeoColor.labelSecondary` after T-2100) for the border colour instead of `Color.white.opacity(0.15)`. The shape, padding, animation, and text colour are unchanged.
  *Depends on: T-2100, T-2102, T-2104.*

- [ ] **T-2206** Apply the same `\.colorSchemeContrast` reactive border pattern to the speaker card (T-1002) — when contrast is increased, add a 1 pt border in `BeoColor.muted` (aliased as `BeoColor.labelSecondary`). No other v1.0 contrast handling changes.
  *Depends on: T-2100, T-2205.*

- [ ] **T-2207** Verify reactivity — toggle Increase Contrast in iOS Settings while the simulator is foregrounded with the app running. The visible buttons and speaker card must re-render their border treatment within one display frame (verified by visual inspection at 60 fps recording, or by logging the environment value on each `body` invocation).
  *Depends on: T-2205, T-2206.*

- [ ] **T-2208** Confirm light-mode simulator behaviour end-to-end — switch the simulator to Light Mode, launch the app, navigate through: home idle → language picker (first launch) → home idle → command recognition → confirmation sheet → confirmed → home idle. At every step, no surface inside the app's `WindowGroup` flashes light. System-rendered permission alerts may render in light mode and are explicitly out of scope for this verification.
  *Depends on: T-2202, T-2203.*

- [ ] **T-2209** Document the dark-mode-only constraint in `iOS/Voxio/DesignSystem/README.md` (or, if no README exists, as a header comment in `DarkGlassButton.swift`). Future-proof: any new `.sheet`, `.popover`, or `.fullScreenCover` content view must include `.preferredColorScheme(.dark)` on its body root.
  *Depends on: T-2202, T-2203.*

---

### E-23 — v1.1 Visual QA & Regression Hardening

Catch v1.1 regressions before they ship by adding snapshot tests and cross-referencing every v1.0 acceptance criterion against the new visual layer. Confirm the v1.0 functional surface is intact.

**Depends on:** E-20, E-21, E-22

- [ ] **T-2301** Add snapshot tests for `HomeView` idle state in: dark mode (default), dark mode + Increase Contrast, dark mode + largest Dynamic Type accessibility size. All three must pass on the iPhone 15 Pro simulator frame.
  *Depends on: T-2002, T-2206.*

- [ ] **T-2302** Add snapshot tests for `ConfirmationSheet` rendered with a sample read-back string, in: dark mode, dark mode + Increase Contrast, light-mode system / dark-mode app (verifies T-2203 is effective).
  *Depends on: T-2105, T-2106, T-2203.*

- [ ] **T-2303** Add snapshot tests for `LanguagePickerSheet` first-launch presentation in: dark mode, dark mode + Increase Contrast, light-mode system / dark-mode app (verifies T-2202 is effective).
  *Depends on: T-2107, T-2202.*

- [ ] **T-2304** Add snapshot tests for `DarkGlassButton` in all four roles (`.default`, `.confirm`, `.cancel`, `.disabled`) and for `DarkGlassIconButton` in two roles (`.default`, `.cancel`). **Verify visual parity with the design spec v1.1 reference image `ButtonLookAndFeel.png` before committing the reference snapshots** — confirm the reference image was generated at the same dimensions used in the snapshot test, so the deliberate `Capsule()` shape change (from v1.0's `RoundedRectangle(cornerRadius: 12)`) matches the design intent. Identified by ADR-001-v1.1-visual-layer §Conflict 3.
  *Depends on: T-2103, T-2104.*

- [ ] **T-2305** Run the v1.0 E-13 accessibility audit (T-1308) against every screen after v1.1 lands. Resolve any new tap-target or contrast violations introduced by the visual changes.
  *Depends on: T-2002, T-2110, T-2206.*

- [ ] **T-2306** Run the v1.0 E-14 animation profile (T-1410) on a minimum-spec device (A15). Confirm 60 fps is maintained during sheet present/dismiss with the new dark glass buttons and the new background.
  *Depends on: T-2002, T-2105, T-2106.*

- [ ] **T-2307** Re-run the existing E-19 unit test suite (T-1909) and confirm all six sub-cases still pass after `DarkGlassButton` replaces the language-picker rows, the hint dismissal, and the "?" hint trigger.
  *Depends on: T-2107, T-2108, T-2109.*

- [ ] **T-2308** Cross-reference every v1.0 acceptance criterion in E-10, E-11, E-12, E-13, E-14, and E-19 against the v1.1 implementation. Document any deviation. The expectation is zero deviations to functional behaviour. Pay particular attention to haptic timing — confirm T-1108 sheet-appear `.medium` impact and T-1109 confirm-tap `.success` notification both still fire from their existing call sites and that `DarkGlassButton` does not emit a third haptic (per T-2105 acceptance).
  *Depends on: E-20, E-21, E-22 complete.*

- [ ] **T-2309** Manual exploratory pass on a physical iPhone (not simulator) — verify the specular highlight on the dark glass buttons responds to device tilt as the iOS 26 `.glassEffect(.interactive())` API specifies. Document the device model and iOS version used.
  *Depends on: T-2105, T-2106.*

---

### E-24 — Three-Tier Voice Command Parsing

Replace the v1.0 keyword/regex-only parsing pipeline with a three-tier router that routes each transcript through the most accurate available classifier on the device, falling through to lower tiers on unavailability or low confidence. Tier 1 uses Foundation Models on devices that have Apple Intelligence; Tier 2 uses a retrained per-language `NLModel` and is the **primary floor** for all supported devices; Tier 3 is the existing keyword `CommandParser`, retained unchanged as a deterministic safety net. Both English and Danish must be covered at every tier. The intent set in `VoiceCommand.swift` is unchanged.

**Depends on:** none in v1.1 (architecturally additive; the existing `CommandParser` from E-18 becomes Tier 3 without modification)
**Supersedes:** v1.0 task IDs T-1801, T-1802, T-1803, T-1804, T-1805, T-1806, T-1807, T-1808, T-1809, T-1810 — the rendering of those task IDs is replaced by E-24's tasks. The existing `CommandParser` Swift file shipped under E-18 remains in place. The retired task IDs remain in v1.0 history; they do not cease to exist as historical references.

#### Corpus creation

- [ ] **T-2401** Inventory open-source NLU / intent corpora suitable for adaptation to the Voxio 13-intent set. Candidates to evaluate (non-exhaustive): SNIPS NLU benchmark, MASSIVE (Amazon, multilingual including Danish), Clinc150, ATIS, DSTC-style audio command sets, Common Voice transcript exports filtered to media-control intents. For each candidate, record: licence (must permit redistribution / training of a derived model in a commercial app), language coverage (must cover or be adaptable to en + da), intent overlap with `VoiceCommand`, and approximate utterance count after filtering. Output: a one-page evaluation document in `Specification/Voxio 1.1/parsing/corpus-sources.md` listing the chosen sources and licences.
  *No dependencies. Prerequisite for T-2402.*

- [ ] **T-2402** Define the canonical intent label set used during corpus assembly and training. Each `VoiceCommand` case maps to exactly one label; slots (volume delta/level, favorite index) are encoded in a structured per-utterance record alongside the intent label. Document the label-to-`VoiceCommand` mapping in `Specification/Voxio 1.1/parsing/intent-labels.md`. Slots are extracted by Tier 1 via guided generation and by Tier 2 via simple regex post-processing on the transcript (since `NLModel` itself is a single-label classifier).
  *Depends on: T-2401.*

- [ ] **T-2403** Adapt the chosen open-source corpora to the Voxio intent label set. For each source utterance, label it with one of the 13 intents or discard it. Produce: `Specification/Voxio 1.1/parsing/corpus-en-adapted.jsonl` and `Specification/Voxio 1.1/parsing/corpus-da-adapted.jsonl`. Record the source corpus, original label, and Voxio label per utterance for traceability.
  *Depends on: T-2402.*

- [ ] **T-2404** Generate supplementary utterances to fill coverage gaps where the adapted corpora are thin. Targets: ≥ 300 utterances per intent per language, with ≥ 10 distinct paraphrase patterns per intent. Patterns must include: imperative ("pause"), polite request ("could you pause"), discourse markers ("um, pause please"), contractions ("let's pause"), Danish equivalents per pattern. Generation may use an offline LLM (any local model) or hand-authored seeds; the **shipped model is trained only on the resulting static corpus**, not on a live LLM. Produce: `Specification/Voxio 1.1/parsing/corpus-en-generated.jsonl` and `Specification/Voxio 1.1/parsing/corpus-da-generated.jsonl`. Record the generation method per utterance.
  *Depends on: T-2402.*

- [ ] **T-2405** Merge adapted (T-2403) and generated (T-2404) corpora into the final training set per language. Deduplicate exact-string matches. Hold out 10 % of utterances per intent per language as the test set; another 10 % as the validation set. Produce: `corpus-en-train.jsonl`, `corpus-en-val.jsonl`, `corpus-en-test.jsonl`, `corpus-da-train.jsonl`, `corpus-da-val.jsonl`, `corpus-da-test.jsonl`. Verify class balance — no intent below 250 train utterances; rebalance via additional generation if needed.
  *Depends on: T-2403, T-2404.*

- [ ] **T-2406** Curate a separate **regression corpus** containing every canonical phrasing the v1.0 `CommandParser` is known to handle correctly (extracted from the existing v1.0 unit tests and from the keyword tables in `CommandParser.swift`). At least 50 utterances per language. Stored at `Specification/Voxio 1.1/parsing/corpus-regression.jsonl`. This corpus is used by T-2416 to prove zero v1.0 regressions; it is **not** used for training (to avoid the model memorising the exact keyword phrasings the keyword parser already handles trivially).
  *Depends on: T-2402.*

#### Tier 2 NLModel training

- [ ] **T-2407** Train an English `MLTextClassifier` via Create ML on `corpus-en-train.jsonl` validated against `corpus-en-val.jsonl`. Hyperparameter sweep: model algorithm (`maxEnt` vs `transferLearning`), max-iterations, regularisation. Select the configuration with the highest validation accuracy. Export to `iOS/Voxio/Resources/ParsingModel-en.mlmodel`. Target validation accuracy ≥ 92 %. Target on-disk size ≤ 200 KB.
  *Depends on: T-2405.*

- [ ] **T-2408** Train a Danish `MLTextClassifier` on `corpus-da-train.jsonl` validated against `corpus-da-val.jsonl`. Same hyperparameter sweep and acceptance criteria as T-2407. Export to `iOS/Voxio/Resources/ParsingModel-da.mlmodel`. Target validation accuracy ≥ 92 %.
  *Depends on: T-2405.*

- [ ] **T-2409** Evaluate the held-out test set (`corpus-en-test.jsonl`, `corpus-da-test.jsonl`) for each trained model. Produce a confusion matrix per language. Identify the lowest-recall intent in each language. If recall on any single intent falls below 85 %, regenerate utterances for that intent (T-2404 amendment), retrain (T-2407 or T-2408), and re-evaluate. Stored at `Specification/Voxio 1.1/parsing/eval-en.md` and `eval-da.md` including metrics, confusion matrices, and per-intent recall.
  *Depends on: T-2407, T-2408.*

- [ ] **T-2410** Determine the per-language confidence threshold below which Tier 2 falls through to Tier 3. Method: on the held-out test set, compute the precision-vs-recall curve per language; choose the threshold that maximises F1 for the `.unknown` rejection decision (i.e. above threshold → trust Tier 2; below threshold → fall through). Default starting point: 0.55. Record the per-language thresholds in `eval-en.md` and `eval-da.md` and as a constant in the router source.
  *Depends on: T-2409.*

- [ ] **T-2411** Slot extraction from the transcript for `.setVolume(N)`, `.adjustVolume(±N)`, and `.playFavorite(index:)`. Tier 2 emits only the intent label; the router post-processes the transcript with regex/keyword logic borrowed from the existing `CommandParser` to extract the numeric slots. For Tier 1 (T-2412), slots are emitted directly by guided generation. Slot extraction failure on a Tier 2 hit (e.g. classified as `.adjustVolume` but no number found) falls through to Tier 3 — Tier 3 has its own slot logic and may succeed. Document the slot grammar in `Specification/Voxio 1.1/parsing/slot-extraction.md`.
  *Depends on: T-2409.*

#### Tier 1 Foundation Models integration

- [ ] **T-2412** Define a `@Generable` Swift type `IntentResult` representing the constrained model output: `intent: IntentLabel` (an `enum` matching the 13 `VoiceCommand` cases), plus optional `volumeLevel: Int?`, `volumeDelta: Int?`, `favoriteIndex: Int?` slots. Annotate `intent` with `@Guide(description: …, .anyOf([...]))` enumerating every label. Annotate slot ranges (`favoriteIndex` 1–4, `volumeLevel` 0–100, `volumeDelta` -50…50). Add the type in `iOS/Voxio/Core/Voice/IntentResult.swift`.
  *No dependencies. Prerequisite for T-2413.*

- [ ] **T-2413** Build `FoundationModelsParser` (Tier 1 implementation) in `iOS/Voxio/Core/Voice/FoundationModelsParser.swift`. API: `func parse(_ transcript: String, language: Language) async -> VoiceCommand?` (returns `nil` if Tier 1 is unavailable or the call fails). Internally:
  - At init, check `SystemLanguageModel.default.availability`; if not `.available`, the type is unusable and any `parse` call returns `nil` immediately.
  - At init, prewarm a `LanguageModelSession` with the per-language system prompt (English and Danish prompt templates differ — both stored in the source as constants).
  - On each `parse` call, send the transcript with the prewarmed session and request a structured `IntentResult` via guided generation.
  - Map the returned `IntentResult` into the corresponding `VoiceCommand` case.
  - On error, timeout (> 1.5 s soft budget), or unavailability, return `nil`.
  *Depends on: T-2412.*

- [ ] **T-2414** Integrate prewarming into app startup. In `VoxioApp` (or `VoiceToText.start`), kick off the Tier 1 prewarm on a `Task.detached` during the existing mic/permission setup phase, and wait for it (with a 2 s budget) only at the moment the first transcript is finalised. Log `Log.info("[CommandParserRouter] tier1 prewarm started")` and `… prewarm complete` at the matching log points.
  *Depends on: T-2413.*

#### Router and call-site wiring

- [ ] **T-2415** Extend the existing `CommandParserRouter` (introduced in commit `63467c0`) to wrap all three tiers behind a single async API: `func parse(_ transcript: String) async -> VoiceCommand`. Internal flow:
  1. If Tier 1 is available, call it; if it returns a non-`nil` `VoiceCommand`, return it.
  2. Else, call Tier 2 (`NLModel` for the active language) — apply slot extraction (T-2411). If the prediction confidence is ≥ threshold (T-2410) and slot extraction succeeded where required, return the resulting `VoiceCommand`.
  3. Else, call Tier 3 (existing `CommandParser`). Return whatever it returns (which may be `.unknown(transcript)`).
  Tier selection is computed once at router init based on `SystemLanguageModel.default.availability` and on whether the per-language `.mlmodel` is present in the bundle. Subsequent runtime degradations (Tier 1 timeout pattern, Tier 2 missing model) downgrade the active tier set for the remainder of the session. Source in `iOS/Voxio/Core/Voice/CommandParserRouter.swift`.
  *Depends on: T-2407, T-2408, T-2410, T-2411, T-2413.*

- [ ] **T-2416** Update `VoiceToText.swift:50` to call the async router. Replace the synchronous `CommandParser(language: lang).parse(text)` call with a `Task` that awaits `router.parse(text)` and delivers the result on the main actor before invoking `onCommand` and `onFinalTranscript`. Preserve ordering: `onFinalTranscript` fires before `onCommand` (matches v1.0 ordering). Preserve the existing `Log.info("[Voice] \(command)")` line.
  *Depends on: T-2415.*

#### Verification

- [ ] **T-2417** Privacy / network audit. Run a packet capture (Charles Proxy or `nettop`) for a 10-command session covering both languages. Confirm zero outbound traffic from the parsing pipeline — only the existing Mozart REST/WebSocket traffic is observed. Repeat the test with the device in Airplane Mode (LAN preserved): every command must classify correctly. Document the test method and result in `Specification/Voxio 1.1/parsing/privacy-audit.md`. Acceptance: zero non-Mozart packets traceable to the parsing path.
  *Depends on: T-2416.*

- [ ] **T-2418** Latency observation. Instrument the router to record per-tier wall-clock latency from `parse(_)` entry to return on every call. Aggregate the data over a 30-command session per language across both A15 (iPhone 13) and A17 Pro (iPhone 15 Pro) hardware. Report: median, p95 per tier per device. Target: median Tier 1 ≤ 500 ms, median Tier 2 ≤ 50 ms, p95 Tier 1 ≤ 1.5 s, p95 Tier 2 ≤ 200 ms. If targets are missed, file follow-up tasks; do not block ship if Tier 2 is within budget on A15 (the contractual floor). Result documented in `Specification/Voxio 1.1/parsing/latency-report.md`.
  *Depends on: T-2416.*

- [ ] **T-2419** Regression and accuracy verification. Run two distinct test passes:
  - **Regression pass:** Run `corpus-regression.jsonl` (T-2406) through the full router. Required pass rate: 100 % — every canonical v1.0 phrasing must classify identically to the v1.0 keyword parser. Any miss is a blocker.
  - **Accuracy pass:** Run `corpus-en-test.jsonl` and `corpus-da-test.jsonl` through the full router. Required: ≥ 92 % overall accuracy per language with Tier 1 disabled (proves Tier 2 floor is met). With Tier 1 enabled: ≥ 96 % per language. Per-intent recall ≥ 85 %.
  Failures in either pass block ship until corpus regeneration / retraining (T-2404, T-2407, T-2408) closes the gap. Documented in `Specification/Voxio 1.1/parsing/accuracy-report.md`.
  *Depends on: T-2406, T-2416.*

---

## Task Summary (v1.1 only)

| Epic | Tasks | Notes |
|---|---|---|
| E-20 Fixed App Background | 8 | Supersedes v1.0 T-1001 |
| E-21 Dark Liquid Glass Button System | 13 | Includes T-2100 compile-blocker prerequisite. Supersedes v1.0 T-1104, T-1105 (rendering) |
| E-22 Dark-Mode-Only Visual Layer | 9 | Closes the sheet-presentation gap from v1.0 |
| E-23 v1.1 Visual QA & Regression Hardening | 9 | Depends on E-20, E-21, E-22 |
| E-24 Three-Tier Voice Command Parsing | 19 | Supersedes v1.0 T-1801–T-1810 (rendering). Existing `CommandParser` shipped under E-18 retained as Tier 3. |
| **Total (v1.1 only)** | **58** | Cumulative project total: 179 (v1.0) + 58 = **237** |

---

## Recommended Implementation Order

1. **E-20 first** — the background swap is the lowest-risk change, has no dependencies on the other two epics, and unlocks correct visual baselines for snapshot fixtures used in E-21 and E-22.
   - Sub-order: T-2001 → T-2002 → T-2004 → T-2003, T-2005, T-2006, T-2007, T-2008 in parallel.

2. **E-22 sheet enforcement in parallel with E-20** — adding `.preferredColorScheme(.dark)` to sheet bodies (T-2202, T-2203) is independent of the button work and the background. Doing it early prevents light-mode flash regressions during E-21 development.
   - Sub-order: T-2201 → T-2202, T-2203, T-2204 in parallel → T-2208, T-2209.

3. **E-24 corpus work starts in parallel with all of the above** — corpus assembly (T-2401 through T-2406) is independent of every visual task and is on the critical path because it gates Tier 2 training, which gates the router. Begin immediately.

4. **E-21 component build, starting with T-2100** — the compile-blocker prerequisite must merge first. Then the component, then call-site replacements.
   - Sub-order: **T-2100 (must merge first)** → T-2101 → T-2102 → T-2103 → T-2104 → T-2105, T-2106, T-2107, T-2108, T-2109, T-2110 in parallel → T-2111, T-2112.

5. **E-22 contrast-reactive border tasks** — T-2205, T-2206, T-2207 depend on `DarkGlassButton` existing (T-2102) and on T-2100 (token aliases) — and on the speaker card being visible against the new background.

6. **E-24 Tier 2 training, then Tier 1 integration, then router and call-site** — T-2407, T-2408 (training) depend on the corpus; T-2412, T-2413, T-2414 (Tier 1) are independent of training and can run in parallel; T-2415 router and T-2416 call-site wire-up depend on both Tier 1 and Tier 2 being ready.

7. **E-23 ships last (visual)** — visual snapshot tests and the regression cross-reference run only after E-20, E-21, and E-22 are merged.

8. **E-24 verification last (parsing)** — T-2417, T-2418, T-2419 run only after T-2416 lands. T-2419 regression-and-accuracy gating is a hard ship blocker.

A reasonable team sequence (assuming one full-time iOS engineer plus one part-time ML engineer):

```
Week 1:    iOS:  T-2100, T-2001–T-2008 (E-20), T-2201–T-2204 (E-22 enforcement)
           ML:   T-2401, T-2402, T-2403, T-2404 (corpus assembly, both languages)
Week 2:    iOS:  T-2101–T-2104 (DarkGlassButton component), T-2412 (IntentResult)
           ML:   T-2405, T-2406 (corpus finalisation, regression set)
Week 3:    iOS:  T-2105–T-2110 (call-site replacements), T-2413, T-2414 (Tier 1)
           ML:   T-2407, T-2408 (NLModel training, both languages)
Week 4:    iOS:  T-2111, T-2112, T-2205–T-2209 (contrast + cleanup), T-2415 (router)
           ML:   T-2409, T-2410, T-2411 (eval + thresholds + slot extraction)
Week 5:    iOS:  T-2416 (call-site wiring), T-2301–T-2309 (E-23 visual QA)
           Joint: T-2417, T-2418, T-2419 (privacy / latency / accuracy verification)
```

---

## Open Questions

1. **AppBackground.png delivery format** — Owner: Design team. Default assumption: design provides a single 642 × 1077 px PNG with @1x, @2x, @3x scales pre-exported, ≤ 600 KB optimised. Question: is a vector / SVG source available in case future iPad layouts re-open the asset?
2. **Confirm role icon tint colour token name** — Owner: Design team. Default assumption: re-use the existing `BeoColor.accent` (`#C8A97E`) token from v1.0. Question: should v1.1 introduce a dedicated `confirmIconTint` token for future flexibility, or stay coupled to `accent`?
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
| How is the Confirm action visually distinguished? | Same dark glass pill; only the leading SF Symbol is tinted with `--accent`. The label remains white. |
| How is the Cancel action visually distinguished? | Same dark glass pill; both label and icon in `Color.red` (system adaptive — not a hex value). |
| Sheet dark mode? | Each sheet body root explicitly applies `.preferredColorScheme(.dark)` in addition to the `WindowGroup`-level modifier. |
| Increase Contrast detection API? | SwiftUI `@Environment(\.colorSchemeContrast)`. T-2204 audits for any `UIAccessibility.isContrastEnabled` references (expected zero) and closes as N/A. |
| Increase Contrast effect on `DarkGlassButton`? | Border width increases to 1.0 pt and border colour becomes `BeoColor.muted` (alias `labelSecondary`). Shape, padding, and animation unchanged. |
| Pre-iOS-26 fallback for `.glassEffect`? | None. Deployment target stays at iOS 26. |
| `GlassEffectContainer` required for buttons? | No. Required only when multiple glass surfaces should visually merge — single buttons render correctly without it. |
| Hit area policy? | Minimum 44 × 44 pt for every interactive element, including the visually 36 × 36 pt icon-only variant which uses `.frame(minWidth: 44, minHeight: 44)` on the outer `Button` wrapper. |
| Animation system changes? | None. v1.0 spring tokens (`BeoAnimation.spring`, `cardExpand`, `toast`) remain authoritative. The `.interactive()` glass-effect modifier adds native press feedback on top of the existing `scaleEffect(0.95)` press animation. |
| Haptics in `DarkGlassButton`? | **None.** The component does not call `UIImpactFeedbackGenerator` or `UINotificationFeedbackGenerator`. Existing v1.0 haptics remain at their existing call sites: T-1108 sheet-appear `.medium` impact in `ConfirmationSheet.onAppear`; T-1109 confirm-tap `.success` notification in the confirm action handler. Both must survive the v1.1 migration unchanged. |
| `BeoColor` naming? | Codebase uses `text` and `muted`. T-2100 adds aliases `labelPrimary` and `labelSecondary` so v1.1 code can use either name. No rename in v1.1. |
| New tokens added in v1.1? | `appBackground` asset constant; `DarkGlassButton.{overlayColor, borderColor, borderWidth, paddingV, paddingH, iconGap, iconOnlySize, pressedScale, pressSpringResponse, pressSpringDamping}`; `BeoColor.labelPrimary` / `BeoColor.labelSecondary` aliases. |
| Are any v1.0 tasks removed? | No tasks are deleted from v1.0. T-1001 is superseded by E-20 (rendering); T-1104 and T-1105 are superseded by E-21 (rendering); T-1801 through T-1810 are superseded by E-24 (rendering of the parsing pipeline). All v1.0 task IDs remain in history. |
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
