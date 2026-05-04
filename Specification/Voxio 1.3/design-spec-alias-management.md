# Design Specification: Voxio Alias Management
**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-04
**Platform:** iOS 26 (iPhone, portrait) — SwiftUI
**Design Language:** DarkGlass (dark Liquid Glass, warm-gold accent)
**References:** VoxioSpecification-1.3.md US-49 / E-34 / T-3402 / T-3405, design-spec-bo-voice-control v1.1 (DarkGlass tokens), design-spec-telemetry-admin.md (format reference), CLAUDE.md (`BeoColor`, `Spacing`, `Radius`, `BeoAnimation`, `BeoType`)

---

## Design Philosophy

Aliases are the most personal feature in Voxio. A user opens the alias screens with one of two intents in mind: "I want my speaker to understand the way *I* talk", or "I taught it something wrong and I want to fix it". Both intents are quiet, considered actions — the user is shaping the system, not consuming content. The screens should reflect that: composed, low-pressure, and unambiguous about cause and effect.

That orientation drives three decisions in this document. First, the Add/Edit sheet is a **two-step guided form**, not a flat field-list. The single thing that makes alias creation feel hard is the leap between "what I say" and "what the app does"; splitting them into two visible steps with a live preview between them makes the mapping explicit. Second, deletion is gated by an alert with the user's actual phrase quoted in the body — the user sees what they are about to delete, not a generic "are you sure". Third, the empty state is warm rather than instructional. A first-time user who has never created an alias does not need a tutorial; they need an example and a button.

The screens inherit the DarkGlass aesthetic from the rest of Voxio v1.2/v1.3 — dark backgrounds, frosted-glass cards, gold accent — and reuse the existing design tokens without introducing new ones.

---

## Visual Language

### Colour palette (existing tokens — do not redefine)

All colours below resolve from `Assets.xcassets` via the `BeoColor` enum. Every token is light/dark adaptive; on the alias screens the system is forced to dark variants because the sheets sit on top of the dark home background.

| Token | Usage on alias screens |
|---|---|
| `BeoColor.bg` (`BgPrimary`) | Sheet and list background fill |
| `BeoColor.cardBg` (`CardSurface`) | Card / list-row surface — the frosted-glass layer |
| `BeoColor.cardBorder` (`CardBorder`) | 0.5 pt hairline around cards and section dividers — same low-opacity white used by the rest of the app |
| `BeoColor.text` (`LabelPrimary`) | Primary text — phrase strings, sheet titles, primary button label *when over a non-gold surface* |
| `BeoColor.muted` (`LabelSecondary`) | Secondary text — "→ Jazz Radio", helper copy, step indicator, section header text |
| `BeoColor.accent` (`Accent` / `#C8A97E`) | Primary CTA fill, mic-button active fill, live-preview highlight border, step-indicator active dot, section selected state |
| `BeoColor.separator` (`BeoSeparator`) | List row separators inside speaker sections |
| `Color.red` (system semantic) | Destructive button label, "Delete all" button, destructive alert action |

`BeoColor.accent` is `#C8A97E`. White text on this gold fails WCAG AA (2.7:1 — same issue documented in `design-spec-telemetry-admin.md` §7.5). Therefore: the primary CTA button uses **`BeoColor.text` (dark) on gold**, not white on gold. This is a deliberate carry-over from the admin-site decision and applies consistently to the "Add alias" / "Save changes" buttons throughout these screens.

No new design tokens are introduced. The DarkGlass card surface and border are unchanged from v1.1.

### Typography ramp (`BeoType`)

| Token | Usage |
|---|---|
| `BeoType.speakerName` (34 pt semibold) | Sheet title at the top of the Add/Edit sheet ("Add alias" / "Edit alias") and the empty-state headline |
| `BeoType.nowPlaying` (22 pt regular) | Phrase string in each list row — the user's spoken phrase |
| `BeoType.confirmation` (17 pt regular) | Step-2 command-option labels, live-preview phrase rendering |
| `BeoType.body` (15 pt regular) | Resolved-command secondary line ("→ Jazz Radio"), helper text, button labels, picker option labels |
| `BeoType.caption` (12 pt medium) | Section header text (uppercased speaker name), step indicator ("1 of 2"), inline validation messages |

The phrase in each list row uses `BeoType.nowPlaying` rather than `BeoType.speakerName` — speaker names dominate on the home screen, but a phrase is the thing the user actually scans for in this list, so the same prominent-but-not-display weight is reused.

### Spacing and radius

All measurements use existing tokens:

- **`Spacing.s4`** — vertical gap between phrase and resolved-command line in a list row
- **`Spacing.s8`** — gap between command-option icon and its label, gap between mic button and phrase field
- **`Spacing.s12`** — vertical padding inside list rows, vertical gap between form rows in the Add/Edit sheet
- **`Spacing.s16`** — horizontal padding on the sheet, gap between live preview and form
- **`Spacing.s20`** — vertical gap between section header and the first row of a speaker group
- **`Spacing.s24`** — vertical padding around the primary CTA button at the bottom of the sheet

- **`Radius.card`** (20 pt) — speaker section card, command-option card in step 2, live-preview panel
- **`Radius.pill`** (100 pt) — mic button, segmented speaker selector, step-indicator dots
- **`Radius.sheet`** (16 pt) — the Add/Edit sheet itself, picker pop-overs

### Motion

All transitions use `BeoAnimation.spring` for navigation and selection state changes. The two-step transition between Step 1 and Step 2 inside the Add/Edit sheet uses `BeoAnimation.cardExpand` (a slightly slower spring, 0.4 / 0.7) — the user is moving forward in a flow, not toggling a state. Toast-style banners (e.g. validation messages) use `BeoAnimation.toast`. The mic-button waveform animation is a continuous 1.4-second loop, suspended on `Reduce Motion`.

---

## Screen Index

| § | Screen | Sheet / Navigation | Purpose |
|---|---|---|---|
| 1 | Alias List | Pushed from Settings > Personalisation > "Aliases" | Browse, edit, delete aliases grouped by speaker |
| 2 | Add / Edit Alias sheet | Modal `.sheet` from Alias List | Two-step guided form to create or update an alias |
| 3 | Confirmation alerts | iOS native `Alert` over the originating screen | Gate deletion of single alias and bulk-delete-per-speaker |

---

## Section 1 — Alias List screen

### 1.1 Purpose

The user's overview of every alias they have created, grouped by the speaker the alias is scoped to (US-49 mandates per-speaker scope). The screen has to support fast scanning ("which speaker has 'morning music' on it?"), single-tap editing, and unmistakable deletion.

### 1.2 Layout (top to bottom, with content)

```
┌──────────────────────────────────────────┐
│  ← Settings           Aliases       +    │  ← Nav bar
├──────────────────────────────────────────┤
│                                          │
│   BEOLAB                                 │  ← Section header (BeoType.caption, muted)
│   ┌────────────────────────────────────┐ │
│   │ morning music                      │ │  ← Row: phrase (nowPlaying)
│   │ → Favourite 5                      │ │     resolved command (body, muted)
│   ├────────────────────────────────────┤ │
│   │ chill mode                         │ │
│   │ → Volume 35                        │ │
│   ├────────────────────────────────────┤ │
│   │ kitchen sync                       │ │
│   │ → Join Beosound                    │ │
│   └────────────────────────────────────┘ │
│                                          │
│   Delete all aliases for Beolab          │  ← Destructive button (red, plain)
│                                          │
│   BEOSOUND                               │
│   ┌────────────────────────────────────┐ │
│   │ jazz time                          │ │
│   │ → Jazz Radio                       │ │
│   └────────────────────────────────────┘ │
│                                          │
│   Delete all aliases for Beosound        │
│                                          │
└──────────────────────────────────────────┘
```

### 1.3 Navigation bar

Standard iOS large-title navigation bar in DarkGlass appearance.

| Element | Detail |
|---|---|
| Back button | "← Settings" — returns to the Settings sheet stack. Tint `BeoColor.accent`. |
| Title | "Aliases" — large title, `BeoType.speakerName`, `BeoColor.text`. Collapses to inline title on scroll per iOS standard. |
| Trailing button | `plus.circle.fill` SF Symbol, 24 pt, `BeoColor.accent`. Tap opens the Add Alias sheet (§2). VoiceOver label: "Add alias". |

### 1.4 Speaker section

Each speaker that has at least one alias renders as one section. Sections are sorted alphabetically by speaker name. Speakers with zero aliases do not appear (US-49: "After all aliases for a speaker are deleted the speaker group is removed from the list").

**Section header:**
- Uppercased speaker name, `BeoType.caption`, `BeoColor.muted`
- 16 pt leading padding, 8 pt bottom padding
- 20 pt top padding from the previous section (or from nav-bar bottom for the first section)

**Row container:**
- `BeoColor.cardBg` fill, `BeoColor.cardBorder` 0.5 pt stroke, `Radius.card` corner radius
- Rows inside the container are separated by `BeoColor.separator` hairlines, inset 16 pt from leading edge
- Container has 16 pt horizontal margin from the screen edges

### 1.5 Alias row

| Property | Value |
|---|---|
| Min height | 64 pt (well above the 44 pt accessibility minimum, accommodates two lines) |
| Vertical padding | `Spacing.s12` top and bottom |
| Horizontal padding | `Spacing.s16` leading and trailing |
| Tap target | Entire row (full width × full height) |
| Tap action | Opens the Edit Alias sheet (§2) pre-filled with this alias |

**Row content (vertical stack, `Spacing.s4` between lines):**

| Line | Text | Style |
|---|---|---|
| Primary | The user's spoken phrase, e.g. "morning music" | `BeoType.nowPlaying`, `BeoColor.text`, single line, truncates with ellipsis at the trailing edge |
| Secondary | `→ <resolved-command>` — see resolution table below | `BeoType.body`, `BeoColor.muted`, single line, truncates with ellipsis |

**Resolved-command text resolution:**

| Alias target | Secondary line text |
|---|---|
| Play favourite by name | `→ <FavouriteName>` (e.g. "→ Jazz Radio") |
| Play favourite by number | `→ Favourite <n>` (e.g. "→ Favourite 5") |
| Set volume | `→ Volume <n>` (e.g. "→ Volume 40") |
| Join speaker | `→ Join <SpeakerName>` (e.g. "→ Join Beosound") |

A trailing `chevron.right` SF Symbol (12 pt, `BeoColor.muted`) at the row's trailing edge signals tap-to-edit. Inset 16 pt from the trailing edge.

**Row states:**

| State | Visual |
|---|---|
| Rest | `BeoColor.cardBg` fill |
| Pressed (touch down) | Fill darkens by ~8% — use `.contentShape(Rectangle())` and standard SwiftUI button press feedback |
| Swiped (partial reveal) | Trailing edge reveals a red "Delete" action button (system swipe action) |

### 1.6 Swipe-to-delete

iOS-standard trailing swipe action on each row (`SwiftUI` `.swipeActions(edge: .trailing)`).

| Property | Value |
|---|---|
| Action button label | "Delete" |
| Background | System red |
| Foreground | White |
| Tap behaviour | Triggers the same confirmation alert as the explicit delete button (see §3.1) — the row is **not** deleted on swipe alone (US-49: "A swipe-to-delete gesture triggers the same confirmation prompt as the explicit delete button") |

### 1.7 Per-speaker bulk delete button

After the row container of each speaker section, a single full-width plain destructive button:

| Property | Value |
|---|---|
| Label | "Delete all aliases for `<SpeakerName>`" |
| Style | Plain text button, no background fill |
| Foreground | System red (semantic destructive colour, not `BeoColor.accent`) |
| Font | `BeoType.body` |
| Alignment | Centred horizontally inside the section's 16 pt margin |
| Top padding | `Spacing.s12` from the row container |
| Bottom padding | `Spacing.s20` before the next section |
| Tap action | Triggers the bulk-delete confirmation alert (§3.2) |
| Min tap target | 44 pt tall — pad vertically if the button label height alone is shorter |

### 1.8 Empty state — no aliases at all

When `PersonalisationStore.aliases.count == 0` across all speakers, the list contents are replaced by a centred empty state. The nav bar (with the `+` button) remains visible — the user must always have a way to add their first alias.

**Layout:**

```
┌──────────────────────────────────────────┐
│  ← Settings           Aliases       +    │
├──────────────────────────────────────────┤
│                                          │
│                                          │
│              ┌──────────┐                │
│              │   〰️🗨️   │                │  ← Speech-bubble-with-waveform icon, gold
│              └──────────┘                │
│                                          │
│           No aliases yet                 │  ← Headline (speakerName)
│                                          │
│   Teach Voxio your own phrases. Say      │  ← Body copy (body, muted)
│   "morning music" and have it play       │
│   your favourite breakfast playlist.     │
│                                          │
│         ┌────────────────────┐           │
│         │    Add alias       │           │  ← Primary CTA (gold)
│         └────────────────────┘           │
│                                          │
└──────────────────────────────────────────┘
```

| Element | Detail |
|---|---|
| Icon | A composed glyph: SF Symbol `text.bubble` (or `speech.bubble.fill`) overlaid with a small waveform glyph. 64 × 64 pt. Tint `BeoColor.accent` at 80% opacity over a circular `BeoColor.cardBg` background, `Radius.pill`. Decorative; `accessibilityHidden(true)`. |
| Headline | "No aliases yet" — `BeoType.speakerName`, `BeoColor.text`, centred |
| Body copy | Two-sentence concept explainer, EN + DA. `BeoType.body`, `BeoColor.muted`, centred, max width 320 pt to keep line length readable |
| Primary CTA | `DarkGlassButton` *variant — see §1.9* with the gold accent fill and dark label. Label "Add alias". Centred, 220 pt min width. Same `+` flow as the nav bar button. |
| Vertical centring | The icon-headline-body-CTA stack is centred vertically in the available content area; on smaller devices it falls back to top-anchoring with `Spacing.s24` from the nav bar |

The empty state copy in Danish: headline "Ingen aliasser endnu", body "Lær Voxio dine egne sætninger. Sig 'morgenmusik' og få din yndlingsplayliste til at spille."

### 1.9 Primary CTA button (used here and in §2.6)

Voxio's existing `DarkGlassButton` is the dark frosted-glass variant. The alias screens introduce a single new visual variant (no new tokens — all values come from existing `BeoColor` and `Radius` tokens) used **only** for the primary action on the empty state and at the bottom of the Add/Edit sheet:

| Property | Value |
|---|---|
| Background fill | `BeoColor.accent` (`#C8A97E`) at 100% opacity |
| Border | None (the gold fill is its own affordance) |
| Foreground | `BeoColor.text` (dark) — contrast 6.0:1, passes WCAG AA |
| Font | `BeoType.body` weight semibold |
| Corner radius | `Radius.pill` |
| Padding | 14 pt vertical, 24 pt horizontal |
| Min tap target | 44 pt tall |
| Pressed state | `pressedScale` 0.95 with `pressSpringResponse` 0.3 (`DarkGlassButtonTokens` values) |
| Disabled state | Background `BeoColor.accent` at 35% opacity, foreground `BeoColor.text` at 50% opacity |

This is the **only** place in the alias flow that uses gold as a fill colour. Everywhere else gold is used as an accent (mic button active, step-indicator dot, live-preview highlight) — it never appears as a fill on a destructive or secondary action.

---

## Section 2 — Add / Edit Alias sheet

### 2.1 Purpose

The single most important screen in the feature. Its job is to make the mental jump from "what I say" to "what should happen" feel obvious. The sheet is a guided two-step form — not a single dense page of fields — and it shows a live preview of the resulting mapping before the user commits.

### 2.2 Sheet container

| Property | Value |
|---|---|
| Presentation | iOS standard `.sheet` modal — partial-height with detents `[.medium, .large]`. Defaults to `.large`. |
| Corner radius | `Radius.sheet` (16 pt) — automatic from iOS sheet styling |
| Background | `BeoColor.bg` |
| Drag indicator | iOS default grabber, visible at the top |
| Dismiss | Swipe down OR "Cancel" button in the sheet header — both prompt for confirmation only if there are unsaved changes (see §2.7) |

### 2.3 Sheet header

A 56 pt tall header strip pinned to the top of the sheet content, separated from the body by a `BeoColor.separator` hairline.

```
┌───────────────────────────────────────────────────┐
│ Cancel        Add alias / Edit alias        🗑     │  ← Edit-mode shows trash; Add-mode shows nothing
│                  ●○  1 of 2                       │  ← Step indicator on second row
└───────────────────────────────────────────────────┘
```

| Element | Detail |
|---|---|
| Leading button | "Cancel" — `BeoType.body`, `BeoColor.accent`. Closes sheet (with confirmation if dirty). |
| Title | "Add alias" or "Edit alias" — `BeoType.speakerName` shrunk to fit (22 pt sheet-title style); centred |
| Trailing button (edit mode only) | `trash` SF Symbol, 22 pt, system red. VoiceOver label: "Delete alias for `<phrase>`". Triggers confirmation alert (§3.1). Hidden in Add mode. |
| Step indicator | Two pill-shaped dots, `Radius.pill`, 8 pt diameter, 4 pt gap. Active dot `BeoColor.accent`; inactive dot `BeoColor.muted` at 40%. Plus the text "1 of 2" or "2 of 2" — `BeoType.caption`, `BeoColor.muted`, 8 pt leading from the dots. |

The step indicator sits centred on a second row inside the header.

### 2.4 Step 1 — "What do you want to say?"

Step 1 is dominated by the phrase input. There are no other interactive controls on the page beyond the mic button and the Continue button — every pixel is in service of getting the user's phrase captured.

```
┌───────────────────────────────────────────────────┐
│  What do you want to say?                         │  ← Step heading
│                                                   │
│  Say exactly what you want Voxio to hear,         │  ← Helper text
│  e.g. "morning music".                            │
│                                                   │
│  ┌─────────────────────────────────────┐  ┌────┐  │
│  │  morning music▍                     │  │ 🎙 │  │  ← Phrase field + mic button
│  └─────────────────────────────────────┘  └────┘  │
│                                                   │
│  ⚠️ Already used for "→ Volume 35".               │  ← Warning (inline, conditional)
│                                                   │
│                                                   │
│                                                   │
│                                                   │
│              ┌────────────────────┐               │
│              │     Continue       │               │  ← Primary CTA
│              └────────────────────┘               │
└───────────────────────────────────────────────────┘
```

#### 2.4.1 Step heading

| Property | Value |
|---|---|
| Text | "What do you want to say?" (EN) / "Hvad vil du sige?" (DA) |
| Font | `BeoType.speakerName` shrunk to 28 pt, semibold |
| Colour | `BeoColor.text` |
| Top padding | `Spacing.s24` from the step indicator |
| Horizontal padding | `Spacing.s16` |

#### 2.4.2 Helper text

| Property | Value |
|---|---|
| Text | "Say exactly what you want Voxio to hear, e.g. \"morning music\"." (EN) / "Sig præcis det, du vil have Voxio til at høre, f.eks. \"morgenmusik\"." (DA) |
| Font | `BeoType.body` |
| Colour | `BeoColor.muted` |
| Top padding | `Spacing.s8` from the heading |

#### 2.4.3 Phrase input field

| Property | Value |
|---|---|
| Field type | `TextField` with `.textInputAutocapitalization(.never)` and `.autocorrectionDisabled(false)` — autocorrect helps catch typos in user-written phrases without forcing a particular form |
| Background | `BeoColor.cardBg` |
| Border | `BeoColor.cardBorder` 0.5 pt at rest; `BeoColor.accent` 1 pt while focused; system red 1 pt while showing a validation warning |
| Corner radius | `Radius.card` |
| Padding | `Spacing.s16` horizontal, 14 pt vertical |
| Font | `BeoType.nowPlaying` |
| Placeholder | "Type or dictate a phrase" / "Skriv eller diktér en sætning" — `BeoColor.muted` at 60% |
| Auto-focus | Yes — `@FocusState` is set to the field on sheet appear in Add mode; in Edit mode the field is pre-filled and **not** auto-focused (the user is more likely editing the command, not the phrase) |
| Top padding | `Spacing.s20` from helper text |

#### 2.4.4 Mic button

A circular button trailing the phrase field, separated by `Spacing.s8`.

| Property | Value (idle) | Value (listening) |
|---|---|---|
| Diameter | 48 pt | 48 pt |
| Background | `BeoColor.cardBg` | `BeoColor.accent` |
| Border | `BeoColor.cardBorder` 0.5 pt | `BeoColor.accent` 1 pt (no contrast border needed) |
| Icon | `mic` SF Symbol, 22 pt, `BeoColor.text` | `mic.fill` SF Symbol, 22 pt, `BeoColor.text` (dark on gold for contrast) |
| Animation | None | Three vertical bars (`waveform` glyph or three short rectangles) animating in a 1.4 s repeating loop above the icon — bars rise and fall at staggered phases. Suspended when `accessibilityReduceMotion` is true; static three-bar glyph remains. |
| Tap target | 48 × 48 pt (already meets 44 pt minimum) | unchanged |

**Tap behaviour:**

| State | Tap action |
|---|---|
| Idle | Request speech recognition authorisation if not granted; on grant, start `SFSpeechRecognizer` session and switch to listening state. On denial, show inline error "Speech recognition not available — type the phrase instead." |
| Listening | Stop the recognition session. The most recent recognised string is committed to the phrase field, replacing any current contents. Switch back to idle. |

VoiceOver label idle: "Dictate phrase". VoiceOver label listening: "Stop dictation". Hint: "Double-tap to begin or end dictation".

#### 2.4.5 Inline validation

A single inline message line appears between the phrase field and the Continue button, pushed in from the leading edge with a small warning glyph.

| Trigger | Glyph | Colour | Message |
|---|---|---|---|
| Phrase is empty (Continue tapped) | `exclamationmark.circle` | system red | "Enter a phrase first." (EN) / "Indtast en sætning først." (DA) |
| Phrase already exists for the same speaker | `exclamationmark.circle` | system red | "A phrase already exists for this action. Delete the existing alias first." (EN) / "En sætning findes allerede for denne handling. Slet det eksisterende alias først." (DA) |
| Phrase contains the trigger word "Voxio" | `exclamationmark.circle` | system red | "Phrases cannot contain \"Voxio\" — it's the app's wake word." (EN) / "Sætninger må ikke indeholde \"Voxio\" — det er appens aktiveringsord." (DA) |

Empty-phrase, duplicate-phrase, and Voxio-containing errors all block Continue — the user must resolve the issue before proceeding.

The message uses `BeoType.caption` and animates in with `BeoAnimation.toast`. Top padding `Spacing.s8` from the field.

#### 2.4.6 Continue button

| Property | Value |
|---|---|
| Style | Primary CTA (§1.9) — gold fill, dark label |
| Label | "Continue" (EN) / "Fortsæt" (DA) |
| Width | 220 pt |
| Position | Centred horizontally; pinned to the bottom safe area of the sheet with `Spacing.s24` bottom padding. Uses `.safeAreaInset(edge: .bottom)` so the keyboard pushes the rest of the content up but the button remains glued above the keyboard. |
| Disabled state | When the phrase field is empty |
| Tap action | Validates the phrase; if valid, slides Step 2 in from the trailing edge using `BeoAnimation.cardExpand` and updates the step indicator to "2 of 2" |

#### 2.4.7 Keyboard handling

The sheet wraps the Step 1 form in a `ScrollView` so that small devices (iPhone SE) can still see the helper text when the keyboard is up. The Continue button uses `.safeAreaInset(edge: .bottom)` to remain pinned above the keyboard regardless of scroll position. The mic button is **not** part of the safe-area inset — it lives next to the field and scrolls with it; pressing it dismisses the keyboard before starting dictation.

### 2.5 Step 2 — "What should it do?"

Step 2 is denser than Step 1: the user makes three nested decisions (speaker, command type, command parameter). The screen is structured so that each decision visually consumes the previous one, and the live preview at the top reassures the user that their selections add up to what they intended.

```
┌───────────────────────────────────────────────────┐
│  What should it do?                               │  ← Step heading
│                                                   │
│  ┌─────────────────────────────────────────────┐  │
│  │  "morning music"                            │  │  ← Live preview panel
│  │  → Favourite 5 on Beolab                    │  │
│  └─────────────────────────────────────────────┘  │
│                                                   │
│  ON SPEAKER                                       │  ← Sub-section caption
│  ┌────────────┬────────────┬─────────────────┐    │
│  │  Beolab    │ Beosound   │ Kitchen         │    │  ← Speaker segmented control
│  └────────────┴────────────┴─────────────────┘    │
│                                                   │
│  COMMAND                                          │  ← Sub-section caption
│  ┌─────────────────────────────────────────────┐  │
│  │  ♫  Play a favourite                  ›    │  │  ← Command-type rows
│  ├─────────────────────────────────────────────┤  │
│  │  #️⃣  Play favourite by number          ›    │  │
│  ├─────────────────────────────────────────────┤  │
│  │  🔊  Set volume                       ›    │  │
│  ├─────────────────────────────────────────────┤  │
│  │  🔗  Join another speaker             ›    │  │
│  └─────────────────────────────────────────────┘  │
│                                                   │
│  [Detail control reveals here when selected]     │
│                                                   │
│              ┌────────────────────┐               │
│              │    Add alias       │               │  ← Primary CTA (Save in edit)
│              └────────────────────┘               │
└───────────────────────────────────────────────────┘
```

#### 2.5.1 Live preview panel

| Property | Value |
|---|---|
| Container | Full-width card, `BeoColor.cardBg` fill, `BeoColor.accent` 1 pt border (gold highlight to signal "this is the live thing"), `Radius.card` |
| Padding | `Spacing.s16` |
| Top line | `"<phrase>"` quoted — `BeoType.confirmation`, `BeoColor.text` |
| Arrow | `→` glyph between the lines, `BeoColor.muted` |
| Bottom line | Resolved-command description as it would appear in the list (§1.5) plus " on `<SpeakerName>`" — `BeoType.body`, `BeoColor.muted` |
| Empty state | When the user has not yet picked a command type, the bottom line reads "Pick a command below" / "Vælg en kommando nedenfor" in `BeoColor.muted` italic |
| Update | Live — every selection change re-renders the preview with `BeoAnimation.toast` cross-fade |

The preview panel is the headline element of Step 2. It sits directly under the step heading in a non-scrolling region above the scrollable form, remaining visible as the user scrolls through the command picker and detail controls.

#### 2.5.2 Speaker selector

A segmented control listing every discovered speaker by name, scoped to the speakers `MdnsDiscovery` has resolved at sheet-open time. Pre-selected to the home screen's currently active speaker (or the first discovered speaker if none is active).

| Property | Value |
|---|---|
| Caption | "ON SPEAKER" / "PÅ HØJTTALER" — `BeoType.caption`, `BeoColor.muted`, 16 pt leading padding |
| Container | iOS-standard `Picker` styled `.segmented`, full-width inside `Spacing.s16` margin |
| Selected segment | `BeoColor.accent` background, `BeoColor.text` (dark) label |
| Unselected segments | `BeoColor.cardBg` background, `BeoColor.muted` label |
| Overflow behaviour | If more than 3 speakers are discovered, switch to a `Menu`-style picker showing the selected speaker and a chevron; the menu opens to a list of all speakers |

When the speaker changes, the live preview's "on `<SpeakerName>`" trailing clause updates immediately. If switching speakers would invalidate the current detail-control selection (e.g. picked Favourite 5 on Beolab, switched to Beosound which has no Favourite 5), the detail control resets to its empty state and the CTA disables until re-selected.

**Edit mode only:** when the user selects a different speaker than the alias was originally created on, a `BeoType.caption` / `BeoColor.muted` annotation renders directly below the selector: *"This will move the alias from `<originalSpeaker>`."* The annotation persists until the user either reverts to the original speaker or saves. No additional confirmation is shown at save time — the inline annotation is sufficient.

#### 2.5.3 Command-type picker

Four rows, vertically stacked inside a single card container.

| Property | Value |
|---|---|
| Caption | "COMMAND" / "KOMMANDO" — same style as speaker caption |
| Container | `BeoColor.cardBg` fill, `BeoColor.cardBorder` 0.5 pt border, `Radius.card` |
| Row height | 56 pt — comfortably above 44 pt minimum |
| Row separator | `BeoColor.separator` hairline, 16 pt leading inset |
| Row layout | Icon (24 × 24 pt SF Symbol or emoji, leading) → label (`BeoType.body`, `BeoColor.text`) → trailing chevron `chevron.right` 12 pt `BeoColor.muted` |
| Selected row | Row background `BeoColor.accent` at 12% opacity; chevron rotated 90° (becomes `chevron.down`); icon and label colour unchanged |

**The four command-type rows:**

| Icon (SF Symbol) | EN label | DA label | Resolved intent |
|---|---|---|---|
| `music.note` | "Play a favourite" | "Afspil en favorit" | Play favourite by name |
| `number` | "Play favourite by number" | "Afspil favorit efter nummer" | Play favourite by number |
| `speaker.wave.2.fill` | "Set volume" | "Vælg lydstyrke" | Set volume |
| `link` | "Join another speaker" | "Tilslut en anden højttaler" | Join speaker |

When a row is selected, the corresponding detail control expands inline directly **below** the picker card (not inside it) with `BeoAnimation.cardExpand`. Selecting a different row collapses the previous detail control and expands the new one. Tapping the selected row again does **not** collapse the detail control — there is always a detail control showing once one has been picked.

#### 2.5.4 Detail controls (one per command type)

All four detail controls share a common chrome — a card with `BeoColor.cardBg`, `BeoColor.cardBorder` 0.5 pt, `Radius.card`, `Spacing.s16` padding, full-width inside `Spacing.s16` margin.

**A. Play a favourite (by name)**

A picker showing the speaker's known favourites. Source: `PersonalisationStore` cached favourites for the selected speaker, populated from `GET /scenes` when the speaker first connects (per `CLAUDE.md` Mozart API notes).

| Property | Value |
|---|---|
| Title | "Choose favourite" |
| Layout | Vertical scrolling list of favourites, max 6 visible before scroll. Each row: 40 pt tall, favourite name (`BeoType.body`, `BeoColor.text`), trailing checkmark (`checkmark`, `BeoColor.accent`) when selected. |
| Empty state | "No favourites available for this speaker." `BeoType.body`, `BeoColor.muted`. CTA disabled. |
| Loading state | Skeleton row placeholders if the favourites are still being fetched (rare — favourites are cached). |

**B. Play favourite by number**

A numeric stepper with a large readout.

| Property | Value |
|---|---|
| Title | "Favourite number" |
| Range | 1 – 9 (B&O Mozart speakers expose 9 preset slots in the API) |
| Layout | A `Stepper` with a centred 48 pt-tall numeric readout (`BeoType.speakerName`, `BeoColor.text`) and `−` / `+` buttons on either side, each 44 × 44 pt, `BeoColor.cardBg` filled circles with `BeoColor.accent` glyph. |
| Default | 1 |

**C. Set volume**

A slider with snapping and a numeric readout.

| Property | Value |
|---|---|
| Title | "Volume level" |
| Range | 0 – 100, snaps to multiples of 5 |
| Readout | Right-aligned numeric value (`BeoType.confirmation`, `BeoColor.text`), shows percentage symbol; updates live as the slider drags |
| Slider track | iOS-default `Slider` with `.tint(BeoColor.accent)`. Track height 4 pt. Thumb 28 pt (default iOS). |
| Default | 40 |

**D. Join another speaker**

A picker showing other discovered speakers (excluding the speaker selected in §2.5.2).

| Property | Value |
|---|---|
| Title | "Speaker to join" |
| Layout | Same row structure as the favourite picker (§A). |
| Empty state | "No other speakers discovered." `BeoType.body`, `BeoColor.muted`. CTA disabled. |
| Default | First other speaker if any |

#### 2.5.5 Save button (primary CTA)

| Property | Value |
|---|---|
| Style | Primary CTA (§1.9) |
| Label (Add mode) | "Add alias" / "Tilføj alias" |
| Label (Edit mode) | "Save changes" / "Gem ændringer" |
| Width | 220 pt |
| Position | Centred, pinned to bottom safe area with `Spacing.s24` padding (same treatment as Step 1's Continue) |
| Disabled state | Disabled until: a speaker is selected, a command type is selected, AND the detail control has a valid value |
| Tap action | Persists the alias via `PersonalisationStore.saveAlias(...)`, dismisses the sheet, returns to Alias List with the new/updated row visible |

#### 2.5.6 Back button to Step 1

A small "← Back" link in the upper-left of the Step 2 content area (under the header), `BeoType.body`, `BeoColor.accent`. Tap returns to Step 1 with `BeoAnimation.cardExpand` reverse, preserving all current Step 2 selections in memory so that returning forward does not reset them.

(The header's "Cancel" remains the close-the-whole-sheet action — the in-page Back is for moving between steps.)

### 2.6 Edit mode specifics

Edit mode is structurally identical to Add mode. Differences:

| Aspect | Add mode | Edit mode |
|---|---|---|
| Sheet title | "Add alias" | "Edit alias" |
| Trailing header button | (none) | `trash` icon — destructive, triggers single-alias delete confirmation (§3.1) |
| Phrase field | Empty, auto-focused | Pre-filled with the existing phrase, **not** auto-focused |
| Speaker selector | Pre-selected to current active speaker | Pre-selected to the alias's speaker; switching it is allowed but treated as a destructive change (the alias is removed from the original speaker's group and added to the new one) |
| Command-type picker | No selection until user picks | Pre-selected to the alias's existing command type, with the corresponding detail control already expanded and pre-filled |
| CTA label | "Add alias" | "Save changes" |
| CTA disabled state | Until valid form | Until the form has been *changed* AND is valid — disabled if the user opens the sheet and changes nothing |
| Cancel-with-dirty check | Compares against empty initial state | Compares against the original alias's values |

### 2.7 Cancel-with-unsaved-changes flow

If the user attempts to dismiss the sheet (swipe down OR Cancel button) while the form differs from its initial state, a confirmation alert appears:

| Property | Value |
|---|---|
| Title | "Discard changes?" / "Kassér ændringer?" |
| Message | "Your alias will not be saved." / "Dit alias vil ikke blive gemt." |
| Primary action | "Discard" / "Kassér" — destructive (system red) — closes the sheet without saving |
| Secondary action | "Keep editing" / "Fortsæt redigering" — default — dismisses the alert, sheet remains open |

The user can disable the swipe-to-dismiss gesture entirely while the form is dirty by setting `.interactiveDismissDisabled(isDirty)`. This is the SwiftUI-recommended pattern.

---

## Section 3 — Confirmation alerts

All deletion paths route through a native iOS `Alert` modal. The alerts are deliberately verbatim to the wording in US-49 — the user must see the actual phrase or count they are about to remove.

### 3.1 Delete single alias

Triggered by:
- Swipe-to-delete on a row in §1.6
- Tap on the trash icon in the Edit Alias sheet header (§2.6)

| Property | Value |
|---|---|
| Title | "Delete alias?" / "Slet alias?" |
| Message | "This will permanently remove \"`<phrase>`\"." / "Dette fjerner permanent \"`<phrase>`\"." |
| Primary action | "Delete" / "Slet" — `.destructive` role (system red) |
| Secondary action | "Cancel" / "Annullér" — `.cancel` role |
| On confirm | Calls `PersonalisationStore.deleteAlias(_:)`, dismisses any open Edit sheet, the row animates out of the list. If this was the last alias for the speaker, the entire speaker section collapses with `BeoAnimation.spring`. If this was the last alias overall, the empty state (§1.8) renders. |
| On cancel | Alert dismisses; row remains; if triggered from swipe, the swipe action retracts |

VoiceOver: the destructive action is announced as destructive; the alert title is announced as the alert role.

### 3.2 Delete all aliases for speaker

Triggered by tapping the per-speaker bulk delete button (§1.7).

| Property | Value |
|---|---|
| Title | "Delete all aliases for `<SpeakerName>`?" / "Slet alle aliasser for `<SpeakerName>`?" |
| Message | "This will permanently remove all `<N>` aliases for `<SpeakerName>`. This cannot be undone." / "Dette fjerner permanent alle `<N>` aliasser for `<SpeakerName>`. Dette kan ikke fortrydes." |
| Primary action | "Delete All" / "Slet alle" — `.destructive` role |
| Secondary action | "Cancel" / "Annullér" — `.cancel` role |
| On confirm | Calls `PersonalisationStore.deleteAllAliases(for: speakerId)`, the speaker section animates out with `BeoAnimation.spring`. If this was the last speaker with aliases, the empty state renders. |
| On cancel | Alert dismisses; section remains |

The `<N>` count is the live count at the time the button was tapped — recomputed even if aliases were modified between sessions.

---

## Section 4 — UX/UI Issues and Open Questions

### Issue 1 — Duplicate phrase: warn vs block vs overwrite — **RESOLVED**

**Decision (2026-05-04): Block.** A duplicate phrase on the same speaker is an error. Continue is disabled until the user changes the phrase or deletes the existing alias first. Error message updated in §2.4.5 accordingly.

### Issue 2 — Live preview position when content scrolls

**Description:** Step 2 has more content than fits on small devices (iPhone SE) when a detail control is expanded. The live preview panel is the user's anchor — losing sight of it while scrolling weakens the Step 2 design.

**Recommendation:** Pin the live preview panel below the sheet header, above the scrolling form. The preview is part of the non-scrolling region; the form (speaker selector, command picker, detail control, Save) scrolls beneath it. On larger devices the entire page may not need to scroll, in which case the preview sits naturally at the top with no special treatment. Alternative: show a compact preview echo near the Save button. Designer prefers the former.

**Decision needed from:** Designer + iOS engineer.

### Issue 3 — Reserved-word filter for the phrase ("Voxio") — **RESOLVED**

**Decision (2026-05-04): Block.** Phrases containing "Voxio" (case-insensitive) are rejected at Step 1 with an error. Continue is disabled. Error message updated in §2.4.5 accordingly. `PersonalisationStore.saveAlias()` must also enforce this server-side to guard against direct API calls.

### Issue 4 — Mic-button waveform animation budget

**Description:** A continuously animating gold waveform during dictation is visually engaging, but `SFSpeechRecognizer` sessions may run for several seconds — the animation must not sap battery or trigger thermal throttling on older devices.

**Recommendation:** Use a 3-bar abstract waveform (rectangles) animated by phase-shifted sine functions, max 30 fps, suspended on `accessibilityReduceMotion`. Avoid using `Canvas` or `Metal` for this; standard `Animation.easeInOut(duration: 0.7).repeatForever(autoreverses: true)` on three `Rectangle`s is sufficient and cheap. Verify on iPhone 12 baseline.

**Decision needed from:** iOS engineer — confirm performance.

### Issue 5 — Speaker selector overflow at 4+ speakers — **RESOLVED**

**Decision (2026-05-04): Switch to Menu at > 3 speakers.** Character-length threshold not used. The spec at §2.5.2 already reflects this: "If more than 3 speakers are discovered, switch to a Menu-style picker."

### Issue 6 — Edit mode: changing the speaker re-categorises the alias — **RESOLVED**

**Decision (2026-05-04): Show warning annotation.** When the user picks a different speaker in Edit mode, render the `BeoColor.muted` annotation "This will move the alias from `<originalSpeaker>`." No further confirmation at save time. Spec at §2.5.2 updated accordingly.

### Issue 7 — Empty state per-speaker after bulk delete

**Description:** US-49 specifies "After all aliases for a speaker are deleted the speaker group is removed from the list". This means there is no transient empty section header visible after the bulk delete animation — the entire section collapses out of existence. The collapse animation should feel intentional, not glitchy.

**Recommendation:** Animate the bulk delete in two phases: (1) all rows fade out with `BeoAnimation.toast` over 200 ms, (2) the section header and bulk-delete button collapse vertically over 250 ms with `BeoAnimation.spring`. If this was the last speaker section, the empty state cross-fades in over 300 ms. Total delete-to-empty-state time: ~750 ms.

**Decision needed from:** iOS engineer — verify SwiftUI `withAnimation` orchestration handles the chained timing cleanly.

### Issue 8 — Favourite picker source-of-truth and freshness

**Description:** Step 2 detail control A ("Play a favourite") shows the speaker's favourite list. The list is cached in `PersonalisationStore` (per T-3303 / E-33 work). If the user has not used a speaker for several days, the cache may be stale (favourites added or renamed in B&O's app since). Should the picker fetch fresh on open, show stale-with-refresh, or trust the cache?

**Recommendation:** On Add/Edit sheet open in Step 2, kick off a non-blocking `GET /scenes` refresh for the selected speaker. While the refresh is in flight, the picker shows the cached list — the user can pick from cache. When the refresh returns, if the list has changed, swap the data with `BeoAnimation.toast` and show a small toast banner "Favourites updated". If the user has already saved the alias and the favourite they picked is no longer in the new list, the alias still saves (favourite IDs are stable on B&O hardware) — handle disappeared-favourite at parse time, not at save time.

**Decision needed from:** Voice-pipeline engineer — confirm favourite ID stability across renames.

### Issue 9 — Step 2 "Back" interacting with sheet swipe-down

**Description:** A user on Step 2 who swipes down anywhere on the sheet will dismiss the entire sheet, not return to Step 1. This is iOS-standard sheet behaviour but contradicts the visual model of "I can swipe right-to-left between steps and back". The in-page Back button (§2.5.6) covers this, but a user might still try to swipe down expecting to go back one step.

**Recommendation:** Accept the iOS-standard behaviour. The Back button is sufficient and visually obvious. Do not introduce a custom horizontal-swipe gesture between steps — it conflicts with text-field selection gestures and adds complexity for marginal gain. Document this for the implementer.

**Decision needed from:** No external decision needed. Flag for implementer awareness.

### Issue 10 — VoiceOver announcement order for the live preview

**Description:** When a VoiceOver user changes a Step 2 selection, the live preview updates. If the preview has `accessibilityElement(children: .combine)` and an `aria-live` equivalent (`UIAccessibility.post(notification: .announcement, ...)`), every selection change announces the full preview — which is verbose. If it does not announce, the user may not realise the preview updated at all.

**Recommendation:** Throttle preview announcements: post an announcement at most every 1.5 seconds, debounced, with the latest preview text. A user moving the volume slider gets one announcement at the end of their drag, not 50 mid-drag. Combine the speaker selection, command type, and detail value into one combined string for the announcement: "Preview: morning music to Favourite 5 on Beolab".

**Decision needed from:** Designer — confirm the 1.5 s throttle is acceptable.

---

## Section 5 — Accessibility Requirements

### 5.1 Tap targets

Every interactive element on these screens meets or exceeds 44 × 44 pt:

| Element | Size |
|---|---|
| Alias list row | 64 pt tall, full width (well above) |
| Trash icon in sheet header (Edit) | 44 × 44 pt hit area around the 22 pt symbol |
| Mic button | 48 × 48 pt |
| Continue / Save / Add alias CTA | 44 pt tall × 220 pt wide |
| Step indicator dots | Decorative — not interactive — but each dot is 8 pt with a 36 pt invisible hit area for a future "tap to go back" affordance (out of scope v1.3) |
| Stepper `−` / `+` | 44 × 44 pt |
| Speaker segmented control segment | At least 44 × 44 pt; falls back to Menu picker if width forces it below this |
| Per-speaker bulk delete button | 44 pt tall, full row width |
| Swipe-to-delete action | iOS standard 44 pt minimum |

### 5.2 VoiceOver labels

| Element | Label |
|---|---|
| `+` button in nav bar | "Add alias" |
| Alias list row | "`<phrase>`, `<resolved-command>`. Double-tap to edit." |
| Trailing chevron in row | (decorative — `accessibilityHidden(true)`) |
| Per-speaker bulk delete button | "Delete all `<N>` aliases for `<SpeakerName>`. Destructive." |
| Trash icon in Edit sheet header | "Delete alias for `<phrase>`. Destructive." |
| Mic button (idle) | "Dictate phrase. Double-tap to begin dictation." |
| Mic button (listening) | "Stop dictation." |
| Step indicator | "Step 1 of 2" / "Step 2 of 2" |
| Live preview panel | "Preview: `<phrase>` to `<resolved-command>` on `<SpeakerName>`" |
| Command-type rows | Label only — the SF Symbol is decorative. "Play a favourite" / "Set volume" etc. |
| Slider in volume detail | iOS-default — "Volume, `<n>` percent. Adjustable." |
| Stepper in number detail | iOS-default — "Favourite number, `<n>`. Adjustable." |

### 5.3 Focus management

- On Add Alias sheet open: focus moves to the phrase field; VoiceOver announces "Add alias. What do you want to say? Phrase, edit text."
- On Edit Alias sheet open: focus moves to the sheet title (not the field — the user is more likely orienting to "what alias am I editing").
- On Continue tap: focus moves to the live preview panel — the first thing on Step 2.
- On Back tap from Step 2: focus returns to the Continue button on Step 1.
- On Save tap: focus moves to the now-visible row in the list (the new or updated alias).
- On delete confirmation: after the alert is dismissed (either action), focus returns to the cell or button that triggered it; if that cell no longer exists (it was deleted), focus moves to the next cell or, if the section is empty, the section above's last cell.

### 5.4 Reduce Motion

When `accessibilityReduceMotion` is true:

- Step 1 → Step 2 transition: replaced with a 200 ms cross-fade.
- Mic-button waveform: replaced with a static three-bar glyph (no rise/fall animation).
- Bulk delete two-phase animation: replaced with a single fade-out of the entire section.
- Live preview update: replaced with an instant swap (no `BeoAnimation.toast` cross-fade).
- Press-state scale on the primary CTA: disabled (no scale; opacity nudge only).

### 5.5 Dynamic Type

All text uses `BeoType` tokens which already support Dynamic Type via `Font.system`. No fixed-pixel text sizes are introduced. The only layout consequence is that on the largest accessibility sizes (`accessibility4` / `accessibility5`):

- The alias list row's two-line content may grow to three or four lines — the row's `min height` becomes `intrinsic`.
- The segmented speaker selector falls back to the Menu-style picker (§2.5.2) regardless of speaker count.
- The Step 2 detail control card may need to scroll independently of the rest of the form.

These are consequences, not design failures — the spec accepts them.

### 5.6 Colour contrast

| Combination | Ratio | Compliant |
|---|---|---|
| `BeoColor.text` on `BeoColor.bg` (dark mode) | 16.1:1 (estimated from token brief) | AAA |
| `BeoColor.muted` on `BeoColor.cardBg` | 4.7:1 (estimated) | AA |
| `BeoColor.text` (dark) on `BeoColor.accent` (gold) | 6.0:1 | AA |
| `BeoColor.text` (light) on `BeoColor.accent` | 2.7:1 | **Fails AA** — never used; primary CTA is dark-on-gold |
| System red on `BeoColor.bg` | (depends on iOS dynamic colour) | Trust system semantic |

The primary CTA dark-on-gold decision is identical to the admin-site decision documented in `design-spec-telemetry-admin.md` §7.5 option 2 — the visual system across both surfaces is now consistent.

---

## Section 6 — Out of Scope (v1.3)

- **Reordering aliases within a speaker section.** v1.3 sorts by `createdAt` descending. No drag-to-reorder.
- **Searching or filtering aliases.** With a 200-entry per-speaker cap and typical usage of 1–10 aliases per speaker, a search bar is not needed.
- **Importing/exporting aliases.** No JSON import, no share sheet, no migration path between devices. Cross-device sync is out of scope for v1.3 entirely.
- **Tagging or grouping aliases beyond their speaker.** No labels, no folders, no favourites within favourites.
- **Per-alias enable/disable toggle.** An alias is either present (active) or deleted. No "pause this alias" affordance.
- **Voice testing inside the sheet** ("Try it now" button that runs the alias against the parser without committing). Useful but adds a parse-pipeline dependency to a save flow that should remain isolated. Defer.
- **Alias usage statistics.** A "last used" timestamp is captured for `ConfirmedCommand` entries but not surfaced for `Alias` rows in v1.3.
- **Smart suggestions** ("Looks like you say 'morning music' a lot — add as alias?"). Deferred to v2 (see VoxioSpecification-1.3.md "Out of Scope (v1.3 initial)").
- **Bulk import from `ConfirmedCommand` ("learned phrases")**. The Learned Phrases screen and the Aliases screen are siblings with no cross-promotion path in v1.3.
- **Localised speaker name aliases** (an alias that works for a speaker named "Beolab" in English and "Beolab" in Danish — they are the same string today, so this is a non-issue, but if speaker name localisation arrives in v1.4 the alias model may need revisiting).
- **iPad layout, landscape orientation.** Inherits the v1.2 platform constraints.

---

## Appendix A — SF Symbol reference

All icons used on these screens come from Apple's SF Symbols library. None are custom artwork.

| Use | Symbol | Size at use | Tint |
|---|---|---|---|
| Add alias (nav bar) | `plus.circle.fill` | 24 pt | `BeoColor.accent` |
| Empty state hero | `text.bubble` (or `speech.bubble.fill`) | 64 pt inside circle | `BeoColor.accent` 80% |
| Row trailing chevron | `chevron.right` | 12 pt | `BeoColor.muted` |
| Edit sheet trash | `trash` | 22 pt | system red |
| Mic button (idle) | `mic` | 22 pt | `BeoColor.text` |
| Mic button (listening) | `mic.fill` | 22 pt | `BeoColor.text` (dark on gold) |
| Inline error | `exclamationmark.circle` | 14 pt | system red |
| Inline warning | `exclamationmark.triangle` | 14 pt | system orange |
| Command type "Play favourite" | `music.note` | 24 pt | `BeoColor.accent` |
| Command type "Favourite by number" | `number` | 24 pt | `BeoColor.accent` |
| Command type "Set volume" | `speaker.wave.2.fill` | 24 pt | `BeoColor.accent` |
| Command type "Join speaker" | `link` | 24 pt | `BeoColor.accent` |
| Command-row trailing chevron | `chevron.right` / `chevron.down` (selected) | 12 pt | `BeoColor.muted` |
| Volume slider tint | (slider thumb) | iOS default | `BeoColor.accent` |
| Stepper buttons | `minus` / `plus` | 22 pt inside 44 pt circle | `BeoColor.accent` glyph on `BeoColor.cardBg` |
| Favourite picker selected | `checkmark` | 16 pt | `BeoColor.accent` |

---

## Appendix B — String catalogue (EN + DA)

Every user-visible string on the alias screens. Strings should be added to `Localizable.xcstrings`.

| Key | English | Danish |
|---|---|---|
| `aliases.title` | "Aliases" | "Aliasser" |
| `aliases.add` | "Add alias" | "Tilføj alias" |
| `aliases.bulkDelete.button` | "Delete all aliases for %@" | "Slet alle aliasser for %@" |
| `aliases.empty.headline` | "No aliases yet" | "Ingen aliasser endnu" |
| `aliases.empty.body` | "Teach Voxio your own phrases. Say \"morning music\" and have it play your favourite breakfast playlist." | "Lær Voxio dine egne sætninger. Sig \"morgenmusik\" og få din yndlingsplayliste til at spille." |
| `aliasSheet.add.title` | "Add alias" | "Tilføj alias" |
| `aliasSheet.edit.title` | "Edit alias" | "Redigér alias" |
| `aliasSheet.cancel` | "Cancel" | "Annullér" |
| `aliasSheet.back` | "Back" | "Tilbage" |
| `aliasSheet.continue` | "Continue" | "Fortsæt" |
| `aliasSheet.add.cta` | "Add alias" | "Tilføj alias" |
| `aliasSheet.edit.cta` | "Save changes" | "Gem ændringer" |
| `aliasSheet.step.1of2` | "1 of 2" | "1 af 2" |
| `aliasSheet.step.2of2` | "2 of 2" | "2 af 2" |
| `step1.heading` | "What do you want to say?" | "Hvad vil du sige?" |
| `step1.helper` | "Say exactly what you want Voxio to hear, e.g. \"morning music\"." | "Sig præcis det, du vil have Voxio til at høre, f.eks. \"morgenmusik\"." |
| `step1.placeholder` | "Type or dictate a phrase" | "Skriv eller diktér en sætning" |
| `step1.error.empty` | "Enter a phrase first." | "Indtast en sætning først." |
| `step1.warning.duplicate` | "Already used for %@." | "Allerede brugt til %@." |
| `step1.warning.voxio` | "Avoid using \"Voxio\" — it's the app's wake word." | "Undgå at bruge \"Voxio\" — det er appens vækningsord." |
| `step2.heading` | "What should it do?" | "Hvad skal det gøre?" |
| `step2.preview.empty` | "Pick a command below" | "Vælg en kommando nedenfor" |
| `step2.section.speaker` | "ON SPEAKER" | "PÅ HØJTTALER" |
| `step2.section.command` | "COMMAND" | "KOMMANDO" |
| `step2.cmd.favouriteByName` | "Play a favourite" | "Afspil en favorit" |
| `step2.cmd.favouriteByNumber` | "Play favourite by number" | "Afspil favorit efter nummer" |
| `step2.cmd.setVolume` | "Set volume" | "Vælg lydstyrke" |
| `step2.cmd.join` | "Join another speaker" | "Tilslut en anden højttaler" |
| `step2.detail.favouriteByName.title` | "Choose favourite" | "Vælg favorit" |
| `step2.detail.favouriteByName.empty` | "No favourites available for this speaker." | "Ingen favoritter tilgængelige for denne højttaler." |
| `step2.detail.favouriteByNumber.title` | "Favourite number" | "Favoritnummer" |
| `step2.detail.setVolume.title` | "Volume level" | "Lydstyrke" |
| `step2.detail.join.title` | "Speaker to join" | "Højttaler at tilslutte" |
| `step2.detail.join.empty` | "No other speakers discovered." | "Ingen andre højttalere fundet." |
| `mic.idle.label` | "Dictate phrase" | "Diktér sætning" |
| `mic.listening.label` | "Stop dictation" | "Stop diktering" |
| `mic.denied` | "Speech recognition not available — type the phrase instead." | "Talegenkendelse er ikke tilgængelig — skriv sætningen i stedet." |
| `dirty.discard.title` | "Discard changes?" | "Kassér ændringer?" |
| `dirty.discard.message` | "Your alias will not be saved." | "Dit alias vil ikke blive gemt." |
| `dirty.discard.confirm` | "Discard" | "Kassér" |
| `dirty.discard.cancel` | "Keep editing" | "Fortsæt redigering" |
| `delete.single.title` | "Delete alias?" | "Slet alias?" |
| `delete.single.message` | "This will permanently remove \"%@\"." | "Dette fjerner permanent \"%@\"." |
| `delete.single.confirm` | "Delete" | "Slet" |
| `delete.single.cancel` | "Cancel" | "Annullér" |
| `delete.bulk.title` | "Delete all aliases for %@?" | "Slet alle aliasser for %@?" |
| `delete.bulk.message` | "This will permanently remove all %lld aliases for %@. This cannot be undone." | "Dette fjerner permanent alle %lld aliasser for %@. Dette kan ikke fortrydes." |
| `delete.bulk.confirm` | "Delete All" | "Slet alle" |
| `delete.bulk.cancel` | "Cancel" | "Annullér" |
| `resolved.favouriteByName` | "→ %@" | "→ %@" |
| `resolved.favouriteByNumber` | "→ Favourite %lld" | "→ Favorit %lld" |
| `resolved.setVolume` | "→ Volume %lld" | "→ Lydstyrke %lld" |
| `resolved.join` | "→ Join %@" | "→ Tilslut %@" |

---

*End of design specification v1.0*
