# Design Specification: Voxio Feature 3 UI (Onboarding, Settings, Help)
**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-04
**Platform:** iOS 26 (iPhone, portrait) — SwiftUI
**Design Language:** DarkGlass (dark Liquid Glass, warm-gold accent)
**References:** VoxioSpecification-1.3.md US-60–US-66 / E-38 / E-39 / E-40, design-spec-alias-management.md (format reference and CTA token decisions), CLAUDE.md (`BeoColor`, `Spacing`, `Radius`, `BeoAnimation`, `BeoType`, `DarkGlassButton`)

---

## Summary

Feature 3 introduces three screens that frame the rest of v1.3 for the user: an onboarding cover that teaches the trigger-word pattern on first launch (E-38), a Settings sheet that gathers every voice-model and personalisation control in one place (E-39), and a redesigned Help sheet that lists every supported command in both languages (E-40).

These screens are the *connective tissue* of the release. They contain almost no business logic of their own; instead they introduce, expose, and explain the work happening in E-33–E-37. The design therefore prioritises legibility, hierarchy, and unambiguous cause-and-effect over decoration. The DarkGlass aesthetic is preserved exactly as it appears elsewhere in the app — same backgrounds, same card surfaces, same gold accent — and no new design tokens are introduced.

The three screens share three structural ideas that recur throughout this document. First, **gold is rare**: it appears only on the onboarding "Get started" CTA, on active toggle thumbs (system iOS behaviour), and as an active-language indicator in Help. Everywhere else gold is absent. Second, **rows are quiet**: standard iOS list-row affordances (chevrons, toggles, large titles) are used unmodified — the design does not invent custom controls for things iOS already does well. Third, **dimming is functional, not decorative**: a row dims to 0.4 opacity *only* when the controlling toggle is off, and that dimming makes the row non-interactive. There is no other use of opacity changes on these screens.

---

## Visual Language

### Colour palette (existing tokens — do not redefine)

| Token | Usage on Feature 3 screens |
|---|---|
| `BeoColor.bg` (`BgPrimary`) | Sheet, cover, and list background fill across all three screens |
| `BeoColor.cardBg` (`CardSurface`) | Onboarding example-row card surface, Help section card surface |
| `BeoColor.cardBorder` (`CardBorder`) | 0.5 pt hairline around onboarding example card and Help section cards |
| `BeoColor.text` (`LabelPrimary`) | Primary text — onboarding headline, settings row labels, help phrases in the active language |
| `BeoColor.muted` (`LabelSecondary`) | Secondary text — onboarding body copy, settings section footers, help phrases in the inactive language, disclosure chevrons, "About" version string |
| `BeoColor.accent` (`Accent` / `#C8A97E`) | "Get started" CTA fill (with dark label per `design-spec-alias-management.md` §1.9), active-language indicator in Help, system `Toggle` tint, orb gradient stop where the orb is reused |
| `BeoColor.separator` (`BeoSeparator`) | List row separators inside the Settings list |

The "dark text on gold" rule for primary CTAs is inherited unchanged from `design-spec-alias-management.md` §1.9. White-on-gold is never used on these screens.

No new design tokens are introduced.

### Typography ramp (`BeoType`)

| Token | Usage on Feature 3 screens |
|---|---|
| `BeoType.speakerName` (34 pt semibold) | Onboarding headline, sheet large titles ("Settings", "Help") when the platform shows a large title |
| `BeoType.nowPlaying` (22 pt regular) | Onboarding sub-headline ("Just say the speaker's name"), Help section card titles |
| `BeoType.confirmation` (17 pt regular) | Onboarding example phrases (the *"Beolab, play"* lines), Help phrase rows in the active language |
| `BeoType.body` (15 pt regular) | Settings row labels, Settings row trailing values, Help phrase rows in the inactive language, "Get started" button label, About version string |
| `BeoType.caption` (12 pt medium) | Settings section header text (uppercased), Settings section footer/description text, Help action-name column header |

Dynamic Type is supported throughout via the `BeoType` tokens; no fixed-pixel font sizes are introduced.

### Spacing and radius

| Token | Usage |
|---|---|
| `Spacing.s4` | Vertical gap between EN/DA phrase pair in a Help row |
| `Spacing.s8` | Gap between toggle and its description text in Settings, gap between orb and headline in Onboarding |
| `Spacing.s12` | Vertical padding inside Settings rows, vertical gap between onboarding example rows |
| `Spacing.s16` | Horizontal padding on all three sheets, gap between onboarding body copy and example list |
| `Spacing.s20` | Gap between Settings sections, gap between onboarding example list and CTA |
| `Spacing.s24` | Vertical padding around the "Get started" CTA, vertical padding around Help section cards |

| Token | Usage |
|---|---|
| `Radius.card` (20 pt) | Onboarding example card container, Help section card container |
| `Radius.pill` (100 pt) | "Get started" CTA, Help language-toggle segmented control, Settings row trailing chevron hit-area is implicit (no special radius) |
| `Radius.sheet` (16 pt) | Settings sheet, Help sheet, Onboarding-as-sheet (US-66 re-show path) |

### Motion

All transitions use existing `BeoAnimation` tokens.

- Onboarding entrance: `BeoAnimation.spring` opacity-and-translate from below by 12 pt. **Reduce Motion:** replaced with `BeoAnimation.toast` opacity-only fade (no translate).
- Onboarding orb: reuses the existing home-screen orb; its idle pulse animation is unchanged. Suspended on Reduce Motion (static gradient).
- Settings sheet: iOS-standard `.sheet` slide. Toggle row dimming on/off cross-fades over 200 ms with `BeoAnimation.toast`.
- Help sheet: iOS-standard `.sheet` slide. Language-toggle switch cross-fades the two phrase columns with `BeoAnimation.toast`.

---

## Screen Index

| § | Screen | Presentation | Purpose |
|---|---|---|---|
| 1 | Onboarding | `.fullScreenCover` on first launch; `.sheet` from Settings (US-66) | Introduce app concept, trigger-word pattern, and starter examples |
| 2 | Settings | `.sheet` from `gear` toolbar button | Hub for voice-model, personalisation, language, help, and about |
| 3 | Help | `.sheet` from `questionmark.circle` toolbar button or Settings > Help | Reference of all supported commands, EN + DA |

---

## Section 1 — Onboarding screen

### 1.1 Purpose

A first-time user must, in under 30 seconds of looking at this screen, understand three things: (1) Voxio controls B&O speakers by listening to the microphone, (2) every command starts with the speaker's name, and (3) here are some real example phrases to copy. The screen does not teach the *whole* command vocabulary — that is what Help is for. It teaches the *shape* of a command.

The screen is shown twice in two different presentations. On first launch it is a `.fullScreenCover` with no swipe-to-dismiss — the user must tap "Get started" to leave. From Settings (US-66) it is a `.sheet` that *is* swipe-dismissible; the content is identical, only the presentation differs.

### 1.2 Layout (top to bottom, with content)

```
┌──────────────────────────────────────────┐
│                                          │
│                                          │
│              ┌──────────┐                │
│              │          │                │  ← Orb graphic (reused from home)
│              │    ◉     │                │     96 pt diameter
│              │          │                │
│              └──────────┘                │
│                                          │
│            Welcome to Voxio              │  ← Headline (BeoType.speakerName)
│                                          │
│       Just say the speaker's name.       │  ← Sub-headline (BeoType.nowPlaying)
│                                          │
│   Voxio listens through your microphone  │  ← Body copy (BeoType.body, muted)
│   and controls Bang & Olufsen speakers   │
│   on your network.                       │
│                                          │
│   Try saying:                            │  ← Examples lead-in (BeoType.caption)
│   ┌────────────────────────────────────┐ │
│   │  "Beolab, play"                    │ │
│   ├────────────────────────────────────┤ │  ← Example card (Radius.card,
│   │  "Beolab, volume up"               │ │     BeoColor.cardBg)
│   ├────────────────────────────────────┤ │
│   │  "Beolab, stop"                    │ │
│   └────────────────────────────────────┘ │
│                                          │
│         ┌────────────────────┐           │
│         │    Get started     │           │  ← Primary CTA (gold, dark label)
│         └────────────────────┘           │
│                                          │
└──────────────────────────────────────────┘
```

### 1.3 Background

Full-screen `BeoColor.bg` fill. No imagery, no gradient, no pattern. The orb graphic provides the only colour interest above the fold.

The cover variant (first launch) extends content edge-to-edge with no chrome — there is no nav bar, no close button, no swipe indicator. The sheet variant (US-66 re-show) shows the iOS-default sheet grabber at the top and is swipe-dismissible.

### 1.4 Orb graphic

Reuses the existing home-screen orb component as-is. The orb is the visual signature of the app, and seeing it on first launch creates continuity with the main UI the user is about to enter.

| Property | Value |
|---|---|
| Diameter | 96 pt |
| Position | Vertically anchored to ~20% from the top of the safe area; horizontally centred |
| State | Idle pulse animation (the orb's default state when not actively listening) |
| Accessibility | `accessibilityHidden(true)` — decorative; the headline carries the meaning |
| Reduce Motion | Static gradient, no pulse |

If the orb component cannot be reused without a discovered speaker context (the home orb depends on `Speaker` state), substitute a static rendering: `Circle()` filled with a radial gradient from `BeoColor.accent` at 80% to `BeoColor.accent` at 20%, framed by a 0.5 pt `BeoColor.cardBorder` stroke. The static rendering is the Reduce-Motion fallback regardless.

### 1.5 Headline and sub-headline

| Element | Style | Text (EN) | Text (DA) |
|---|---|---|---|
| Headline | `BeoType.speakerName`, `BeoColor.text`, centred | "Welcome to Voxio" | "Velkommen til Voxio" |
| Sub-headline | `BeoType.nowPlaying`, `BeoColor.text`, centred | "Just say the speaker's name." | "Sig bare højttalerens navn." |

`Spacing.s8` between orb and headline. `Spacing.s12` between headline and sub-headline.

### 1.6 Body copy

| Property | Value |
|---|---|
| Style | `BeoType.body`, `BeoColor.muted`, centred |
| Max width | 320 pt — keeps line length readable on iPhone 16 Pro Max and avoids awkward 4-line wrapping |
| Top padding | `Spacing.s16` from sub-headline |
| Text (EN) | "Voxio listens through your microphone and controls Bang & Olufsen speakers on your network." |
| Text (DA) | "Voxio lytter gennem mikrofonen og styrer Bang & Olufsen-højttalere på dit netværk." |

The body copy intentionally names the microphone explicitly. The user is about to be asked for microphone permission on dismiss; flagging it here removes any surprise.

### 1.7 Examples lead-in

A single line of text immediately above the example card, prefacing the list.

| Property | Value |
|---|---|
| Style | `BeoType.caption`, `BeoColor.muted`, centred |
| Top padding | `Spacing.s20` from body copy |
| Bottom padding | `Spacing.s12` to example card |
| Text (EN) | "Try saying:" |
| Text (DA) | "Prøv at sige:" |

### 1.8 Example card

A single rounded card containing three example phrase rows separated by hairline dividers. Phrases use the placeholder name "Beolab" — chosen because it is short, recognisable, and matches the most common B&O speaker family name.

| Property | Value |
|---|---|
| Container | `BeoColor.cardBg` fill, `BeoColor.cardBorder` 0.5 pt stroke, `Radius.card` |
| Container width | Full width inside `Spacing.s16` horizontal margin from the screen edges |
| Row height | 48 pt (above the 44 pt minimum; rows are not interactive but the spacing reads as intentional) |
| Row separator | `BeoColor.separator` hairline, full-width inside the card |
| Row padding | `Spacing.s16` horizontal, `Spacing.s12` vertical |
| Row content | Single line per row, `BeoType.confirmation`, `BeoColor.text`, leading-aligned |
| Quote treatment | The phrase text is wrapped in U+201C / U+201D curly quotes — *"Beolab, play"* not "Beolab, play" — to read as a quoted utterance |

**Three rows (EN):**
- *"Beolab, play"*
- *"Beolab, volume up"*
- *"Beolab, stop"*

**Three rows (DA):**
- *"Beolab, afspil"*
- *"Beolab, skru op"*
- *"Beolab, stop"*

Rows are not interactive. `accessibilityElement(children: .combine)` on the card so VoiceOver announces the three examples as one block: "Examples: Beolab play. Beolab volume up. Beolab stop."

### 1.9 Get started button

The single CTA on the screen.

| Property | Value |
|---|---|
| Style | Primary CTA per `design-spec-alias-management.md` §1.9 — `BeoColor.accent` fill at 100%, `BeoColor.text` (dark) label, no border |
| Font | `BeoType.body` semibold |
| Corner radius | `Radius.pill` |
| Padding | 14 pt vertical, 24 pt horizontal |
| Min size | 44 pt tall × 220 pt wide |
| Position | Centred horizontally; pinned to bottom safe area with `Spacing.s24` bottom padding |
| Pressed state | `pressedScale` 0.95 (`DarkGlassButtonTokens`); disabled on Reduce Motion |
| Label (EN) | "Get started" |
| Label (DA) | "Kom i gang" |

**Tap action — first-launch cover:**
1. Set `@AppStorage("hasCompletedOnboarding") = true`.
2. Trigger microphone permission request if not yet determined (`AVAudioApplication.requestRecordPermission`).
3. Trigger speech recognition permission request if not yet determined (`SFSpeechRecognizer.requestAuthorization`).
4. Dismiss the cover. The home view appears underneath as the next surface.

Permission denials are handled by the home view's existing flow — onboarding does not show a denied state itself.

**Tap action — sheet (US-66 re-show):**
1. Dismiss the sheet.
2. Do **not** modify `hasCompletedOnboarding`.
3. Do **not** re-trigger permission requests.

### 1.10 Visual hierarchy summary

Reading top to bottom, the user sees: a familiar circular gold-tinted graphic (the orb), then a welcome line (proper noun), then the *one rule* of the app (sub-headline), then the why (body), then the *how* (three quoted examples), then the CTA. Each element is visually quieter than the one above it except for the CTA at the bottom — which is the only gold fill on the page and therefore the obvious action.

### 1.11 Reduce Motion behaviour

| Behaviour | Default | Reduce Motion |
|---|---|---|
| Cover entrance | `BeoAnimation.spring` translate-from-below + opacity | `BeoAnimation.toast` opacity-only fade |
| Orb pulse | Continuous | Static gradient |
| CTA press | Scale to 0.95 | Opacity dip to 0.7 |
| Sheet entrance (US-66) | iOS-standard sheet slide | iOS handles Reduce Motion automatically |

---

## Section 2 — Settings sheet

### 2.1 Purpose

The Settings sheet is the integration screen for v1.3. Every user-facing toggle and navigation row introduced by Features 1, 2, and 3 lives here. The screen is intentionally familiar — it uses iOS-standard `List` chrome, standard `Toggle` controls, and standard disclosure rows. There is no custom layout. A user who has used any iOS Settings-style screen knows how to use this one without being taught.

The sheet is opened from a `gear` icon in the `HomeView` toolbar (E-39 T-3902), and is *suppressed* during an active voice-command countdown (the gear is disabled while `coordinator.isPending == true`).

### 2.2 Layout (top to bottom, with content)

```
┌──────────────────────────────────────────┐
│  ╳                Settings               │  ← Sheet header
├──────────────────────────────────────────┤
│                                          │
│  VOICE MODEL                             │  ← Section header (caption, muted)
│  ┌────────────────────────────────────┐  │
│  │ Help improve voice control     ⚪  │  │  ← Toggle row
│  ├────────────────────────────────────┤  │
│  │ Shared data                    ›   │  │  ← Nav row
│  └────────────────────────────────────┘  │
│   Anonymised parses are uploaded to      │  ← Section footer (caption, muted)
│   help train future voice models. No     │
│   audio, no favourite or speaker names.  │
│                                          │
│  PERSONALISATION                         │
│  ┌────────────────────────────────────┐  │
│  │ Personalise voice control      ⚫  │  │
│  ├────────────────────────────────────┤  │
│  │ Aliases                        ›   │  │
│  ├────────────────────────────────────┤  │
│  │ Learned phrases                ›   │  │
│  └────────────────────────────────────┘  │
│   Aliases and learned phrases stay on    │
│   this device.                           │
│                                          │
│  LANGUAGE                                │
│  ┌────────────────────────────────────┐  │
│  │ Language               English  ›  │  │  ← Value row
│  └────────────────────────────────────┘  │
│                                          │
│  HELP & ABOUT                            │
│  ┌────────────────────────────────────┐  │
│  │ Help                           ›   │  │
│  ├────────────────────────────────────┤  │
│  │ Show introduction again        ›   │  │
│  ├────────────────────────────────────┤  │
│  │ About                  1.3.0  ›    │  │
│  └────────────────────────────────────┘  │
│                                          │
└──────────────────────────────────────────┘
```

### 2.3 Sheet container

| Property | Value |
|---|---|
| Presentation | iOS standard `.sheet` modal — `.large` detent only (full-height); no `.medium` |
| Corner radius | `Radius.sheet` (16 pt) — automatic from iOS sheet styling |
| Background | `BeoColor.bg` |
| Drag indicator | iOS default grabber, visible at the top |
| Dismiss | Swipe down OR close button in the sheet header |
| Suppression | The gear toolbar button is `.disabled(coordinator.isPending)`; if the sheet is somehow presented during a pending countdown, it dismisses itself and the countdown continues uninterrupted |

### 2.4 Sheet header

A 56 pt tall header strip pinned to the top of the sheet content, separated from the body by a `BeoColor.separator` hairline.

| Element | Detail |
|---|---|
| Leading button | `xmark` SF Symbol, 22 pt, `BeoColor.accent`, 44 × 44 pt hit area. Tap dismisses the sheet. VoiceOver label: "Close settings". |
| Title | "Settings" / "Indstillinger" — `BeoType.speakerName` shrunk to fit (22 pt sheet-title style); centred |
| Trailing button | None |

### 2.5 List style and section chrome

The body of the sheet uses SwiftUI's `List` with `.listStyle(.insetGrouped)` re-tinted for DarkGlass.

| Property | Value |
|---|---|
| List background | `BeoColor.bg` |
| Section card background | `BeoColor.cardBg` |
| Section card border | None (the inset-grouped style uses internal corner radii, not a stroke); `BeoColor.cardBorder` 0.5 pt stroke is added via `.listRowBackground` if the system style does not produce a sufficient hairline against `BeoColor.bg` |
| Section corner radius | `Radius.card` (20 pt) |
| Section horizontal margin | `Spacing.s16` from screen edges |
| Section header style | `BeoType.caption` uppercased, `BeoColor.muted`, leading-aligned, 16 pt leading padding, `Spacing.s8` bottom padding |
| Section footer style | `BeoType.caption`, `BeoColor.muted`, leading-aligned, 16 pt leading padding, `Spacing.s8` top padding |
| Row separator | `BeoColor.separator` hairline, 16 pt leading inset, between rows within the same section |
| Row min height | 56 pt (above 44 pt minimum, accommodates two-line subtitle in toggle rows) |
| Row horizontal padding | `Spacing.s16` leading and trailing |

### 2.6 Section 1 — Voice model

Two rows. Section footer reproduces the privacy summary from US-53 in plain language.

#### 2.6.1 "Help improve voice control" toggle row

| Property | Value |
|---|---|
| Row label | "Help improve voice control" / "Hjælp med at forbedre stemmestyring" |
| Label style | `BeoType.body`, `BeoColor.text` |
| Trailing control | iOS-standard `Toggle` with `.tint(BeoColor.accent)` |
| Default state | Off (per US-53 / E-35 T-3506 — opt-in by default) |
| Wired to | `TelemetryUploader.isEnabled` (T-3506) |
| Row min height | 56 pt |

The full description from US-62 lives in the section footer (see §2.6.3), not as a subtitle on the row — keeping the row compact preserves the visual rhythm of the list.

#### 2.6.2 "Shared data" navigation row

| Property | Value |
|---|---|
| Row label | "Shared data" / "Delte data" |
| Trailing | `chevron.right` 12 pt, `BeoColor.muted` |
| Tap action | Pushes the Shared Data screen (US-55 / E-36) onto the sheet's navigation stack |
| Wired to | E-36 view |

#### 2.6.3 Section footer (description)

| Property | Value |
|---|---|
| Style | `BeoType.caption`, `BeoColor.muted` |
| Text (EN) | "Anonymised parses are uploaded to help train future voice models. No audio, no favourite or speaker names." |
| Text (DA) | "Anonymiserede kommandoer uploades for at hjælpe med at træne fremtidige stemmemodeller. Ingen lyd, ingen favorit- eller højttalernavne." |

### 2.7 Section 2 — Personalisation

Three rows. The first row controls the visibility of the next two.

#### 2.7.1 "Personalise voice control" toggle row

| Property | Value |
|---|---|
| Row label | "Personalise voice control" / "Personalisér stemmestyring" |
| Trailing control | iOS-standard `Toggle` with `.tint(BeoColor.accent)` |
| Default state | On (per US-52 / E-34 T-3404) |
| Wired to | `PersonalisationStore.isEnabled` (T-3404) |

#### 2.7.2 "Aliases" navigation row

| Property | Value |
|---|---|
| Row label | "Aliases" / "Aliasser" |
| Trailing | `chevron.right` 12 pt, `BeoColor.muted` |
| Tap action | Pushes the Alias List screen (`design-spec-alias-management.md` §1) onto the sheet's navigation stack |
| Dimming | When the personalisation toggle is off, the row dims to 0.4 opacity and `.allowsHitTesting(false)`. The chevron, label, and full row contents are dimmed together. |

#### 2.7.3 "Learned phrases" navigation row

| Property | Value |
|---|---|
| Row label | "Learned phrases" / "Lærte sætninger" |
| Trailing | `chevron.right` 12 pt, `BeoColor.muted` |
| Tap action | Pushes the Learned Phrases screen (US-51 / E-34 T-3403) |
| Dimming | Same rule as Aliases row: 0.4 opacity, hit-testing disabled, when toggle is off |

#### 2.7.4 Dimming behaviour

The dimming on the two child rows responds *immediately* to the toggle state — there is no delay, no confirmation. Cross-fade duration is 200 ms (`BeoAnimation.toast`). Disabling Reduce Motion replaces the cross-fade with an instant swap.

When dimmed, VoiceOver announces the row as "Aliases, dimmed, off". The row remains in the accessibility tree but is announced as inactive.

#### 2.7.5 Section footer

| Property | Value |
|---|---|
| Style | `BeoType.caption`, `BeoColor.muted` |
| Text (EN) | "Aliases and learned phrases stay on this device." |
| Text (DA) | "Aliasser og lærte sætninger forbliver på denne enhed." |

### 2.8 Section 3 — Language

A single value row.

| Property | Value |
|---|---|
| Row label | "Language" / "Sprog" |
| Trailing value | Current language label as a localised string: "English" or "Dansk". Style: `BeoType.body`, `BeoColor.muted`. |
| Trailing icon | `chevron.right` 12 pt, `BeoColor.muted`, with `Spacing.s8` between the value text and the chevron |
| Tap action | Presents the existing `LanguagePickerSheet` over the current sheet (sheet-on-sheet — iOS handles the layering) |
| Wired to | E-39 T-3905 |

The language value is *not* localised inside its own translation — Danish users see "Dansk" as the value when Danish is selected, English users see "English". This matches the `LanguagePickerSheet` convention and avoids the awkward "Danish" / "English" strings in the language someone has just decided they cannot read.

No section footer.

### 2.9 Section 4 — Help & About

Three rows.

#### 2.9.1 "Help" navigation row

| Property | Value |
|---|---|
| Row label | "Help" / "Hjælp" |
| Trailing | `chevron.right` 12 pt, `BeoColor.muted` |
| Tap action | Presents the `HelpView` as a sheet over the Settings sheet |
| Wired to | E-40 / E-39 T-3906 |

#### 2.9.2 "Show introduction again" navigation row

| Property | Value |
|---|---|
| Row label | "Show introduction again" / "Vis introduktion igen" |
| Trailing | `chevron.right` 12 pt, `BeoColor.muted` |
| Tap action | Presents the `OnboardingView` as a sheet (US-66) over the Settings sheet. Does **not** modify `hasCompletedOnboarding`. |
| Wired to | E-38 T-3805 / E-39 T-3906 |

#### 2.9.3 "About" row

| Property | Value |
|---|---|
| Row label | "About" / "Om" |
| Trailing value | App version + build number, e.g. "1.3.0 (412)". Style: `BeoType.body`, `BeoColor.muted`. |
| Trailing icon | `chevron.right` 12 pt, `BeoColor.muted` |
| Tap action | v1.3: tap is a no-op (the version is shown inline); a future version may push a credits / acknowledgements screen. The chevron is shown for visual consistency with the other rows but the row is `.disabled(true)` if no destination exists. |

If the chevron-on-disabled-row reads as broken, an alternative is to omit the chevron and the tap target entirely — leaving "About 1.3.0 (412)" as a plain value-display row. **Flagged as Open Question 1.**

### 2.10 Toolbar gear button (HomeView)

Although strictly a `HomeView` concern, the toolbar button is the entry point for this screen and is specified here for completeness.

| Property | Value |
|---|---|
| Symbol | `gear` SF Symbol, 22 pt |
| Tint | `BeoColor.text` at rest, `BeoColor.muted` when disabled |
| Hit area | 44 × 44 pt |
| Position | Trailing toolbar position, alongside the existing language and help buttons. Order, leading to trailing: language, help, gear. |
| Disabled state | `.disabled(coordinator.isPending)` — gear is dimmed and unresponsive during an active voice-command countdown |
| VoiceOver label | "Settings" / "Indstillinger" |
| VoiceOver hint | "Opens settings" / "Åbner indstillinger" |

---

## Section 3 — Help screen

### 3.1 Purpose

A reference card for everything the voice parser understands. Unlike the v1.2 `HintCardView` (which showed a single tip), `HelpView` is a complete enumeration of all supported commands across the three command categories defined in v1.3 — single-speaker, grouping, and system/broadcast — in both English and Danish.

The screen is reachable from two places: the existing `questionmark.circle` toolbar button in `HomeView` (rewired in E-40 T-4006) and the "Help" row in Settings (E-39 T-3906). Both entry points open the same sheet.

### 3.2 Layout (top to bottom, with content)

```
┌──────────────────────────────────────────┐
│  ╳         Help          [EN ▸ DA]       │  ← Sheet header + language toggle
├──────────────────────────────────────────┤
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ Single speaker                     │  │  ← Section card title
│  │                                    │  │
│  │ Play          [Beolab], play       │  │  ← Action label | active phrase
│  │               [Beolab], afspil     │  │     inactive phrase (muted)
│  │ ────────────────────────────────── │  │
│  │ Pause         [Beolab], pause      │  │
│  │               [Beolab], pause      │  │
│  │ ────────────────────────────────── │  │
│  │ Stop          [Beolab], stop       │  │
│  │               [Beolab], stop       │  │
│  │ ... (12 rows total)                │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ Grouping                           │  │
│  │                                    │  │
│  │ Join          [Beolab], join       │  │
│  │               [Beosound]           │  │
│  │               [Beolab], tilslut    │  │
│  │               [Beosound]           │  │
│  │ ────────────────────────────────── │  │
│  │ Leave group   [Beolab], leave the  │  │
│  │               group                │  │
│  │               [Beolab], forlad     │  │
│  │               gruppen              │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ All speakers                       │  │
│  │                                    │  │
│  │ Stop all      stop everything      │  │
│  │               stop alt             │  │
│  │ ... (7 rows total)                 │  │
│  └────────────────────────────────────┘  │
│                                          │
└──────────────────────────────────────────┘
```

### 3.3 Sheet container

| Property | Value |
|---|---|
| Presentation | iOS standard `.sheet` modal — `.large` detent only |
| Corner radius | `Radius.sheet` (16 pt) |
| Background | `BeoColor.bg` |
| Drag indicator | iOS default grabber, visible at the top |
| Dismiss | Swipe down OR close button in the sheet header |
| Body wrapping | Vertical `ScrollView` containing the three section cards stacked vertically with `Spacing.s24` between them |

### 3.4 Sheet header

A 56 pt tall header strip pinned to the top of the sheet content, separated from the body by a `BeoColor.separator` hairline.

| Element | Detail |
|---|---|
| Leading button | `xmark` SF Symbol, 22 pt, `BeoColor.accent`, 44 × 44 pt hit area. Tap dismisses the sheet. VoiceOver label: "Close help". |
| Title | "Help" / "Hjælp" — `BeoType.speakerName` shrunk to fit (22 pt sheet-title style); centred |
| Trailing | Language toggle (see §3.5) |

### 3.5 Language toggle

A small two-segment pill control showing the active language in `BeoColor.accent` and the inactive language in `BeoColor.muted`. Tapping the inactive segment swaps which language is rendered prominently in the rows.

| Property | Value |
|---|---|
| Container | iOS-standard `Picker` styled `.segmented`, 88 pt wide |
| Corner radius | `Radius.pill` |
| Segments | "EN" and "DA" — fixed two-letter codes; not localised |
| Active segment | `BeoColor.accent` background, `BeoColor.text` (dark) label, `BeoType.caption` semibold |
| Inactive segment | Transparent background, `BeoColor.muted` label, `BeoType.caption` regular |
| Default state | The app's current recognition language; reads from the same source the `LanguagePickerSheet` writes to |
| Persistence | Per-session — flipping the toggle in Help does **not** change the recognition language. It only changes which column is rendered prominently on the Help screen. The current recognition language is restored as the active toggle state on next sheet open. |
| Tap action | Cross-fades the two language columns within each row using `BeoAnimation.toast` (200 ms). On Reduce Motion: instant swap. |
| Position | Trailing edge of sheet header, with `Spacing.s16` from the right edge |
| VoiceOver | "Help language. English. Selected. / Danish. Double-tap to switch." (and reverse) |

The toggle is intentionally session-only — a user reading help in English to learn what to say in Danish does not want to flip their recognition language back and forth.

**Speaker-name placeholder substitution is independent of the language toggle.** If a real speaker has been discovered, `[Speaker]` is replaced with that speaker's name in *both* language columns regardless of which is active.

### 3.6 Section card

The three sections are rendered as three independent cards. Each card is self-contained and uses the same chrome.

| Property | Value |
|---|---|
| Container | `BeoColor.cardBg` fill, `BeoColor.cardBorder` 0.5 pt stroke, `Radius.card` |
| Container width | Full width inside `Spacing.s16` horizontal margin |
| Internal padding | `Spacing.s16` horizontal, `Spacing.s16` top, `Spacing.s12` bottom |
| Title | `BeoType.nowPlaying`, `BeoColor.text`, leading-aligned, `Spacing.s12` bottom padding |
| Row separator | `BeoColor.separator` hairline between rows, 0 pt leading inset (full row width) |
| Vertical gap between cards | `Spacing.s24` |

**The three sections:**

| Section | Title (EN) | Title (DA) | Row count |
|---|---|---|---|
| 1 | "Single speaker" | "Enkelt højttaler" | 12 |
| 2 | "Grouping" | "Gruppering" | 2 |
| 3 | "All speakers" | "Alle højttalere" | 7 |

Phrase content for all rows is taken verbatim from the US-65 tables in `VoxioSpecification-1.3.md` and is **not** duplicated here. The design spec specifies layout; the source spec specifies content.

### 3.7 Phrase row layout

Each row is a two-column layout: an action label on the left, and a stacked pair of phrases on the right (active language above, inactive language below).

```
┌──────────────────────────────────────────────────────┐
│  Volume up        [Beolab], volume up                │  ← Active phrase (BeoType.confirmation)
│                   [Beolab], skru op                  │  ← Inactive phrase (BeoType.body, muted)
└──────────────────────────────────────────────────────┘
```

| Property | Value |
|---|---|
| Row min height | 56 pt (44 pt minimum + content) |
| Vertical padding | `Spacing.s12` top and bottom |
| Action label column | Fixed width 110 pt; `BeoType.caption`, `BeoColor.muted`, top-aligned to first line |
| Phrase column | Flexible width filling remaining space |
| Active phrase | `BeoType.confirmation`, `BeoColor.text`, leading-aligned, single line preferred (wraps to 2 lines if needed) |
| Inactive phrase | `BeoType.body`, `BeoColor.muted`, leading-aligned, single line preferred |
| Vertical gap inside phrase column | `Spacing.s4` between active and inactive phrase |
| Quote treatment | Phrases are *italicised* (matching the `*[Speaker], play*` markdown convention in the source spec) but are **not** wrapped in quote marks — they are reference text, not quoted speech |

The action label uses `BeoType.caption` (12 pt) so the phrases visually dominate. The action label is the *index* into the table; the phrases are the *content*.

### 3.7.1 Speaker name substitution

Per US-65 acceptance criteria:

| Placeholder | Substitution rule | Fallback |
|---|---|---|
| `[Speaker]` | First discovered speaker name from `MdnsDiscovery.speakers` sorted by discovery time | Literal text "[Speaker]" rendered in italic with no substitution |
| `[Speaker A]` | First discovered speaker name | Literal "[Speaker A]" |
| `[Speaker B]` | Second discovered speaker name | Literal "[Speaker B]" |

Substitution is computed at sheet-open time and remains stable for the duration the sheet is open — a speaker discovered or lost mid-view does not cause the rows to re-render. Re-opening the sheet picks up the latest list.

When the placeholder text is rendered as a fallback, the literal "[Speaker]" string remains italicised but is *not* localised — the placeholder reads identically in both columns. The substituted speaker name is shown unitalicised, in the same `BeoType.confirmation` style as the surrounding phrase, to read as a real speaker reference.

### 3.7.2 Action label content

Action labels are short (one or two words). The active language column (currently selected via §3.5) is the canonical source. The full action labels are listed below for reference; phrases come from the US-65 tables.

**Section 1 — Single speaker:**

| Action (EN) | Action (DA) |
|---|---|
| Play | Afspil |
| Pause | Pause |
| Stop | Stop |
| Resume | Fortsæt |
| Volume | Lydstyrke |
| Volume up | Skru op |
| Volume up by | Skru op med |
| Volume down | Skru ned |
| Mute | Tavs |
| Unmute | Lyd til |
| Play favourite | Afspil favorit |
| List favourites | Vis favoritter |

**Section 2 — Grouping:**

| Action (EN) | Action (DA) |
|---|---|
| Join | Tilslut |
| Leave group | Forlad gruppe |

**Section 3 — All speakers:**

| Action (EN) | Action (DA) |
|---|---|
| Stop all | Stop alle |
| Pause all | Pause alle |
| Resume all | Genoptag alle |
| Volume down all | Skru ned alle |
| Volume up all | Skru op alle |
| Mute all | Mute alle |
| Unmute all | Unmute alle |

Action labels in the inactive language are **not** rendered — the action-label column shows only the active language. Only the phrase column shows both languages. This is intentional: the action label is a navigational aid for the user reading help in their preferred language; the phrase column is the reference content where bilingual context matters.

### 3.8 Toolbar `questionmark.circle` button (HomeView)

Specified for completeness. The button itself already exists in `HomeView` and is rewired in E-40 T-4006 to present `HelpView` instead of `HintCardView`.

| Property | Value |
|---|---|
| Symbol | `questionmark.circle` SF Symbol, 22 pt |
| Tint | `BeoColor.text` |
| Hit area | 44 × 44 pt |
| Position | Trailing toolbar position, between the language and gear buttons |
| VoiceOver label | "Help" / "Hjælp" |

---

## Section 4 — Accessibility

### 4.1 Tap targets

| Element | Size |
|---|---|
| Onboarding "Get started" CTA | 44 pt tall × 220 pt wide |
| Settings sheet close button | 44 × 44 pt around 22 pt symbol |
| Settings list row | 56 pt tall, full row width |
| Settings `Toggle` | iOS-default — 51 × 31 pt thumb in a 44 pt-tall row |
| Help sheet close button | 44 × 44 pt |
| Help language toggle segment | At least 44 × 44 pt; the 88 pt-wide control accommodates this with a slight reduction in height — verify on device |
| Help phrase row | 56 pt tall — non-interactive but VoiceOver-readable |
| Toolbar buttons (gear, help, language) | 44 × 44 pt each |

### 4.2 VoiceOver labels

| Element | Label |
|---|---|
| Onboarding orb | (decorative — `accessibilityHidden(true)`) |
| Onboarding example card | `accessibilityElement(children: .combine)` — "Examples: Beolab, play. Beolab, volume up. Beolab, stop." |
| "Get started" CTA | "Get started. Closes onboarding and opens the main screen." |
| Settings close button | "Close settings" / "Luk indstillinger" |
| Settings toggle row | "Help improve voice control. Off. Switch button. Double-tap to toggle." (matches iOS default `Toggle` announcement; do not override) |
| Settings dimmed row (Aliases, when off) | "Aliases. Dimmed. Disable personalisation to enable." |
| Settings nav row | "Aliases. Button. Double-tap to open." |
| Settings language row | "Language. English. Button. Double-tap to change." |
| Settings About row | "About. Version 1.3.0 build 412." (no action announcement if the row is disabled) |
| Help close button | "Close help" / "Luk hjælp" |
| Help language toggle | "Help language. English. Selected. / Danish. Double-tap to switch." |
| Help phrase row | "Volume up. Active phrase: Beolab, volume up. Other language: Beolab, skru op." (combined element) |
| Toolbar gear (enabled) | "Settings" |
| Toolbar gear (disabled during countdown) | "Settings. Dimmed. Voice command in progress." |

### 4.3 Focus management

- On Onboarding cover open: focus moves to the headline. VoiceOver announces "Welcome to Voxio. Heading."
- On Onboarding sheet open (US-66 re-show): focus moves to the sheet grabber, then announces the headline on next swipe.
- On "Get started" tap: focus moves to the home view's main control (handled by `HomeView`).
- On Settings sheet open: focus moves to the sheet title "Settings".
- On Settings personalisation toggle change: focus stays on the toggle; the dimmed/undimmed state of the next two rows is announced as a state change.
- On Settings nav row tap: focus moves to the destination screen's title.
- On Help sheet open: focus moves to the sheet title "Help".
- On Help language toggle change: focus stays on the toggle; the rows below re-render with the new active language.

### 4.4 Reduce Motion

| Behaviour | Default | Reduce Motion |
|---|---|---|
| Onboarding cover entrance | Spring translate-from-below + fade | Opacity-only fade |
| Onboarding orb | Idle pulse animation | Static gradient |
| "Get started" press | Scale 0.95 | Opacity 0.7 |
| Settings sheet entrance | iOS-default sheet slide | iOS handles automatically |
| Settings dim/undim | 200 ms cross-fade | Instant swap |
| Help sheet entrance | iOS-default sheet slide | iOS handles automatically |
| Help language column swap | 200 ms cross-fade | Instant swap |

### 4.5 Dynamic Type

All text uses `BeoType` tokens which support Dynamic Type via `Font.system`. Layout consequences at the largest accessibility sizes (`accessibility4` / `accessibility5`):

- **Onboarding example rows** may grow to two lines per phrase. The card height adapts; spacing tokens remain.
- **Settings rows** may exceed 56 pt for toggles whose label wraps. Trailing controls remain right-aligned and vertically centred.
- **Help phrase rows** may grow significantly — both phrases may wrap to two or three lines each. The action-label column maintains its 110 pt width; consider increasing it to 130 pt if action labels themselves wrap awkwardly. **Flagged as Open Question 4.**
- **Help language toggle** segment text remains "EN" / "DA" — short enough to never wrap.

### 4.6 Colour contrast

| Combination | Ratio | Compliant |
|---|---|---|
| `BeoColor.text` on `BeoColor.bg` | 16.1:1 (estimated) | AAA |
| `BeoColor.muted` on `BeoColor.bg` | 4.7:1 (estimated) | AA |
| `BeoColor.muted` on `BeoColor.cardBg` | 4.5:1 (estimated) | AA — borderline; verify on device |
| `BeoColor.text` (dark) on `BeoColor.accent` (gold) | 6.0:1 | AA — used on "Get started" CTA and Help language-toggle active segment |
| `BeoColor.text` on `BeoColor.cardBg` (dimmed row at 0.4 opacity) | ~6.4:1 (16.1 × 0.4) | AA — passes; dimming is an *intent* signal, not a contrast requirement |

The "dimmed row passes AA" calculation is approximate — at 40% opacity over the card background, the effective contrast ratio is high enough to remain readable, but the row is *also* `.allowsHitTesting(false)`, so legibility-as-affordance is intentionally muted. A user who can read the row cannot interact with it; this is the desired state.

---

## Section 5 — Out of Scope (v1.3)

- **Per-section search or filtering in Help.** With 21 total rows across three sections, scanning is fast enough without search.
- **Tap-to-copy on a Help phrase row.** Useful but adds an interaction model the rest of the screen does not have. Defer.
- **Tap-to-test on a Help phrase row** ("Try this command now"). Same reason — adds a parse-pipeline dependency to a help screen. Defer.
- **Animated illustration in Onboarding.** A short Lottie or video could explain the trigger-word pattern visually; out of scope for v1.3 as it adds an asset pipeline dependency. Static orb + text is sufficient.
- **Multi-step Onboarding wizard.** Explicitly excluded by VoxioSpecification-1.3.md "Out of Scope (v1.3 initial)".
- **Settings search.** Settings has 9 rows total — search is unwarranted.
- **Inline credits / acknowledgements screen** behind the About row. v1.3 shows only the version inline.
- **Per-speaker substitution in Help Section 2** when fewer than two speakers are discovered. Fallback to literal `[Speaker A]` / `[Speaker B]`.

---

## Section 6 — UX/UI Issues and Open Questions

### Issue 1 — About row chevron when tap is a no-op

**Description:** §2.9.3 specifies a chevron on the About row even though tapping it does nothing in v1.3. A chevron-on-disabled-row is a known iOS convention violation — it suggests an action that does not exist.

**Recommendation:** Remove the chevron from the About row. Render it as a plain value-display row: "About 1.3.0 (412)" with no trailing affordance. If a future version adds a credits screen, re-add the chevron at that time.

**Decision needed from:** Designer + iOS engineer.

### Issue 2 — Onboarding orb dependency on `Speaker` state

**Description:** The home-screen orb is bound to `Speaker.playbackState` and other live state. Onboarding is shown before any speaker is discovered, so the orb has no live state to bind to. Reusing the component as-is may cause a bound-property crash or render an unintended idle state.

**Recommendation:** Render onboarding's orb as a standalone "static" mode of the orb component — same gradient, same diameter, but no state bindings. If the component cannot be cleanly decoupled, fall back to the simpler radial-gradient `Circle()` rendering described in §1.4.

**Decision needed from:** iOS engineer.

### Issue 3 — Help language toggle vs. recognition language source-of-truth

**Description:** §3.5 specifies that flipping the Help language toggle does *not* change the recognition language — it is a per-session display preference for Help only. A user might reasonably expect flipping it to change the app's actual language. The reverse (changing the app language while Help is open) should update the toggle's active state.

**Recommendation:** Add a one-line caption below the language toggle in the Help sheet header: "Display only. Change app language in Settings." (EN) / "Kun visning. Skift sprog i indstillinger." (DA). `BeoType.caption`, `BeoColor.muted`, max 2 lines. This makes the per-session scope explicit. Alternative: drop the per-session scope and have the toggle change the actual recognition language — simpler, but creates a path where a user's app language flips without their intent. Designer prefers the explicit caption.

**Decision needed from:** Designer + iOS engineer.

### Issue 4 — Help action-label column width at large Dynamic Type

**Description:** §4.5 flags that at `accessibility4` / `accessibility5`, action labels themselves may wrap awkwardly within the 110 pt column. "Volume up by" or "List favourites" (or DA "Genoptag alle") are already at the wrap boundary at default size.

**Recommendation:** At default size, 110 pt is correct. At `accessibility3` and above, switch to a stacked layout: action label on its own line above the phrase pair, full row width. This degrades the table-like scannability slightly but accepts the larger text.

**Decision needed from:** iOS engineer — verify the `.dynamicTypeSize` breakpoint handling.

### Issue 5 — Settings "Personalisation" toggle off + dimmed Aliases row VoiceOver behaviour

**Description:** §2.7.4 specifies that dimmed rows announce as "dimmed, off" via VoiceOver. iOS does not have a native "dimmed" announcement for SwiftUI `List` rows; this requires a manual `accessibilityValue("Dimmed.")` and `accessibilityHint`. A VoiceOver user trying to tap the row will get the announcement but no action — risking the impression of a bug.

**Recommendation:** Add the explicit accessibility hint "Disable personalisation to enable" on the dimmed rows so the user understands *why* the row is unresponsive. Additionally, ensure the Personalisation toggle row is announced as the *cause* — VoiceOver users navigating linearly will encounter it first.

**Decision needed from:** Accessibility reviewer.

### Issue 6 — First-launch permission prompts firing immediately on dismiss

**Description:** §1.9 specifies that tapping "Get started" triggers microphone and speech-recognition permission requests. Two simultaneous system prompts may stack visually or queue in an unspecified order, creating a confusing first-time experience.

**Recommendation:** Trigger the microphone permission request first; on completion (granted or denied), trigger the speech-recognition request. Both completions resolve before the cover dismisses. Fallback: dismiss the cover *before* the permission requests, letting the home view see the "permissions not yet determined" state and trigger them itself with whatever sequencing the existing flow uses. The latter is simpler but may show the home view briefly with "no microphone permission" UI before the prompt appears.

**Decision needed from:** iOS engineer — verify which sequencing produces the cleanest first-launch experience.

### Issue 7 — Settings sheet suppression during countdown

**Description:** US-66 / §2.3 specify that the gear button is disabled during `coordinator.isPending`. But what if the user opens Settings and *then* a voice command starts (the orb is always listening)? The Settings sheet is open over the home view; the countdown is happening underneath. The user cannot cancel the countdown from Settings.

**Recommendation:** Two options. (A) Auto-dismiss Settings when a countdown starts. (B) Allow Settings to remain open; the countdown completes underneath without interruption, and the user sees the result toast on dismissal. Option B is less surprising and matches the "Settings is a configuration surface, not a control surface" model. Option A is more deferential to the active command. Designer leans toward B.

**Decision needed from:** Designer + product.

---

## Appendix A — Onboarding string catalogue (EN + DA)

The Settings and Help screens inherit their strings from the US-62 / US-63 / US-64 / US-65 tables in `VoxioSpecification-1.3.md` and from existing localisations of `LanguagePickerSheet`. The Onboarding screen introduces new strings catalogued below. All keys should be added to `Localizable.xcstrings`.

| Key | English | Danish |
|---|---|---|
| `onboarding.headline` | "Welcome to Voxio" | "Velkommen til Voxio" |
| `onboarding.subheadline` | "Just say the speaker's name." | "Sig bare højttalerens navn." |
| `onboarding.body` | "Voxio listens through your microphone and controls Bang & Olufsen speakers on your network." | "Voxio lytter gennem mikrofonen og styrer Bang & Olufsen-højttalere på dit netværk." |
| `onboarding.examplesLeadIn` | "Try saying:" | "Prøv at sige:" |
| `onboarding.example1` | "Beolab, play" | "Beolab, afspil" |
| `onboarding.example2` | "Beolab, volume up" | "Beolab, skru op" |
| `onboarding.example3` | "Beolab, stop" | "Beolab, stop" |
| `onboarding.cta` | "Get started" | "Kom i gang" |
| `onboarding.voiceOver.examplesLabel` | "Examples" | "Eksempler" |
| `onboarding.voiceOver.ctaHint` | "Closes onboarding and opens the main screen." | "Lukker introduktionen og åbner hovedskærmen." |

---

## Appendix B — SF Symbol reference

| Use | Symbol | Size | Tint |
|---|---|---|---|
| Settings sheet close | `xmark` | 22 pt | `BeoColor.accent` |
| Settings nav row trailing chevron | `chevron.right` | 12 pt | `BeoColor.muted` |
| Settings toolbar entry | `gear` | 22 pt | `BeoColor.text` (`BeoColor.muted` when disabled) |
| Help sheet close | `xmark` | 22 pt | `BeoColor.accent` |
| Help toolbar entry | `questionmark.circle` | 22 pt | `BeoColor.text` |
| Toggle tint (system control) | (system) | iOS default | `BeoColor.accent` |

No custom artwork. The orb on the Onboarding screen is the existing app component, not an SF Symbol.

---

*End of design specification v1.0*
