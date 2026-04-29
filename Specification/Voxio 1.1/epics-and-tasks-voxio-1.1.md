# Epics & Tasks: Voxio v1.1
**Version:** 1.1  
**Status:** Draft  
**Date:** 2026-04-29  
**References:** VoxioSpecification-1.1, epics-and-tasks-bo-voice-control v1.3 (E-01–E-19), ADR-001-v1.1-visual-layer, ADR-002-v1.1-parsing (pending)  
**Languages:** English (`en-US`) and Danish (`da-DK`) — both fully supported

---

## Overview

This document breaks the Voxio v1.1 functional specification into epics and their constituent tasks. Each epic maps to a coherent area of the v1.1 release. Tasks are written at a level where a single developer can pick one up and complete it independently. v1.1 adds seven new epics (E-20 through E-26), continuing the numbering from v1.0's E-19. Task IDs begin at T-2001 and run through T-2610.

---

## Epic Index

| # | Epic | User Stories | Supersedes |
|---|---|---|---|
| E-20 | Fixed App Background | US-13, US-14 | v1.0 T-1001 |
| E-21 | Dark Liquid Glass Button System | US-15, US-16, US-17 | v1.0 T-1104, T-1105 (rendering only — fully removed by E-25) |
| E-22 | Dark-Mode-Only Visual Layer | US-18, US-19 | — |
| E-23 | v1.1 Visual QA & Regression Hardening | All v1.1 visual US | — |
| E-24 | Three-Tier Voice Command Parsing | US-20, US-21, US-22, US-23 | v1.0 T-1801–T-1810 (rendering; existing `CommandParser` retained as Tier 3) |
| E-25 | Auto-Execute Confirmation with Countdown Cancel | US-24, US-25 | v1.0 T-1104 (Yes button), T-1108 (haptic re-wired), T-0805 (10 s timeout), T-1109 (haptic re-wired) |
| E-26 | "Voxio" Trigger Word | US-26, US-27 | v1.0 T-0301, T-0302, T-0303 |

---

## E-20 — Fixed App Background

Replace the deep-charcoal gradient (and the original v1.0 plan to render the user's iOS wallpaper through a glass layer) with a fixed `AppBackground.png` asset rendered full-bleed behind every screen.

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

## E-21 — Dark Liquid Glass Button System

Build the single reusable dark-glass pill button as a SwiftUI view in `DesignSystem/`. Replace every existing button rendering (language-picker rows, hint dismissal, "?" hint trigger, the new countdown Cancel control) with this view. The two distinct visual variants required by v1.0 (Confirm = filled gold, Cancel = outlined) are unified under a single component with role-based icon/label tinting; the `.confirm` role has no call sites in v1.1 because the Yes button is removed by E-25, but the role is retained in the source for forward compatibility.

**Depends on:** none (additive design-system work)  
**Supersedes:** v1.0 T-1104 (Yes button — removed entirely by E-25), T-1105 (No button rendering — replaced by E-25 countdown Cancel)

### Compile-blocker prerequisite

- [ ] **T-2100** Reconcile `BeoColor` naming so v1.1 token references compile. Add the following aliases to `iOS/Voxio/DesignSystem/BeoColor.swift`:
  ```swift
  static let labelPrimary   = BeoColor.text
  static let labelSecondary = BeoColor.muted
  ```
  Do not rename `text` or `muted`; existing v1.0 call sites continue to use those names. Both pairs (the originals and the aliases) must compile and resolve to the same `Color` asset. This task must merge before T-2102 begins, otherwise `DarkGlassButton` will fail to compile. Identified by ADR-001-v1.1-visual-layer §Conflict 1.
  *No dependencies. Prerequisite for T-2102, T-2205, T-2206.*

### Component build

- [ ] **T-2101** Add v1.1 button design tokens to `DesignTokens.swift` — append a `DarkGlassButton` enum (or extend an existing tokens enum) with: `overlayColor = Color.black.opacity(0.45)`, `borderColor = Color.white.opacity(0.15)`, `borderWidth: CGFloat = 0.5`, `paddingV: CGFloat = 10`, `paddingH: CGFloat = 16`, `iconGap: CGFloat = 6`, `iconOnlySize: CGFloat = 36`, `pressedScale: CGFloat = 0.95`, `pressSpringResponse: Double = 0.3`, `pressSpringDamping: Double = 0.7`. Mirror the design spec v1.1 §Design Tokens Reference exactly.
  *No dependencies. Prerequisite for T-2102.*

- [ ] **T-2102** Build `DarkGlassButton` SwiftUI view in `iOS/Voxio/DesignSystem/DarkGlassButton.swift`. API: `init(label: String, systemImage: String? = nil, role: Role = .default, action: @escaping () -> Void)`. `Role` enum cases: `.default`, `.confirm`, `.cancel`, `.disabled`. Body composes a `Button` with `.glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: Capsule())`, `.overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))`, content `HStack { icon; label }`, padding from tokens, and the `scaleEffect(0.95)` press animation via `ButtonStyle`. **The component must not call `UIImpactFeedbackGenerator` or `UINotificationFeedbackGenerator`** — haptics remain the responsibility of the call site.
  *Depends on: T-2100, T-2101.*

- [ ] **T-2103** Implement `DarkGlassButton.Role` rendering rules:
  - `.default` — label `BeoColor.labelPrimary` (alias for `BeoColor.text`), icon white
  - `.confirm` — label `BeoColor.labelPrimary`, icon `BeoColor.accent` (`#C8A97E`) — retained for forward compatibility but with no v1.1 call sites
  - `.cancel` — label and icon both `Color.red` (system adaptive red — not a hex value, so the colour follows iOS's accessibility rendering)
  - `.disabled` — entire button at `.opacity(0.4)` and `.disabled(true)`
  Each role must produce visually distinct output but share shape, padding, border, and press animation.
  *Depends on: T-2102.*

- [ ] **T-2104** Build `DarkGlassIconButton` icon-only variant in the same file — circular pill, 36 × 36 pt visual size (via an inner `.frame(width: 36, height: 36)` on the visual capsule), `.frame(minWidth: 44, minHeight: 44)` on the outer `Button` wrapper for the hit area, single SF Symbol centred. Same role enum and same press animation as `DarkGlassButton`. The component must not emit haptics. API: `init(systemImage: String, role: Role = .default, accessibilityLabel: String, action: @escaping () -> Void)`.
  *Depends on: T-2102, T-2103.*

### Call-site replacements

- [ ] **T-2107** Replace the language-picker row rendering in `LanguagePickerSheet` (T-1902) with two `DarkGlassButton` instances — one per language. Labels: "English" and "Dansk", role: `.default`. The existing `setLanguage(_:)` and dismiss behaviour from T-1902 / T-1903 is unchanged. **Visible shape change:** rows that were `RoundedRectangle(cornerRadius: 12)` become `Capsule()`; deliberate per ADR-001-v1.1-visual-layer §Conflict 3 and verified against `ButtonLookAndFeel.png` in T-2304.
  *Depends on: T-2103.*

- [ ] **T-2108** Replace the "?" hint button rendering in `HomeView`'s status bar (T-1906) with `DarkGlassIconButton(systemImage: "questionmark.circle", accessibilityLabel: hintButtonAccessibilityLabel, action: toggleHint)`. The existing `accessibilityLabel` localisation logic from T-1906 must continue to work. Visible change: the previously bare `Button { Image(systemName:) }` gains a 36 × 36 pt dark glass capsule surface with the standard hairline border.
  *Depends on: T-2104.*

- [ ] **T-2109** Replace the "Got it" / "OK" hint dismissal button rendering in `HintCardView` (T-1905) with `DarkGlassButton(label: dismissLabel, role: .default, action: dismissHint)`. Auto-hide behaviour and `hasSeenHint` persistence from T-1905 unchanged. **Visible shape change:** the dismiss button moves from `RoundedRectangle(cornerRadius: Radius.sheet)` (16 pt corner radius) to `Capsule()`. Deliberate per ADR-001-v1.1-visual-layer §Conflict 5; verified in T-2304. The hint card itself remains `RoundedRectangle(cornerRadius: Radius.card)` — only the button inside it changes shape.
  *Depends on: T-2103.*

- [ ] **T-2110** Audit `iOS/Voxio/` for any remaining `Button { … }` definitions that render visible interactive controls and replace each with `DarkGlassButton` or `DarkGlassIconButton`. Acceptable exceptions: (a) speaker selector pills (a separate component, T-1004, retains its existing pill style), (b) `accessibilityElement` decorative wrappers, (c) gesture-target views without a visible button surface, (d) the v1.0 Yes / No buttons which are removed entirely by E-25 — not replaced. Document each exception in a code comment referencing this task.
  *Depends on: T-2103, T-2104.*

> Note: the v1.0 confirm-button replacement (T-2105) and cancel-button replacement (T-2106) tasks are removed in v1.1.3 because the Yes button is deleted entirely by E-25 and the cancel control is built fresh under T-2502 against the new countdown surface, not as a 1:1 replacement of the v1.0 No button. T-2105 and T-2106 IDs are retired (do not reuse).

### Component verification

- [ ] **T-2111** Add SwiftUI previews for `DarkGlassButton` and `DarkGlassIconButton` rendering all four roles in dark mode and dark + Increase Contrast mode. Each preview is a standalone `#Preview` block in the same file.
  *Depends on: T-2102, T-2104.*

- [ ] **T-2112** Verify hit areas — every `DarkGlassButton` and `DarkGlassIconButton` instance reports a tap target of at least 44 × 44 pt via the Accessibility Inspector. Add a snapshot test that fails if the button's `.frame` falls below that minimum.
  *Depends on: T-2102, T-2104.*

---

## E-22 — Dark-Mode-Only Visual Layer

Enforce dark mode at every presentation boundary: the main window, every `.sheet`, every `.popover` (none currently shipped, but defensive), and every system-rendered surface that sits inside the app's `WindowGroup`. Add the SwiftUI `@Environment(\.colorSchemeContrast)` reactive Increase Contrast border path. Audit for any legacy `UIAccessibility.isContrastEnabled` references; close as N/A if none are found.

**Depends on:** none

- [ ] **T-2201** Audit `iOS/Voxio/` for every `.sheet`, `.fullScreenCover`, `.popover`, and `.alert` modifier. Build a list of sheet content roots (`LanguagePickerSheet.body`, the new countdown surface root from T-2502, plus any future sheets). Document the list as a code comment in `VoxioApp.swift`.
  *No dependencies. Prerequisite for T-2202.*

- [ ] **T-2202** Add `.preferredColorScheme(.dark)` to the body root of `LanguagePickerSheet`. Verify on a light-mode simulator that the sheet renders dark on first present, on dismissal, and on re-present. Place the modifier as the last modifier on the outermost view in `body`, after layout/frame modifiers and before any presentation modifiers.
  *Depends on: T-2201.*

- [ ] **T-2203** Add `.preferredColorScheme(.dark)` to the body root of the countdown surface (T-2502). Verify on a light-mode simulator that the surface renders dark on present, on dismissal, and on re-present immediately after the next parsed command. Same placement convention as T-2202.
  *Depends on: T-2201, T-2502.*

- [ ] **T-2204** Audit `iOS/Voxio/` for any reference to `UIAccessibility.isContrastEnabled`. If any are found, replace them with `@Environment(\.colorSchemeContrast)` reads. The expected outcome (per ADR-001-v1.1-visual-layer §Context, item 4) is zero hits — the codebase is SwiftUI-first. Document the audit result in a code comment in `BeoColor.swift` or the project's accessibility-related file and close the task. Do **not** remove `UIAccessibility.post(notification:)` VoiceOver announcements such as the one in `LanguagePickerSheet.onAppear` — those are accessibility announcements, not contrast detection.
  *No dependencies.*

- [ ] **T-2205** Add `@Environment(\.colorSchemeContrast) private var contrast` to `DarkGlassButton` and `DarkGlassIconButton` (T-2102, T-2104). When `contrast == .increased`, render the border at 1.0 pt width and use `BeoColor.muted` (aliased as `BeoColor.labelSecondary` after T-2100) for the border colour instead of `Color.white.opacity(0.15)`. The shape, padding, animation, and text colour are unchanged.
  *Depends on: T-2100, T-2102, T-2104.*

- [ ] **T-2206** Apply the same `\.colorSchemeContrast` reactive border pattern to the speaker card (T-1002) — when contrast is increased, add a 1 pt border in `BeoColor.muted` (aliased as `BeoColor.labelSecondary`). No other v1.0 contrast handling changes.
  *Depends on: T-2100, T-2205.*

- [ ] **T-2207** Verify reactivity — toggle Increase Contrast in iOS Settings while the simulator is foregrounded with the app running. The visible buttons and speaker card must re-render their border treatment within one display frame (verified by visual inspection at 60 fps recording, or by logging the environment value on each `body` invocation).
  *Depends on: T-2205, T-2206.*

- [ ] **T-2208** Confirm light-mode simulator behaviour end-to-end — switch the simulator to Light Mode, launch the app, navigate through: home idle (passive) → language picker (first launch) → home idle (passive) → trigger word → command recognition (active) → countdown surface → auto-execute → home idle (passive). At every step, no surface inside the app's `WindowGroup` flashes light. System-rendered permission alerts may render in light mode and are explicitly out of scope for this verification.
  *Depends on: T-2202, T-2203.*

- [ ] **T-2209** Document the dark-mode-only constraint in `iOS/Voxio/DesignSystem/README.md` (or, if no README exists, as a header comment in `DarkGlassButton.swift`). Future-proof: any new `.sheet`, `.popover`, or `.fullScreenCover` content view must include `.preferredColorScheme(.dark)` on its body root.
  *Depends on: T-2202, T-2203.*

---

## E-23 — v1.1 Visual QA & Regression Hardening

Catch v1.1 regressions before they ship by adding snapshot tests and cross-referencing every v1.0 acceptance criterion against the new visual layer. Confirm the v1.0 functional surface is intact except where deliberately amended by E-25 / E-26.

**Depends on:** E-20, E-21, E-22, E-25, E-26

- [ ] **T-2301** Add snapshot tests for `HomeView` idle state in: dark mode (default), dark mode + Increase Contrast, dark mode + largest Dynamic Type accessibility size. Capture both the passive-orb state and the active-orb state. All three variants must pass on the iPhone 15 Pro simulator frame.
  *Depends on: T-2002, T-2206, T-2602.*

- [ ] **T-2302** Add snapshot tests for the countdown surface (T-2502) rendered with a sample read-back string and the digit at 3, 2, 1 in: dark mode, dark mode + Increase Contrast, light-mode system / dark-mode app (verifies T-2203 is effective).
  *Depends on: T-2502, T-2203.*

- [ ] **T-2303** Add snapshot tests for `LanguagePickerSheet` first-launch presentation in: dark mode, dark mode + Increase Contrast, light-mode system / dark-mode app (verifies T-2202 is effective).
  *Depends on: T-2107, T-2202.*

- [ ] **T-2304** Add snapshot tests for `DarkGlassButton` in three roles used in v1.1 (`.default`, `.cancel`, `.disabled`) and for `DarkGlassIconButton` in two roles (`.default`, `.cancel`). The `.confirm` role is captured in a preview but does NOT have a snapshot test (no v1.1 call site). **Verify visual parity with the design spec v1.1 reference image `ButtonLookAndFeel.png` before committing the reference snapshots** — confirm the reference image was generated at the same dimensions used in the snapshot test, so the deliberate `Capsule()` shape change (from v1.0's `RoundedRectangle(cornerRadius: 12)`) matches the design intent. Identified by ADR-001-v1.1-visual-layer §Conflict 3.
  *Depends on: T-2103, T-2104.*

- [ ] **T-2305** Run the v1.0 E-13 accessibility audit (T-1308) against every screen after v1.1 lands. Resolve any new tap-target or contrast violations introduced by the visual changes.
  *Depends on: T-2002, T-2110, T-2206.*

- [ ] **T-2306** Run the v1.0 E-14 animation profile (T-1410) on a minimum-spec device (A15). Confirm 60 fps is maintained during countdown surface present/dismiss with the new dark glass cancel button, the new background, and the orb passive↔active transition.
  *Depends on: T-2002, T-2502, T-2602.*

- [ ] **T-2307** Re-run the existing E-19 unit test suite (T-1909) and confirm all six sub-cases still pass after `DarkGlassButton` replaces the language-picker rows, the hint dismissal, and the "?" hint trigger.
  *Depends on: T-2107, T-2108, T-2109.*

- [ ] **T-2308** Cross-reference every v1.0 acceptance criterion in E-10, E-11, E-12, E-13, E-14, and E-19 against the v1.1 implementation. Document any deviation. The only expected functional deviations are those introduced deliberately by E-25 (confirmation flow) and E-26 (listening posture). Pay particular attention to haptic timing — confirm T-1108 sheet-appear `.medium` impact is now wired to countdown start (T-2503), T-1109 `.success` is now wired to auto-execute (T-2504), and the new `.error` cancel haptic (T-2505) does not double-fire.
  *Depends on: E-20, E-21, E-22, E-25, E-26 complete.*

- [ ] **T-2309** Manual exploratory pass on a physical iPhone (not simulator) — verify the specular highlight on the dark glass buttons responds to device tilt as the iOS 26 `.glassEffect(.interactive())` API specifies. Document the device model and iOS version used.
  *Depends on: T-2502.*

---

## E-24 — Three-Tier Voice Command Parsing

Replace the v1.0 keyword/regex-only parsing pipeline with a three-tier router that routes each transcript through the most accurate available classifier on the device, falling through to lower tiers on unavailability or low confidence. Tier 1 uses Foundation Models on devices that have Apple Intelligence; Tier 2 uses a retrained per-language `NLModel` and is the **primary floor** for all supported devices; Tier 3 is the existing keyword `CommandParser`, retained unchanged as a deterministic safety net. Both English and Danish must be covered at every tier. The intent set in `VoiceCommand.swift` is unchanged.

**Depends on:** none in v1.1 (architecturally additive; the existing `CommandParser` from E-18 becomes Tier 3 without modification)  
**Supersedes:** v1.0 task IDs T-1801, T-1802, T-1803, T-1804, T-1805, T-1806, T-1807, T-1808, T-1809, T-1810 — the rendering of those task IDs is replaced by E-24's tasks. The existing `CommandParser` Swift file shipped under E-18 remains in place. The retired task IDs remain in v1.0 history; they do not cease to exist as historical references.

### Corpus creation

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

- [ ] **T-2406** Curate a separate **regression corpus** containing every canonical phrasing the v1.0 `CommandParser` is known to handle correctly (extracted from the existing v1.0 unit tests and from the keyword tables in `CommandParser.swift`). At least 50 utterances per language. Stored at `Specification/Voxio 1.1/parsing/corpus-regression.jsonl`. This corpus is used by T-2419 to prove zero v1.0 regressions; it is **not** used for training (to avoid the model memorising the exact keyword phrasings the keyword parser already handles trivially).
  *Depends on: T-2402.*

### Tier 2 NLModel training

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

### Tier 1 Foundation Models integration

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

### Router and call-site wiring

- [ ] **T-2415** Extend the existing `CommandParserRouter` (introduced in commit `63467c0`) to wrap all three tiers behind a single async API: `func parse(_ transcript: String) async -> VoiceCommand`. Internal flow:
  1. If Tier 1 is available, call it; if it returns a non-`nil` `VoiceCommand`, return it.
  2. Else, call Tier 2 (`NLModel` for the active language) — apply slot extraction (T-2411). If the prediction confidence is ≥ threshold (T-2410) and slot extraction succeeded where required, return the resulting `VoiceCommand`.
  3. Else, call Tier 3 (existing `CommandParser`). Return whatever it returns (which may be `.unknown(transcript)`).
  Tier selection is computed once at router init based on `SystemLanguageModel.default.availability` and on whether the per-language `.mlmodel` is present in the bundle. Subsequent runtime degradations (Tier 1 timeout pattern, Tier 2 missing model) downgrade the active tier set for the remainder of the session. Source in `iOS/Voxio/Core/Voice/CommandParserRouter.swift`.
  *Depends on: T-2407, T-2408, T-2410, T-2411, T-2413.*

- [ ] **T-2416** Update `VoiceToText.swift:50` to call the async router. Replace the synchronous `CommandParser(language: lang).parse(text)` call with a `Task` that awaits `router.parse(text)` and delivers the result on the main actor before invoking `onCommand` and `onFinalTranscript`. Preserve ordering: `onFinalTranscript` fires before `onCommand` (matches v1.0 ordering). Preserve the existing `Log.info("[Voice] \(command)")` line.
  *Depends on: T-2415.*

### Verification

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

## E-25 — Auto-Execute Confirmation with Countdown Cancel

Replace the Yes/No two-button confirmation pattern with an auto-execute model. After the spoken read-back finishes, a 3-second countdown runs. The action fires automatically at the end of the countdown unless the user cancels (by tapping Cancel or by saying "cancel" / "no" / "nej" / "annuller"). The Yes button is removed entirely. The 10-second confirmation timeout from T-0805 is replaced by this 3-second auto-execute.

**Depends on:** E-21 component build (T-2102, T-2103) — the countdown surface uses `DarkGlassButton(role: .cancel)`. E-22 sheet enforcement (T-2203) — the countdown surface body root needs `.preferredColorScheme(.dark)`.  
**Supersedes:** v1.0 T-1104 (Yes button rendering and behaviour — removed entirely), T-1108 (sheet-appear haptic wiring — re-wired to countdown start), T-0805 (10-second confirmation timeout — replaced by 3-second auto-execute). T-1109 (confirm-tap `.success` haptic) is re-wired to fire on auto-execute. T-1105 (No button rendering) is also superseded — the cancel control is built fresh against the countdown surface, not migrated from the v1.0 No button.

### Coordinator API change

- [ ] **T-2501** Replace the `ConfirmationCoordinator` confirm/cancel API with the countdown API. Remove `func confirm()` and `func cancel()`. Add `func startCountdown(action: @escaping () async -> Void, readBack: String, onResolved: @escaping (Resolution) -> Void)` where `Resolution` is `enum { case fired, cancelled }`. Add `func cancelCountdown(reason: CancelReason)` where `CancelReason` is `enum { case userTap, userVoice, interruption }`. Preserve the existing v1.0 `pendingCommand` storage convention if it exists, but the actual action execution now happens inside `startCountdown`'s timer-expiry path. The 10-second confirmation timeout from T-0805 is removed — the only timer that lives in the coordinator is the 3-second countdown.
  *No dependencies. Prerequisite for T-2502, T-2504, T-2505.*

### Countdown surface

- [ ] **T-2502** Build the `CountdownConfirmationSurface` SwiftUI view in `iOS/Voxio/Features/Confirmation/CountdownConfirmationSurface.swift` (creating the `Confirmation` folder if needed). API: `init(readBackText: String, secondsRemaining: Int, onCancel: () -> Void)`. Body composes a dark Liquid Glass card containing: the read-back text label, the countdown text "Cancelling in {n}…" / "Annullerer om {n}…" (localised) where `{n}` is `secondsRemaining`, and a single `DarkGlassButton(label: cancelLabel, systemImage: "xmark", role: .cancel, action: onCancel)`. The body root applies `.preferredColorScheme(.dark)` per T-2203. The numeric value updates each whole second; the digit substitution is instantaneous (no scale/opacity transition; Reduce Motion friendly by construction). The label "Cancel"/"Annuller" is supplied via `LanguageService` / `String(localized:)`.
  *Depends on: T-2102, T-2103, T-2501.*

- [ ] **T-2503** Wire the countdown-start `.medium` impact haptic. Trigger `UIImpactFeedbackGenerator(style: .medium).impactOccurred()` once when the countdown surface appears (i.e. on `onAppear` of the surface, after TTS read-back has completed). This is the re-wiring of the v1.0 T-1108 haptic from sheet-appear to countdown-start. The haptic must NOT fire during the read-back phase; only after read-back completes and the countdown actually starts.
  *Depends on: T-2502.*

- [ ] **T-2504** Wire the auto-execute `.success` notification haptic. Trigger `UINotificationFeedbackGenerator().notificationOccurred(.success)` at the moment the timer expires and the bound action is invoked. Fires exactly once per successful auto-execute. This is the re-wiring of the v1.0 T-1109 haptic from confirm-tap to auto-execute.
  *Depends on: T-2501.*

- [ ] **T-2505** Wire the cancel `.error` notification haptic. Trigger `UINotificationFeedbackGenerator().notificationOccurred(.error)` when `cancelCountdown(reason:)` is invoked with `.userTap` or `.userVoice`. Do NOT fire `.error` for `.interruption` cancellations (OS interruptions are not user-driven). Fires exactly once per cancel.
  *Depends on: T-2501.*

### Voice cancel

- [ ] **T-2506** Implement the voice-cancel grammar. While the countdown surface is on screen, the active speech-recognition session continues to deliver partial transcripts to `VoiceToText` (existing v1.0 transcript stream, unchanged). Add a lightweight cancel-detector that scans incoming partial transcripts for whole-word presence of `cancel`, `no`, `nej`, `annuller` (case-insensitive). On match, call `coordinator.cancelCountdown(reason: .userVoice)` and stop further matching for this countdown instance (idempotent on subsequent matches in the same buffer). Match logic lives in `iOS/Voxio/Features/Confirmation/CancelGrammar.swift`. Tokens are not routed through the `CommandParserRouter` (Tier 3 keyword detection is sufficient and faster).
  *Depends on: T-2501.*

### State integration

- [ ] **T-2507** Update the parsed-command handler to call `coordinator.startCountdown(action:readBack:onResolved:)` instead of presenting the v1.0 Yes/No `ConfirmationSheet`. The TTS read-back continues to play first; the countdown starts on TTS completion (matches v1.0 read-back-then-confirm ordering). The bound action is the existing v1.0 use-case handler call (`Speaker.play()`, `Speaker.setVolume()` etc.) — unchanged. On `Resolution.fired`, the coordinator transitions the orb back to passive (E-26 `triggerWordController.returnToPassive()`); on `Resolution.cancelled`, same transition.
  *Depends on: T-2502, T-2506.*

- [ ] **T-2508** Remove the v1.0 `ConfirmationSheet` view, the `.sheet(isPresented:)` modifier that presented it, the Yes-tap handler, the No-tap handler, and the 10-second `Task.sleep` from `ConfirmationCoordinator`. Audit `iOS/Voxio/` for any lingering references to `ConfirmationSheet` and remove them. Replace with the new countdown surface presentation path. Document in a code comment that the v1.0 IDs T-1104, T-1105, T-1108 (haptic wiring location), and T-0805 are superseded by E-25.
  *Depends on: T-2507.*

### Verification

- [ ] **T-2509** Unit-test the countdown state machine for: (a) countdown completes without cancel → action fires exactly once and `.success` haptic fires once, (b) tap-cancel during countdown → action does not fire and `.error` haptic fires once, (c) voice-cancel during countdown → action does not fire and `.error` haptic fires once, (d) tie between voice-cancel and timer expiry → action does not fire (cancellation wins ties), (e) OS interruption (e.g. simulated app-will-resign-active notification) during countdown → action does not fire and no `.error` haptic. Tests live in `iOS/VoxioTests/CountdownTests.swift`.
  *Depends on: T-2501, T-2503, T-2504, T-2505, T-2506.*

- [ ] **T-2510** Manual verification on physical device: trigger the orb to active, issue a parseable command, confirm read-back plays, confirm countdown surface appears immediately after TTS, confirm digit substitution at each second, confirm tapping Cancel within the window cancels and produces `.error` haptic, confirm saying "cancel" within the window cancels, confirm doing nothing within the window auto-executes and produces `.success` haptic, confirm orb returns to passive after each resolution. Document the device model, iOS version, and any deviations.
  *Depends on: T-2509.*

---

## E-26 — "Voxio" Trigger Word

Replace the always-listening model with a wake-word activation model. The app's speech-recognition pipeline runs in a low-cost passive mode that scans for "Voxio" only; on detection, the pipeline switches to the full v1.0 active mode for the next utterance. The orb visibly distinguishes the two states. The v1.0 always-on entry path (T-0301, T-0302, T-0303) is replaced.

**Depends on:** none — the wake-word state machine is additive at the source level, but it changes the entry point of the existing speech pipeline.  
**Supersedes:** v1.0 T-0301 (always-on `SFSpeechRecognizer` instantiation), T-0302 (`VoiceInputManager` start/stop semantics — the start-on-foreground / stop-on-background pair is preserved but the start path now lands in passive state, not active), T-0303 (silence detection as the entry point — silence detection is now the **exit** path from active back to passive, not the entry from idle).

### Trigger detection

- [ ] **T-2601** Build `TriggerWordDetector` in `iOS/Voxio/Core/Voice/TriggerWordDetector.swift`. Implementation strategy: **default to `SFSpeechRecognizer` in a continuous on-device recognition mode scanning for whole-word "Voxio" in incoming partial transcripts**. The detector emits a callback `onTriggerDetected: () -> Void` exactly once per detection, then suspends until re-armed by the state machine (T-2602) returning to passive. Match is case-insensitive on whole-word boundary. Configuration: `requiresOnDeviceRecognition = true` is set so no audio reaches Apple's servers (matches v1.0 privacy posture). If iOS 26 exposes a dedicated keyword-spotting API (Q20 — investigation in T-2603), use it as the implementation under the same callback surface; the state-machine consumer (T-2602) does not need to know which path is active.
  *No dependencies. Prerequisite for T-2602, T-2603.*

- [ ] **T-2602** Build `TriggerWordController` in `iOS/Voxio/Core/Voice/TriggerWordController.swift` — the state machine. States: `passive`, `active`. Public API: `func start()` (move to passive and arm `TriggerWordDetector`), `func returnToPassive(reason: ReturnReason)` (called by E-25 on countdown resolution, or by the 5-second silence timer in active state). `ReturnReason` is `enum { case silence, command, interruption }`. On `onTriggerDetected` from T-2601: transition to active, suspend `TriggerWordDetector`, hand control to the existing v1.0 active speech pipeline (the same `SFSpeechRecognizer`-driven full-transcript capture path that v1.0 used after T-0301), and start a 5-second silence-timeout timer. On the active pipeline's silence-detection callback (the existing v1.0 `silenceTimeout`): hand the captured transcript to the `CommandParserRouter` (E-24); the resolution path through E-25 eventually calls back into `returnToPassive(reason: .command)`. On 5-second silence-timeout firing with no captured speech: `returnToPassive(reason: .silence)`. Log every transition at INFO.
  *Depends on: T-2601.*

- [ ] **T-2603** Investigate the iOS 26 keyword-spotting / wake-word API surface (Q20). Read the iOS 26 release notes, WWDC25 sessions, and `Speech.framework` and `AudioToolbox` documentation. Specifically, determine whether iOS 26 exposes a dedicated low-power keyword-spotting primitive (e.g. an extension to `SFSpeechRecognizer` such as a `requiresContinuousRecognition: false` mode, or a new framework-level API). Document findings in `Specification/Voxio 1.1/triggerword/keyword-spotting-investigation.md`. **Decision rule:** if the dedicated API exists and is at least 30 % more power-efficient than the `SFSpeechRecognizer`-based default, adopt it inside `TriggerWordDetector` (replacing the default implementation under the same callback surface). Otherwise, keep the `SFSpeechRecognizer` default and accept the battery cost. Investigation is a prerequisite for T-2606.
  *Depends on: T-2601.*

- [ ] **T-2604** Update the mic-permission usage description and the hint card. Update `NSMicrophoneUsageDescription` in the iOS target's Info.plist (or the equivalent build settings) to: "Voxio listens for the wake word 'Voxio' so you can control your speakers by voice. All speech recognition happens on your device." (English; Danish translation through `LanguageService`). Update `HintCardView` example phrases (T-1905 content) to: "Try saying: Voxio, Beosound play" / "Prøv at sige: Voxio, Beosound spil". Update the home-screen status text for the passive state to "Say 'Voxio' to start" / "Sig 'Voxio' for at starte". Active-state status text remains "Listening…" / "Lytter…" from v1.0.
  *No dependencies (string changes only). Prerequisite for T-2606.*

### Trigger-in-utterance handling

- [ ] **T-2605** Add transcript pre-processing for the trigger-in-utterance pattern. When the active pipeline finalises a transcript, before handing it to the `CommandParserRouter`, strip a leading "Voxio" / "voxio" token (with any directly-following comma or whitespace) from the transcript. Implementation: a small pure function `stripTriggerPrefix(_ transcript: String) -> String` in `TriggerWordController.swift` (or a sibling helper file). Whole-word match on the leading token only — "Voxio" inside the transcript (e.g. "play voxio podcast") is left untouched. Unit-tested in `iOS/VoxioTests/TriggerStripTests.swift` covering: leading "Voxio,", leading "voxio ", leading "Voxio" (no separator → still strip if followed by whitespace), embedded "voxio" (no strip), capitalisation variants.
  *Depends on: T-2602.*

### Orb states

- [ ] **T-2606** Build the dual-state orb animation. In the existing orb view (`HomeView` or its child), add an `@Environment` or `@Observable` binding to `TriggerWordController.state`. When `state == .passive`, render: scale ≤ 70 % of v1.0 active scale, slow pulse cycle ≥ 2 s (a `withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true))` modulating opacity or scale), and a less saturated colour treatment (use `BeoColor.muted`-toned overlay). When `state == .active`, render the v1.0 active animation exactly (scale + glow respond to live RMS audio level). Transition between states is animated (≤ 250 ms cross-fade); under Reduce Motion the transition is a plain opacity cross-fade with no scale animation. Animation tokens added to `DesignTokens.swift` under a new `OrbState` enum: `passiveScale: CGFloat = 0.7`, `passivePulseDuration: Double = 2.0`, `transitionDuration: Double = 0.25`.
  *Depends on: T-2602, T-2603, T-2604.*

### Reliability and verification

- [ ] **T-2607** Reliability test — recall measurement. Record a 50-utterance bilingual test set covering: 25 utterances starting with "Voxio" alone (then a command), 25 utterances starting with "Voxio, " (combined trigger+command). Half English, half Danish. Speaker at ~1 m from the device in a quiet room at conversational volume. Run each utterance through a build with `TriggerWordController` engaged. Required: ≥ 95 % of utterances trigger the passive→active transition within 250 ms of the end of "Voxio". Document in `Specification/Voxio 1.1/triggerword/reliability-recall.md`.
  *Depends on: T-2606.*

- [ ] **T-2608** Reliability test — false-activation measurement. Run a 1-hour foregrounded idle session in a household environment with low-volume background music or TV (typical living-room conditions). Required: ≤ 1 false passive→active transition per hour. Document in `Specification/Voxio 1.1/triggerword/reliability-false-activation.md`. If the rate exceeds 1/hour, file follow-up tasks to tune the trigger detector (e.g. add a confidence floor on the `SFSpeechRecognizer` partial transcript) — not a hard ship blocker but a monitor.
  *Depends on: T-2606.*

- [ ] **T-2609** Privacy / network audit for the trigger-word path. Reuse the harness from T-2417. Run a packet capture for a 10-minute foregrounded session that includes ~10 trigger-word activations. Required: zero outbound packets attributable to the trigger-word listening path. Document in `Specification/Voxio 1.1/triggerword/privacy-audit.md`. Spec acceptance forbids any outbound traffic from this path.
  *Depends on: T-2606.*

- [ ] **T-2610** Battery / energy measurement. Run the Xcode Instruments Energy gauge on iPhone 13 (A15) for a 5-minute foregrounded idle session in passive state (no triggers, no commands). Compare against an equivalent v1.0 build's measurement (or a control build with v1.0 always-on `SFSpeechRecognizer` enabled). Required: ≥ 30 % reduction in mic-attributed energy use in the v1.1 passive build. Document in `Specification/Voxio 1.1/parsing/battery-report.md` (shared file with parsing battery work). If the target is not met, T-2603 may direct adopting the iOS 26 keyword-spotting API; do this before ship.
  *Depends on: T-2606.*

---

## Recommended Implementation Order

1. **E-20 first** — the background swap is the lowest-risk change, has no dependencies on the other epics, and unlocks correct visual baselines for snapshot fixtures used in E-21 / E-22 / E-25.
   - Sub-order: T-2001 → T-2002 → T-2004 → T-2003, T-2005, T-2006, T-2007, T-2008 in parallel.

2. **E-22 sheet enforcement in parallel with E-20** — adding `.preferredColorScheme(.dark)` to the language picker (T-2202) is independent of every other task and prevents light-mode flash regressions during E-21 / E-25 development. T-2203 (countdown surface dark-mode) waits for T-2502.
   - Sub-order: T-2201 → T-2202, T-2204 in parallel; T-2203 waits.

3. **E-24 corpus work starts in parallel with all of the above** — corpus assembly (T-2401 through T-2406) is independent of every visual task and is on the critical path because it gates Tier 2 training, which gates the router. Begin immediately.

4. **E-26 trigger-word investigation T-2603 in parallel** — the iOS 26 keyword-spotting API investigation is independent and gates the implementation choice in T-2606. Schedule it early so the result is available before T-2606 begins.

5. **E-21 component build, starting with T-2100** — the compile-blocker prerequisite must merge first. Then the component, then call-site replacements.
   - Sub-order: **T-2100 (must merge first)** → T-2101 → T-2102 → T-2103 → T-2104 → T-2107, T-2108, T-2109, T-2110 in parallel → T-2111, T-2112.

6. **E-25 coordinator API change T-2501 unblocks countdown surface T-2502** — once T-2103 (the `.cancel` role rendering) and T-2501 are both in, T-2502 can build. After T-2502 lands, T-2203 (sheet dark-mode for the countdown surface) can be wired.

7. **E-26 state machine and orb states** — T-2601 → T-2602 → T-2604 in parallel; T-2606 (orb states) waits on T-2602 and T-2603.

8. **E-22 contrast-reactive border tasks** — T-2205, T-2206, T-2207 depend on `DarkGlassButton` existing (T-2102) and on T-2100 (token aliases) — and on the speaker card being visible against the new background.

9. **E-25 haptics, voice-cancel, integration** — T-2503 → T-2506 → T-2507 → T-2508 in sequence; T-2504, T-2505 in parallel after T-2501.

10. **E-24 Tier 2 training, then Tier 1 integration, then router and call-site** — T-2407, T-2408 (training) depend on the corpus; T-2412, T-2413, T-2414 (Tier 1) are independent of training and can run in parallel; T-2415 router and T-2416 call-site wire-up depend on both Tier 1 and Tier 2 being ready.

11. **E-25 unit tests T-2509 → manual T-2510**; **E-26 reliability T-2607, T-2608, privacy T-2609, battery T-2610** — all run after the relevant build tasks land.

12. **E-23 ships last (visual)** — visual snapshot tests and the regression cross-reference run only after E-20, E-21, E-22, E-25, E-26 are merged.

13. **E-24 verification last (parsing)** — T-2417, T-2418, T-2419 run only after T-2416 lands. T-2419 regression-and-accuracy gating is a hard ship blocker.

A reasonable team sequence (assuming one full-time iOS engineer plus one part-time ML engineer):

```
Week 1:    iOS:  T-2100, T-2001–T-2008 (E-20), T-2201, T-2202, T-2204 (E-22 enforcement),
                 T-2603 (Q20 investigation), T-2604 (string updates)
           ML:   T-2401, T-2402, T-2403, T-2404 (corpus assembly, both languages)
Week 2:    iOS:  T-2101–T-2104 (DarkGlassButton component), T-2412 (IntentResult),
                 T-2501 (coordinator API change), T-2601 (TriggerWordDetector)
           ML:   T-2405, T-2406 (corpus finalisation, regression set)
Week 3:    iOS:  T-2107–T-2110 (call-site replacements), T-2413, T-2414 (Tier 1),
                 T-2502 (countdown surface), T-2602 (state machine), T-2605 (prefix strip)
           ML:   T-2407, T-2408 (NLModel training, both languages)
Week 4:    iOS:  T-2111, T-2112, T-2203, T-2205–T-2209 (contrast + cleanup),
                 T-2503–T-2508 (haptics + voice cancel + integration), T-2606 (orb states),
                 T-2415 (router)
           ML:   T-2409, T-2410, T-2411 (eval + thresholds + slot extraction)
Week 5:    iOS:  T-2416 (parsing call-site wiring), T-2509, T-2510 (countdown verification),
                 T-2301–T-2309 (E-23 visual QA),
                 T-2607–T-2610 (trigger-word reliability + privacy + battery)
           Joint: T-2417, T-2418, T-2419 (parsing privacy / latency / accuracy verification)
```

---

## Task Summary

| Epic | Tasks | Notes |
|---|---|---|
| E-20 Fixed App Background | 8 | Supersedes v1.0 T-1001 |
| E-21 Dark Liquid Glass Button System | 11 | Includes T-2100 compile-blocker prerequisite. T-2105 and T-2106 are retired (do not reuse) — superseded by E-25 fresh-build of the cancel control. Supersedes v1.0 T-1104 (Yes button removed entirely), T-1105 (No button rendering replaced by countdown). |
| E-22 Dark-Mode-Only Visual Layer | 9 | Closes the sheet-presentation gap from v1.0 |
| E-23 v1.1 Visual QA & Regression Hardening | 9 | Depends on E-20, E-21, E-22, E-25, E-26 |
| E-24 Three-Tier Voice Command Parsing | 19 | Supersedes v1.0 T-1801–T-1810 (rendering). Existing `CommandParser` shipped under E-18 retained as Tier 3. |
| E-25 Auto-Execute Confirmation with Countdown Cancel | 10 | Supersedes v1.0 T-1104 (Yes button), T-1108 (haptic re-wired to countdown start), T-0805 (10 s timeout replaced by 3 s auto-execute). T-1109 `.success` haptic re-wired to auto-execute. |
| E-26 "Voxio" Trigger Word | 10 | Supersedes v1.0 T-0301, T-0302, T-0303. Default implementation uses `SFSpeechRecognizer` in continuous on-device mode; T-2603 investigates the iOS 26 keyword-spotting API per Q20. |
| **Total (v1.1 only)** | **76** | Cumulative project total: 179 (v1.0) + 76 = **255**. v1.0 task IDs T-1104, T-1105, T-1108, T-0805, T-0301, T-0302, T-0303, T-1801–T-1810 are superseded but remain in v1.0 history. |

> Note on the E-21 count: v1.1.2 reported 13 tasks for E-21 (including T-2105 and T-2106 for Yes/No button replacement). v1.1.3 retires T-2105 and T-2106 (the Yes button is deleted by E-25; the cancel control is built fresh against the countdown surface in T-2502). The remaining 11 E-21 tasks are T-2100, T-2101, T-2102, T-2103, T-2104, T-2107, T-2108, T-2109, T-2110, T-2111, T-2112.
