# Design Specification: Voxio Home Screen Redesign
**Version:** 1.2
**Status:** Draft
**Date:** 2026-05-08
**Platform:** iOS 26 (iPhone, portrait) — SwiftUI
**Design Language:** DarkGlass (dark Liquid Glass, warm-gold accent)
**References:** VoxioSpecification-1.4.md Feature 3, design-spec-feature3-ui.md (format + token reference), CLAUDE.md (`BeoColor`, `Spacing`, `Radius`, `BeoAnimation`, `BeoType`, `DarkGlassButtonTokens`)

---

## Design Philosophy

The home screen today feels like a voice assistant that happens to show playback state. After v1.4 it should feel like a music player that happens to listen. Three principles drive this redesign:

**State is always visible.** A user who picks up the phone should know — without tapping anything — what is playing, where, at what volume, and which speakers are linked. No hunting.

**Feedback is immediate.** Every action, whether spoken or tapped, produces a visible result within one animation frame. The user should never wonder if their input registered.

**Gold is playing.** The `BeoColor.accent` (`#C8A97E`) marks exactly one thing: audio that is actively playing. Anything paused, stopped, or inactive is white or muted. This rule is binary — a speaker either has the gold treatment or it does not.

The DarkGlass aesthetic is preserved without change — same dark background, same glass card surfaces, same motion tokens.

---

## Visual Language

### Colour palette (existing tokens — no new tokens in v1.0)

| Token | Usage in this spec |
|---|---|
| `BeoColor.bg` (`BgPrimary`) | Background fill (unchanged) |
| `BeoColor.cardBg` (`CardSurface`) | Session card surface (unchanged) |
| `BeoColor.cardBorder` (`CardBorder`) | Session card hairline border (unchanged) |
| `BeoColor.text` (`LabelPrimary`) | Speaker name, track title, active pill label |
| `BeoColor.muted` (`LabelSecondary`) | Paused/stopped state labels, inactive pill labels, sub-track text |
| `BeoColor.accent` (`Accent` / `#C8A97E`) | Playing indicator bars, active pill border + text, active volume fill — playing state only |
| `BeoColor.separator` (`BeoSeparator`) | Dividers inside session card if needed |

*No new colour tokens are introduced in v1.0. If the group membership chip requires a distinct surface, it reuses `BeoColor.cardBg` at reduced opacity (`.white.opacity(0.07)` — same as the existing now-playing panel).*

### Typography (`BeoType`)

| Token | Usage |
|---|---|
| `BeoType.speakerName` (34 pt semibold) | Session card primary name |
| `BeoType.nowPlaying` (22 pt regular) | Track title in now-playing panel |
| `BeoType.confirmation` (17 pt regular) | Transcript overlay (unchanged) |
| `BeoType.body` (15 pt regular) | State label ("Playing", "Paused"), bottom bar pill label |
| `BeoType.caption` (12 pt medium) | Sub-track / source, group member chips, page dot area |

No new type tokens are introduced.

### Spacing and radius

Existing tokens apply throughout. Notable usages:

| Token | Value | Usage in this spec |
|---|---|---|
| `Spacing.s4` | 4 pt | Vertical padding inside group member chips |
| `Spacing.s8` | 8 pt | Gap between session card and page dots; gap between member chips; gap between page dots |
| `Spacing.s12` | 12 pt | Vertical padding inside bottom bar pills |
| `Spacing.s16` | 16 pt | Horizontal page margin for session card strip; horizontal padding inside member chips |
| `Spacing.s20` | 20 pt | Gap between session strip and voice feedback area |
| `Spacing.s24` | 24 pt | Internal card horizontal padding (unchanged) |

| Token | Usage |
|---|---|
| `Radius.card` (20 pt) | Session card corners (unchanged) |
| `Radius.pill` (100 pt) | Bottom bar pills, group member chips |

### Motion

All transitions use existing `BeoAnimation` tokens unless noted.

- **Session card swipe:** native `ScrollView` horizontal paging with momentum. Card entrance uses `BeoAnimation.spring`. **Reduce Motion:** snap without spring.
- **Page indicator:** dot scale + opacity cross-fade on `BeoAnimation.toast` (200 ms). **Reduce Motion:** opacity only, no scale.
- **Bottom bar playing indicator:** same staggered animation as existing `PlaybackBars` component — reuse it verbatim. The three bars cycle between `(lo, hi)` height pairs `[(6, 14), (14, 6), (10, 16)]` (in points, at the reference 20 pt frame; scaled proportionally for the 10 pt pill variant). Each bar uses `.easeInOut(duration: 0.38 + i * 0.06).repeatForever(autoreverses: true).delay(i * 0.12)`. **Reduce Motion:** static bars at the midpoint of each bar's lo–hi range (`(lo + hi) / 2`).
- **Feedback pulse:** `BeoAnimation.toast` opacity flash (0→1→0 over 300 ms) on the element that was acted on. **Reduce Motion:** omit pulse; rely on state change only.
- **State label colour change** (e.g. "Paused" → "Playing"): cross-fade on `BeoAnimation.toast`. **Reduce Motion:** instantaneous.

---

## Screen Index

| § | Area | Change type |
|---|---|---|
| 1 | Action feedback | Enhancement to existing toast + new in-place pulse |
| 2 | Bottom speaker bar | Replacement of `SpeakerSelectorPill` |
| 3 | Session card strip | Replacement of single `SpeakerCard` with swipeable multi-card strip |
| 4 | Discovery / loading state | Replacement of plain empty state with animated discovery experience |
| 5 | Offline / no network state | New dedicated full-screen offline state |

---

## Section 1 — Action feedback

### 1.1 Purpose

The current feedback system consists of a top-of-screen toast and passive state text on the card. This is sufficient for voice commands but leaves touch actions — which will be added in Feature 1 — without immediate on-element confirmation. This section specifies how feedback works across both voice and touch interactions.

### 1.2 Toast (existing — retained with one change)

The existing `ToastView` slides in from the top. It covers three kinds:
- `.success(message:)` — green-tinted (or accent-tinted, TBD per UQ-1)
- `.error(message:, list:)` — destructive tint
- `.volumeLimit(message:, isMax:)` — directional arrow indicator

**Change:** Success toasts triggered by touch actions (Feature 1) use the same `ToastView`. No new toast type is introduced for touch. The touch layer calls the same `showToast()` path as voice.

### 1.3 In-place feedback pulse (new)

When a touch control is activated (Feature 1), the now-playing panel on the session card briefly pulses: opacity drops to 0.6 and recovers over `BeoAnimation.toast` (300 ms). This gives instant on-card confirmation that the tap registered, before the speaker state updates from the API.

```
Action tap
    → panel opacity: 1.0 → 0.6 → 1.0   (300 ms, BeoAnimation.toast)
    → API call in-flight
    → speaker state updates → card re-renders with new state
```

If the API call fails, a `.error` toast appears as usual. The pulse does not distinguish success from failure — it only signals receipt.

**Reduce Motion:** pulse is omitted entirely. The state change on API response is the only feedback.

### 1.4 State label clarity (enhancement)

The current state label ("Playing", "Paused", "Stopped") is `BeoType.body` in `.secondary` colour regardless of state. Proposed:

| State | Label colour |
|---|---|
| Playing / Started | `BeoColor.accent` |
| Paused | `BeoColor.muted` |
| Stopped / Idle | `BeoColor.muted` |
| Loading / Connecting | `BeoColor.muted` (with system `ProgressView` spinner inline — see UQ-2) |

This costs no new tokens. The colour swap is the only change.

### 1.5 Accessibility

- All toasts carry `.accessibilityAnnouncement` so VoiceOver users hear the result.
- The pulse is `accessibilityHidden(true)` — it is decorative.
- State label colour changes are reinforced by the label text itself; colour alone does not carry meaning.

---

## Section 2 — Bottom speaker bar

### 2.1 Purpose

The current `SpeakerSelectorPill` shows speaker names as tappable pills. It solves the selection problem but gives no playback context — you cannot tell which speakers are playing, which are in a group, or which one the card is currently showing. The redesign makes playback state visible at a glance and groups co-playing speakers.

### 2.2 Layout

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│  ┌──────────────────┐   ┌────────────┐   ┌────────────┐   │
│  │ Badeværelse  ▐▌▌ │   │ Pejsestuen │   │    Stue    │   │
│  └──────────────────┘   └────────────┘   └────────────┘   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

- Pills scroll horizontally, same as today.
- Each pill shows: speaker name + (if playing) `PlaybackBars` component at 10 pt height, right-aligned inside the pill.
- Playing pill: `BeoColor.accent` text, gold border at 1 pt, `PlaybackBars` visible (gold).
- Inactive/paused pill: `BeoColor.text` label, no border, no bars.
- Selected pill: the pill currently driving the session card. May or may not be playing. Selection uses existing glass highlight + gold border (retain current behaviour for the playing case; for non-playing selected pill, use white border at 0.4 opacity instead of gold).

### 2.3 Group membership indicator

Speakers that are playing together (in the same `Group`) are shown adjacent in the bar with a subtle visual link:

```
  ┌──────────────┐  ┌─────────────┐
  │ Badeværelse ▐▌│──│ Stue     ▐▌│
  └──────────────┘  └─────────────┘
       group member connector
```

The connector is a 1 pt line in `BeoColor.muted` at 0.3 opacity between adjacent grouped pills. The pills themselves are not otherwise changed. The connector is a static element; Reduce Motion has no additional effect on it.

*Open question: see UQ-3 — whether grouping re-sorts pill order.*

### 2.4 Pill anatomy

```
┌──────────────────────────────┐
│  Speaker Name           ▐▌▌  │  ← gold bars only if playing
│  (BeoType.body, 15 pt)       │
└──────────────────────────────┘

padding-H: Spacing.s16 (left) + Spacing.s8 (between text and bars) + Spacing.s12 (right)
padding-V: Spacing.s12 top + bottom
min-width: 44 pt (accessibility minimum, unchanged)
border-radius: Radius.pill (100 pt)
```

### 2.5 Accessibility

- Each pill: `accessibilityLabel` = `"\(name)\(isPlaying ? ", playing" : "")\(isSelected ? ", selected" : "")"`. The formula resolves to the following four cases, which must be produced exactly:
  - idle, unselected → `"Stue"`
  - playing, unselected → `"Stue, playing"`
  - idle, selected → `"Stue, selected"`
  - playing, selected → `"Stue, playing, selected"`
- `accessibilityHint` = `isSelected ? "" : "Show this speaker"`.
- `PlaybackBars` within pill: `accessibilityHidden(true)`.
- The pill row auto-scrolls to keep the pill matching `selectedSpeaker` visible whenever the binding changes externally (e.g. swiping the session strip selects a new host). Animation: `BeoAnimation.spring`. Reduce Motion: instantaneous scroll.

---

## Section 3 — Session card strip

### 3.1 Purpose

The home screen currently shows one card for the selected speaker. In v1.4, it becomes a horizontal strip — one card per active session — that the user can swipe through. A session is defined as a solo speaker or a group of speakers playing together. Idle/stopped speakers are not shown as sessions; they appear only in the bottom bar.

*Open question: see UQ-4 — whether stopped speakers have a session card.*

### 3.2 What is a session

A session maps 1:1 with a `Group` in the existing data model:
- A solo playing speaker → one session (group of 1)
- Two or more speakers joined → one session (group of n)
- An idle speaker → no session card; only visible in the bottom bar

If no speaker is playing, the card area shows the existing empty state unchanged.

### 3.3 Layout — strip

```
         ← swipe →

  ┌──────────────────────────────────────────┐
  │                                          │
  │  Badeværelse                   beolink   │
  │  ● Playing                               │
  │                                          │
  │  DR P1  dr.dk/p1                    ▐▌▌  │
  │  ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬    20  │
  │                                          │
  │  ┌────────────┐  ┌──────────┐            │
  │  │ + Stue     │  │+ Kitchen │            │  ← group member chips (only if group)
  │  └────────────┘  └──────────┘            │
  │                                          │
  └──────────────────────────────────────────┘

           ●  ○  ○        ← page dots
```

- Cards are full-width minus `Spacing.s16` horizontal margin on each side.
- Adjacent cards peek at 8 pt on the trailing edge to signal swipeability (only when >1 session).
- Page dots appear below the strip when >1 session. One dot per session. Active dot: 8 pt diameter, `BeoColor.accent`. Inactive dot: 6 pt, `BeoColor.muted` at 0.4 opacity. Spacing between dots: `Spacing.s8`.

### 3.4 Session card anatomy

The session card extends the existing `SpeakerCard` with one new region at the bottom — the group member chip row. All existing regions are unchanged:

```
┌──────────────────────────────────────────┐
│  [Speaker name]              [badge]     │  ← header (unchanged)
│  [State label]                           │
├──────────────────────────────────────────┤
│  [Track title]                   [bars]  │  ← now-playing panel (unchanged)
│  [Sub-track / source]                    │
├──────────────────────────────────────────┤
│  [Volume track]                     [n]  │  ← volume track (unchanged)
├──────────────────────────────────────────┤
│  [+ Member A]  [+ Member B]  …           │  ← NEW: group member chips (only if group)
└──────────────────────────────────────────┘
```

**Group member chips:**
- Horizontal, left-aligned, `HStack(spacing: Spacing.s8)`.
- Chip label: `"+ Speaker Name"` — the `+` signals "also playing here".
- Font: `BeoType.caption` (12 pt medium), `BeoColor.muted`.
- Background: `.white.opacity(0.07)` in `Capsule()` — same surface as the now-playing panel.
- Padding: `Spacing.s8` H, `Spacing.s4` V.
- The primary speaker (card title) is not repeated in the chip row.
- If there are no group members, the chip row is absent — no empty space.
- Padding below chip row to card edge: `Spacing.s16`.

### 3.5 Swipe behaviour

- The strip uses `ScrollView(.horizontal)` with `.scrollTargetBehavior(.viewAligned)` and `.scrollPosition(id:)`. `TabView(.page)` is rejected because it cannot produce the 8 pt trailing peek (UQ-5 resolved — see §7).
- Swiping to a session card selects that session's host speaker in the bottom bar. The bottom bar scrolls to show the selected speaker.
- Conversely, tapping a speaker in the bottom bar scrolls the card strip to that speaker's session. If the speaker is a group member (not host), it scrolls to the group's session card.
- Tapping an **idle** speaker (a speaker that has no session card because nothing is playing on it) does NOT change the strip's scroll position — the strip stays where it was.
- **Initial mount:** the strip aligns to the session whose host matches the current `selectedSpeaker`. If `selectedSpeaker` is `nil` or matches no playing host or member, the strip aligns to the first session. **No animation** fires on this initial alignment.
- **Subsequent transitions** (swipe, pill-tap, programmatic change): animated with `BeoAnimation.spring`. Reduce Motion: snap without spring.
- **Re-entrancy guard:** the strip and the pill row both react to the shared `selectedSpeaker` binding. Implementations must short-circuit when the incoming value already matches the current scroll position, otherwise the two `onChange` observers loop each other.
- **Session disappears mid-view:** when the speaker referenced by `selectedSpeaker` is removed from `discovery.groups` while its card is visible, the strip aligns to the first remaining session. `selectedSpeaker` itself is left untouched — the pill row's filter will hide the now-absent pill and the next discovery cycle replaces it. No additional UI change is needed.
- **`discovery.groups` ordering:** assumed stable across renders within a single discovery cycle (groups are appended in discovery order; only group composition changes cause a re-shape). Implementers must not re-sort the array on every render — doing so will cause spurious page reflows.

### 3.6 Single-session fallback

When only one session exists, the strip behaves exactly as the current single-card layout — no peek, no page dots. This is a no-regression requirement.

### 3.7 Accessibility

- Each session card: `accessibilityElement(children: .ignore)`, `accessibilityLabel` matching the existing `SpeakerCard.accessibilityDescription` + group members appended (e.g. `"also playing: Stue, Kitchen"`).
- Swipe gesture does not override VoiceOver swipe. VoiceOver users navigate between session cards using the standard element focus order.
- Page dots: `accessibilityHidden(true)` — the cards themselves carry the information.

---

## Section 4 — Discovery / loading state

### 4.1 Purpose

The current discovering state shows a plain card with a `speaker.slash` icon and a "Looking for speakers…" string. This feels like an error state rather than an intentional, premium experience. The app should feel alive while it scans — like the orb is searching.

Discovery has two distinct phases that need different visual treatments:

| Phase | Condition | Duration |
|---|---|---|
| **Pre-settle** | `!discovery.didSettle` | Typically 2–5 s on a healthy LAN |
| **Post-settle, no speakers** | `discovery.didSettle && speakerCount == 0` | Persists until a speaker appears |

### 4.2 Pre-settle — animated scanning

The card area is replaced by a full-width scanning animation centred on the orb. No card chrome, no pill selector.

```
              ┌──────────────────────────────┐
              │                              │
              │       ○ ○ ○ ○ ○              │  ← expanding pulse rings
              │     ○           ○            │
              │   ○    ┌──────┐   ○          │
              │   ○    │  orb │   ○          │  ← orb at centre
              │   ○    └──────┘   ○          │
              │     ○           ○            │
              │       ○ ○ ○ ○ ○              │
              │                              │
              │    Searching for speakers    │  ← BeoType.body, muted
              │                              │
              └──────────────────────────────┘
```

**Pulse rings:** three concentric rings expand outward from the orb and fade to zero opacity. Each ring is a `Circle()` stroke in `BeoColor.accent` at low opacity (0.15 starting). Staggered: ring 2 starts 0.6 s after ring 1, ring 3 after ring 2. Each ring expands from orb diameter (96 pt) to 200 pt over 2.0 s with `.easeOut`, then repeats. Opacity animates from 0.15 → 0 over the same duration.

**Orb:** the existing orb idle-pulse animation plays unchanged. The pulse rings are layered behind the orb in z-order.

**Label:** `BeoType.body`, `BeoColor.muted`, centred below the orb. Copy: "Searching for speakers…" / "Søger efter højttalere…"

**Reduce Motion:** rings are replaced by a single static ring at 0.1 opacity. The orb pulse animation suspends (static gradient). Label still appears.

### 4.3 Post-settle, no speakers found

After `discovery.didSettle` fires with no speakers found (and the device has WiFi — see §5 for no-WiFi state):

```
              ┌──────────────────────────────┐
              │                              │
              │        [ orb — dim ]         │  ← orb at 0.4 opacity, no pulse
              │                              │
              │     No speakers found        │  ← BeoType.nowPlaying, text primary
              │                              │
              │  Make sure your B&O speaker  │  ← BeoType.body, muted, centred
              │  is on and on the same       │
              │  Wi-Fi network.              │
              │                              │
              │      [ Search again ]        │  ← DarkGlassButton (secondary style)
              └──────────────────────────────┘
```

- "Search again" triggers a fresh `discovery.start()` call with a brief spinner inside the button during the new scan (returns to the pre-settle animation — §4.2).
- The top `ConnectionStatusChip` stays visible and continues to show `wifi.slash` + "Offline" (pending §5 fix — once network detection is separated from speaker count, this chip reflects true WiFi state).

### 4.4 Speaker found mid-scan

When the first speaker resolves during the pre-settle phase, the scanning animation crossfades to the normal home screen (session card + bottom bar) using `BeoAnimation.spring`. The transition is not abrupt — the orb remains in position and the card slides in from below with opacity.

### 4.5 Accessibility

- The pulse rings are `accessibilityHidden(true)` — decorative.
- The "Searching…" label is announced once via `.accessibilityAnnouncement` on appearance.
- "Search again" button: standard `accessibilityLabel` "Search again for speakers".

---

## Section 5 — Offline / no network state

### 5.1 Purpose

Currently the app conflates "no speakers found" with "offline" — both show the same chip text ("Offline") because `ConnectionStatusChip` derives its state from `speakerCount == 0`. True offline (no WiFi) and "WiFi but no B&O speakers found" are different problems requiring different messaging.

This section specifies a dedicated offline state and recommends separating network detection from speaker discovery.

### 5.2 Network state detection

The implementation must introduce a `NWPathMonitor` (from `Network.framework`) to independently track WiFi availability. This drives a new `isOnWifi: Bool` property in the discovery service (or a separate `NetworkMonitor` observable). The result feeds into:

- `ConnectionStatusChip` — shows true WiFi state, not speaker count proxy
- Home screen state machine — distinguishes offline from "searching" from "no speakers"

**State machine:**

| WiFi | `didSettle` | Speaker count | State shown |
|---|---|---|---|
| false | any | 0 | **Offline** (§5.3) |
| true | false | 0 | **Discovering** — pre-settle animation (§4.2) |
| true | true | 0 | **No speakers found** (§4.3) |
| true | any | > 0 | **Normal home screen** (§§1–3) |

### 5.3 Offline state layout

The card area is replaced by the offline state. No bottom bar, no page dots.

```
              ┌──────────────────────────────┐
              │                              │
              │        [ orb — off ]         │  ← orb at 0.2 opacity, no animation
              │                              │
              │         No Wi-Fi             │  ← BeoType.nowPlaying, text primary
              │                              │
              │  Connect to the same Wi-Fi   │  ← BeoType.body, muted, centred
              │  network as your B&O         │
              │  speakers to get started.    │
              │                              │
              └──────────────────────────────┘
```

- No "retry" button — when WiFi reconnects, `NWPathMonitor` fires automatically and the app transitions to the discovering state (§4.2) without user action.
- The `ConnectionStatusChip` in the top bar reflects true offline state: `wifi.slash` symbol + "No Wi-Fi" label (replaces the current "Offline" copy which is ambiguous — see UQ-8).
- The waveform and mic-status label are hidden in offline state (mic is inactive).
- Voice recognition does not start until WiFi is available.

### 5.4 Transition back online

When `NWPathMonitor` reports WiFi restored, the offline state cross-fades to the pre-settle discovering animation (§4.2) automatically. The orb animates back to full opacity and the pulse rings begin. No user action required.

**Transition timing:** `BeoAnimation.toast` (200 ms opacity fade), then `BeoAnimation.spring` for the orb restore.

### 5.5 Accessibility

- On entering offline state: `.accessibilityAnnouncement("No Wi-Fi connection")`.
- On WiFi restored: `.accessibilityAnnouncement("Wi-Fi connected, searching for speakers")`.
- Orb at reduced opacity is `accessibilityHidden(true)` — it is decorative.

---

## Section 6 — UX/UI Issues and Open Questions

All questions resolved. See Resolved Decisions below.

| # | Question | Impact | Status |
|---|---|---|---|
| UQ-1 | Should success toasts use `BeoColor.accent` (gold) or a system green tint? | Toast visual | Resolved |
| UQ-2 | Should the "Connecting…" state show an inline spinner or a dimmed label? | Card state clarity | Resolved |
| UQ-3 | Should grouped speakers be re-sorted adjacent in the bottom bar? | Bottom bar | Resolved |
| UQ-4 | Should stopped/idle speakers have a session card? | Session strip scope | Resolved |
| UQ-5 | `ScrollView` with paging vs `TabView(.page)` for session strip? | Implementation | Resolved |
| UQ-6 | Group chip overflow when >3 members? | Group chip row | Resolved |
| UQ-7 | Parallax highlight on all session cards or front-most only? | Card motion | Resolved |
| UQ-8 | `ConnectionStatusChip` copy — separate offline from discovering? | Top bar chip | Resolved |
| UQ-9 | Auto-retry discovery or user-tap only? | Discovery retry | Resolved |

---

## Section 5 — Accessibility Requirements

- All interactive elements meet the 44×44 pt minimum touch target (unchanged from current implementation).
- State label colour changes are accompanied by text label changes — colour is never the sole indicator.
- `PlaybackBars` animations suspend on Reduce Motion.
- All new text elements support Dynamic Type via `BeoType` tokens.
- VoiceOver order: session card → voice feedback → bottom bar pills. The page dots region is `accessibilityHidden(true)` per §3.7 — VoiceOver users navigate session cards via the standard element focus order, which already conveys position.

---

## Section 7 — Resolved Decisions

| # | Decision | Rationale |
|---|---|---|
| UQ-1 | Success toasts use **white/neutral** tint, not gold. | Gold is reserved exclusively for the playing state. Green breaks the palette. |
| UQ-2 | "Connecting…" state shows an **inline `ProgressView` spinner** (12 pt) alongside the state label. | A dimmed label alone is ambiguous — user cannot tell if the app froze or is working. |
| UQ-3 | Bottom bar pill order follows **discovery order** (not re-sorted by group). The group connector line links grouped pills wherever they sit. If non-adjacent, connector is omitted and group membership is visible via session card chips only. | Re-sorting mid-session is jarring and disorienting. |
| UQ-4 | Stopped/idle speakers appear in the **bottom bar only** — no session card. | Session strip is a "now playing" surface; an idle speaker has nothing to show there. |
| UQ-5 | Session strip uses **`ScrollView(.horizontal)` with `.scrollTargetBehavior(.viewAligned)`** and paging. | Provides the card-peek affordance that `TabView(.page)` cannot cleanly support. |
| UQ-6 | Group chip overflow (>3 members) uses a **"+N more" chip**. Tapping it is deferred to the F2 multiroom UI. | Horizontal scroll inside a swipeable card creates a gesture conflict. |
| UQ-7 | Parallax specular highlight applies to the **front-most (visible) session card only**. Offscreen cards are frozen. | Motion on all cards simultaneously would feel chaotic. |
| UQ-8 | `ConnectionStatusChip` copy splits into three distinct states: **"Searching…"** (pre-settle), **"No Wi-Fi"** (offline), **"n speakers"** (connected). Driven by `NWPathMonitor` + `discovery.didSettle`. | Current "Offline" copy conflates two different problems. |
| UQ-9 | Discovery **auto-retries every 30 s** silently. After 10 s of no result, a "Still looking…" label appears below the search label. "Search again" button forces an immediate retry. | Auto-retry is seamless; the visible label after 10 s ensures the user knows the app is still working. |

---

## Section 8 — Out of Scope (v1.4)

- Touch playback controls (play/pause, volume, favorites) — specified in `design-spec-touch-playback-controls.md`.
- Multiroom join/leave touch UI — specified in `design-spec-multiroom-grouping.md`.
- Landscape / iPad layout.
- Lock Screen / Live Activity now-playing surface.
- Dark/Light mode variants — the app is dark-only (unchanged).

---

## Appendix A — SF Symbol reference

| Symbol | Usage |
|---|---|
| `questionmark.circle` | Help button (unchanged) |
| `gearshape` | Settings button (unchanged) |
| `speaker.slash` | Empty state (unchanged) |
| `wifi.slash` | Offline state chip (existing in `ConnectionStatusChip`) |
| No new symbols in §1–§3 | `PlaybackBars` is a custom view; page dots and pulse rings are custom drawn |

---

## Appendix B — String catalogue (EN + DA)

New strings introduced in this spec:

| Key | English | Danish |
|---|---|---|
| `state.playing` | "Playing" | "Spiller" |
| `state.paused` | "Paused" | "Sat på pause" |
| `state.stopped` | "Stopped" | "Stoppet" |
| `state.connecting` | "Connecting…" | "Forbinder…" |
| `groupChip.prefix` | "+" | "+" |
| `a11y.sessionCard` | "Session %d of %d" | "Session %d af %d" |
| `a11y.alsoPlaying` | "Also playing: %@" | "Spiller også: %@" |
| `a11y.pillPlaying` | "%@, playing" | "%@, spiller" |
| `a11y.pillSelected` | "%@, selected" | "%@, valgt" |

| `discovery.searching` | "Searching for speakers…" | "Søger efter højttalere…" |
| `discovery.noSpeakers.title` | "No speakers found" | "Ingen højttalere fundet" |
| `discovery.noSpeakers.body` | "Make sure your B&O speaker is on and on the same Wi-Fi network." | "Sørg for, at din B&O højttaler er tændt og på samme Wi-Fi-netværk." |
| `discovery.searchAgain` | "Search again" | "Søg igen" |
| `offline.title` | "No Wi-Fi" | "Ingen Wi-Fi" |
| `offline.body` | "Connect to the same Wi-Fi network as your B&O speakers to get started." | "Opret forbindelse til det samme Wi-Fi-netværk som dine B&O højttalere for at komme i gang." |
| `chip.searching` | "Searching…" | "Søger…" |
| `chip.noWifi` | "No Wi-Fi" | "Ingen Wi-Fi" |
| `a11y.offline` | "No Wi-Fi connection" | "Ingen Wi-Fi-forbindelse" |
| `a11y.wifiRestored` | "Wi-Fi connected, searching for speakers" | "Wi-Fi forbundet, søger efter højttalere" |

*State strings may already exist in the codebase under `Speaker.stateDisplay` — verify before adding new localisation keys.*
