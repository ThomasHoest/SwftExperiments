# Voxio Specification — v1.4
**Version:** 1.4.0
**Status:** Draft
**Date:** 2026-05-08
**Platform:** iOS 26 (iPhone, portrait)
**References:** VoxioSpecification-1.3.md, CLAUDE.md

**Amendment history**

| Version | Date | Summary |
|---|---|---|
| 1.4.0 | 2026-05-08 | Initial draft. Three features: F1 Touch Playback Controls, F2 Multiroom Grouping, F3 Home Screen Redesign. |
| 1.4.1 | 2026-05-11 | Added "Feature Dependencies" section (F3 → F2 hard, F3 → F1 soft, shared platform changes, recommended sequencing) per architect review. |

---

## Introduction

Voxio v1.4 shifts the app from voice-only to voice-first. The primary goal is to make core playback actions — play/pause, volume, favorites, and multiroom grouping — fully accessible through touch, without requiring the user to speak a command.

A secondary goal is a significant improvement to the home screen: better visual feedback, a redesigned speaker picker, and a swipeable session view that gives users a clear picture of what is playing and where.

Voice control remains fully functional and unchanged. Touch controls are additive — a new layer on top of the existing voice pipeline.

What v1.4 changes:

1. **Touch playback controls** — play/pause/stop, volume adjustment, and favorite selection are now available as touch targets on the now-playing card. No voice required.
2. **Multiroom grouping via touch** — users can join and unjoin speakers from a touch UI. Active groups are clearly visualised.
3. **Home screen redesign** — improved user feedback, a visually refreshed bottom speaker bar, and a swipeable card interface for browsing active playing sessions and their group members.

### What is NOT changing in v1.4

- Voice command parsing pipeline — unchanged.
- All existing `VoiceCommand` cases and intent vocabulary — unchanged.
- The "Voxio" trigger word and orb state machine — unchanged.
- The Mozart and BNR API integrations — unchanged.
- The backend and telemetry pipeline — unchanged.
- Language coverage — English and Danish only.
- Deployment target — iOS 26 (unchanged).
- iPad layout and landscape orientation — out of scope.
- Streaming service integrations (Spotify, Deezer, Tidal) — deferred to v1.5.

---

## Technical Context

| Decision | Choice | Rationale |
|---|---|---|
| Touch controls placement | On the now-playing card | Keeps controls contextual and avoids a separate control surface |
| Multiroom join model | Existing `Group` abstraction (unchanged) | Touch UI is a new surface over the existing grouping API |

*Further technical decisions will be added as per-feature specs are written.*

---

## Goals

- Allow users to perform all primary playback actions (play, pause, stop, volume, favorites) by touch alone
- Allow users to join and unjoin speakers into groups by touch alone
- Show users which speakers are playing together in a group
- Make the home screen bottom bar clearer and more visually polished
- Allow users to swipe between active playing sessions
- Improve feedback so users always know the result of an action

---

## Out of Scope (v1.4)

- New voice commands or changes to the parsing pipeline
- Streaming service integrations (Spotify, Deezer, Tidal) — moved to v1.5
- Backend or telemetry changes
- iPad layout and landscape orientation
- New language support
- Live Activity / Lock Screen now-playing surface
- WidgetKit changes

---

## Feature 1 — Touch Playback Controls

*Full detail in `spec-touch-playback-controls.md` · Design in `design-spec-touch-playback-controls.md` · Tasks in `epics-and-tasks-touch-playback-controls.md`*

Users can play, pause, stop, adjust volume, and start a favorite directly from the now-playing card — no voice command required. Controls are only shown where the speaker state supports them (e.g. favorite picker only when favorites are available).

---

## Feature 2 — Multiroom Grouping

*Full detail in `spec-multiroom-grouping.md` · Design in `design-spec-multiroom-grouping.md` · Tasks in `epics-and-tasks-multiroom-grouping.md`*

Users can join and unjoin speakers into a group from a touch UI. The current group composition is clearly shown on the home screen so users always know which speakers are playing together.

---

## Feature 3 — Home Screen Redesign

*Full detail in `spec-home-screen-redesign.md` · Design in `design-spec-home-screen-redesign.md` · Tasks in `epics-and-tasks-home-screen-redesign.md`*

Three improvements to the home screen: (1) better visual feedback after user actions; (2) a redesigned bottom speaker bar that is clearer and more polished; (3) a swipeable session interface — one card per active playing session, showing group members — so users can browse and switch between sessions.

---

## Feature Dependencies

The three v1.4 features share the home screen and `SpeakerCard.swift`. Their dependency relationships are summarised below; per-feature specs and epic docs are the source of truth for the details.

```
                F3 (Home Screen Redesign)
                          │
              ┌───────────┴───────────┐
              │ hard                  │ soft (shared file)
              ▼                       ▼
   F2 (Multiroom Grouping)   F1 (Touch Playback Controls)
```

### F3 → F2 (hard dependency — F2 cannot ship until F3 lands)

F2 attaches drag and drop interactions to UI surfaces F3 introduces. Specifically:

- **F3 / E-52** — `SessionStripView` and session card root. F2 / E-59 (T-5905) attaches `.dropDestination(for: SpeakerIdentifier.self)` to each session card.
- **F3 / E-53** — display-only `GroupChipRow` on the session card. F2 / E-60 (T-6002) adds the loading-chip variant to this row; F2 / E-61 (T-6102) adds tap-to-remove to its chips.
- **F3 / E-54** — refactored `SpeakerSelectorPill` and extracted `PlaybackBars`. F2 / E-59 (T-5903, T-5904) attaches `.draggable(speaker.identifier)` to the new pill.

F2 development can proceed in parallel against stub F3 components; verification (F2 / T-5910, T-6005, T-6107) and ship require the real F3 surfaces to be merged.

### F3 → F1 (soft dependency — same file)

F1 modifies `SpeakerCard.cardContent` internals (volume slider, transport row, favorites row, stopped-state pill). F3 / E-53 mounts the new `GroupChipRow` at the bottom of the same view body, and F3 / E-54 extracts the private `PlaybackBars` struct out of `SpeakerCard.swift`. The two features can be implemented in parallel; merge conflicts at integration are expected and managed by sequencing the `PlaybackBars` extraction first (see "Recommended sequencing" below).

F3's discovery state machine (E-55) reserves the "speakers discovered but none playing" empty/idle card slot for F1's stopped-state card layout. F1's stopped-state Play pill renders in this slot, not inside the session strip — confirmed in F3 spec §Technical Requirements (the "Normal (idle empty/idle card + bottom bar)" row of the state matrix).

### F1 → F2 (no functional dependency)

F1 introduces `SpeakerGroup.setVolumeOnAllMembers(_:)` (or equivalent) using `withTaskGroup` for concurrent group-volume broadcast. F2 does not consume this helper. The two features can ship in either order from F2's perspective.

### Shared platform changes

| Change | Owner | Required by |
|---|---|---|
| `PlaybackBars` extraction to `Features/Home/Components/PlaybackBars.swift` | F3 / E-54 T-5401 | F3 (E-54), F1 (kept in `SpeakerCard` view) |
| `NetworkMonitor` (`@Observable @MainActor` wrapper around `NWPathMonitor`) | F3 / E-55 T-5501 | F3 only |
| `SpeakerDiscoveryService.restart()` + 30 s auto-retry timer | F3 / E-55 T-5510, T-5511 | F3 only |
| `HapticEngine.dragLifted()` / `.dragEnteredDropZone()` / `.dragCancelled()` (new methods) | F2 / E-59 prereq | F2 only |
| `SpeakerIdentifier: Transferable` conformance | F2 / E-59 T-5901 | F2 only |
| `SpeakerGroup.setVolumeOnAllMembers(_:)` | F1 / E-57 T-5704 | F1 only |
| `DarkGlassIconButton` accepts variable size (default 36 pt; F1 passes 52 pt) | F1 / E-56 T-5602 | F1 only |

### Recommended sequencing

1. **F3 / E-54 T-5401** — extract `PlaybackBars` to a shared component file. Standalone PR. Lands first to avoid merge conflicts between F1 and the rest of F3.
2. **F3 / E-52** — `SessionStripView`, page dots, two-way binding with bottom bar. Unblocks F2 / E-59 drop destination.
3. **F3 / E-53** — `GroupChipRow` mount on `SpeakerCard`. Unblocks F2 / E-60 loading chip and F2 / E-61 tap-to-remove.
4. **F3 / E-54 (remainder)** — `SpeakerSelectorPill` rewrite, group connector line, always-visible bar logic. Unblocks F2 / E-59 `.draggable` attachment.
5. **F3 / E-55** — `NetworkMonitor`, `ConnectionStatusChip` rewrite, discovery/offline state machine. Wraps the entire `cardArea` produced by E-52. Lands last in F3.
6. **F1 / E-56 → E-57 → E-58** — fully parallel with F3 from day one. Sequence within F1 is enforced by the F1 epics doc.
7. **F2 / E-59 → E-60 → E-61** — can start in parallel against stubbed F3 surfaces; ships only after F3 / E-52, E-53, and E-54 are merged.

A two-engineer team can run F1 and F3 in parallel from week one. F2 joins once F3 / E-53 and E-54 are nearing merge.

---

## Open Questions

| # | Question | Owner | Status |
|---|---|---|---|
| Q-1 | Should volume control be a slider, stepper (+/−), or both? | Design | Open |
| Q-2 | What is the touch affordance for the multiroom join — a sheet, inline checkboxes, or a dedicated group editor? | Design | Open |
| Q-3 | How many sessions are realistic to display in the swipeable view — is pagination needed? | Product | Open |
| Q-4 | Should favorites be shown on the card directly, or behind a tap-to-expand affordance? | Design | Open |

---

## Resolved Decisions

*None yet.*
