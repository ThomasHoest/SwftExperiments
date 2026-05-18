# Design Specification: Touch Playback Controls
**Version:** 1.2
**Status:** Draft
**Date:** 2026-05-08
**Platform:** iOS 26 (iPhone, portrait) — SwiftUI
**Design Language:** DarkGlass (dark Liquid Glass, warm-gold accent)
**References:** VoxioSpecification-1.4.md Feature 1, design-spec-home-screen-redesign.md (card anatomy, token decisions), CLAUDE.md (`BeoColor`, `Spacing`, `Radius`, `BeoAnimation`, `DarkGlassIconButton`, `DarkGlassButton`)

---

## Design Philosophy

Touch controls are a layer on top of voice — not a replacement. The design principle is **one tap, one action, immediate result**. Unlike voice commands, touch is unambiguous: the user tapped a specific control deliberately. There is no confirmation countdown for touch actions.

Controls live inside the session card. They do not float outside it, appear as a separate panel, or require a mode switch. The card is the control surface.

**Gold means playing.** The play button uses `BeoColor.accent` when the speaker is paused/stopped — pressing it will start audio. All other controls stay white. This matches the gold-as-active-state rule from `design-spec-home-screen-redesign.md §Design Philosophy`.

---

## Visual Language

All existing tokens apply. No new tokens are introduced.

### Transport controls use large `DarkGlassIconButton`

Transport buttons use `DarkGlassIconButton` at an increased size — 52 pt visual frame, 64 pt hit area — to feel deliberate and premium. The play/pause is a single toggle button. Stop is a secondary action and slightly smaller (44 pt visual, 56 pt hit area).

| Control | SF Symbol | Role | Notes |
|---|---|---|---|
| Play/Pause toggle | `play.fill` / `pause.fill` | `.confirm` / `.default` | Gold when paused/stopped (start audio); white when playing (pause audio) |

Stop is not a separate control. Pause and stop are functionally equivalent on Mozart speakers — pause leaves the source ready to resume, which is the correct behaviour in both cases. Volume +/− buttons are also removed. Volume is controlled via the interactive slider (§1.3).

### Volume uses the existing slider bar (made interactive)

The existing gold volume track is promoted to an interactive `Slider`. The visual appearance is unchanged — gold fill on dark track — but it now accepts drag gestures. No new visual component is introduced.

### Favorites use `DarkGlassButton` (pill, full-width row)

Each favorite is a `DarkGlassButton` with the favorite name as label and no icon. Role `.default`. If the favorite is currently active (playing), role `.confirm` (gold label).

---

## Screen Index

| § | Surface | Trigger |
|---|---|---|
| 1 | Session card — playing state | Controls visible; Pause + Stop + vol stepper |
| 2 | Session card — paused state | Controls visible; Play + Stop + vol stepper |
| 3 | Session card — stopped/idle state | Minimal; Play only |
| 4 | Favorites row | Shown below controls when favorites are available |

---

## Section 1 — Session card playing state

### 1.1 Full card anatomy (playing, with controls)

```
┌──────────────────────────────────────────┐
│  Badeværelse                   beolink   │  ← header (unchanged)
│  ● Playing                               │
├──────────────────────────────────────────┤
│  DR P1  dr.dk/p1                   ▐▌▌  │  ← now-playing panel (unchanged)
├──────────────────────────────────────────┤
│  ══════════════════════════════   20     │  ← volume slider (interactive, NEW)
├──────────────────────────────────────────┤
│                                          │
│              [     ⏸     ]               │  ← NEW: single large toggle button
│                                          │
│  [Morning]   [Dinner]   [Jazz]  →        │  ← favorites row
└──────────────────────────────────────────┘
```

### 1.2 Transport row layout

A single centred play/pause toggle button. No stop button — pause and stop are functionally equivalent on Mozart speakers.

- **Play/Pause toggle** — 52 pt visual / 64 pt hit area. Centred with `frame(maxWidth: .infinity)` and `Spacing.s24` horizontal padding. Gold (`role: .confirm`) when paused or stopped; white (`role: .default`) when playing.

```
┌──────────────────────────────────────────┐
│                                          │
│         ┌───────────────────────┐        │
│         │          ⏸           │        │
│         └───────────────────────┘        │
│                                          │
└──────────────────────────────────────────┘
```

- Horizontal padding: `Spacing.s24` each side.
- Vertical padding: `Spacing.s16` top, `Spacing.s20` bottom.

### 1.3 Volume slider

The existing gold volume track is promoted to an interactive `Slider(value:in:step:)` with `step: 5` (0–100). Visual appearance is identical to the current static bar — same gold fill, same track height (4 pt), same volume number on the trailing end. The thumb is invisible (custom `SliderStyle` with zero-size thumb — the fill is the affordance). Dragging anywhere on the bar sets volume.

- Slider fires `speaker.setVolume(_:)` on drag end (`.onEditingChanged`), not on every point, to avoid spamming the API.
- The volume number updates live during drag.
- Horizontal padding: `Spacing.s24` each side (unchanged from static bar).
- Vertical padding: `Spacing.s12` above, `Spacing.s12` below (increased from static bar to enlarge the drag target).

---

## Section 2 — Session card paused state

### 2.1 Layout

Identical to §1 — the play/pause toggle simply switches icon and role:

- Toggle shows `play.fill`, role `.confirm` (gold) — pressing will resume.
- State label: `BeoColor.muted` ("Paused"), not accent.
- `PlaybackBars` in the now-playing panel: hidden (static, no animation). Panel stays visible so the track title is readable.
- Volume slider and Stop button remain visible.

```
┌──────────────────────────────────────────┐
│  Badeværelse                   beolink   │
│  Paused                                  │  ← muted, not gold
├──────────────────────────────────────────┤
│  DR P1  dr.dk/p1                   ░░░   │  ← bars static/dim
├──────────────────────────────────────────┤
│  ══════════════════════════════   20     │  ← slider (same)
├──────────────────────────────────────────┤
│                                          │
│              [▶ gold — play  ]           │
│                                          │
│  [Morning]   [Dinner]   [Jazz]           │
└──────────────────────────────────────────┘
```

---

## Section 3 — Session card stopped / idle state

### 3.1 Layout

When the speaker is stopped or idle, there is no current track and no volume to show. The card collapses to the header + a single centred Play button.

```
┌──────────────────────────────────────────┐
│  Badeværelse                             │  ← no source badge when idle
│  Stopped                                 │  ← BeoColor.muted
│                                          │
│             [▶  Play]                    │  ← DarkGlassButton (full-width pill)
│                                          │    role .confirm (gold label + icon)
└──────────────────────────────────────────┘
```

- No now-playing panel, no volume track, no volume stepper in stopped state.
- Play button: `DarkGlassButton` (pill, not icon-only) with label "Play" and `play.fill` icon, role `.confirm`, `frame(maxWidth: .infinity)` with `Spacing.s24` horizontal padding.
- Tapping Play calls `speaker.play()` directly (resumes last source).
- Vertical padding below header: `Spacing.s20`. Below Play button: `Spacing.s20`.

---

## Section 4 — Favorites row

### 4.1 Purpose

Allows the user to start a specific preset/scene without voice. Shown below the transport row when the speaker has at least one favorite.

### 4.2 Layout

```
┌──────────────────────────────────────────┐
│  [transport row — see §1/§2]             │
├──────────────────────────────────────────┤
│                                          │
│  ┌──────────┐  ┌──────────┐  ┌────────┐ │
│  │ Morning  │  │ Dinner   │  │  Jazz  │ │  ← DarkGlassButton pills
│  └──────────┘  └──────────┘  └────────┘ │
│                                          │
└──────────────────────────────────────────┘
```

- Favorites scroll horizontally in a `ScrollView(.horizontal, showsIndicators: false)`.
- Each favorite: `DarkGlassButton` with favorite display name, no icon, `.default` role.
- If a favorite is currently active (matched against `speaker.nowPlaying`): role `.confirm` (gold label) — see UQ-1.
- Maximum visible favorites without scrolling: 3 (at typical iPhone width).
- Horizontal padding: `Spacing.s24` leading, trailing fades with a gradient mask to signal scrollability.
- Vertical padding: `Spacing.s8` top (below transport row divider), `Spacing.s20` bottom.
- If zero favorites: row is absent, no empty space.

### 4.3 Favorites shown in stopped state

In the stopped state (§3), the favorites row appears below the Play button. The user can start a specific favorite directly even when nothing is playing.

```
┌──────────────────────────────────────────┐
│  Badeværelse                             │
│  Stopped                                 │
│                                          │
│             [▶  Play]                    │
│                                          │
│  [Morning]  [Dinner]  [Jazz]  →          │
│                                          │
└──────────────────────────────────────────┘
```

---

## Section 5 — Interaction model

### 5.1 No confirmation countdown

Voice commands go through a countdown confirmation step before execution. Touch actions do not — a deliberate tap is unambiguous. Touch controls call the speaker action directly and immediately.

### 5.2 Haptics

Touch controls use the existing `HapticEngine`:
- Transport actions (play, pause, stop, favorite): `HapticEngine.shared.commandRecognised()`
- Volume limit hit (vol at 0 or 100): `HapticEngine.shared.limitReached()`
- Error: `HapticEngine.shared.errorOccurred()`

### 5.3 In-place feedback

On tap, the now-playing panel pulse fires (per `design-spec-home-screen-redesign.md §1.3`) before the API result returns. On API success the speaker state updates and the card re-renders. On failure a `.error` toast appears (unchanged toast behaviour).

### 5.4 Volume slider behaviour

The slider fires `speaker.setVolume(_:)` on drag end (not per point). Step is 5. The volume number trails the drag in real time. No haptic on volume change (continuous gesture — haptic on drag-end limit would be distracting).

### 5.5 Mute

Mute is not surfaced as a transport control button in v1.4 — it remains voice-only. The muted state is indicated by the volume track showing 0 and the volume number showing "0". See UQ-3.

---

## Section 6 — UX/UI Issues and Open Questions

| # | Question | Impact | Status |
|---|---|---|---|
| UQ-1 | How do we determine if a favorite is "currently active"? The speaker's `nowPlaying` track name may not match the favorite's display name reliably. | Favorite highlight | Resolved |
| UQ-2 | Should a mute button be included in the transport row? Current position: voice-only in v1.4. | Transport row | Resolved |
| UQ-3 | On a card that is part of a group (multiple speakers joined), do touch controls apply to the host speaker only, or all group members simultaneously? | Group touch scope | Resolved |

### Resolved decisions

| # | Decision | Rationale |
|---|---|---|
| UQ-1 | **No active-favorite highlight.** Favorites are always shown in `.default` role (white label). Matching the active favorite reliably is not possible — the speaker's `nowPlaying` data does not expose the preset ID. | Unreliable matching is worse than no highlight. |
| UQ-2 | **No mute button in the transport row.** Mute remains voice-only in v1.4. | Keeps the transport row minimal — one button is cleaner than two. |
| UQ-3 | **Transport controls (play/pause) target the lead speaker only.** Volume is sent to all group members simultaneously via `speaker.setVolume(_:)` on each member. | B&O grouping is leader/follower — the followers mirror play state from the leader automatically. Volume is independent per speaker and must be broadcast. |

---

## Section 7 — Accessibility Requirements

- All buttons meet the 44 × 44 pt minimum hit area (`DarkGlassIconButton` guarantees this).
- Transport buttons: explicit `accessibilityLabel` — "Pause", "Play", "Stop", "Volume down", "Volume up".
- Volume limits: `accessibilityAnnouncement("Volume at maximum")` / `"Volume at minimum"` when limit is reached.
- Favorites: `accessibilityLabel` = favorite display name. No active-playing suffix (UQ-1 resolved: highlight not implemented).
- VoiceOver order within card: header → now-playing panel → volume track → transport controls → favorites.
- Transport row uses `accessibilityElement(children: .contain)` so VoiceOver navigates each button individually.

---

## Section 8 — Out of Scope (v1.4)

- Separate stop control — pause is functionally equivalent on Mozart speakers.
- Seek/scrub within a track — Mozart API does not expose position.
- Queue management or skip next/previous.
- Mute touch control — voice-only in v1.4.
- Broadcast touch controls (apply action to all speakers) — voice-only in v1.4.
- Multiroom join/leave from the card — specified in `design-spec-multiroom-grouping.md`.

---

## Appendix A — SF Symbol reference

| Symbol | Usage |
|---|---|
| `play.fill` | Play button (stopped/paused state) |
| `pause.fill` | Pause button (playing state) |
| `stop.fill` | Stop button |
| `plus` | Volume up |
| `minus` | Volume down |

---

## Appendix B — String catalogue (EN + DA)

| Key | English | Danish |
|---|---|---|
| `a11y.play` | "Play" | "Afspil" |
| `a11y.pause` | "Pause" | "Pause" |
| `a11y.stop` | "Stop" | "Stop" |
| `a11y.volumeUp` | "Volume up" | "Skru op" |
| `a11y.volumeDown` | "Volume down" | "Skru ned" |
| `a11y.volumeMax` | "Volume at maximum" | "Lydstyrken er på maksimum" |
| `a11y.volumeMin` | "Volume at minimum" | "Lydstyrken er på minimum" |
| `a11y.favoritePlaying` | — removed (UQ-1: active highlight not implemented) | — |
| `controls.play` | "Play" | "Afspil" |
