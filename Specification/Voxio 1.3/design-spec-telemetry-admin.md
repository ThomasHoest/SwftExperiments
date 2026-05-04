# Design Specification: Voxio Telemetry Admin Site
**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-04
**Platform:** Web — Next.js 15 hybrid app on Azure Static Web Apps, desktop browser
**Design Language:** Neutral functional admin (light theme, system sans-serif, single B&O accent)
**References:** spec-telemetry-backend-admin.md v1.1, design-spec-widget-voxio-1.2.md (format reference), VoxioSpecification-1.1.md (brand colour reference), shadcn/ui component library

---

## Design Philosophy

The Voxio telemetry admin site is an internal tool. Its users are 1–5 engineers and data labellers who will spend long sessions triaging events, applying labels, and exporting CSV files for retraining. They do not need to be impressed; they need to be fast.

That orientation drives every design decision in this document. The site does not use the iOS app's dark Liquid Glass aesthetic. There is no orb, no warm-gold-on-navy hero surface, no animated background. The canvas is white, the type is the default system stack, and the only piece of brand colour that survives is a single accent line for "selected" states and the primary action button — `#C8A97E`, used sparingly enough that nothing else competes with it.

What the admin site does inherit from the broader Voxio brand is restraint. No needless decoration. No icons for things that are obvious from text. No animation longer than 150 ms. The information is the design.

---

## Design Principles (Admin-Specific)

1. **Density over aesthetics** — A row in the events table is 36 pt tall, not 56. The information that an admin scans for (timestamp, intent, parser path, outcome, flag) all fits on one line at one zoom level. Whitespace serves legibility, not breathing room.
2. **Data first, chrome last** — Navigation, filters, and pagination are present but quiet. The viewport is dominated by the table or the event detail. No marketing card, no hero section, no welcome message.
3. **No ambiguity in destructive actions** — Deletion is irreversible by design (GDPR cascade). The deletion form requires the user to type `DELETE` in plain text, the destructive button is unmistakably red, and a confirmation summary lists exactly what is about to be removed. There is no "are you sure?" modal because the form itself is the safety gate.
4. **Keyboard-first** — A labeller working through 200 events in a sitting should never have to reach for the mouse. Every primary action has a visible shortcut hint, focus rings are obvious, and the tab order is verifiable.

---

## Visual Language

The admin site is a light-theme web application. No dark mode in v1. No theme switcher. The reasoning is straightforward: this is a labelling surface that will be open beside the team's terminal and editor; consistency with whatever those tools use is the user's problem, not ours, and a light surface gives more contrast on tabular data than a dark one.

The single piece of brand DNA is the warm gold accent, `#C8A97E`, used in three specific places only:

- The "active" indicator on the current navigation tab (a 2 pt underline).
- The primary call-to-action button background on the deletion confirmation and the export download action.
- The `correct` label state badge background.

Everywhere else, the palette is neutral grey.

---

## Section 1 — Colour Palette

### 1.1 Neutral palette (light theme)

| Token | Hex | Usage |
|---|---|---|
| `bg.canvas` | `#FFFFFF` | Page background |
| `bg.subtle` | `#F8F7F5` | Table header row, hover row, sidebar fills |
| `bg.muted` | `#F1EFEC` | Disabled inputs, code/JSON viewers |
| `border.default` | `#E5E2DD` | Table borders, card borders, input borders at rest |
| `border.strong` | `#C8C3BB` | Input border on focus, divider on dense surfaces |
| `text.primary` | `#1F1D1A` | Body text, table cells, headings |
| `text.secondary` | `#6B665D` | Field labels, helper text, muted timestamps |
| `text.placeholder` | `#A09488` | Input placeholders |
| `text.inverse` | `#FFFFFF` | Text on the gold and red CTA buttons |

The off-white `#F8F7F5` and the warm grey borders (`#E5E2DD`) are deliberately tuned warm rather than cold blue — this is the only carry-over from the Voxio palette that asserts itself across the otherwise neutral admin theme. It is subtle enough that a casual viewer reads it as "white".

### 1.2 Brand accent (used sparingly)

| Token | Hex | Usage |
|---|---|---|
| `accent.gold` | `#C8A97E` | Active nav-tab underline, primary CTA background, `correct` label badge |
| `accent.gold.hover` | `#B8986D` | Hover state of the gold CTA button |
| `accent.gold.subtle` | `#F4ECDD` | `correct` label badge background |

`accent.gold` is the same `#C8A97E` defined in `BeoColor.accent` in the iOS app. There is exactly one accent colour. Do not introduce a second.

### 1.3 Semantic palette

| Token | Hex | Usage |
|---|---|---|
| `success.fg` | `#1F6F47` | Confirmed-outcome text, success toast text |
| `success.bg` | `#E8F3EE` | Success toast background |
| `warning.fg` | `#8A5A00` | `likelyMisparse` flag text, `recoverableUnknown` flag text |
| `warning.bg` | `#FCF1DA` | Flag badge background |
| `danger.fg` | `#A11C1C` | Delete button background, destructive-confirmation text, `incorrect` label badge |
| `danger.bg` | `#FCEBEB` | Error toast background, `incorrect` label badge background |
| `info.fg` | `#1F4F8A` | Informational toast text, neutral filter pill text |
| `info.bg` | `#E8EEF7` | Informational toast background |

Outcome and flag colours are paired with text inside the badge — no admin should ever have to remember "blue means cancelled". The text is always present. Colour reinforces, never replaces.

---

## Section 2 — Typography

### 2.1 Font stack

```
font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
```

System sans-serif. No web font load. No SF Pro Display. The admin site is opened from a Mac, a Windows machine, and (occasionally) Linux — the system stack reads native on each.

A monospace stack is used for technical fields (deviceId, event JSON, timestamps in CSV preview):

```
font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
```

### 2.2 Type ramp

| Token | Size | Line height | Weight | Usage |
|---|---|---|---|---|
| `type.h1` | 24 px | 32 px | 600 | Page title (e.g. "Events", "Stats") |
| `type.h2` | 18 px | 24 px | 600 | Card / section title |
| `type.h3` | 14 px | 20 px | 600 | Table column header, form group label |
| `type.body` | 14 px | 20 px | 400 | Body text, table cell, form input |
| `type.bodyStrong` | 14 px | 20 px | 500 | Inline emphasis, selected row label |
| `type.small` | 12 px | 16 px | 400 | Helper text, badge text, pagination label |
| `type.smallStrong` | 12 px | 16 px | 600 | Filter pill label, badge label uppercase |
| `type.mono` | 13 px | 18 px | 400 | deviceId, raw JSON, CSV preview |

`type.body` at 14 px is the workhorse. Tabular data uses 14 px / 20 px line height; this gives a 36 pt row height with 8 pt vertical padding (standard shadcn `<TableRow>` density adjusted from the default 48 pt).

No Dynamic Type, no rem-based scaling for accessibility — admin-site users override at the browser level. Layout is fixed-pixel for reliability.

---

## Section 3 — Layout and Navigation

### 3.1 Page shell

The shell is a top-navigation layout. There is no left sidebar in v1 — the admin site has six pages and one of them is a sign-in landing; a sidebar would be wasted vertical space.

```
┌─────────────────────────────────────────────────────────────────┐
│  Voxio Admin   Events   Stats   Export   Deletion     mrandersen ▾  │  ← Top nav (56 pt)
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [Page content — 1280 pt min, max-width 1440 pt]                │
│                                                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

| Zone | Height | Notes |
|---|---|---|
| Top nav | 56 px | White background, 1 px bottom border (`border.default`), full-bleed |
| Page padding | 24 px horizontal, 24 px top, 32 px bottom | All admin pages |
| Max content width | 1440 px | Centred horizontally on screens > 1440 px |
| Min viewport width | 1280 px | Below this, no special handling — horizontal scroll is acceptable |

### 3.2 Top navigation bar

Left to right inside the 56 px bar:

| Element | Detail |
|---|---|
| Wordmark | "Voxio Admin" — `type.h2` semibold weight, `text.primary`. Acts as a link to `/admin/events`. 16 px right margin. |
| Nav links | "Events" / "Stats" / "Export" / "Deletion" — `type.body`, `text.secondary` at rest, `text.primary` on hover, `text.primary` with a 2 px `accent.gold` underline when active. 24 px gap between links. |
| Spacer | Fills remaining width |
| User menu | GitHub username from `clientPrincipal.userDetails`, `type.body`, `text.secondary`, with a 12 px-down chevron icon. Click opens a dropdown menu (shadcn `<DropdownMenu>`) containing one item: "Sign out" → `/.auth/logout`. |

The active tab is determined by the current pathname's first segment under `/admin/`. `/admin/events/{id}` keeps the "Events" tab active.

### 3.3 Responsive behaviour

The admin site is desktop-first and desktop-only in v1. Behaviour at small viewports:

- 1280 px and above: the layout described above renders as designed.
- Below 1280 px (down to ~1024 px): the layout still renders, but column widths in the events table may force horizontal scrolling. This is acceptable.
- Below 1024 px: behaviour is unspecified. The page does not become a mobile layout. There is no hamburger menu. If the user shrinks the window further, content overflows horizontally with browser scroll. This is documented and intentional — admin users work on full-size displays.

No mobile breakpoint, no tablet breakpoint, no touch-target compensation.

### 3.4 Toasts and inline feedback

Toasts appear bottom-right, 24 px from each edge. Stacking direction: bottom-up. Toast width 360 px, vertical padding 12 px, horizontal padding 16 px. Auto-dismiss after 5 seconds; persistent toasts (e.g. failed deletion) require explicit dismissal via an `xmark` icon in the top-right of the toast.

Toast variants:

| Variant | Background | Foreground | Icon |
|---|---|---|---|
| Success | `success.bg` | `success.fg` | `check-circle` |
| Error | `danger.bg` | `danger.fg` | `alert-circle` |
| Info | `info.bg` | `info.fg` | `info` |

Inline error messages on form inputs appear directly below the input in `danger.fg` at `type.small`, with a 4 px top margin. The input's border switches to `danger.fg` while the error is present.

---

## Section 4 — Screen Specs

### 4.1 Sign-in landing — `/admin` (unauthenticated)

The user lands here when they navigate to any `/admin/*` URL while not signed in. SWA's auth middleware redirects them here (or directly to `/.auth/login/github` per the SWA configuration; the landing card is the fallback if SWA returns an authenticated-but-not-admin user).

**Layout:**

A single centred card on an otherwise empty page. The top nav is **not** rendered on this page — there is nothing to navigate to.

```
┌─────────────────────────────┐
│                             │
│      Voxio Admin            │  ← Wordmark, type.h1
│                             │
│      Sign in to continue.   │  ← Body copy
│                             │
│   ┌─────────────────────┐   │
│   │  Sign in with GitHub│   │  ← Primary CTA button
│   └─────────────────────┘   │
│                             │
└─────────────────────────────┘
```

| Element | Detail |
|---|---|
| Card width | 360 px |
| Card padding | 32 px |
| Card border | 1 px `border.default`, 8 px corner radius |
| Card position | Centred horizontally and vertically on the viewport |
| Wordmark | `type.h1`, `text.primary`, centred, no logo glyph |
| Body copy | "Sign in to continue." — `type.body`, `text.secondary`, centred, 8 px top margin |
| Button | Full card width, primary CTA style (gold). Label: "Sign in with GitHub". 24 px top margin from body copy. Clicking navigates to `/.auth/login/github?post_login_redirect_uri=/admin/events`. |

**"Access denied" variant:** when the user is signed in but not in the `admin` role, the same card layout shows:

- Wordmark (unchanged)
- Body copy: "Your GitHub account does not have admin access. Contact engineering to be added."
- Single secondary button: "Sign out" → `/.auth/logout`

No "request access" form. Admin invites happen out of band via the SWA portal.

### 4.2 Events list — `/admin/events`

The primary triage surface. The page is dominated by a single table; everything else (filter bar, pagination) frames it.

**Layout (top to bottom):**

| Zone | Height | Notes |
|---|---|---|
| Page title row | 32 px | "Events" — `type.h1`, left-aligned. Right-aligned: an "Export labelled" secondary button linking to `/admin/export` with current filters preserved as query string. |
| Filter bar | 56 px (single row) | See §4.2.1 |
| Active filter pills | auto (0–32 px) | See §4.2.2. Hidden when no filters applied. |
| Table | flexible | See §4.2.3 |
| Pagination row | 48 px | See §4.2.4 |

#### 4.2.1 Filter bar

Single horizontal row. Inputs left-aligned with 8 px gap between them. Right-aligned: a single "Apply" button (secondary style) and a "Clear" link.

| Field | Control | Width |
|---|---|---|
| Date range | Date range picker (shadcn `<DateRangePicker>`, two stacked dates with a separator) | 240 px |
| Intent | Single-select dropdown, options = the 13 intents from `VoiceCommand` plus "Any intent" | 160 px |
| Parser path | Single-select dropdown, options = `PersonalisationAlias` / `PersonalisationMemory` / `FoundationModels` / `NLModel` / `KeywordRegex` / `Unknown` / "Any path" | 160 px |
| Outcome | Single-select dropdown, options = `confirmed` / `cancelled` / `timedOut` / `unknown` / "Any outcome" | 144 px |
| Locale | Single-select dropdown, options = `en-US` / `da-DK` / "Any locale" | 120 px |
| Flag | Single-select dropdown, options = `likelyMisparse` / `recoverableUnknown` / `broadcast` / "Any flag" / "No flags" | 144 px |
| Search | Text input with placeholder "Search anonymised transcription…" | flexible / fills remaining width |

Filters apply on submit (Apply button or Enter in the search field) — not on every keystroke. The applied filter set is reflected in the URL query string so the page is bookmarkable and shareable.

The filter bar is sticky to the top of the table area (not the viewport) — when the user scrolls a long table, the filter bar stays at the top of the table viewport. Implementation: `position: sticky; top: 56px` (below the top nav).

#### 4.2.2 Active filter pills

Below the filter bar, when any filter is applied, a row of small pills shows what is currently filtered.

| Pill | Style |
|---|---|
| Background | `info.bg` |
| Foreground | `info.fg` |
| Padding | 4 px vertical, 8 px horizontal |
| Border radius | 4 px |
| Font | `type.small` |
| Trailing icon | `xmark` 10 px, removes the filter and re-applies |

Example pills: `Date: 2026-04-01 – 2026-05-04 ×`, `Intent: playFavorite ×`, `Flag: likelyMisparse ×`.

#### 4.2.3 Events table

Column layout (left to right, total 1248 px usable inside 24 px page padding on a 1280 px viewport):

| Column | Width | Header | Cell content | Notes |
|---|---|---|---|---|
| Timestamp | 152 px | "Timestamp" | `2026-05-04 14:32:11Z` (`type.mono`) | Sortable. Default sort: descending. |
| Locale | 64 px | "Locale" | `en-US` / `da-DK` (`type.smallStrong`) | Centred |
| Transcription | flexible (~480 px) | "Transcription" | Anonymised transcription, single-line truncate with `…`, full text on hover via tooltip | Most prominent column |
| Intent | 144 px | "Intent" | Intent name (`type.body`) | |
| Parser | 128 px | "Parser" | Parser path (`type.smallStrong`, `text.secondary`) | |
| Outcome | 112 px | "Outcome" | Coloured pill — see below | |
| Flags | 96 px | "Flags" | Flag badges — see below. Empty cell if no flags. | |
| Label | 72 px | "Label" | Label badge if labelled, "—" if not | |

**Outcome pill styling:**

| Outcome | Pill background | Pill foreground |
|---|---|---|
| `confirmed` | `success.bg` | `success.fg` |
| `cancelled` | `bg.muted` | `text.secondary` |
| `timedOut` | `warning.bg` | `warning.fg` |
| `unknown` | `danger.bg` | `danger.fg` |

**Flag badge styling:**

All three flag types (`likelyMisparse`, `recoverableUnknown`, `broadcast`) render as compact badges, 4 px vertical / 8 px horizontal padding, `type.smallStrong` uppercase, 4 px border radius. Multiple flags stack horizontally with 4 px gap; if the cell would overflow the 96 px column width, the additional flags collapse into a "+N" indicator with a tooltip.

| Flag | Background | Foreground | Display text |
|---|---|---|---|
| `likelyMisparse` | `warning.bg` | `warning.fg` | "MISPARSE" |
| `recoverableUnknown` | `info.bg` | `info.fg` | "RECOVER" |
| `broadcast` | `bg.muted` | `text.secondary` | "BCAST" |

**Label badge styling (Label column):**

| Label state | Background | Foreground | Display text |
|---|---|---|---|
| Unlabelled | (no badge) | `text.placeholder` | "—" |
| `correct` | `accent.gold.subtle` | `text.primary` | "✓ Correct" |
| `incorrect` | `danger.bg` | `danger.fg` | "✗ Incorrect" |
| `discard` | `bg.muted` | `text.secondary` | "Discard" |

**Row interaction:**

| State | Behaviour |
|---|---|
| Rest | White (`bg.canvas`) background |
| Hover | `bg.subtle` background, cursor `pointer` |
| Focus (keyboard) | `bg.subtle` background, 2 px `accent.gold` left border inside the row |
| Active (mouse-down) | `bg.muted` background |
| Selected (visited via the "back" navigation from the detail page) | `bg.subtle` background with persistent 2 px `accent.gold` left border |

Clicking anywhere on a row navigates to `/admin/events/{id}`. The row is the link element (semantic `<tr role="link">` or wrapped in a `<Link>` per shadcn/Tailwind convention; see §6 issue 2).

**Empty table:**

When filters yield zero results, the table area shows a centred message:

> No events match the current filters.
> Try clearing or relaxing them.

with a single "Clear filters" link button. Empty state height: 240 px.

#### 4.2.4 Pagination

Right-aligned at the bottom of the table. shadcn `<Pagination>` component. Page size selector on the left.

| Element | Detail |
|---|---|
| Page size dropdown | "50 per page" / "100 per page" / "200 per page". Default 50. Persists across navigation in the URL query string (`?per=100`). |
| Result count | "Showing 1–50 of 12,847" — `type.small`, `text.secondary`, left of the pagination controls |
| Previous / Next | Icon buttons, 32 × 32 px, with `chevron-left` / `chevron-right` |
| Page indicator | "Page 3 of 257" — `type.small`, centred between Previous and Next |

Cursor-based pagination is acceptable backend-side; the visual treatment above maps cleanly onto either offset or cursor.

### 4.3 Event detail — `/admin/events/{id}`

Two-column layout. Left column shows the event data read-only; right column is the labelling control. The split is fixed (not user-resizable) at 60 / 40.

```
┌──────────────────────────────────────┬───────────────────────┐
│  ← Back to events                    │                       │
│                                      │   Label this event    │
│  Event a1b2c3d4-…                    │                       │
│  ────────────────────────────────    │   ○ Correct           │
│  Timestamp                           │   ○ Incorrect         │
│  2026-05-04 14:32:11.123Z            │     [Intent dropdown] │
│                                      │   ○ Discard           │
│  Locale                              │                       │
│  en-US                               │   ┌───────────────┐   │
│                                      │   │  Save label   │   │
│  Anonymised transcription            │   └───────────────┘   │
│  "play favorite [HASH:a1b2c3d4]"     │                       │
│                                      │   Last labelled by    │
│  Parser → Intent                     │   mrandersen          │
│  FoundationModels → playFavorite     │   2026-05-04 09:11Z   │
│  ...                                 │                       │
└──────────────────────────────────────┴───────────────────────┘
```

#### 4.3.1 Header strip

Above the two columns, a 40 px header strip:

| Element | Detail |
|---|---|
| Back link | "← Back to events" — `type.body`, `text.secondary`, hovers to `text.primary`. Goto `/admin/events` and restores filters from `document.referrer` (or query state if available). 16 px right margin. |
| Event id | `Event a1b2c3d4-…` (truncated UUID) — `type.h2`, `text.primary`. Full UUID available on hover. |
| Spacer | Fills remaining width |
| Copy id button | Icon button with `clipboard` icon, copies the full UUID to clipboard; shows a success toast on copy. |

#### 4.3.2 Left column — event data (read-only)

A flat list of key/value pairs, one per row. Each pair is a 64 px row: 12 px label (`type.h3`, `text.secondary`, uppercased), 4 px gap, value at `type.body`. No card border between fields; only 1 px `border.default` separators between rows.

Field order:

1. Event id (`type.mono`, full UUID)
2. Device id (`type.mono`, full UUID)
3. Timestamp (`type.mono`, ISO 8601)
4. Locale
5. App version (`type.mono`)
6. Model version (`type.mono`)
7. Anonymised transcription — `type.body`, displayed inside a `bg.subtle` rounded panel with 12 px padding to make the content visually distinct. 1-line wrap, no truncation.
8. Parser path
9. Original intent
10. Slots — JSON object pretty-printed in `type.mono` with 2-space indent inside a `bg.muted` panel
11. Outcome — using the same outcome pill style from §4.2.3
12. Flags — same flag-badge styling as §4.2.3, or "(none)" in `text.placeholder` if empty

No "edit" affordance on any of these fields. The original event row is immutable per US-A2.

#### 4.3.3 Right column — labelling control

A vertically stacked form. Card-style container with 1 px `border.default`, 8 px corner radius, 24 px padding.

**Card title:** "Label this event" — `type.h2`, 16 px bottom margin.

**Action picker:** a vertical radio-button group (shadcn `<RadioGroup>`) with three options:

| Option | Visual cue when selected |
|---|---|
| **Correct** — "The parser got this right." | Radio dot in `accent.gold`, label text `text.primary` |
| **Incorrect** — "The parser was wrong; the right intent was…" | Radio dot in `accent.gold`, label text `text.primary`. Reveals an inline intent dropdown directly below. |
| **Discard** — "Not useful for training (e.g. background noise)." | Radio dot in `accent.gold`, label text `text.primary` |

Each option's label is two lines: the bold action name followed by a `type.small` `text.secondary` description.

**Intent dropdown (Incorrect-only):** appears with a 4 px vertical expand animation when "Incorrect" is selected; collapses when not. shadcn `<Select>` with options = the 13 intents from `VoiceCommand` (English display names). The dropdown is required when "Incorrect" is selected — the Save button disables until a value is picked.

**Save button:** Primary CTA style (gold background, white text, 36 px tall). Label: "Save label". Full-width inside the card. 24 px top margin from the action picker.

**Save button states:**

| State | Background | Foreground | Cursor | Notes |
|---|---|---|---|---|
| Idle (clean form, no action selected) | `bg.muted` | `text.placeholder` | `not-allowed` | Disabled |
| Idle (action selected, ready) | `accent.gold` | `text.inverse` | `pointer` | Enabled |
| Loading (POST in flight) | `accent.gold.hover` | `text.inverse` | `wait` | Spinner replaces label text; "Saving…" announced to screen readers |
| Success (after save) | `accent.gold` | `text.inverse` | `pointer` | Resets to idle after success toast appears |
| Error | `accent.gold` | `text.inverse` | `pointer` | Inline error message renders below button in `danger.fg`; button stays enabled so user can retry |

**Existing label section (only when event already has a label):** below the Save button, a 1 px top divider, then a `type.h3` label "Last labelled by", followed by the labeller's GitHub username and the labelled-at timestamp. If the user changes the action and re-saves, this section updates after the next page load (or after the success toast confirms).

**Keyboard shortcuts (visible as hints):**

A small `type.small` `text.secondary` line at the bottom of the card:

> `C` Correct  ·  `I` Incorrect  ·  `D` Discard  ·  `Enter` Save

Pressing `C` / `I` / `D` selects the corresponding radio option. Pressing `Enter` saves when the form is valid.

### 4.4 Export — `/admin/export`

A simple form on a card. The page exists to give the export action its own URL; the same export action is available from the events page header.

**Layout:** centred card, 640 px wide, 32 px padding.

**Card title:** "Export labelled events" — `type.h1`.

**Body copy:** "Downloads a CSV containing one row per labelled event. Filters below mirror the events list and apply to the export. Unlabelled events are excluded." — `type.body`, `text.secondary`, 24 px bottom margin.

**Filter form:** identical to the events list filter bar (§4.2.1), but laid out vertically as a form (each input on its own row, 12 px gap). Filters here also write to the URL query string so the export URL is shareable.

**Filename preview:** below the filters, a `type.mono` line previewing the resulting filename:

> `voxio-labelled-events-2026-05-04.csv`

**Download button:** Primary CTA style (gold). Full width. Label: "Download CSV".

**Download button states:**

| State | Foreground | Trailing icon | Notes |
|---|---|---|---|
| Idle | "Download CSV" | `download` | Default |
| Loading (request sent, awaiting first byte) | "Preparing export…" | spinner (rotating `loader-2`) | Button disabled |
| Downloading (streaming bytes) | "Downloading… 12,847 rows" | spinner | Row counter updates live from streamed response if feasible; otherwise just "Downloading…" |
| Success | "Download CSV" | `download` | Resets after a 4-second toast: "Exported 12,847 labelled events." |
| Error | "Download CSV" | `download` | Inline error message below the button in `danger.fg`: "Export failed: {reason}". Button re-enabled. |

**Empty result note:** if filters yield zero labelled events, the button still triggers a download (the CSV will contain only the header row per US-A3). A `type.small` notice below the button reads: "Current filters match 0 labelled events. The exported file will contain only the header row."

### 4.5 Stats — `/admin/stats`

A read-only dashboard. No filters except a date range; no row-level interaction.

**Layout (top to bottom):**

| Zone | Notes |
|---|---|
| Page title row | "Stats" + a date range picker on the right (default: last 7 days). The picker has preset options: "Last 24 hours", "Last 7 days", "Last 30 days", "Custom…" |
| Top stats row | Four "metric cards" showing top-line counts |
| Aggregation tables row | Three side-by-side tables showing counts by intent, by outcome, by parser path |
| Locale row | One full-width table with counts per locale |

**Metric cards (top stats row):**

Four equal-width cards (each ~24 % width with 16 px gaps), 96 px tall. Each card has:

- Field label at top (`type.h3`, uppercased, `text.secondary`)
- Value at centre (`type.h1`, but rendered at 32 px / 40 px line-height for emphasis, weight 600)
- Optional delta line at bottom (`type.small`, `success.fg` or `danger.fg`) — e.g. "+12% vs prev. period"

| Card | Field label | Value | Delta source |
|---|---|---|---|
| 1 | "TOTAL EVENTS" | Sum of events in range | vs same-length previous period |
| 2 | "DISTINCT DEVICES" | `COUNT(DISTINCT device_id)` | vs prev. period |
| 3 | "MISPARSE FLAGS" | Count of events flagged `likelyMisparse` | vs prev. period |
| 4 | "LABELLED" | Count of events with at least one label | (no delta — labelling is an absolute counter) |

If there is insufficient prior-period data, the delta line shows "—" instead of a percentage.

**Aggregation tables (counts by intent / outcome / parser path):**

Three side-by-side cards. Each card is a table with two columns: the dimension value on the left, the count on the right (right-aligned numerals, `type.mono`). Sorted by count descending. Maximum visible rows: 13 for intent, 4 for outcome, 6 for parser. No "show more" — the spec defines exact maxima.

Each card title at `type.h2`. Each row: 32 px tall, 1 px `border.default` separator. Numeric column right-aligned and right-padded by 16 px.

**Locale table (full width):**

A four-column table: Locale, Events, Distinct devices, Misparse rate (% of events with `likelyMisparse`). Two rows: `en-US`, `da-DK`. Misparse rate column uses a coloured cell — green (`success.fg` text on `success.bg`) when ≤ 5 %, warning (`warning.fg` on `warning.bg`) when 5–15 %, red (`danger.fg` on `danger.bg`) when > 15 %. Thresholds are not user-tunable in v1.

**Loading state:** the entire stats page shows a skeleton placeholder (shadcn `<Skeleton>`) for each card and table while the stats query runs. Skeleton bars use `bg.muted`. Page shell (top nav, title) renders immediately.

**Empty state:** if the date range yields zero events, every metric card shows "0", every aggregation table shows "(no events in this range)" centred in the card body. No error.

### 4.6 Deletion — `/admin/deletion`

A purposefully sober page. The destructive action is gated by a typed confirmation, the button is unmistakably red, and the page structure makes it impossible to delete by accident.

**Layout:** centred card, 560 px wide, 32 px padding.

**Card title:** "Delete telemetry for a device" — `type.h1`.

**Warning panel:** at the top of the card, before any input, a 1-line warning panel.

| Element | Detail |
|---|---|
| Background | `danger.bg` |
| Foreground | `danger.fg` |
| Border-left | 4 px solid `danger.fg` |
| Padding | 12 px vertical, 16 px horizontal |
| Icon | `alert-triangle` 16 px |
| Text | "This action is permanent. All events and labels for the given device ID will be deleted with no recovery." |

**Form:**

Two vertically stacked inputs:

1. **Device ID** — text input. Label "Device ID". Placeholder "e.g. 550e8400-e29b-41d4-a716-446655440000". Validation: must be a valid UUID v4. On invalid format, the input border turns `danger.fg` and an inline message reads "Enter a valid UUID."
2. **Confirmation** — text input. Label "Type DELETE to confirm". Placeholder "DELETE". Helper text: "Required. Case-sensitive." On submit attempt with a value other than the literal string `DELETE`, an inline error reads "Type DELETE to confirm before submitting." (matches the verbatim string in the functional spec error states.)

**Submit button:** Destructive style (red).

| Property | Value |
|---|---|
| Background | `danger.fg` |
| Foreground | `text.inverse` |
| Padding | 12 px vertical, 24 px horizontal |
| Width | Full card width |
| Height | 44 px |
| Hover | Background `#8A1818` (10 % darker) |
| Disabled | Background `bg.muted`, foreground `text.placeholder` |
| Label | "Delete all telemetry for this device" |
| Trailing icon | `trash-2` 16 px |

The button is disabled until **both** the device ID is valid AND the confirmation field contains exactly `DELETE`.

**Result panel (replaces the form on submit):**

After the submit completes, the form area is replaced by a result panel. Three result variants:

| Variant | Panel background | Heading | Body |
|---|---|---|---|
| Success | `success.bg` | "Deleted." | "Deleted 1,243 events and 87 labels for device `550e8400-…`." (counts come from the API response) |
| Idempotent (no data) | `info.bg` | "Nothing to delete." | "No data found for that device ID. Nothing to delete." |
| Failure | `danger.bg` | "Deletion failed." | "Deletion failed. Please try again or contact engineering." with a small `type.mono` block showing the error reference (request id) for engineering follow-up. |

A "Delete another" secondary button appears below the result panel and resets the form to its empty initial state.

---

## Section 5 — Component Library

The recommended component library is **shadcn/ui** — a Tailwind-based, copy-into-repo (not npm-dependency) collection of accessible primitives built on Radix UI. shadcn/ui matches the requirements of this site:

- Keyboard-first by default (focus rings, ARIA attributes, escape handling)
- Composable — primitives, not "blocks", so the dense table layout is not fighting against an opinionated default
- No theming runtime — the warm-neutral palette is implemented as Tailwind tokens directly
- Source code in the repository, so customisation does not require forking

### 5.1 Components per screen

| Screen | shadcn components used |
|---|---|
| All pages | `<Button>`, `<DropdownMenu>` (user menu), `<Toast>` / `<Toaster>` |
| Sign-in | `<Button>`, `<Card>` |
| Events list | `<Table>`, `<Input>` (search), `<Select>` (filters), `<DateRangePicker>` (custom — see below), `<Badge>` (flag/outcome pills), `<Pagination>`, `<Tooltip>` (truncated transcription) |
| Event detail | `<Card>`, `<RadioGroup>`, `<Select>`, `<Button>`, `<Separator>`, `<Skeleton>` (loading state) |
| Export | `<Card>`, `<Input>`, `<Select>`, `<DateRangePicker>`, `<Button>` |
| Stats | `<Card>`, `<Table>`, `<DateRangePicker>`, `<Skeleton>` |
| Deletion | `<Card>`, `<Input>`, `<Button>`, `<Alert>` (warning panel) |

### 5.2 Custom components (not in shadcn out of the box)

| Component | Reason |
|---|---|
| `<DateRangePicker>` | shadcn ships a `<Calendar>` and a `<Popover>`, but a polished date-range picker with preset shortcuts ("Last 7 days") is a recipe rather than a component. Build by composing `<Popover>` + `<Calendar>` with two date inputs and a preset list. ~150 lines of code. |
| `<FilterPill>` | The active-filter pills below the filter bar are simple enough to write directly: a `<div>` with badge styling and a trailing `<button>` with an `xmark`. No shadcn primitive needed. |
| `<MetricCard>` | The four top-row stats cards on `/admin/stats` are a thin wrapper around `<Card>` with prescribed slots (label, value, delta). Keep as a local component in the project. |
| `<DeleteResultPanel>` | The success/idempotent/failure variants of the deletion result are a small switch component. Local to the deletion page. |

No external charting library is required for v1. The stats page uses tables, not bar/line charts. (Issue 5 in §6 flags this for re-evaluation in v1.4.)

---

## Section 6 — UX/UI Issues and Open Questions

### Issue 1 — Pagination strategy: cursor vs offset

**Description:** The events list specifies pagination but the functional spec leaves room for either cursor-based or offset-based pagination on the server. Cursor-based handles the "events stream is constantly being appended" case more cleanly (a new event between page 1 and page 2 doesn't shift page 2's contents); offset is simpler to implement and supports the "Page 3 of 257" indicator more naturally.

**Impact:** If the team chooses cursor-based pagination, the "Page 3 of 257" indicator becomes "Page 3" (no total) because the total is non-trivial to compute on a cursor stream. The Result count ("Showing 1–50 of 12,847") similarly becomes "Showing 50 events".

**Recommendation:** Use offset-based pagination for v1. The events table is small enough (≤ 5 million rows projected) that an offset query with a sensible index is fast, and the affordance of "Page X of Y" is more useful for a labeller than the alternative.

**Decision needed from:** Engineering (DB query approach).

### Issue 2 — Row-as-link semantics

**Description:** The events table specifies that clicking anywhere on a row navigates to the detail page. The semantically correct way to do this varies by framework — Next.js' `<Link>` can wrap a `<tr>` only with `legacyBehavior` and a custom child, or alternatively the entire `<tr>` becomes a `<button>` (which breaks table semantics) or each cell becomes its own `<Link>` (which means the link target is invisible to the user — they can't right-click "Open in new tab" on the row).

**Recommendation:** Make the timestamp cell the primary `<Link>` and apply `onClick` handlers to the rest of the row that navigate via the router. This satisfies right-click affordance for at least one cell while keeping the row clickable. Alternative: wrap each cell's content in a `<Link>`. Designer prefers the former; engineering should validate.

**Decision needed from:** Engineering.

### Issue 3 — Where the export filename is generated

**Description:** The export filename includes the current date — `voxio-labelled-events-2026-05-04.csv`. The functional spec is silent on whether this is the date the export was triggered (client clock) or the latest event's timestamp (server). They will usually agree, but a date-range filter ending two months ago would make the filename misleading.

**Recommendation:** Use the export trigger date (today). It matches the user's mental model: "the file I downloaded today". If the team prefers, append the filter date range to the filename: `voxio-labelled-events-2026-04-01-to-2026-05-04.csv`.

**Decision needed from:** Engineering / data lead.

### Issue 4 — "Discard" semantics in the export CSV

**Description:** The functional spec's CSV column list includes `label_action` with values `correct` / `incorrect` / `discard`. The retraining script's expected behaviour for `discard` rows is undefined in the spec — does the script ignore them, treat them as a negative signal, or include them as a "noise" class? This is a data lead question that the design surfaces but does not answer.

**Recommendation:** Surface it explicitly in the export page body copy: "Discarded events are included in the CSV as `label_action=discard` and should be filtered out by the retraining script unless explicitly used as a noise class."

**Decision needed from:** Data lead.

### Issue 5 — Stats page becomes too sparse without charts

**Description:** The current stats spec is tables + four metric cards. Once volume passes ~10k events/day, time-series patterns ("misparse rate spiked on April 14") become invisible to a static table. The team will likely want a 7-day daily-events sparkline and a 7-day misparse-rate sparkline within months.

**Recommendation:** Defer for v1. Document for v1.4 that adding `recharts` (lightweight, ~30 KB gzipped) and two sparkline components on the stats page will be the natural next step. No design work is needed in v1; the page layout has space for charts to slot into the top row above the metric cards.

**Decision needed from:** Data lead — confirm the v1 spec is acceptable without charts.

### Issue 6 — Confirming labels with keyboard shortcut conflicts

**Description:** The event detail page documents `C` / `I` / `D` / `Enter` shortcuts. If the user clicks into the (only when "Incorrect" is selected) intent dropdown and types, the `D` shortcut is intercepted by the dropdown's typeahead. This is correct behaviour — typeahead in a dropdown should win over a global shortcut.

**Recommendation:** Implement shortcuts as global keydown handlers gated by `event.target` not being inside an `<input>`, `<select>`, or contenteditable element. Standard shadcn behaviour. Document the gate in the implementation README.

**Decision needed from:** No external decision needed. Flag for implementer awareness.

### Issue 7 — How "previous label" is surfaced on the detail page when the same admin re-labels

**Description:** US-A2 says one label per event per admin, with the most recent winning. The detail page currently shows "Last labelled by `mrandersen` on 2026-05-04 09:11Z". If `mrandersen` re-saves with a different action, the previous version is preserved server-side per the resolved decision but is invisible in the UI.

**Recommendation:** v1 surfaces only the most recent label. Add a "Label history" expander in v1.4 if the team finds the audit trail useful. Note in the spec that re-labelling silently overwrites the visible state.

**Decision needed from:** Data lead.

### Issue 8 — Toast collisions during bulk labelling sessions

**Description:** A labeller working through 200 events will dismiss the success toast 200 times. A 5-second auto-dismiss is slightly too long for back-to-back work; a 1.5-second auto-dismiss feels rushed when an admin actually wants to read it.

**Recommendation:** Auto-dismiss success toasts at 2 seconds; auto-dismiss error toasts at 8 seconds (or require manual dismissal — preferred). Verify in user testing. Default to 2 s success / persistent error if uncertain.

**Decision needed from:** Designer + first labeller in a paired session.

### Issue 9 — Skeleton vs spinner on the events table

**Description:** The events table loads after a query that hits the database. On a warm Neon connection, the query returns in 50–200 ms — fast enough that no loading state is needed. On a cold start the query may take 3–5 seconds. The spec is silent on which loading affordance to use.

**Recommendation:** Use a skeleton table (50 grey rows of `bg.muted`) for any load that exceeds 300 ms. Below 300 ms, render no loading state — the page transition itself is the feedback. Implementation: render the skeleton on initial mount, swap to data once the query resolves; if the query resolves in < 300 ms the skeleton flashes briefly which is acceptable.

**Decision needed from:** Engineering — confirm the 300 ms threshold is achievable with React Suspense / Next.js streaming.

### Issue 10 — Authentication failure surface

**Description:** The functional spec routes unauthenticated users via SWA to `/.auth/login/github` directly, never showing the `/admin` landing page. The "Access denied" variant of the landing page is only reached when the user is signed in but not in the `admin` role. In practice, the SWA portal-managed allow-list means an admin-not-in-list user will see Azure's default 403 page first, not our landing page.

**Recommendation:** Confirm with engineering whether SWA's `staticwebapp.config.json` can be configured with a `responseOverrides` block that redirects 403s back to `/admin` so our designed "Access denied" card is the first thing the user sees. If not, accept that the Azure default 403 is what unauthorised users actually encounter, and document `/admin` as a developer-facing fallback only.

**Decision needed from:** Engineering.

---

## Section 7 — Accessibility Requirements

### 7.1 Keyboard navigation

Every primary action is reachable by keyboard:

- Tab order on `/admin/events`: top nav links (left to right) → user menu → filter inputs (left to right) → Apply → Clear → first table row → subsequent table rows (Down arrow) → pagination prev → page-size selector → pagination next.
- Tab order on `/admin/events/{id}`: Back link → Copy id button → (skips the read-only data column entirely — it is non-interactive) → labelling radio group → intent dropdown (when visible) → Save button → Sign out via top nav user menu.
- Down/Up arrows move focus between rows in the events table, not just Tab.
- Enter on a focused row navigates to the detail page.
- Escape closes any open dropdown, popover, or toast.
- The labelling page exposes `C` / `I` / `D` / `Enter` shortcuts as documented in §4.3.3.

Focus rings use the shadcn default 2 px solid outline, but recoloured to `accent.gold` (rather than the default blue) for consistency with the brand. Focus rings render with 2 px offset so they are visible against `bg.subtle` row backgrounds.

### 7.2 ARIA labels

Icon-only controls have explicit `aria-label`:

| Control | aria-label |
|---|---|
| Top nav user menu trigger | "User menu for {username}" |
| Pagination previous | "Previous page" |
| Pagination next | "Next page" |
| Toast dismiss | "Dismiss notification" |
| Active filter pill xmark | "Remove {filter name} filter" |
| Copy event id button | "Copy event ID to clipboard" |
| Back to events link | (text "← Back to events" is its own label; the arrow is decorative `aria-hidden`) |

The labelling radio group has `role="radiogroup"` with `aria-labelledby` pointing to the "Label this event" heading. Each option's description is associated via `aria-describedby`.

The deletion form's typed-`DELETE` confirmation has `aria-required="true"` and `aria-describedby` pointing to the helper text.

### 7.3 Focus management

- After a successful label save, focus moves to the next row's link in the events table when the user navigates back via the Back link. This requires storing the last-focused row in `sessionStorage` keyed by the events list query string.
- After a successful deletion, focus moves to the "Delete another" button on the result panel.
- After a toast dismisses, focus stays where it was — toasts do not steal focus.
- On modal-like surfaces (the user menu dropdown, the filter selects), focus is trapped inside the popover until it closes; on close, focus returns to the trigger.

### 7.4 Screen reader announcements

- Toast appearance is announced via `aria-live="polite"` (success, info) or `aria-live="assertive"` (error, deletion result).
- Form validation errors are announced when they appear (the inline error has `role="alert"`).
- Loading states (download button, save button) update `aria-busy="true"` on the button; the live region announces "Saving label" or "Preparing export" once.
- Filter changes update the result count; the result count node has `aria-live="polite"` so screen readers hear "Showing 1 to 50 of 12,847 events" when filters change.

### 7.5 Colour contrast

All text/background combinations meet WCAG 2.1 AA (4.5:1 for body text, 3:1 for large text and UI components):

| Combination | Ratio | Compliant |
|---|---|---|
| `text.primary` (`#1F1D1A`) on `bg.canvas` (`#FFFFFF`) | 14.7:1 | AAA |
| `text.secondary` (`#6B665D`) on `bg.canvas` | 5.1:1 | AA |
| `text.placeholder` (`#A09488`) on `bg.canvas` | 2.6:1 | Fails AA (deliberate — placeholder, not content) |
| `text.inverse` (`#FFFFFF`) on `accent.gold` (`#C8A97E`) | 2.7:1 | **Fails AA** — see Issue below |
| `text.inverse` on `danger.fg` (`#A11C1C`) | 6.4:1 | AA |
| `success.fg` on `success.bg` | 7.4:1 | AAA |
| `warning.fg` on `warning.bg` | 6.1:1 | AA |
| `danger.fg` on `danger.bg` | 7.2:1 | AAA |
| `info.fg` on `info.bg` | 8.1:1 | AAA |

**Outstanding contrast issue:** The white-on-gold combination on the primary CTA button fails AA at the current `accent.gold` value of `#C8A97E`. Three resolution paths:

1. Darken the accent gold to `#A48355` (reaches 4.5:1 with white). Visually deviates from the iOS app accent.
2. Use `text.primary` (dark) on `accent.gold` instead of white. Reaches 6.0:1. Visually unconventional for a primary CTA but readable.
3. Add a subtle 1 px `text.primary @ 0.6` text shadow to the button label to improve perceived contrast without changing the colour. WCAG does not formally credit text shadows; this is a workaround for visual feel, not for compliance.

**Recommendation:** Use option 2 (dark text on gold). The button still reads as a primary action because of size, position, and the gold accent; legibility wins. Document in §8 as a flagged decision that may revisit in v1.4 once the team has had the site open for a week.

### 7.6 What is NOT covered in v1

- Localisation of the admin UI itself. The admin site is English-only. The event data displayed includes both `en-US` and `da-DK` events, but the UI chrome (button labels, headings) is in English regardless of admin's browser language.
- Reduced motion preferences. The site has near-zero animation; the only motion is the inline expand of the intent dropdown and toast slide-in. Both should be wrapped in `prefers-reduced-motion` checks but the design does not specify alternative motion. Defer to shadcn defaults.
- Forced-colours mode (Windows high contrast). shadcn components handle this acceptably out of the box; no custom design work required for v1.
- Formal WCAG 2.1 AA audit. The site is internal; a self-audit by the implementer using axe-core in CI is sufficient for v1.

---

## Section 8 — Out of Scope (v1)

- **Dark mode.** Light theme only. Adding dark mode requires re-tuning the warm-neutral palette and re-checking contrast. Deferred indefinitely.
- **Mobile / tablet layout.** Desktop-only. No hamburger menu, no responsive table collapse, no touch-target minimum.
- **Multi-language admin chrome.** English-only UI in v1.
- **Dashboard charts.** Stats page uses tables; sparklines and time-series charts deferred to v1.4 (Issue 5 in §6).
- **Bulk labelling actions.** Each event is labelled individually. No "label all selected as Correct" bulk operation. The functional spec explicitly excludes this.
- **Saved filter views.** Filters live in the URL query string; the user can bookmark a filtered view but cannot save a named view ("Misparses last 7 days"). Deferred.
- **Admin profile management.** Username is read-only from `clientPrincipal`. There is no "edit your display name" page, no avatar upload, no preferences. Deferred indefinitely.
- **Activity feed of recent admin actions.** The functional spec defers an audit log; the UI follows.
- **CSV preview before download.** Download triggers immediately. No "preview first 10 rows" affordance.
- **Multi-tab synchronisation.** If two tabs are open and one labels an event, the other tab does not update until refreshed. Deferred.

---

## Appendix A — Component icon reference

All icons are from the `lucide-react` library (the icon set shadcn/ui ships with by default).

| Action | Icon | Size at use |
|---|---|---|
| User menu trigger | `chevron-down` | 12 px |
| Active filter pill remove | `x` | 10 px |
| Pagination previous | `chevron-left` | 16 px |
| Pagination next | `chevron-right` | 16 px |
| Copy event ID | `clipboard` | 16 px |
| Back to events | (no icon — text arrow `←` is part of the link label) | n/a |
| Sort indicator (table headers, when sortable) | `chevron-up` / `chevron-down` | 12 px |
| Download button | `download` | 16 px |
| Loading spinner | `loader-2` (rotating) | 16 px |
| Deletion warning | `alert-triangle` | 16 px |
| Delete button | `trash-2` | 16 px |
| Success toast | `check-circle` | 16 px |
| Error toast | `alert-circle` | 16 px |
| Info toast | `info` | 16 px |

---

## Appendix B — URL routing summary

| Path | Auth required | Renders |
|---|---|---|
| `/admin` | No | Sign-in landing card (or "Access denied" if signed in non-admin) |
| `/admin/events` | Yes (admin role) | Events list table |
| `/admin/events/{id}` | Yes (admin role) | Event detail two-column page |
| `/admin/export` | Yes (admin role) | Export form |
| `/admin/stats` | Yes (admin role) | Stats dashboard |
| `/admin/deletion` | Yes (admin role) | Deletion form |
| `/.auth/login/github` | No | SWA-managed GitHub OAuth flow |
| `/.auth/logout` | Yes | SWA-managed sign-out |

The top nav renders on every `/admin/*` path **except** `/admin` (sign-in landing). It is suppressed there because there is nothing to navigate to.

---

*End of design specification v1.0*
