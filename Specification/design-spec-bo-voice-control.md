# Design Specification: Bang & Olufsen Voice Controller
**Version:** 1.0  
**Status:** Draft  
**Date:** 2026-04-28  
**Platform:** iOS 26  
**Design Language:** Liquid Glass

---

## Design Philosophy

The B&O Voice Controller should feel like a natural extension of Bang & Olufsen's brand identity — understated luxury, precision, and restraint. The iOS 26 Liquid Glass material system aligns well with this: glass is inherently premium, receding behind content rather than competing with it.

The interface must always feel calm and in control. There is no clutter. When the user speaks, the app responds with quiet confidence. The UI should suggest that the speaker is listening — not that it is waiting.

---

## Design Principles

1. **Recede, don't shout** — Glass surfaces let the background breathe. The UI floats over wallpaper and ambient content, never obscuring it unnecessarily.
2. **One thing at a time** — Each interaction state occupies the full screen. There is no multi-panel complexity in v1.
3. **Voice is the primary control** — Visual elements confirm and guide; they do not replace voice.
4. **Feedback is immediate and exact** — The app always speaks back before acting. The UI reflects this with animated confirmation states.
5. **B&O restraint** — No decorative elements without function. No animation for animation's sake.

---

## Visual Language

### Material: Liquid Glass

Following iOS 26 guidelines, the app uses Liquid Glass as its primary surface material throughout.

| Usage | Material Specification |
|---|---|
| Main listening card | Liquid Glass — thick, frosted, with specular highlight on top edge |
| Speaker selector | Liquid Glass — thin, pill-shaped, horizontally scrollable |
| Volume control track | Liquid Glass — inset, flush with card surface |
| Confirmation sheet | Liquid Glass — bottom sheet, full-width, medium blur radius |
| Tab bar | Liquid Glass — system tab bar, shrinks on scroll per iOS 26 behaviour |
| Status chips (playing, muted) | Liquid Glass — compact pill, tinted with system green / gray |

Liquid Glass surfaces must:
- Refract background content visibly but without distortion that impairs legibility
- Carry a single specular highlight responding to device tilt (motion-driven via CoreMotion)
- Use `UIBlurEffect` with `.systemUltraThinMaterial` for lightweight panels and `.systemMaterial` for primary cards
- Transition with the iOS 26 materialisation animation (gradual modulation of light bending, not a simple fade)

### Layering Model

The interface uses four depth layers, consistent with iOS 26's visual layer model:

```
Layer 4 — Dynamic overlay    Confirmation sheet, error toasts
Layer 3 — Glass controls     Cards, pills, volume track, buttons
Layer 2 — Background blur    Wallpaper / ambient content blurred via Liquid Glass
Layer 1 — Content (wallpaper / photo background chosen by user)
```

Controls float on Layer 3 and never touch the edges of the screen without appropriate safe-area padding.

---

## Typography

| Role | Font | Weight | Size |
|---|---|---|---|
| Speaker name (large) | SF Pro Display | Semibold | 34 pt |
| Now playing title | SF Pro Display | Regular | 22 pt |
| Confirmation read-back | SF Pro Text | Regular | 17 pt |
| Body / list labels | SF Pro Text | Regular | 15 pt |
| Caption / status chips | SF Pro Text | Medium | 12 pt |

- All text uses Dynamic Type; minimum accessibility scale respected
- No custom typefaces — SF Pro is the correct choice for a native iOS 26 app aligning with the B&O brand's own preference for refined, geometric letterforms
- Line length for confirmation read-back capped at ~45 characters per line for comfortable spoken-length reading

---

## Colour

The app uses a **near-neutral palette** with a single warm accent, respecting B&O's design vocabulary of black, white, and aluminium tones.

| Token | Light Mode | Dark Mode | Usage |
|---|---|---|---|
| `--bg-primary` | `#F2F0ED` (warm off-white) | `#0D0D0D` (deep black) | App background |
| `--surface-glass` | System `.systemMaterial` | System `.systemMaterial` | Glass card surfaces |
| `--accent` | `#C8A97E` (warm gold) | `#C8A97E` | Active state, waveform, confirm button |
| `--accent-secondary` | `#8C8278` | `#A09488` | Muted state, inactive icons |
| `--label-primary` | `#1C1917` | `#F5F3F0` | Primary text |
| `--label-secondary` | `#6B6560` | `#A09488` | Secondary text, captions |
| `--destructive` | System red | System red | Cancel / stop states |
| `--success` | System green | System green | Confirmed / playing state |

The warm gold accent (`#C8A97E`) is used sparingly: the active waveform animation, the confirm button fill, and the currently-selected speaker pill. Everywhere else is neutral.

Both light and dark modes are fully supported. The Liquid Glass material automatically adapts; only the background and label colours require explicit mode switching.

---

## Screen Inventory

### 1. Home — Idle State

The primary screen when the app is open and listening but no command is in progress.

**Layout:**
- Full-bleed background: user's iOS wallpaper visible through glass layers, or a default deep-charcoal gradient
- Centre: Large Liquid Glass card (speaker card) — rounded rect, 16 pt corner radius, `systemMaterial` blur
  - Speaker name in SF Pro Display Semibold 34 pt
  - Subtitle: current playback status (e.g. "Playing Jazz Radio" or "Idle")
  - Subtle waveform animation in accent gold when actively listening for a command
- Bottom: Liquid Glass tab-style pill — horizontally scrollable list of available speakers; active speaker highlighted with gold tint
- Top trailing: compact status chip showing connection state (green = online, gray = offline)
- Microphone affordance: not a button — a circular breathing animation beneath the speaker card indicates the app is always listening when foregrounded

**Motion:**
- Speaker card materialises on launch using iOS 26 materialisation
- Waveform pulses smoothly at ~1 Hz when idle-listening; reacts to voice amplitude in real time when the user speaks
- Speaker pill scrolls with momentum; active pill snaps to centre

---

### 2. Command Recognition State

Overlays the home screen while the user is speaking.

**Layout:**
- Speaker card expands slightly (scale 1.02, spring animation)
- Waveform animates at full amplitude, accent gold
- Transcription label appears below the card in SF Pro Text 17 pt, updating live as speech is recognised
- No buttons — the user is speaking; no tap affordance is shown

**Motion:**
- Card scale spring: damping 0.7, response 0.4 s
- Transcription fades in with a 0.15 s opacity animation; text updates with a subtle character-by-character reveal

---

### 3. Confirmation Sheet

Appears after the app has parsed the command and is ready to read back the action.

**Layout:**
- Liquid Glass bottom sheet, slides up from below (standard iOS 26 sheet presentation)
- Sheet height: ~280 pt, fixed (not drag-to-dismiss during confirmation — accidental dismissal must be avoided)
- Content:
  - Small label "About to:" in `--label-secondary`
  - Action read-back in SF Pro Display Regular 22 pt — the exact spoken string (e.g. *"Playing Jazz Radio on Beosound"*)
  - Two buttons, full-width, stacked vertically:
    - **Confirm** — filled Liquid Glass button, accent gold tint, label "Yes"
    - **Cancel** — outlined Liquid Glass button, label "No"
  - Mic indicator: small pill at sheet top — "or say Yes / No"

**Motion:**
- Sheet slides up with spring (damping 0.75, response 0.5 s)
- Confirm button has a soft haptic (`.medium` impact) on tap
- On confirmation: sheet dismisses, action executes, a brief success toast appears

---

### 4. Now Playing State

Replaces the idle speaker card when playback is active.

**Layout:**
- Speaker card gains a secondary Liquid Glass inset panel showing:
  - Track / station name (SF Pro Display Regular 22 pt)
  - Animated playback indicator (three bars, animated in accent gold)
- Volume track: horizontal Liquid Glass slider below the card, flush inset
  - Current volume shown as a label on the trailing end (e.g. "42")
  - Track fills with accent gold from left edge to current value
- Active speaker pill in tab row shows gold tint and a small "playing" dot

---

### 5. Error / Unrecognised State

**Layout:**
- A Liquid Glass toast slides down from the top safe area (not a modal — non-blocking)
- Icon: SF Symbol `exclamationmark.bubble` in `--label-secondary`
- Message text in SF Pro Text 15 pt — the exact error string from the functional spec
- Auto-dismisses after 4 seconds with a fade + slide-up animation
- If the error includes a list (e.g. available favorites), the toast expands to show a compact scrollable list beneath the message

---

### 6. Volume Limit Toast

A lighter variant of the error toast, used specifically when volume is clamped.

- Icon: SF Symbol `speaker.slash` (muted) or `speaker.wave.3` (max)
- Message: *"Beosound is already at maximum volume"*
- Accent tint on icon only — label remains neutral

---

## Iconography

All icons use SF Symbols 6 (iOS 26 baseline). No custom iconography in v1.

| Action | SF Symbol |
|---|---|
| Microphone / listening | `mic.fill` |
| Playing | `waveform` |
| Paused | `pause.fill` |
| Stopped | `stop.fill` |
| Volume | `speaker.wave.2.fill` |
| Muted | `speaker.slash.fill` |
| Favorites | `star.fill` |
| Speaker / device | `hifispeaker.fill` |
| Confirm | `checkmark` |
| Cancel | `xmark` |
| Error | `exclamationmark.bubble` |
| Connection offline | `wifi.slash` |

SF Symbols must use the `.hierarchical` rendering mode where the symbol has multiple layers, allowing the Liquid Glass material to interact naturally with symbol depth.

---

## Interaction & Animation Principles

### Haptics
Use `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator` throughout:

| Event | Haptic |
|---|---|
| Command recognised | `.light` impact |
| Confirmation sheet appears | `.medium` impact |
| Action confirmed and sent | `.success` notification |
| Error state | `.error` notification |
| Volume limit reached | `.warning` notification |

### Voice Feedback
The app speaks all confirmation and error strings using `AVSpeechSynthesizer` with the `com.apple.voice.compact.en-US.Samantha` voice (or system default English). Speech rate: 0.5 (AVSpeechUtteranceDefaultSpeechRate). The spoken string always matches the text displayed in the confirmation sheet exactly.

### Transitions
- All screen state changes use shared element transitions anchored on the speaker card
- Sheet presentations use `.sheet` with `presentationDetents([.height(280)])` — no drag handle shown
- Toast animations: slide from top + opacity, spring with damping 0.8

---

## Accessibility

- **VoiceOver:** All interactive elements have `accessibilityLabel` strings. The confirmation sheet announces the read-back string automatically when it appears.
- **Dynamic Type:** All text scales with user's preferred text size. Card height adapts to accommodate larger type.
- **Reduce Motion:** When "Reduce Motion" is enabled, all spring animations are replaced with simple cross-fades at 0.2 s. The waveform animation is replaced with a static pulsing opacity.
- **Increase Contrast:** Liquid Glass blur is reduced; surfaces gain a 1 pt border in `--label-secondary` for legibility.
- **Colour Blind:** The accent gold is not used as the sole differentiator for any state — icon shapes and labels always accompany colour cues.
- **Minimum tap target:** 44 × 44 pt for all tappable elements, per Apple HIG.

---

## Safe Area & Layout

- Respect all iOS 26 safe area insets (top, bottom, leading, trailing)
- Speaker card: horizontally inset 20 pt from screen edges
- Bottom tab pill: sits 12 pt above the home indicator safe area
- Confirmation sheet: extends to the bottom safe area; buttons sit above the home indicator
- No UI elements placed under the Dynamic Island

---

## Screens Summary

| Screen | Trigger | Primary Element |
|---|---|---|
| Home — Idle | App launch / command complete | Speaker card + waveform |
| Command Recognition | Voice detected | Expanded card + live transcription |
| Confirmation Sheet | Command parsed | Bottom sheet + action read-back |
| Now Playing | Playback active | Speaker card + playback panel + volume track |
| Error Toast | Unrecognised / not found / offline | Top toast (non-blocking) |
| Volume Limit Toast | Volume clamped | Top toast (non-blocking) |

---

## Out of Scope for Design (v1)

- Onboarding / first-launch flow (speaker pairing is handled by the B&O app)
- Settings screen
- Dark/light mode toggle — follows system setting automatically
- iPad layout
- Landscape orientation — portrait only in v1

---

## Design Tokens Reference

```swift
// Spacing (8-point grid)
let spacing4: CGFloat = 4
let spacing8: CGFloat = 8
let spacing12: CGFloat = 12
let spacing16: CGFloat = 16
let spacing20: CGFloat = 20
let spacing24: CGFloat = 24

// Corner radii
let radiusCard: CGFloat = 20
let radiusPill: CGFloat = 100 // fully rounded
let radiusSheet: CGFloat = 16 // system default

// Animation
let springDamping: CGFloat = 0.75
let springResponse: CGFloat = 0.45

// Blur materials (UIKit)
let materialPrimary = UIBlurEffect(style: .systemMaterial)
let materialThin = UIBlurEffect(style: .systemUltraThinMaterial)
```
