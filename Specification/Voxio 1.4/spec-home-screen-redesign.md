# Home Screen Redesign Specification — Voxio 1.4
**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-09
**Platform:** iOS 26 (iPhone, portrait) — SwiftUI
**References:** VoxioSpecification-1.4.md (Feature 3), design-spec-home-screen-redesign.md (v1.2 — all visual tokens, layout decisions, and resolved UQs), CLAUDE.md (`Speaker`, `SpeakerGroup`, `SpeakerDiscoveryService`, `BeoColor`, `Spacing`, `Radius`, `BeoAnimation`, `BeoType`)

**Amendment history**

| Version | Date | Summary |
|---|---|---|
| 1.0 | 2026-05-09 | Initial draft. Functional spec for Feature 3 of Voxio 1.4 — home screen redesign. Covers session strip, group chip row, bottom bar redesign, discovery and offline states. |

---

## Introduction

The home screen today shows one card for the currently selected speaker plus a horizontally scrolling pill bar of all discovered speakers. It is functional but fails to convey playback state at a glance: the user cannot see which speakers are playing, which are grouped together, or what other sessions are active. The discovery and offline states are also conflated — the same "Offline" chip appears whether the device has no Wi-Fi or whether Wi-Fi is fine but no B&O speakers were found.

Feature 3 redesigns the home screen around the concept of a **session** (one or more speakers playing together as a `SpeakerGroup`). The card area becomes a swipeable horizontal strip — one card per active session. The bottom pill bar gains a playback indicator and a group-membership connector. Idle speakers stay in the bottom bar but no longer surface as a session card. Discovery and offline states get distinct, premium visual treatments driven by `NWPathMonitor` (Wi-Fi state) and `discovery.didSettle` (scan state).

All visual decisions — colours, spacing, typography, motion, copy strings — are specified in `design-spec-home-screen-redesign.md` and are not duplicated here. This document covers the user-facing behaviour, acceptance criteria, technical surface, and out-of-scope boundaries.

### What is in scope

- Swipeable session card strip on the home screen, one card per active `SpeakerGroup`
- Group member chip row inside each session card (display only — interactivity is F2)
- Bottom bar redesign — `PlaybackBars` per playing pill, group connector line, discovery-order preserved
- Three distinct top-of-screen states — Discovering, Offline, Connected (with speaker count)
- Discovery state pre-settle (animated pulse rings) and post-settle "no speakers found" state with retry
- Dedicated offline state driven by `NWPathMonitor`
- `ConnectionStatusChip` rewrite to show three distinct copy states
- Auto-recovery when Wi-Fi reconnects (no user action required)

### What is NOT in scope (covered elsewhere)

- Touch playback controls on the session card (play/pause, volume, favorites) — Feature 1, `spec-touch-playback-controls.md`
- Touch interactivity on group member chips (tap to leave group, etc.) — Feature 2, `spec-multiroom-grouping.md`
- Voice command parsing or new intents — unchanged from v1.3
- Backend or telemetry changes — unchanged
- iPad layout, landscape orientation, Lock Screen / Live Activity — out of scope per `VoxioSpecification-1.4.md`
- Light-mode variants — app remains dark-only
- Streaming service integrations — deferred to v1.5

---

## Technical Context

| Decision | Choice | Rationale |
|---|---|---|
| Session strip control | `ScrollView(.horizontal)` with `.scrollTargetBehavior(.viewAligned)` and paging | Resolved UQ-5. Provides the 8 pt card-peek affordance that `TabView(.page)` cannot cleanly support. |
| Session model | One session = one `SpeakerGroup`. Sessions are filtered to groups whose host speaker `isPlaying`. | Resolved UQ-4. Idle speakers appear only in the bottom bar — never as a session card. |
| Bottom bar pill order | Discovery order (unchanged from v1.3) — not re-sorted by group | Resolved UQ-3. Re-sorting mid-session is jarring. Group membership is signalled by the connector line and by the session card chip row. |
| Bottom bar group connector | 1 pt line in `BeoColor.muted` at 0.3 opacity drawn between adjacent grouped pills only | Resolved UQ-3. Connector is omitted between non-adjacent grouped pills; group membership remains visible via the session card chip row. |
| Group chip overflow | "+N more" chip when group has > 3 members. Tap is a no-op in F3 (deferred to F2). | Resolved UQ-6. Horizontal scroll inside a swipeable card creates a gesture conflict. |
| Discovery state machine | New three-state machine driven by `(isOnWifi, didSettle, sessionCount)` | Resolved UQ-8. Replaces the current `speakerCount > 0` proxy. |
| Network detection | `NWPathMonitor` (`Network.framework`) on a new `NetworkMonitor` `@Observable @MainActor` class | Independent of speaker discovery. `ConnectionStatusChip` consumes `isOnWifi` instead of inferring from `speakerCount`. |
| Discovery retry | Auto-retry every 30 s silently; "Search again" button forces immediate retry; "Still looking…" sub-label appears after 10 s without a result | Resolved UQ-9. Auto-retry is seamless; the visible label after 10 s ensures the user knows the app is still working. |
| Selected speaker ↔ visible card | Two-way binding: swiping the strip selects the session host in the bottom bar; tapping a bottom-bar pill scrolls the strip to that speaker's session (or to the group session if the speaker is a non-host member). Idle bottom-bar pills do not scroll the strip (no session exists). | Required by acceptance criteria US-62 / US-63. |

---

## Goals

- A user picking up the phone sees, without tapping, what is playing and where, including which speakers are linked into a group
- Swiping between active sessions is one gesture and visibly affordable via the 8 pt card peek and the page dot indicator
- The bottom bar conveys playback state at a glance via gold `PlaybackBars` on each playing pill and a connector line between grouped pills
- The discovery state feels alive — the orb is visibly searching, not broken
- The offline state is unambiguous and recovers automatically when Wi-Fi returns — no user action required
- All four state transitions (Discovering → Connected, Connected → Offline, Offline → Discovering, Discovering → No-speakers-found) animate without jank and announce themselves to VoiceOver

---

## Out of Scope (this version)

- Touch controls inside the session card (play/pause/stop/volume/favorites) — Feature 1
- Touch interactivity on group member chips, multiroom join/leave UI — Feature 2
- "+N more" chip tap action (deferred to F2 multiroom UI)
- Stopped/idle-speaker session cards — Resolved UQ-4 confirms session strip is "now playing" only
- Light-mode variants — app remains dark-only
- iPad layout, landscape orientation
- Lock Screen / Live Activity now-playing surface
- Manual offline retry button — `NWPathMonitor` recovery is automatic per Resolved UQ-9
- Re-ordering bottom bar pills by group — Resolved UQ-3 keeps discovery order

---

## User Stories

---

**US-60 — Swipe between active sessions**
> As a user with two or more speakers playing, I want to swipe horizontally between session cards so that I can see what's playing on each speaker (or group) without leaving the home screen.

**Acceptance criteria:**
- When two or more `SpeakerGroup`s have a playing host, the home screen shows a horizontal strip of session cards — one card per playing group — instead of a single fixed card.
- Each card occupies the full screen width minus `Spacing.s16` on each side; the next card peeks at 8 pt on the trailing edge.
- Swiping horizontally pages between cards with the native `ScrollView` paging feel; the card snaps to alignment after each swipe (no half-page positions).
- Below the strip, page dots appear: one dot per session, the active dot styled per design spec §3.3, the inactive dots styled per design spec §3.3.
- Page dots are not interactive (swipe is the only navigation gesture in F3).
- When the visible card changes, the corresponding session's host speaker becomes the selected speaker in the bottom bar.
- When only one session exists, the strip behaves exactly as the current single-card layout: no peek, no page dots, no horizontal scroll affordance.
- When zero sessions exist (no playing speaker) and at least one speaker is discovered, the existing empty/idle card area is shown unchanged from v1.3.
- Idle/stopped speakers never appear as session cards regardless of discovery state.
- When a speaker transitions from idle → playing, a new session card is inserted into the strip without losing the user's current scroll position (the existing visible card remains visible).
- When a speaker transitions from playing → idle, its session card is removed from the strip; if it was the visible card, the strip animates to the nearest remaining session card (or to the empty/idle card if none remain).
- VoiceOver users navigate session cards in standard element-focus order; the swipe gesture does not interfere with the VoiceOver swipe.

---

**US-61 — See group members on the session card**
> As a user with a group of speakers playing together, I want to see the other speakers in the group listed on the session card so that I always know which speakers are linked.

**Acceptance criteria:**
- When a session's `SpeakerGroup` has more than one member, the session card shows a chip row at the bottom listing each non-host member as `+ <speaker name>`.
- The host speaker (the card's title) is never repeated in the chip row.
- Chip row layout, typography, padding, and styling are exactly as specified in design spec §3.4.
- When the group has more than 3 non-host members, the row shows the first 2 chips followed by a `+N more` chip where N is the count of remaining members.
- When the group has exactly one member (the host), the chip row is absent — the card has no empty space where the row would be.
- Tapping a member chip is a no-op in F3 (interactivity is added in F2).
- When the group composition changes (member joins or leaves), the chip row updates immediately without re-rendering the rest of the card.
- VoiceOver reads the card label including the appended group members per design spec §3.7 (e.g. `"…also playing: Stue, Kitchen"`).

---

**US-62 — Tell which speakers are playing from the bottom bar**
> As a user, I want the bottom bar to show me which speakers are currently playing and which are grouped, so that I have a single overview of the whole system.

**Acceptance criteria:**
- Each pill in the bottom bar shows the speaker name plus, when the speaker is playing, the `PlaybackBars` animation right-aligned inside the pill.
- The pill style for playing, paused/idle, and selected states matches design spec §2.2 exactly.
- When two or more grouped speakers are adjacent in the bottom bar (in discovery order), a 1 pt connector line is drawn between them per design spec §2.3.
- When grouped speakers are not adjacent in the bottom bar, no connector line is drawn — group membership is conveyed via the session card chip row only.
- Pill order is the discovery order; the bar is not re-sorted by group at any time.
- Idle/stopped speakers are shown in the bottom bar (with no `PlaybackBars`, default pill style).
- Tapping a pill scrolls the session card strip to that speaker's session: if the speaker is a session host, the strip scrolls to its card; if the speaker is a non-host group member, the strip scrolls to the group's session card; if the speaker is idle (no session), the tap selects the speaker but does not scroll the strip (the empty/idle card remains visible if no other session exists).
- The currently-visible session card's host speaker is rendered as the selected pill in the bottom bar.
- When a speaker transitions playing → idle, its `PlaybackBars` disappear with the standard fade animation; the pill remains in place.
- When a speaker transitions idle → playing, its `PlaybackBars` appear with the standard fade animation; the pill remains in place.
- VoiceOver labels per design spec §2.5 (`"<name>, playing"`, `"<name>, selected"`).

---

**US-63 — Pick up the phone during discovery and see something happening**
> As a user opening the app while it scans the network, I want to see that the app is actively searching, so that I know it isn't broken or frozen.

**Acceptance criteria:**
- While `discovery.didSettle == false` and at least one Wi-Fi interface is available, the card area shows the discovery-state UI per design spec §4.2: orb at full opacity with the existing idle pulse plus three concentric pulse rings expanding outward from it, plus the centred label "Searching for speakers…" / "Søger efter højttalere…".
- The bottom bar is not shown until at least one speaker is discovered (the strip and the bottom bar both appear together).
- If no speaker has been discovered after 10 seconds, the sub-label "Still looking…" / "Søger stadig…" appears below the search label.
- The discovery service auto-retries the scan every 30 seconds silently — no visible UI change beyond the continued pulse rings and the "Still looking…" sub-label.
- When the first speaker resolves, the discovery UI cross-fades to the normal home screen (session card strip + bottom bar) per design spec §4.4. The orb stays in position; the card slides in from below with opacity.
- The Reduce Motion variant per design spec §4.2 is respected (single static ring at 0.1 opacity; orb pulse suspends).
- The `ConnectionStatusChip` shows "Searching…" / "Søger…" copy throughout the pre-settle phase.
- VoiceOver announces "Searching for speakers" once on entering this state.

---

**US-64 — See a clear "no speakers found" state with a retry option**
> As a user on a healthy Wi-Fi network where no B&O speakers are reachable, I want a clear explanation and a way to manually retry, so that I'm not left staring at an animation that may never end.

**Acceptance criteria:**
- When `isOnWifi == true && discovery.didSettle == true && sessionCount == 0 && discoveredSpeakerCount == 0`, the card area shows the post-settle empty state per design spec §4.3.
- The state shows: a dim orb (0.4 opacity, no pulse), the heading "No speakers found" / "Ingen højttalere fundet", a body paragraph per design spec Appendix B, and a "Search again" / "Søg igen" button.
- Tapping "Search again" triggers `discovery.restart()` and immediately transitions back to the pre-settle discovery UI (US-63). A small spinner appears inside the button briefly during the transition.
- The bottom bar is not shown in this state.
- The `ConnectionStatusChip` continues to show "Searching…" / "Søger…" copy during the manual retry's pre-settle window, then reverts to "No Wi-Fi" or speaker-count copy as appropriate.
- VoiceOver button label: "Search again for speakers" / "Søg igen efter højttalere".

---

**US-65 — See an explicit offline state when Wi-Fi is unavailable**
> As a user without Wi-Fi, I want the app to tell me clearly that it cannot work without Wi-Fi (and not blame the speakers), so that I know what to fix.

**Acceptance criteria:**
- When `NWPathMonitor` reports no Wi-Fi available (`isOnWifi == false`), the card area shows the offline state per design spec §5.3 regardless of `didSettle` or `sessionCount`.
- The state shows: a very-dim orb (0.2 opacity, no animation), the heading "No Wi-Fi" / "Ingen Wi-Fi", a body paragraph per design spec Appendix B, and the sub-label "Recovers automatically when Wi-Fi reconnects" / equivalent Danish.
- The bottom bar is hidden in this state.
- The voice waveform and mic-status label are hidden in this state. Voice recognition does not start while offline.
- The `ConnectionStatusChip` shows "No Wi-Fi" / "Ingen Wi-Fi" copy with the `wifi.slash` symbol.
- There is no manual retry button — recovery is automatic.
- When `NWPathMonitor` reports Wi-Fi restored, the offline UI cross-fades to the discovery UI (US-63) per design spec §5.4. Discovery starts automatically.
- The transition uses `BeoAnimation.toast` (200 ms opacity fade) followed by `BeoAnimation.spring` for the orb restore.
- VoiceOver announces "No Wi-Fi connection" / "Ingen Wi-Fi-forbindelse" on entering this state and "Wi-Fi connected, searching for speakers" / equivalent Danish on Wi-Fi restoration.

---

**US-66 — `ConnectionStatusChip` shows the right copy for the current state**
> As a user, I want the small chip in the top bar to tell me unambiguously whether the app is searching, offline, or connected, so that I know which state the system is in without reading body copy.

**Acceptance criteria:**
- The `ConnectionStatusChip` displays one of three copy states based on `(isOnWifi, didSettle, discoveredSpeakerCount)`:
  - **Searching…** — when `isOnWifi == true && didSettle == false`. Symbol: `wifi`.
  - **No Wi-Fi** — when `isOnWifi == false`. Symbol: `wifi.slash`.
  - **n speakers** — when `isOnWifi == true && didSettle == true && discoveredSpeakerCount > 0`. Symbol: `wifi`. The integer is the count of discovered speakers (not the count of sessions).
- "n speakers" copy uses the existing v1.3 number-only display for parity (chip remains compact).
- "No speakers found" / post-settle empty case shows the chip in the **No Wi-Fi**-style fallback only when Wi-Fi is genuinely down; if Wi-Fi is up but no speakers were found, the chip shows "0 speakers" (a degenerate case of the "n speakers" form).
- Chip styling (padding, glass effect, font) is unchanged from v1.3.
- VoiceOver label per design spec §5.5 (offline announcement) and the existing v1.3 announcement otherwise.
- Chip copy updates within one animation frame of the underlying state change.

---

## Technical Requirements

### Component changes

| Component | Change |
|---|---|
| `HomeView.swift` | `cardArea` replaced with new `SessionStripView` when `sessionCount >= 1`. Existing `emptyState` retained for the "speakers discovered but none playing" case. New state-machine routing at the top of the view body selects between Discovering, Offline, NoSpeakersFound, and Normal layouts. Bottom bar shown only when `sessionCount >= 1` or `discoveredSpeakerCount >= 1`. |
| `SessionStripView` (new) | `ScrollView(.horizontal)` with `.scrollTargetBehavior(.viewAligned)`. Iterates `discovery.groups.filter { $0.hostSpeaker.isPlaying }`. Hosts a child `SpeakerCardView` per session and a `SessionPageDots` view below. Manages `@Binding var selectedSpeaker` two-way with bottom bar. |
| `SessionPageDots` (new) | Renders one dot per session per design spec §3.3. Hidden when sessionCount == 1. `accessibilityHidden(true)`. |
| `SpeakerCardView` | Add `GroupChipRow` at bottom when group has more than one member. New view modifier accepts `[Speaker]` (non-host members) and renders chips per design spec §3.4. No other changes to existing card regions in F3. |
| `GroupChipRow` (new) | `HStack(spacing: Spacing.s8)` of `Capsule()` chips per design spec §3.4. Renders first 3 chips inline; if more, renders 2 chips + `+N more`. Display only — no tap handlers. |
| `SpeakerSelectorPill` | Refactor pill rendering to include `PlaybackBars` (extracted from `SpeakerCard.swift` to a shared `Components/PlaybackBars.swift`) when `speaker.isPlaying`. Add a `@ViewBuilder` helper to draw a 1 pt connector line between adjacent pills that share a `SpeakerGroup`. Pill order remains discovery order. |
| `PlaybackBars` (new shared) | Extract the existing private struct from `SpeakerCard.swift` to `iOS/Voxio/Features/Home/Components/PlaybackBars.swift` for reuse in `SpeakerSelectorPill`. Behaviour unchanged. |
| `ConnectionStatusChip` | Rewrite to consume three inputs: `isOnWifi: Bool`, `didSettle: Bool`, `speakerCount: Int`. Render one of three copy states per US-66. Existing chip styling unchanged. |
| `NetworkMonitor` (new) | `@Observable @MainActor final class NetworkMonitor` wrapping `NWPathMonitor`. Exposes `isOnWifi: Bool` and `isAvailable: Bool`. Lives at the `HomeView` level (`@State private var network = NetworkMonitor()`). Started in `onAppear`, paused on `onDisappear` of the home screen if appropriate. |
| `DiscoveryStateView` (new) | Composite view rendering one of: pre-settle scanning UI (animated pulse rings + label + "Still looking…" sub-label after 10 s); post-settle empty state (dim orb + heading + body + Search again button); offline state (very-dim orb + heading + body + auto-recovery sub-label). Selects between these based on injected `(isOnWifi, didSettle, discoveredSpeakerCount)`. |
| `PulseRingsView` (new) | Three concentric `Circle()` strokes per design spec §4.2 motion specification. Reduce-Motion variant: single static ring. |
| `SpeakerDiscoveryService` | Add public `restart()` convenience that calls `stop()` then `start()` and resets `didSettle = false`. Add internal 30-second auto-retry timer that calls `restart()` while in the post-settle empty state. Cancel the timer when speakers are found or the view disappears. |

### Data model

No changes to the `Speaker`, `SpeakerGroup`, or backend schemas. The session strip is a derived projection over `discovery.groups` filtered by `$0.hostSpeaker.isPlaying`. Group membership for the chip row is read from `SpeakerGroup.members` excluding the host.

### Network state

`NetworkMonitor` runs `NWPathMonitor` on a background `DispatchQueue`. State updates are forwarded to `@MainActor`. The monitor reports:

| State | `isOnWifi` | Notes |
|---|---|---|
| `path.status == .satisfied && path.usesInterfaceType(.wifi) == true` | `true` | Standard "on Wi-Fi" case |
| Cellular only | `false` | App treats this as offline because B&O speakers require LAN |
| No connectivity | `false` | Offline state |

`ConnectionStatusChip` and the home-screen state machine consume `network.isOnWifi`. The existing `discovery.didSettle` continues to drive scan completion.

### Discovery state machine

The home screen selects a layout based on `(network.isOnWifi, discovery.didSettle, sessionCount, discoveredSpeakerCount)` per the matrix in design spec §5.2:

| `isOnWifi` | `didSettle` | `discoveredSpeakerCount` | `sessionCount` | Layout |
|---|---|---|---|---|
| false | any | any | any | Offline (US-65) |
| true | false | 0 | 0 | Discovering — pre-settle (US-63) |
| true | true | 0 | 0 | No speakers found (US-64) |
| true | any | > 0 | 0 | Normal (idle empty/idle card + bottom bar) |
| true | any | > 0 | > 0 | Normal (session strip + bottom bar) |

`sessionCount` is `discovery.groups.filter { $0.hostSpeaker.isPlaying }.count`. `discoveredSpeakerCount` is `discovery.groups.flatMap(\.members).count`.

### API calls

No new API surface. `discovery.start()` and the new `discovery.restart()` are the only added entry points consumed by the UI. All existing Mozart REST/WS calls are unchanged.

### Localisation

All new strings are listed in design spec Appendix B. Add to the existing localisation catalogues for English and Danish. State strings (`state.playing`, `state.paused`, etc.) may already exist under `Speaker.stateDisplay`; verify before adding duplicate keys.

### Accessibility

- All new interactive elements meet the 44×44 pt minimum touch target.
- Reduce Motion: pulse rings, `PlaybackBars`, and the in-place pulse all suspend per design spec §1.5, §2.2, §4.2, §4.5.
- Dynamic Type: all new text uses `BeoType` tokens.
- VoiceOver order: status bar → session card → page dots region (label "Session n of m") → voice feedback → bottom bar pills.
- All state transitions that change card-area meaning announce via `.accessibilityAnnouncement` per design spec §1.5, §3.7, §4.5, §5.5.

---

## Error States

| Scenario | Expected Behaviour |
|---|---|
| Speaker discovered mid-pre-settle scan | Cross-fade from discovery UI to normal home screen per US-63 acceptance criteria; orb stays in position; card slides in from below. |
| All speakers disappear (e.g. all powered off) post-discovery | If `discoveredSpeakerCount` drops to 0, the home screen returns to either Offline (if `isOnWifi == false`) or No-speakers-found (if `isOnWifi == true && didSettle == true`). Bottom bar disappears. |
| Wi-Fi drops while speakers are playing | Home screen transitions to Offline state per US-65 within one `NWPathMonitor` callback. Existing speaker state is retained in memory but not displayed; on Wi-Fi restore the discovery service is restarted. |
| Wi-Fi flaps (drops and immediately returns) | Each `NWPathMonitor` event drives one transition. Debouncing is not added in F3 — rapid flaps may produce visible flicker; acknowledged. |
| User taps "Search again" while pre-settle is already running | No-op. The button is hidden during pre-settle (US-64 acceptance criterion). |
| `discovery.restart()` fails to discover any new speakers within 30 s | The post-settle empty state remains shown; the 30-second auto-retry continues silently. |
| User swipes the session strip during a card insertion/removal animation | Native `ScrollView` paging handles the gesture; swipe wins. The animation completes after the gesture ends. |
| Group composition changes (member joins) while the corresponding session card is visible | Chip row updates in place per US-61 acceptance criterion. The card itself does not re-render or reflow. |
| Speaker host changes within a group while the session card is visible | Card title updates to the new host's name. Members chip row recomputes. Card retains its position in the strip. |
| Voice command starts while in Offline state | Voice recognition does not start while offline (US-65 acceptance criterion). The mic indicator is hidden. |
| Bottom bar overflows screen width | Existing horizontal scroll behaviour is preserved (`SpeakerSelectorPill` already supports horizontal scroll). |

---

## Non-Functional Requirements

**Latency**

- Session card swipe-to-snap: completes within `BeoAnimation.spring` (≈ 450 ms).
- Wi-Fi loss → Offline state transition: rendered within 200 ms of the `NWPathMonitor` callback.
- Wi-Fi restore → Discovery state transition: rendered within 200 ms of the `NWPathMonitor` callback.
- First speaker discovered → normal home screen: cross-fade completes within 600 ms (`BeoAnimation.spring` after a 200 ms opacity fade).
- "Search again" tap → pre-settle UI restored: within 200 ms.
- Page dot indicator change on swipe: within one animation frame (16 ms) of the `ScrollView` paging snap.

**Performance**

- Up to 8 concurrent sessions render without dropped frames at 60 fps on iPhone 14 (the existing target device).
- `PlaybackBars` animations on up to 8 simultaneous bottom-bar pills do not measurably increase CPU usage above the v1.3 baseline.
- Pulse rings during discovery do not exceed 2% CPU on the same device.

**Accessibility**

- All state transitions support VoiceOver announcements per US-63 / US-65 / design spec §4.5 / §5.5.
- Reduce Motion: all decorative motion (pulse rings, `PlaybackBars`, in-place pulse, card spring) suspends per design spec sections referenced above.
- Dynamic Type up to AX5 size: layout reflows; chip row falls back to vertical wrapping if the row exceeds the card width.
- 44×44 pt minimum touch target on "Search again" button and all bottom-bar pills (existing constraint preserved).

**Privacy**

- `NWPathMonitor` reports interface availability only; no IP/SSID/Wi-Fi name is logged or surfaced.
- No new telemetry events are emitted by F3 components.

**Availability behaviour**

- All discovery and offline states are local-only — they require no backend.
- Auto-retry behaviour (30 s loop, 10 s "Still looking…" label) runs entirely on-device.

---

## Open Questions

*No open questions remain for F3. All UQs in `design-spec-home-screen-redesign.md` §6 are resolved per §7. Master spec questions Q-1–Q-4 in `VoxioSpecification-1.4.md` belong to F1/F2 and do not affect F3.*

---

## Resolved Decisions

| Question | Decision |
|---|---|
| Session strip control implementation | `ScrollView(.horizontal)` with `.scrollTargetBehavior(.viewAligned)` per resolved UQ-5. |
| Are stopped/idle speakers shown as session cards? | No — bottom bar only per resolved UQ-4. |
| Are bottom bar pills re-sorted by group? | No — discovery order preserved per resolved UQ-3. |
| Group chip overflow when more than 3 members | "+N more" chip; tap deferred to F2 per resolved UQ-6. |
| `ConnectionStatusChip` copy | Three distinct states ("Searching…" / "No Wi-Fi" / "n speakers") driven by `NWPathMonitor` + `discovery.didSettle` per resolved UQ-8. |
| Discovery retry behaviour | Auto-retry every 30 s; "Still looking…" sub-label after 10 s; "Search again" button forces immediate retry per resolved UQ-9. |
| Network detection mechanism | `NWPathMonitor` (`Network.framework`) wrapped in a new `NetworkMonitor` `@Observable @MainActor` class. |
| Offline state retry mechanism | Automatic via `NWPathMonitor` — no manual "Retry" button. |
| Parallax highlight on session cards | Front-most card only per resolved UQ-7. Offscreen cards are frozen. |
| Bottom bar pill a11y hint | `isSelected ? "" : "Show this speaker"` per design-spec §2.5. Resolved from E-54 review gap. |
| Pill a11y label states (combined "playing + selected") | Four explicit states enumerated in design-spec §2.5: idle/playing × selected/unselected. Resolved from E-54 review gap. |
| Pill row auto-scroll on external `selectedSpeaker` change | Pill row scrolls to keep the selected pill visible (mirror of session strip behaviour). `BeoAnimation.spring`; instant on Reduce Motion. Resolved from E-52 review gap. |
| `scrollHostId` initial value on first mount | `selectedSpeaker`'s group host if it matches a playing group; otherwise `groups.first?.hostSpeaker.id`. No animation on initial assignment. Resolved from E-52 review gap. |
| Animation policy: initial vs. subsequent `scrollHostId` change | No animation on the initial `nil → ID` assignment in `onAppear`. Subsequent changes (swipe, pill-tap, programmatic) animate with `BeoAnimation.spring` (Reduce Motion: snap). Resolved from E-52 review gap. |
| Removed-speaker reset policy when the selected speaker disappears mid-view | Strip aligns to `groups.first?.hostSpeaker.id`; `selectedSpeaker` itself is left untouched (pill row filter hides the absent pill; next discovery cycle replaces). Resolved from E-52 review gap. |
| `PlaybackBars` canonical `(lo, hi)` height pairs | `[(6, 14), (14, 6), (10, 16)]` at reference 20 pt frame; scaled proportionally for other heights. Documented in design-spec §Motion and ADR-E54 §7. Resolved from E-54 review gap. |
| Reduce Motion treatment of bottom-bar group connector line | None — connector is a static element regardless of Reduce Motion. Documented in design-spec §2.3. Resolved from E-54 review gap. |
| VoiceOver order: page dots region | Removed from VoiceOver order; page dots are `accessibilityHidden(true)` per design-spec §3.7. Resolved from E-52 review (contradictory spec text in §Accessibility cleaned up). |
| `discovery.groups` ordering stability across renders | Stable within a discovery cycle (appended in discovery order, not re-sorted). Implementers must not introduce `.sorted(by:)`. Resolved from E-52 review gap. |

---

## Amendment History

| Date | Source | Change |
|---|---|---|
| 2026-05-09 | Initial draft | First version of the home screen redesign functional spec. Five user stories (US-60 through US-66, plus US-66 covering the chip rewrite) covering swipeable sessions, group chip display, bottom bar clarity, discovery feedback, no-speakers-found state, and offline feedback. Derived from `design-spec-home-screen-redesign.md` v1.2 and `VoxioSpecification-1.4.md` v1.4.0. |
| 2026-05-11 | E-52 / E-54 review fallout | Added 11 resolved-decision rows covering pill a11y hint, four pill a11y label states, pill-row auto-scroll, `scrollHostId` initial value and animation policy, removed-speaker reset, `PlaybackBars` canonical (lo, hi) pairs, connector Reduce Motion treatment, page-dots VoiceOver order, and `discovery.groups` ordering stability. Each was a spec gap surfaced during agent-team reviews of E-52 and E-54. Corresponding clarifications also added to `design-spec-home-screen-redesign.md` §§Motion / 2.3 / 2.5 / 3.5 / §Accessibility, `ADR-E52` §7, and `ADR-E54` §7. |
