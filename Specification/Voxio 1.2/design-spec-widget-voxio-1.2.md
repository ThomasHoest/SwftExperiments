# Design Specification: Voxio 1.2 Widgets
**Version:** 1.0  
**Status:** Draft  
**Date:** 2026-05-01  
**Platform:** iOS 26 (iPhone, portrait)  
**Design Language:** Liquid Glass  
**References:** design-spec-bo-voice-control v1.1, VoxioSpecification-1.1.md, research-findings-voxio-1.2.md, BeoColor.swift, DesignTokens.swift

---

## Design Philosophy

Widgets are ambient surfaces — they live on the Home Screen and in Control Center at all times, seen without intentional navigation. The Voxio widget must earn its place there by being instantly readable and genuinely useful with one tap. It cannot listen; it cannot speak. It controls.

The widget design follows the same visual principles as the main app: dark Liquid Glass on the navy orb background, warm gold accent used sparingly, restraint in everything. On iOS 26 the system automatically applies Liquid Glass rendering to widget backgrounds, which aligns perfectly with the established aesthetic. The design leans into this rather than fighting it.

The widget is not a miniaturised version of the main app. It is a purpose-built remote control tile: the right information at a glance, the right action in one tap.

---

## Design Principles (Widget-Specific)

1. **Glanceable first** — The user reads the widget before they tap it. Track name, playback state, and speaker name must be legible in under a second.
2. **One-tap actions only** — Every button is a single discrete action. No multi-step flows, no sheets, no navigation.
3. **Honest fallback** — When the app is not running, the widget says so plainly and offers to launch the app. It does not pretend to be functional.
4. **No microphone affordance** — There is no mic button, no waveform, no "say Voxio" prompt. Voice interaction on a widget means Siri. The widget's job is touch.
5. **Size contract** — `systemSmall` shows the minimum viable set of information and one primary action. `systemMedium` extends that with a secondary action row and more track detail. Never cram `systemMedium` content into `systemSmall`.

---

## Visual Language

Widgets on iOS 26 receive automatic Liquid Glass background rendering. This means:

- The widget container itself renders as a frosted glass panel — no custom background image is drawn inside the widget.
- Controls placed inside the widget use `Button(intent:)` which renders with the system's interactive glass treatment.
- The warm gold accent (`#C8A97E`) is used on the active playback indicator and on the play/pause button when playing — identical to its role on the main `SpeakerCard`.
- Text uses `BeoColor.labelPrimary` (`#F5F3F0`) for primary labels and `BeoColor.labelSecondary` (`#A09488`) for secondary labels.
- Icons use SF Symbols with `.hierarchical` rendering mode throughout.

The widget does not and cannot use `AppBackground.png` — the system-provided glass background replaces it. This is acceptable: the glass tile reads as a Voxio surface because of the token palette and the gold accent, not because of the background image.

---

## Section 1 — Widget UX Flows

### 1.1 Adding and Configuring a Widget

**Home-screen widget (systemSmall / systemMedium):**

1. User long-presses the Home Screen → enters jiggle mode → taps the "+" button.
2. Searches for "Voxio" in the widget gallery.
3. Selects `systemSmall` or `systemMedium`.
4. The widget is placed with the **default configuration**: the speaker that was active most recently when the app was last foregrounded. If no preference is stored, the first discovered speaker is used. If no speaker has ever been discovered, the empty state is shown (§1.5).
5. The user long-presses the placed widget → taps "Edit Widget".
6. A widget configuration sheet appears showing a picker: **"Speaker"** — lists all speakers the app has ever discovered, plus a **"Automatic (most recent)"** option at the top.
7. The user selects a speaker and dismisses. The widget immediately reflects the new configuration.

**Control Widget:**

1. User opens Control Center in edit mode (long-press the Control Center or Settings → Control Center → Customise) → taps "+" next to "Voxio".
2. After placement, the user can long-press the Control Center tile to configure it with the same speaker picker as above.
3. Default configuration: "Automatic (most recent)" — follows the active speaker from the app.

**Shared data contract:** Speaker selection, current playback state, and track metadata are written to an **App Group shared container** (`UserDefaults(suiteName: "group.T-Creative.Voxio")`) every time the main app receives a speaker event. The widget reads from this container. This is an engineering prerequisite — see §6 (UX/UI Issues) for the open question on entitlement setup.

---

### 1.2 App Running vs. App Not Running

| Scenario | Widget Behaviour |
|---|---|
| App is running in the background (the normal case) | Widget shows live playback state. `Button(intent:)` taps execute via `AudioPlaybackIntent`, which routes to the app process. Actions complete without opening the app. |
| App is fully terminated | The `AudioPlaybackIntent` cannot route to the app process. The widget transitions to the **App-not-running fallback state** (§2.5, §3.5). Buttons are replaced by a single "Open Voxio" button. |
| App is launching (cold start, < 2 s) | Widget shows the last-known state from the shared container. Buttons may fire before the app is fully initialised — the app must handle intent delivery gracefully on launch. |
| App is in the foreground | Widget shows live state. Actions execute normally. |

The app-not-running state is **detected at intent execution time**, not at widget render time. The widget always renders with the last-known state from the shared container. If the intent fails to route (the app is terminated), the intent's `perform()` method returns an error, and the widget refreshes to show the fallback. See §6 for the design decision on whether to detect this proactively via a heartbeat.

---

### 1.3 What Happens When the User Taps a Button

1. **Immediate visual feedback:** iOS 26 provides native press feedback on `Button(intent:)` — a subtle glass shimmer and scale-down matching the main app's `DarkGlassButtonTokens.pressedScale` (0.95). No custom animation is required or possible inside a widget.
2. **Intent fires:** The `AudioPlaybackIntent` executes in the main app process. The app performs the Mozart API call (e.g. `POST /playback/state`).
3. **Widget reloads:** On completion, the intent triggers `WidgetCenter.shared.reloadAllTimelines()` from within the main app. The widget fetches fresh state from the shared container and re-renders.
4. **Error case:** If the Mozart API call fails (speaker unreachable, timeout), the intent's `perform()` should write the error state to the shared container and reload timelines. The widget re-renders showing the last-known state with a brief error indicator (see §2.5 Error State).

**Round-trip expectation:** From button tap to widget re-render: target ≤ 3 seconds on a normal home network. This matches the existing v1.0 voice-command-to-action NFR.

---

### 1.4 Siri Voice Interaction Flow

Voice interaction with Voxio from a widget surface (lock screen, Home Screen) is mediated by Siri via `AppShortcutsProvider`. There is no mic button in any widget.

**Invocation phrases (English):**
- "Pause Voxio"
- "Play Voxio"
- "Mute Voxio"
- "Turn up the volume in Voxio"
- "Turn down the volume in Voxio"
- "Play [favorite name] in Voxio" (requires resolved favorite name parameter)

**Invocation phrases (Danish):**
- "Sæt Voxio på pause"
- "Afspil Voxio"
- "Slå Voxio fra"
- "Skru op for lyden i Voxio"
- "Skru ned for lyden i Voxio"

**On success:** Siri confirms the action with a brief spoken confirmation (system-provided). No sheet, no countdown. The intent fires directly — the 3-second auto-execute countdown from E-25 does **not** apply to Siri-invoked intents. Siri is the confirmation.

**On failure (speaker unreachable):** Siri speaks the error string: "I couldn't reach [Speaker Name]. Make sure Voxio is running and the speaker is on the network." The widget does not update (the action was not completed).

**On failure (app not running):** Siri speaks: "To control your speaker, open Voxio first." The user is not automatically deep-linked into the app.

**Important constraint:** Siri phrases map to `AppShortcutsProvider` — they invoke the same `AudioPlaybackIntent`-conforming intents as the widget buttons. The app must be running in the background for these to reach the Mozart network stack. This is the same constraint as widget button taps (§1.2).

---

### 1.5 Empty State — No Speakers Discovered Yet

Shown when:
- The widget is first added before the app has ever been launched.
- The app has been installed but no B&O speaker has been discovered on the network.
- The configured speaker has been removed from the shared container (e.g. after an app data reset).

**Content:**
- SF Symbol `hifispeaker.slash` (or `hifispeaker` with a slash overlay — confirm SF Symbols 6 availability), 24 pt, `BeoColor.labelSecondary`
- Label: "No speaker found" / "Ingen højttaler fundet" in `BeoType.caption` at 12 pt, `BeoColor.labelSecondary`
- Single action button: "Open Voxio" — a `Link` (not a `Button(intent:)`) that opens the app via URL scheme

This state applies equally to `systemSmall`, `systemMedium`, and the Control Widget. The Control Widget shows the empty state as a greyed-out tile with the "Open Voxio" label.

---

## Section 2 — Home-Screen Widget: systemSmall

### 2.1 Layout

The `systemSmall` widget is approximately 155 × 155 pt on a standard iPhone. It carries the minimum viable playback information and a single primary action.

```
┌─────────────────────────────┐
│  [hifispeaker.fill]  Beosound  │  ← Speaker name row
│  ─────────────────────────  │
│  Jazz Radio                 │  ← Track / station name (primary)
│  Spotify                    │  ← Source label (secondary)
│                             │
│    ┌──────────────────┐     │
│    │  ▶  Play         │     │  ← Primary action button
│    └──────────────────┘     │
└─────────────────────────────┘
```

**Vertical layout (top to bottom):**

| Zone | Content | Height (approx.) |
|---|---|---|
| Speaker header | Speaker icon + Speaker name | 20 pt |
| Track name | Primary track / station label | 38 pt (2-line max) |
| Source | Source name (Spotify, Deezer, etc.) | 16 pt |
| Spacer | Flexible | auto |
| Primary button | Play/Pause icon + label | 36 pt |

Internal padding: 12 pt on all edges (`Spacing.s12`).  
Spacing between zones: 4 pt (`Spacing.s4`).  
Button bottom margin: 4 pt above widget edge (to 12 pt edge padding = 16 pt from physical edge).

---

### 2.2 Controls

One button only in `systemSmall`. Its content and icon change based on playback state:

| Playback State | Button Label | Button Icon | Icon Tint |
|---|---|---|---|
| Playing | "Pause" | `pause.fill` | `BeoColor.accent` (`#C8A97E`) |
| Paused | "Play" | `play.fill` | `BeoColor.accent` (`#C8A97E`) |
| Stopped / Idle | "Play" | `play.fill` | `BeoColor.labelSecondary` |
| Loading / Unknown | "—" | `ellipsis` | `BeoColor.labelSecondary` |

The button uses the same visual pattern as `DarkGlassButton`: the iOS 26 `.glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: Capsule())` applied to a `Button(intent:)`. The 0.5 pt hairline border (`Color.white.opacity(0.15)`) is applied as a `.overlay(Capsule().strokeBorder(...))`.

Button width: fills available width minus 12 pt horizontal padding on each side, giving approximately 131 pt width.  
Button height: 36 pt (matching `DarkGlassButtonTokens.iconOnlySize` as a baseline — the labelled variant is taller at its natural size).

---

### 2.3 States

| State | Speaker Name | Track Name | Source | Button | Accent Treatment |
|---|---|---|---|---|---|
| **Playing** | Speaker name, primary weight | Track/station name, 1-line truncate | Source name | Pause — accent gold icon | Gold `play.fill` in button |
| **Paused** | Speaker name | Track/station name (last known) | Source name | Play — muted icon | Muted icon |
| **Stopped / Idle** | Speaker name | "—" (em dash) | "—" | Play — muted icon | None |
| **Loading** | Speaker name | Animated `…` (three dots, not animated in widget — static ellipsis) | "—" | Disabled `ellipsis` button | None |
| **App not running** | Speaker name (from cache) | Last known track or "—" | Last known source or "—" | "Open Voxio" link button | None — gold removed |
| **Empty** | "No speaker found" | — | — | "Open Voxio" link button | None |

**Playing state indicator:** A three-bar animated playback indicator is not available in widgets (no `TimelineAnimation` for continuous bars in WidgetKit). Use a static `waveform` SF Symbol in accent gold at 14 pt, placed leading the track name, to indicate playing state. When paused or stopped, this symbol is hidden.

---

### 2.4 Typography

| Element | Font | Weight | Size | Colour Token |
|---|---|---|---|---|
| Speaker name | SF Pro Text | Semibold | 12 pt | `BeoColor.labelPrimary` |
| Track name | SF Pro Display | Regular | 15 pt | `BeoColor.labelPrimary` |
| Source label | SF Pro Text | Regular | 11 pt | `BeoColor.labelSecondary` |
| Button label | SF Pro Text | Medium | 13 pt | `BeoColor.labelPrimary` |

Note: `BeoType` tokens are defined for the main app and use sizes (34 pt speaker name, 22 pt now playing) that are too large for the widget canvas. The widget uses a separate, smaller type ramp defined in §5 as new `BeoType.widget*` tokens. These are **not** used in the main app.

Dynamic Type is **not** supported in WidgetKit — widget text is rendered at fixed sizes. The sizes above are chosen to remain legible at the widget's physical dimensions.

---

### 2.5 Colours

All existing `BeoColor` tokens apply. No new colour tokens are required for `systemSmall`.

| Element | Token | Value |
|---|---|---|
| Speaker icon | `BeoColor.labelSecondary` | `#A09488` |
| Speaker name | `BeoColor.labelPrimary` | `#F5F3F0` |
| Track name | `BeoColor.labelPrimary` | `#F5F3F0` |
| Source | `BeoColor.labelSecondary` | `#A09488` |
| Playing indicator (waveform) | `BeoColor.accent` | `#C8A97E` |
| Button label | `BeoColor.labelPrimary` | `#F5F3F0` |
| Button icon (playing state) | `BeoColor.accent` | `#C8A97E` |
| Button icon (stopped/paused state) | `BeoColor.labelSecondary` | `#A09488` |
| Button surface | `DarkGlassButtonTokens.overlayColor` | `black.opacity(0.45)` |
| Button border | `DarkGlassButtonTokens.borderColor` | `white.opacity(0.15)` |
| App-not-running overlay tint | `BeoColor.labelSecondary` at 0.5 opacity | `#A09488` at 50% |

---

### 2.6 Spacing

| Element | Token | Value |
|---|---|---|
| Widget edge padding (all sides) | `Spacing.s12` | 12 pt |
| Speaker icon to speaker name gap | `Spacing.s4` | 4 pt |
| Track name top margin | `Spacing.s8` | 8 pt |
| Source label top margin | `Spacing.s4` | 4 pt |
| Button top margin (from source) | flexible spacer | auto |
| Button internal padding (vertical) | `WidgetButtonToken.paddingV` | 8 pt (new token — see §5) |
| Button internal padding (horizontal) | `WidgetButtonToken.paddingH` | 12 pt (new token — see §5) |
| Button icon to label gap | `DarkGlassButtonTokens.iconGap` | 6 pt |

---

## Section 3 — Home-Screen Widget: systemMedium

### 3.1 Layout

The `systemMedium` widget is approximately 329 × 155 pt on a standard iPhone. It uses a two-column layout: **left column for information, right column for the action grid**.

```
┌─────────────────────────────────────────────────────┐
│  [hifispeaker.fill] Beosound Stage                  │  ← Speaker header (full width)
│  ─────────────────────────────────────────────────  │
│                                      │              │
│  [waveform] Jazz Radio               │  [▶ / ⏸]   │  ← Track + primary control
│  Spotify · 74                        │  [−] Vol [+] │  ← Source/vol info + vol controls
│                                      │              │
└─────────────────────────────────────────────────────┘
```

More precisely, the medium widget is divided horizontally after the speaker header row:

**Top row (full width):** Speaker name with icon. Height: 22 pt.  
**Content area (below speaker header):** Two columns separated by a hairline divider at `BeoColor.separator` opacity 0.15.

| Left column | Right column |
|---|---|
| Track name (primary, 2-line) | Primary action button (play/pause) |
| Source + volume display | Volume control row (−  vol icon  +) |

Column split: left column 55% of content width, right column 45%.  
Internal padding: 12 pt all edges (`Spacing.s12`).  
Column gap: 12 pt (`Spacing.s12`).

---

### 3.2 Information Shown

| Element | Detail |
|---|---|
| Speaker name | Full name, 1-line truncate, `BeoType.widgetSpeakerName` (12 pt semibold) |
| Speaker icon | `hifispeaker.fill` at 12 pt, `BeoColor.labelSecondary` |
| Playing indicator | `waveform` SF Symbol at 12 pt in `BeoColor.accent` when playing; hidden when not playing |
| Track name | Track title or station name; 2-line truncate; `BeoType.widgetTrack` (15 pt regular) |
| Source | Source name (Spotify, Deezer, etc.) followed by a `·` separator and the volume number (e.g. "Spotify · 74"); `BeoType.widgetCaption` (11 pt regular); `BeoColor.labelSecondary` |
| Volume level | Embedded in the source line (see above) — not a standalone element in `systemMedium`. The volume number is the only volume feedback shown; there is no slider or track bar. |

---

### 3.3 Controls

The right column contains two button rows.

**Row 1 — Primary action (play/pause):**

Same play/pause button as `systemSmall` but occupying the full right-column width. The button is a `Button(intent: AudioPlaybackIntent)`.

**Row 2 — Volume controls:**

Three elements in an HStack:

| Element | Icon | Intent | Label |
|---|---|---|---|
| Volume down | `minus.circle.fill` | `AdjustVolumeIntent(delta: -10)` | None (icon only) |
| Volume icon | `speaker.wave.2.fill` | None (decorative) | None |
| Volume up | `plus.circle.fill` | `AdjustVolumeIntent(delta: +10)` | None (icon only) |

Volume buttons use the **icon-only variant**: `DarkGlassButtonTokens.iconOnlySize` (36 pt circular). All three elements are centred within the right column.

Volume buttons are disabled when:
- The app is not running.
- Volume data is not available from the shared container.

Volume up is disabled at 100; volume down is disabled at 0. Disabled buttons render at `opacity: 0.4`.

**No skip button in systemMedium for v1.2.** Skip/next-track would require a dedicated intent and Mozart API endpoint knowledge that the research did not confirm across all B&O sources. This is an open question flagged in §6.

---

### 3.4 States

| State | Left Column | Right Column | Accent Treatment |
|---|---|---|---|
| **Playing** | Playing indicator visible, track name, source · volume | Pause button (active) + vol controls | Gold waveform + gold pause icon |
| **Paused** | No playing indicator, last track name, source · volume | Play button + vol controls | No gold on left; gold play icon |
| **Stopped / Idle** | No playing indicator, "—" track, "—" source | Play button (muted) + vol controls | None |
| **Loading** | "—" track, "—" source | Disabled `ellipsis` button + disabled vol controls | None |
| **App not running** | Last known state, muted to 50% opacity | "Open Voxio" button full-column-width, no vol row | None |
| **Empty** | "No speaker found" centred | "Open Voxio" button | None |

**App-not-running treatment:** The entire widget content is rendered at 50% opacity. A subtle overlay label "Open to control" appears at `BeoType.widgetCaption` centred over the content. The "Open Voxio" button is placed in the right column, replacing the play/pause and volume rows.

---

### 3.5 Typography

| Element | Font | Weight | Size | Colour Token |
|---|---|---|---|---|
| Speaker name | SF Pro Text | Semibold | 12 pt | `BeoColor.labelPrimary` |
| Track name | SF Pro Display | Regular | 15 pt | `BeoColor.labelPrimary` |
| Source · volume | SF Pro Text | Regular | 11 pt | `BeoColor.labelSecondary` |
| Button label (play/pause) | SF Pro Text | Medium | 13 pt | `BeoColor.labelPrimary` |
| "Open to control" overlay | SF Pro Text | Regular | 11 pt | `BeoColor.labelSecondary` |

Same widget type ramp as `systemSmall` (§2.4). No additional typography tokens are needed beyond those defined in §5.

---

### 3.6 Colours and Spacing

Colour tokens identical to `systemSmall` (§2.5). No additional colour tokens required for `systemMedium`.

Spacing additions for `systemMedium`:

| Element | Token | Value |
|---|---|---|
| Column divider stroke | `BeoColor.separator` at 0.15 opacity | `Color("BeoSeparator")` at 15% |
| Column gap | `Spacing.s12` | 12 pt |
| Volume row top margin | `Spacing.s8` | 8 pt |
| Volume icon size (icon-only buttons) | `DarkGlassButtonTokens.iconOnlySize` | 36 pt |
| Volume icon-to-icon spacing | `Spacing.s8` | 8 pt |

---

## Section 4 — Control Widget

### 4.1 Overview

The Control Widget appears in Control Center and on the Lock Screen. It uses the `ControlWidgetButton` and `ControlWidgetToggle` APIs from iOS 18+ (`AppIntentControlConfiguration`).

A Control Widget tile is approximately 60 × 60 pt (square). It has no custom background — the system renders it with the standard Control Center glass tile treatment, which on iOS 26 is Liquid Glass. The design does not override this background.

---

### 4.2 Layout

The Control Widget provides two controls. Because the tile is square and small, the two controls are vertically stacked:

```
┌──────────────────┐
│                  │
│   ▶ / ⏸         │  ← Play/Pause ControlWidgetButton
│                  │
│   🔇 / 🔊        │  ← Mute ControlWidgetToggle
│                  │
└──────────────────┘
```

Due to the tile's physical size constraint, the two icons are stacked with 8 pt spacing between them, centred within the tile. The system's own `ControlWidgetButton` and `ControlWidgetToggle` APIs control the visual rendering — the design specifies icon choice and active/inactive tint only.

---

### 4.3 Controls

**Control 1 — Play/Pause:**

| Property | Value |
|---|---|
| API | `ControlWidgetButton` |
| Intent | `AudioPlaybackIntent` (toggle play/pause) |
| Label | "Voxio Play" |
| Icon (inactive / paused) | `play.fill` |
| Icon (active / playing) | `pause.fill` |
| Tint (active / playing) | `BeoColor.accent` (`#C8A97E`) |
| Tint (inactive) | System default (white, adapted by system) |

**Control 2 — Mute:**

| Property | Value |
|---|---|
| API | `ControlWidgetToggle` |
| Intent | `MuteIntent` / `UnmuteIntent` |
| Label | "Voxio Mute" |
| Icon (unmuted / off) | `speaker.wave.2.fill` |
| Icon (muted / on) | `speaker.slash.fill` |
| Tint (muted / on) | System default active tint (system provided, white on dark background in Control Center) |
| Tint (unmuted / off) | System default |

Note: the mute toggle tint when active is **not** overridden with gold. Muting is a suppression action, not a positive playback action. Using gold here would be inconsistent with the main app where gold signifies active playback. The system's default active tint (white-on-dark for the enabled state) is correct and sufficient.

---

### 4.4 States

| State | Play/Pause Icon | Play/Pause Tint | Mute Icon | Tile Appearance |
|---|---|---|---|---|
| **Playing, unmuted** | `pause.fill` | Gold accent | `speaker.wave.2.fill` | Normal (system glass tile) |
| **Playing, muted** | `pause.fill` | Gold accent | `speaker.slash.fill` | Normal |
| **Paused, unmuted** | `play.fill` | System default | `speaker.wave.2.fill` | Normal |
| **Paused, muted** | `play.fill` | System default | `speaker.slash.fill` | Normal |
| **App not running** | `play.fill` | Dimmed (system disabled) | `speaker.wave.2.fill` | Dimmed — system handles this at the `ControlWidgetButton` level via `isEnabled: false` |
| **No speaker** | `play.fill` | System disabled | `speaker.wave.2.fill` | Dimmed |

**App not running:** `ControlWidgetButton` and `ControlWidgetToggle` support an `isEnabled` flag. When the app is terminated, the intent cannot execute; the controls set `isEnabled: false` and the system automatically dims the tile and prevents interaction. The system may show a "Requires [App Name]" label — this is acceptable and expected iOS 26 behaviour.

---

### 4.5 Configuration

The Control Widget supports per-speaker targeting via `AppIntentControlConfiguration`. The configuration picker is the same speaker selector as the home-screen widget (§1.1): the list of discovered speakers plus "Automatic (most recent)".

The tile's displayed label (below the icon grid in Control Center, on devices that show it) is the speaker name when a specific speaker is selected, or "Voxio" when set to Automatic.

---

## Section 5 — Design Tokens

### 5.1 New Tokens Required

The following tokens are required for v1.2 and must be added to `DesignTokens.swift` and `BeoColor.swift` as appropriate.

**New `BeoType` tokens (widget type ramp):**

| Token | Font | Weight | Size | Notes |
|---|---|---|---|---|
| `BeoType.widgetSpeakerName` | SF Pro Text | Semibold | 12 pt | Widget speaker header; not used in main app |
| `BeoType.widgetTrack` | SF Pro Display | Regular | 15 pt | Widget track name; distinct from `BeoType.body` (15 pt Regular but SF Pro Text, not Display) |
| `BeoType.widgetCaption` | SF Pro Text | Regular | 11 pt | Widget secondary labels; smaller than `BeoType.caption` (12 pt Medium) |

Note: `BeoType.widgetTrack` intentionally uses SF Pro **Display** at 15 pt to match the character of the main app's now-playing text (`BeoType.nowPlaying` at 22 pt Display), just at a widget-appropriate size.

**New `Spacing` tokens:**

No new `Spacing` tokens required. The existing tokens cover all widget layout needs: `s4`, `s8`, `s12`.

**New `Radius` tokens:**

No new `Radius` tokens required. Widget button pills use `Radius.pill` (100). The system provides container radii for the widget frame.

**New `WidgetButtonToken` namespace:**

The `DarkGlassButtonTokens` padding values (10 pt vertical, 16 pt horizontal) are too large for the widget canvas. A separate token namespace is required:

| Token | Value | Notes |
|---|---|---|
| `WidgetButtonToken.paddingV` | 8 pt | Compressed vertical padding for widget buttons |
| `WidgetButtonToken.paddingH` | 12 pt | Compressed horizontal padding for widget buttons |
| `WidgetButtonToken.iconGap` | 6 pt | Same as `DarkGlassButtonTokens.iconGap` — no change |
| `WidgetButtonToken.iconOnlySize` | 36 pt | Same as `DarkGlassButtonTokens.iconOnlySize` — no change |

These tokens are widget-extension-only. The main app continues to use `DarkGlassButtonTokens` unchanged.

---

### 5.2 Token Conflicts and Issues

| Issue | Detail | Resolution |
|---|---|---|
| `BeoType.body` uses SF Pro Text vs. `BeoType.widgetTrack` uses SF Pro Display at the same 15 pt size | Intentional distinction. Track names are content labels (Display); UI labels are text labels (Text). The two tokens must coexist without being confused. | Add inline comments in `DesignTokens.swift` distinguishing their use contexts. |
| `DarkGlassButtonTokens` padding tokens are too large for widgets | 10 pt / 16 pt padding on a 155 pt canvas leaves insufficient content space. | New `WidgetButtonToken` namespace. Do **not** change `DarkGlassButtonTokens` — those values are correct for the main app. |
| `BeoColor.separator` is defined in `Assets.xcassets` but not in `BeoColor.swift` as a static token | The column divider in `systemMedium` uses this colour. The asset name `"BeoSeparator"` is referenced in `BeoColor.swift` but not exposed as a static property. | Add `static let separator = Color("BeoSeparator")` to `BeoColor`. This is a minor, non-breaking addition. |
| Widget extensions cannot import the main app's DesignSystem directly | The widget extension is a separate target. `BeoColor.swift` and `DesignTokens.swift` must be added to the widget extension target's membership, or extracted into a shared Swift Package. | Engineering decision: simplest path is adding these two files to the widget extension target. Flag for E-27 architecture. |

---

## Section 6 — UX/UI Issues and Open Questions

### Issue 1 — App Groups entitlement (engineering prerequisite, blocks all widget state)

**Description:** The widget extension reads speaker state (name, playback state, track name, source, volume, mute state) from a shared container. This requires an App Groups entitlement (`group.T-Creative.Voxio`) on both the main app target and the widget extension target. This entitlement is not currently present in the project and requires provisioning profile updates.

**Impact:** Without App Groups, the widget cannot display live state. Every widget render would show the empty/fallback state.

**Resolution needed from:** Engineering (provisioning, Xcode project setup). This is not a design decision — it is a hard dependency. Design cannot be fully verified until this is in place.

**Flag:** This must be resolved before any widget UI work begins. It is a P0 blocker.

---

### Issue 2 — App-not-running detection granularity

**Description:** The design specifies that the widget shows a fallback state when the app is not running. However, the widget cannot proactively detect whether the app is running at render time — it only discovers this when an intent fails to execute. This means there is a window between the user tapping a button and the fallback state appearing.

**Two design options:**

| Option | Approach | Trade-off |
|---|---|---|
| A (recommended) | On intent failure, write "app_not_running" flag to shared container, reload timelines. Widget re-renders with fallback. | 1–2 second lag before fallback appears. User gets one failed tap before the UI corrects itself. |
| B | Main app writes a "last seen alive" timestamp to the shared container on every event. Widget treats the app as "running" only if the timestamp is < 60 seconds old. | More proactive but requires the app to write frequently; stale state on background kill. |

**Recommendation:** Option A. The one failed tap is acceptable — widgets are not expected to be millisecond-responsive. Option B adds complexity for minimal gain.

**Decision needed from:** Product / Engineering sign-off.

---

### Issue 3 — Skip / next-track control

**Description:** The `systemMedium` research suggests adding a skip button. The research findings confirm `AudioPlaybackIntent` can make LAN network calls, but do not confirm a reliable skip/next-track endpoint across all B&O Mozart sources (the `/playback/state` endpoint supports `play`, `pause`, `stop` — skip depends on the active source). Designing a skip button that sometimes silently fails is worse than omitting it.

**Recommendation:** Omit skip from v1.2. Add it in v1.3 once the BNR / Mozart source-agnostic skip command is confirmed. If engineering confirms a reliable skip endpoint before v1.2 ships, it can be added to `systemMedium` in the right column between the play/pause and volume rows.

**Icon if added:** `forward.fill`, `BeoColor.labelPrimary`.  
**Intent if added:** `SkipIntent` conforming to `AudioPlaybackIntent`.

**Decision needed from:** Engineering (confirm Mozart skip endpoint availability per source).

---

### Issue 4 — Volume feedback in systemSmall

**Description:** `systemSmall` shows no volume information. A user who taps a widget volume control (not present in small) and sees no feedback will be confused. `systemSmall` deliberately omits volume because the canvas is too small to show both a volume number and a playback track name at legible sizes.

**Mitigation:** The source line in `systemMedium` shows the volume number inline (`Spotify · 74`). Users who want volume feedback should use `systemMedium`. This trade-off is intentional and acceptable.

**No action required.** Document in widget onboarding copy if any is written.

---

### Issue 5 — Two widgets or one (with size variants)?

**Description:** WidgetKit bundles multiple size configurations in a single `Widget` definition. The question is whether to ship one widget definition (Voxio Player) that supports both `systemSmall` and `systemMedium`, or two separate widget definitions (Voxio Small and Voxio Medium). A single definition is simpler and is the iOS convention.

**Recommendation:** One widget definition, two supported sizes. This is the correct iOS 26 pattern.

**Decision needed from:** Engineering (widget bundle configuration).

---

### Issue 6 — Stale track data after app is terminated

**Description:** The shared container persists the last-known track name and playback state. If the user terminates the app, the widget may show stale "Playing: Jazz Radio" state even though nothing is playing. This is misleading.

**Mitigation options:**

| Option | Approach |
|---|---|
| A | Main app writes `playback_state: stopped` to shared container when the app enters background (via `scenePhase` `.background`). Widgets show paused/stopped state when app is not running. |
| B | Widget shows last known state but adds "· last seen" relative timestamp (e.g. "· 3m ago") in the source line when the `last_seen` timestamp is > 5 minutes old. |
| C (recommended) | App writes state on every speaker event AND on `scenePhase` `.background` with a synthetic "paused" state. Widget renders this honestly. On app termination, iOS may not deliver the background phase reliably — document this as a known edge case. |

**Recommendation:** Option C. The stale-track risk is mitigated by writing a background-phase event. Document in the spec that post-termination staleness of up to 60 seconds is an accepted edge case.

**Decision needed from:** Engineering sign-off on `scenePhase` background-write implementation.

---

### Issue 7 — Accessibility in widgets

**Description:** WidgetKit has limited accessibility support compared to full SwiftUI. The following must be explicitly verified during implementation:

- `Button(intent:)` must have `accessibilityLabel` strings set on each button (e.g. "Play Beosound", "Pause Beosound", "Volume up", "Volume down", "Mute Beosound").
- Minimum tap target of 44 × 44 pt applies to widget buttons. In `systemSmall` the primary button fills the width and is taller than 44 pt — compliant. Volume buttons in `systemMedium` are 36 × 36 pt visually; the `Button` wrapper must use `.frame(minWidth: 44, minHeight: 44)`.
- VoiceOver reads buttons from top-left to bottom-right. Ensure the speaker name is the first VoiceOver focus element.
- Dynamic Type is not available in widgets — the fixed type sizes (§5.1) must be legible at the default system text size without adaptation.
- Control Widget labels ("Voxio Play", "Voxio Mute") are announced by Siri and VoiceOver when long-pressing the Control Center tile. These strings must be localised.

**Flag:** Accessibility labels on widget buttons are a design deliverable — the spec must include the string table. See §6.8 below.

---

### Issue 8 — Widget accessibility label strings

The following `accessibilityLabel` strings must be implemented:

| Element | English | Danish |
|---|---|---|
| Play button (paused/stopped state) | "Play [Speaker Name]" | "Afspil [Højttalernavn]" |
| Pause button (playing state) | "Pause [Speaker Name]" | "Sæt [Højttalernavn] på pause" |
| Volume up button | "Volume up" | "Skru op" |
| Volume down button | "Volume down" | "Skru ned" |
| Mute toggle (unmuted) | "Mute [Speaker Name]" | "Slå [Højttalernavn] fra" |
| Mute toggle (muted) | "Unmute [Speaker Name]" | "Slå [Højttalernavn] til igen" |
| Open Voxio button (fallback) | "Open Voxio" | "Åbn Voxio" |
| Widget (VoiceOver widget description) | "[Speaker Name], [State], [Track Name]" | "[Højttalernavn], [Tilstand], [Spornavn]" |

These strings are inserted via `.accessibilityLabel()` on each `Button(intent:)` in the widget view.

---

### Issue 9 — Control Widget on macOS and watchOS (iOS 26 cross-platform)

**Description:** The research notes that on iOS 26, Control Widgets are available on macOS and watchOS via paired iPhone with no additional implementation. The Voxio Control Widget will appear in these surfaces automatically.

**Impact:** The design must ensure the two-icon layout reads correctly at the smaller tile sizes used on watchOS (which may render the Control Widget differently). This should be verified during implementation with a watchOS simulator.

**No design change required for v1.2.** Flag as a post-ship verification task.

---

### Issue 10 — Gold accent on pause button (colour convention check)

**Description:** This spec uses `BeoColor.accent` (gold) on the play/pause button icon when playing. In the main app, gold is used for the active waveform and the playing state bars — always as a "currently active / positive playback" signal. Gold on the pause button means "you are playing and can pause." This is consistent with the main app's convention.

However: when the user is paused and the button shows "Play," the icon is in `BeoColor.labelSecondary` (muted grey). A user might read the grey icon as "unavailable" rather than "ready to play."

**Considered alternative:** Always show the play/pause icon in `BeoColor.labelPrimary` (white) regardless of state. Use the icon shape (`play.fill` vs `pause.fill`) as the primary state differentiator, not colour.

**Recommendation:** Keep the original convention (gold when playing, grey when paused). The grey-icon-as-unavailable risk is mitigated by the track name and playing indicator — together they make the state clear. Flattening to always-white removes a useful signal.

**No action required.** Decision documented here for implementation reference.

---

## Section 7 — Screen States Summary

### Home-Screen Widget (systemSmall)

| State | Trigger | Primary Visual Cue |
|---|---|---|
| Playing | Playback active in app/shared container | Gold `waveform` symbol + gold `pause.fill` button |
| Paused | Playback paused | No waveform; grey `play.fill` button; last track name |
| Stopped / Idle | No active playback | No waveform; grey `play.fill` button; "—" track name |
| Loading | App just launched, state not yet in container | `ellipsis` button disabled; "—" labels |
| App not running | Intent failure or > 60 s stale timestamp | 50% opacity content; "Open Voxio" button |
| Empty | No speaker in shared container | `hifispeaker.slash` icon; "No speaker found" label; "Open Voxio" |

### Home-Screen Widget (systemMedium)

Same state table as `systemSmall`, with the addition that volume controls are disabled in the Loading and App-not-running states.

### Control Widget

| State | Play Icon | Mute Icon | Tile |
|---|---|---|---|
| Playing, unmuted | `pause.fill` gold | `speaker.wave.2.fill` | Normal |
| Playing, muted | `pause.fill` gold | `speaker.slash.fill` | Normal |
| Paused, unmuted | `play.fill` white | `speaker.wave.2.fill` | Normal |
| Paused, muted | `play.fill` white | `speaker.slash.fill` | Normal |
| App not running | `play.fill` dimmed | `speaker.wave.2.fill` dimmed | System-dimmed, `isEnabled: false` |
| No speaker | `play.fill` dimmed | `speaker.wave.2.fill` dimmed | System-dimmed |

---

## Section 8 — Out of Scope (v1.2)

- **Live Activity "now playing"** — Lock screen + Dynamic Island persistent card. Deferred to v1.3 per research findings.
- **systemLarge widget** — The information density does not justify a large widget for a playback remote. Deferred indefinitely.
- **Widget for iPad** — Portrait iPhone only in this release. `systemMedium` on iPad would need a different layout re-evaluation.
- **Landscape orientation for widgets** — N/A; widgets are portrait on iPhone.
- **Widget mic button / waveform** — Architecturally impossible. No mic access in widget extensions. There is no workaround and no future path to enable this.
- **Favorite-selection in widget** — Playing a specific favorite from a widget requires resolving the favorite name, which is beyond the touch-surface design scope of v1.2. Deferred to v1.3.
- **Now-playing album art** — No album art in any widget in v1.2. The glass aesthetic does not require imagery; the track name and playing indicator are sufficient at this canvas size.
- **watchOS native app** — The Control Widget appearing on watchOS via iOS 26 mirroring is the only watchOS surface in v1.2.

---

## Appendix A — SF Symbol Reference

| Action | SF Symbol | Rendering Mode |
|---|---|---|
| Speaker device | `hifispeaker.fill` | `.hierarchical` |
| Playing indicator | `waveform` | `.hierarchical` |
| Play | `play.fill` | `.monochrome` |
| Pause | `pause.fill` | `.monochrome` |
| Volume up | `plus.circle.fill` | `.hierarchical` |
| Volume down | `minus.circle.fill` | `.hierarchical` |
| Volume icon (decorative) | `speaker.wave.2.fill` | `.hierarchical` |
| Muted | `speaker.slash.fill` | `.hierarchical` |
| No speaker (empty state) | `hifispeaker.slash` | `.hierarchical` |
| Open app (fallback) | `arrow.up.forward.app.fill` | `.hierarchical` |

All symbols use SF Symbols 6 (iOS 26 baseline). Where `.hierarchical` is specified, the secondary layers render at reduced opacity, allowing the Liquid Glass material to interact with symbol depth as specified in design-spec-bo-voice-control §Iconography.

---

## Appendix B — Design Tokens Reference (v1.2 additions)

```swift
// Widget type ramp — widget extension only; not used in the main app target
extension BeoType {
    static let widgetSpeakerName = Font.system(size: 12, weight: .semibold, design: .default)
    static let widgetTrack       = Font.system(size: 15, weight: .regular,  design: .rounded)
    static let widgetCaption     = Font.system(size: 11, weight: .regular,  design: .default)
}

// Widget button padding — separate from DarkGlassButtonTokens (which remain unchanged)
enum WidgetButtonToken {
    static let paddingV:   CGFloat = 8
    static let paddingH:   CGFloat = 12
    static let iconGap:    CGFloat = 6    // same as DarkGlassButtonTokens.iconGap
    static let iconOnlySize: CGFloat = 36 // same as DarkGlassButtonTokens.iconOnlySize
}

// BeoColor addition — expose the BeoSeparator asset as a static token
extension BeoColor {
    static let separator = Color("BeoSeparator")  // T-2700: new addition for v1.2
}
```

No new colour asset values are required. The existing `BeoSeparator` asset in `Assets.xcassets` is assumed to already exist (referenced in `SpeakerCard.swift`'s divider use); the only change is exposing it via `BeoColor.separator`.

**`BeoType.widgetTrack` uses `.rounded` design** for the SF Pro Display variant at 15 pt. This is an intentional soft warmth at small sizes — the rounded design reads slightly more premium than `.default` at sub-16 pt on a widget canvas. Flag for design team review if the `.default` variant is preferred for strict consistency with the main app type tokens.

---

*End of design specification v1.0*
