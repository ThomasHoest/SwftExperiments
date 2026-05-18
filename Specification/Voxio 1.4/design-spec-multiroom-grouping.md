# Design Specification: Multiroom Grouping
**Version:** 1.1
**Status:** Draft
**Date:** 2026-05-08
**Platform:** iOS 26 (iPhone, portrait) — SwiftUI
**Design Language:** DarkGlass (dark Liquid Glass, warm-gold accent)
**References:** VoxioSpecification-1.4.md Feature 2, design-spec-home-screen-redesign.md (§2 bottom bar, §3.4 group chip row), design-spec-touch-playback-controls.md, CLAUDE.md (`BeoColor`, `Spacing`, `Radius`, `BeoAnimation`, `DarkGlassButton`)

---

## Design Philosophy

Multiroom grouping is spatial — you're placing a speaker into a playing session. The join gesture reflects this directly: the user drags a speaker pill from the bottom bar and drops it onto the session card. The card is the group. The pill is the speaker. The drag is the join.

**Drag to join, tap to leave.** Joining uses a drag gesture from the bottom bar onto the session card. No sheets, no modals, no Add chip. Removing a group member is a single tap on the chip — immediate, no confirmation.

**The bottom bar is the speaker palette.** Speakers that are not yet in a session live in the bottom bar as draggable pills. Dragging one onto a session card joins it to that group. The spatial relationship — bar at the bottom, card above — reinforces the "move into" mental model.

**Group membership is always visible.** The group chip row at the bottom of the session card (introduced in F3 as display-only) shows every member at a glance. It becomes the interactive leave surface in F2.

---

## Visual Language

No new design tokens. The existing `DarkGlassButton` pill shape is reused for the drag ghost. Drag-state visual variants are defined below.

### Bottom bar pill drag states

| State | Appearance |
|---|---|
| Idle (draggable) | Normal pill — `BeoType.caption`, `BeoColor.muted` / `white.opacity(0.07)` |
| Idle (not draggable — playing host or already grouped) | 0.5 opacity; long-press gesture disabled |
| Long-press held | Pill scales to 1.06×, subtle shadow lift (`shadow(color: .black.opacity(0.4), radius: 8, y: 4)`) |
| Drag ghost | Semi-transparent copy of pill (0.85 opacity) follows finger, 1.06× scale |
| Source dimmed (in-flight join) | Original pill dims to 0.5 opacity, non-draggable, until API call resolves |

### Session card drop target states

| State | Appearance |
|---|---|
| Idle | Normal card — no indicator |
| Ghost hovering above card | Card border becomes `BeoColor.accent` at 1.5 pt width; card background gains a subtle gold inner glow (`.overlay(Capsule().stroke(BeoColor.accent, lineWidth: 1.5))`) |
| Drop complete | Border fades out over 0.25 s; new group chip appears with spring entry |

### Group member chip (display + remove)

Member chips in the chip row are unchanged from F3's display definition. They gain a tap target for the remove action.

---

## Screen Index

| § | Surface | Trigger |
|---|---|---|
| 1 | Bottom bar — idle | Speakers discovered, not yet grouped |
| 2 | Drag in progress | User long-presses a pill and drags |
| 3 | Session card — drop zone active | Drag ghost enters the card bounds |
| 4 | Session card — after drop | Speaker joined; chip appears |
| 5 | Group member chip — remove | User taps an existing group chip |

---

## Section 1 — Bottom bar (idle — draggable pills)

### 1.1 Drag affordance

The bottom bar pills are draggable via a **long press → drag** gesture. A long press of 0.35 s initiates the drag — this threshold prevents accidental drags during horizontal bar scroll.

On long-press initiation:
- A "lift" haptic fires (`HapticEngine.shared.dragLifted()`).
- The pill scales to 1.06× with a `BeoAnimation.spring` transition.
- A ghost copy appears at the pill's position, ready to follow the finger.

```
┌──────────────────────────────────────────┐
│  [Badeværelse ▐▌▌] — [Stue]—[Kitchen]   │  ← bottom bar
│   playing pill      draggable pills      │
│   (not draggable)                        │
└──────────────────────────────────────────┘
```

### 1.2 Draggable vs non-draggable pills

- **Solo playing speaker** pill: not draggable (it is the group host).
- **Idle/stopped speaker** pill: draggable.
- **Speaker already in a group** pill: not draggable. Shown at 0.5 opacity in the bottom bar to signal unavailability. The long-press gesture is disabled — it does not initiate a drag.

### 1.3 Drag handle visual

Pills show no persistent drag handle icon — the long-press gesture is the affordance. A one-time coach mark appears on the first session where a draggable speaker exists: `"Drag to join this session"` in `BeoType.caption`, `BeoColor.muted`, positioned above the first draggable pill, fading out after 3 s. Dismissed permanently once the user completes a drag or taps the screen.

---

## Section 2 — Drag in progress

### 2.1 Ghost pill

The drag ghost is a copy of the pill rendered at 0.85 opacity, 1.06× scale, following the user's finger. It uses the same visual pill style as the bottom bar — dark glass capsule, speaker name label.

```
                 ╔═══════════╗
                 ║   Stue    ║  ← ghost (follows finger, 0.85 opacity)
                 ╚═══════════╝

 [Badeværelse] ─ [░░░░░] ─ [Kitchen]   ← "Stue" pill dimmed in bar
```

- The ghost clips to the screen bounds — it cannot drag outside the viewport.
- If the finger moves back over the bottom bar without releasing over a card, the drag cancels: ghost animates back to the source pill with a `BeoAnimation.spring` return; source pill restores to full opacity.

### 2.2 Invalid drop zones

Dropping over any area that is not a session card cancels the drag. A cancel haptic fires (`HapticEngine.shared.dragCancelled()`).

---

## Section 3 — Session card — drop zone active

When the drag ghost enters the bounds of a session card, the card enters the **drop zone active** state:

```
┌─────────────────────────────────────┐  ← gold border (1.5 pt, BeoColor.accent)
│  Badeværelse                        │
│  ● Playing         ← subtle gold    │
│                       inner glow    │
│  [volume]                           │
│  [    ⏸    ]                        │
│  [Fav1]  [Fav2]                     │
│  [+ Kitchen]   ← existing members  │
└─────────────────────────────────────┘
          ╔═══════════╗
          ║   Stue    ║  ← ghost hovering above card
          ╚═══════════╝
```

- Card border: `BeoColor.accent` (gold), 1.5 pt, applied via `.overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(BeoColor.accent, lineWidth: 1.5))`.
- Card background: `BeoColor.accent` at 0.04 opacity overlaid on the existing card background.
- Animation: border fades in with `BeoAnimation.spring` as the ghost enters the card bounds.
- If there are multiple cards in the strip (§3.5 of F3), each card activates its own drop zone independently when the ghost enters its bounds.

---

## Section 4 — Session card — after drop

### 4.1 Drop action

When the user releases the ghost over a session card:

1. `HapticEngine.shared.commandRecognised()` fires immediately.
2. The ghost animates (scale down + fade) into the chip row position.
3. A new chip appears in **loading state** — dimmed label, inline `ProgressView` spinner (10 pt) replacing the `+` prefix. The chip is present but not yet confirmed.
4. `speakerToJoin.client.join(peer: hostSpeaker.identifier)` is called with a 10-second client-side timeout. The spinner persists for the full duration. If the call does not complete within 10 seconds, it is treated as a failure — the chip fades out, the source pill restores to full draggable opacity, and an error toast is shown.
5. Card border fades back to normal immediately.
6. Source pill remains at 0.5 opacity (non-draggable) in the bottom bar while the call is in flight.
7. **On success**: chip transitions from loading to full opacity with a brief pulse (1.0 → 0.7 → 1.0 over 0.4 s). Source pill shows the group connector (F3 §2.3).
8. **On failure**: chip fades out; source pill restores to full draggable opacity; `.error` toast appears; `HapticEngine.shared.errorOccurred()` fires.

### 4.2 After-drop card state (loading)

```
┌──────────────────────────────────────┐
│  Badeværelse                beolink  │
│  ● Playing                           │
├──────────────────────────────────────┤
│  DR P1   dr.dk/p1               ▐▌▌  │
├──────────────────────────────────────┤
│  ══════════════════════════    20    │
├──────────────────────────────────────┤
│             [     ⏸     ]            │
├──────────────────────────────────────┤
│  [Fav1]  [Fav2]  [Fav3]             │
├──────────────────────────────────────┤
│                                      │
│  [+ Kitchen]  [⟳ Stue…]             │  ← new chip in loading state (spinner)
│                                      │
└──────────────────────────────────────┘
```

### 4.3 After-drop card state (success)

```
│  [+ Kitchen]  [+ Stue ✦]            │  ← chip resolves to full opacity + pulse
```

---

## Section 5 — Group member chip — remove

### 5.1 Trigger

Tapping an existing group member chip immediately initiates the remove — no confirmation dialog. Touch is a deliberate action.

### 5.2 Remove action

- Tap chip → chip fades out immediately (optimistic, `.transition(.opacity)`).
- `memberSpeaker.client.leave()` is called.
- `discovery.removeMember(memberSpeaker)` updates the group model locally.
- On success: `HapticEngine.shared.commandRecognised()` fires; bottom bar connector for that speaker is removed (F3).
- On failure: chip reappears; `.error` toast appears; `HapticEngine.shared.errorOccurred()` fires.

### 5.4 Group collapses to solo

When the last group member chip is removed, the chip row disappears. The card becomes a solo session. The bottom bar shows the speaker as an independent pill with no connector.

---

## Section 6 — Interaction model

### 6.1 Gesture summary

| Action | Gesture | Result |
|---|---|---|
| Join speaker to group | Long press pill → drag → drop on card | Chip appears in loading state; joins on API success |
| Cancel join | Drag and release outside any card | Ghost returns to bar; no change |
| Remove from group | Tap chip | Chip fades immediately; speaker leaves on API success |

### 6.2 Haptics

| Event | Haptic |
|---|---|
| Drag initiated (long press held) | `HapticEngine.shared.dragLifted()` |
| Ghost enters drop zone | `HapticEngine.shared.dragEnteredDropZone()` |
| Drop success | `HapticEngine.shared.commandRecognised()` |
| Drag cancelled | `HapticEngine.shared.dragCancelled()` |
| Remove success | `HapticEngine.shared.commandRecognised()` |
| API error | `HapticEngine.shared.errorOccurred()` |

### 6.3 Update strategy

**Join** is not optimistic — the chip appears in a loading/spinner state and transitions to full opacity only on API success. Latency can reach 10 seconds; the spinner persists for the full duration. A 10-second client-side timeout is enforced: if the call does not resolve within 10 seconds it is treated identically to an API failure.

**Leave** is optimistic — the chip fades immediately and reappears if the API call fails.

### 6.4 Platform behaviour

`SpeakerClient.join(peer:)` and `.leave()` abstract the Mozart (`beolinkExpand` / `beolinkLeave`) and BNR (`expandExperience`) paths. No platform-specific UI difference is surfaced.

### 6.5 Multiple session cards

When the strip contains multiple cards (F3 §3.3), the user can drag a pill onto any visible card — including one that is partially visible (peeking at the edge). The peeking card activates its drop zone when the ghost enters its bounds. Dragging off the edge of the strip does not trigger a scroll — the user must manually swipe to another card before dragging onto it.

---

## Section 7 — UX/UI Issues and Open Questions

| # | Question | Impact | Status |
|---|---|---|---|
| UQ-1 | Should Remove require confirmation? | Remove flow | Resolved |
| UQ-2 | When a speaker is already in group A and dragged to group B's card — auto-move or prevent? | Drag from grouped pill | Resolved |
| UQ-3 | What is the expected latency of `beolinkExpand`? Should the chip use a spinner? | API loading UX | Resolved |
| UQ-4 | Does the coach mark appear once per app lifetime or once per session? | Discoverability | Resolved |

### Resolved decisions

| # | Decision | Rationale |
|---|---|---|
| UQ-1 | **No confirmation on remove.** Tap chip → immediate leave. | Touch is deliberate and unambiguous. |
| UQ-2 | **Speakers already in a group are not draggable.** They appear at 0.5 opacity in the bottom bar; the long-press gesture is disabled. | Prevents accidental group disruption. The user must first remove the speaker from its current group before adding it elsewhere. |
| UQ-3 | **Join chip shows a spinner for the full API call duration (up to 10 s).** Chip appears in loading state on drop; transitions to full opacity on success; fades on failure. Not optimistic. | `beolinkExpand` latency can reach 10 seconds. Showing a confirmed chip before the call completes would mislead the user. |
| UQ-4 | **Coach mark shows once per app lifetime.** Dismissed on first drag completion or screen tap. | Showing it repeatedly would be intrusive; the gesture is learnable after one encounter. |

---

## Section 8 — Accessibility

Drag-and-drop is not accessible via VoiceOver. An alternate join path is provided:

- Session card: `.accessibilityAction(named: "Add speaker")` that presents a simple picker (system `UIAlertController` action sheet) listing available speakers by name.
- Selecting a speaker from this picker joins it — identical result to a drag.
- Group member chips: `.accessibilityLabel` = `"[Name], in group. Tap to remove."` + `.accessibilityRole(.button)`.
- New chip after join: `UIAccessibility.post(notification: .announcement, argument: "[Name] joined [Host]")`.
- Remove success: `UIAccessibility.post(notification: .announcement, argument: "[Name] removed from group")`.

---

## Section 9 — Out of Scope (v1.4)

- Named group presets or saved group configurations.
- Broadcast controls — apply action to all speakers simultaneously (voice-only in v1.4).
- `beolinkJoin()` without a peer (the physical Join button scenario).
- Per-member volume — touch controls apply to the host speaker only.
- Drag scroll: automatically scrolling the card strip while holding a drag near the edge.
- Drag from within the session card chip row to reorder or move members.

---

## Appendix A — SF Symbol reference

| Symbol | Usage |
|---|---|
| `checkmark` | (Accessibility picker — already-joined indicator) |

---

## Appendix B — String catalogue (EN + DA)

| Key | English | Danish |
|---|---|---|
| `grouping.coachMark` | `"Drag to join this session"` | `"Træk for at tilslutte"` |
| `grouping.removeTitle` | — removed (UQ-1: no confirmation dialog) | — |
| `grouping.removeAction` | — removed (UQ-1: no confirmation dialog) | — |
| `grouping.a11yAddAction` | `"Add speaker"` | `"Tilføj højttaler"` |
| `grouping.a11yJoined` | `"%@ joined %@"` | `"%@ tilsluttede %@"` |
| `grouping.a11yRemoved` | `"%@ removed from group"` | `"%@ fjernet fra gruppe"` |
| `a11y.chip.member` | `"%@, in group. Tap to remove."` | `"%@, i gruppe. Tryk for at fjerne."` |
| `a11y.chip.loading` | `"Connecting %@…"` | `"Forbinder %@…"` |
