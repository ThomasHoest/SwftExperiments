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
