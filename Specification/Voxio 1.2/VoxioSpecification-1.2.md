# Voxio Specification — v1.2
**Version:** 1.2.1
**Status:** Draft
**Date:** 2026-05-01
**Platform:** iOS 26 (iPhone, portrait)
**References:** VoxioSpecification-1.1.md, epics-and-tasks-voxio-1.1.md (E-20–E-26, T-2001–T-2610), design-spec-widget-voxio-1.2.md, research-findings-voxio-1.2.md, api-spec-beonetremote.md, design-spec-group-ui-voxio-1.2.md, CLAUDE.md
**Languages:** English (`en-US`) and Danish (`da-DK`) — both fully supported (unchanged from v1.1)

**Amendment history**

| Version | Date | Summary |
|---|---|---|
| 1.2.0 | 2026-05-01 | Initial draft. Two feature workstreams: ASE/BNR speaker support (E-27, E-28) and iOS widget + voice shortcuts (E-29, E-30, E-31). |
| 1.2.1 | 2026-05-01 | Amendment: Group abstraction and speaker join/leave feature (E-32). Updated E-27 (Group model, GroupDiscovery, SpeakerClient protocol additions). Updated E-29 (join/leave App Intents). New user stories US-41–US-48. New error states and open questions. |

---

## Introduction

Voxio v1.2 adds three independent workstreams. The first extends hardware compatibility to Bang & Olufsen ASE-platform products (Beosound Stage, Beoplay M5, BeoLab 90, and all other `_beoremote._tcp` devices) via the BeoNetRemote (BNR) REST + long-poll API. The second brings the app to the home screen and Control Center through a WidgetKit home-screen widget (`systemSmall` + `systemMedium`), a Control Widget, and Siri voice shortcuts via `AppShortcutsProvider`. The third (added in v1.2.1) introduces the `Group` abstraction — unifying multiple speakers playing in the same Beolink session into a single top-level entity — and the speaker join/leave voice command.

What v1.2 changes:

1. **Shared speaker abstraction** — two new Swift protocols (`SpeakerClient` and `SpeakerEventSource`) in a new `Core/Protocols/` folder decouple `Speaker` from any specific API. `MozartClient` and `MozartEvents` gain retroactive protocol conformances. The entire app layer becomes API-agnostic. `SpeakerClient` also exposes `join(peer:)` and `leave()` for multiroom participation.
2. **BNRClient and BNREvents** — a new concrete client pair implementing the BNR API (press+release playback commands, 0–9000 volume normalisation, long-poll reconnect loop). From `Speaker`'s perspective, a BNR speaker is indistinguishable from a Mozart speaker at compile time.
3. **Dual mDNS discovery** — `MdnsDiscovery` browses both `_bangolufsen._tcp` (Mozart) and `_beoremote._tcp` (BNR) and instantiates the correct client pair via a factory. ASE and Mozart speakers appear identically in the UI and voice interactions.
4. **Group abstraction** — a new `Group` model that holds 1–N `Speaker` members sharing a Beolink session. `GroupDiscovery` reconstructs existing sessions on startup via union-find on the peer graph. The UI and voice pipeline bind to `[Group]` rather than `[Speaker]`. A group-of-1 is visually and behaviourally identical to the current single-speaker card.
5. **App Intents** — `AudioPlaybackIntent`-conforming intents declared in a shared `VoxioIntents` target used by both the main app and the widget extension. `AppShortcutsProvider` registers Siri phrases in English and Danish. Includes `JoinSpeakerIntent` and `LeaveSpeakerIntent`.
6. **Home-screen widget** — a single WidgetKit widget definition (`systemSmall` + `systemMedium`) backed by an App Groups shared container. Displays live speaker name, track, source, volume, and playback state. Interactive `Button(intent:)` controls for play/pause and volume. Liquid Glass rendering on iOS 26.
7. **Control Widget** — a `ControlWidgetButton` (play/pause) and `ControlWidgetToggle` (mute) pair in Control Center and on the lock screen, always one swipe away.

### What is NOT changing in v1.2

- Voice command intents — the `VoiceCommand` enum is unchanged. The new `AppShortcutsProvider` maps Siri phrases to a parallel but distinct `AppIntent` declaration layer; it does not replace the in-app `CommandParserRouter`.
- The three-tier voice command parsing pipeline (E-24) — unchanged. BNR speakers use the exact same voice commands as Mozart speakers.
- The "Voxio" trigger word and orb state machine (E-26) — unchanged.
- The auto-execute countdown confirmation flow (E-25) — unchanged.
- The dark Liquid Glass visual layer (E-20 through E-23) — unchanged.
- The Mozart API integration (E-02) — unchanged. `MozartClient` and `MozartEvents` acquire retroactive protocol conformances with no logic changes.
- Language coverage — English and Danish only. No new languages in v1.2.
- Deployment target — iOS 26 (unchanged). WidgetKit interactive buttons and the Control Widget API require iOS 17 and iOS 18 respectively; both are satisfied by the iOS 26 floor.
- Live Activity ("now playing") — out of scope for v1.2; deferred to v1.3.
- iPad layout and landscape orientation — out of scope (unchanged from v1.1).

---

## Technical Context

| Decision | Choice | Rationale |
|---|---|---|
| Speaker abstraction approach | `protocol SpeakerClient` + `protocol SpeakerEventSource` in `iOS/Voxio/Core/Protocols/`. `Speaker` holds `any SpeakerClient` and `any SpeakerEventSource`. | Swift 5.7+ existential syntax; no type-erasure wrapper needed. Keeps the app layer fully API-agnostic. Researcher Rank 1 recommendation. |
| BNR event channel | `AsyncStream<SpeakerEvent>` with a long-poll `Task` loop inside `BNREvents`. On each server response (event or timeout), yield the parsed event and immediately re-open the connection. | Long-poll server-side timeout duration is undocumented; treating any response as a re-open signal is the only safe strategy. Exponential backoff on network errors matches `MozartEvents` behaviour. |
| Normalised event type | New `SpeakerEvent` enum replacing `BeoEvent` across the app. Contains only the subset of event types meaningful on both platforms: `.playbackState`, `.metadata`, `.volume`, `.battery`, `.source`. | `BeoEvent` carries Mozart-specific types (`.progress`) that BNR does not emit. A normalised enum prevents platform-specific branches in the app layer. |
| BNR volume normalisation | Inside `BNRClient`: read `level / range.maximum * 100` → `Int` percentage; write `percentage * range.maximum / 100` → integer on 0–range.maximum scale. `range.maximum` is read from the device's `GET /BeoZone/Zone/Sound/Volume/Speaker` response. | The BNR range maximum may be less than 9000 on some configurations; using `range.maximum` rather than the hard-coded 9000 is precise and future-safe. |
| BNR press+release playback commands | Encapsulated inside `BNRClient`. The `SpeakerClient.play()`, `.pause()`, `.stop()` protocol requirements each fire two sequential POSTs (press then release) internally. The caller issues a single `await client.play()`. | Hides the BNR two-POST pattern from every call site. MozartClient sends a single POST per command; both conform to the same single-call protocol surface. |
| BNR 501 handling | On `PUT`/`POST` responses with HTTP 501, log at INFO (`Logger.info("[BNRClient] 501 ignored on write")`) and return without throwing. | Community implementations confirm that some BNR devices return 501 but execute the command; treating 501 as a soft warning avoids false error toasts. |
| mDNS discovery extension | Two `NetServiceBrowser` instances inside `MdnsDiscovery` — one for `_bangolufsen._tcp` (existing) and one for `_beoremote._tcp` (new). A factory closure inspects the resolved `serviceType` and returns the correct `(any SpeakerClient, any SpeakerEventSource)` pair. | Mirrors the existing `MdnsDiscovery` architecture. Two independent browsers are simpler and more reliable than a single browser that handles both service types. |
| BNR favorites | Filter `GET /BeoZone/Zone/Sources` by `inUse == true` and `borrowed == false`; map `friendlyName` → `Favorite`. Activate via `POST /BeoZone/Zone/ActiveSources`. | BNR has no dedicated presets endpoint. This is the practical approach documented in the BNR API spec and confirmed by community implementations. |
| App Intents process routing | `AudioPlaybackIntent`-conforming intents (`PlaybackToggleIntent`, `SetVolumeIntent`, `AdjustVolumeIntent`, `MuteIntent`). `AudioPlaybackIntent.perform()` routes to the main app process, enabling Mozart and BNR network calls from a widget tap. | Standard `AppIntent.perform()` executes in the widget extension sandbox with no `URLSession` access to LAN. `AudioPlaybackIntent` is the documented and only supported mechanism for LAN calls from widget actions. Requires the app to be running in the background. |
| App Groups entitlement | `group.T-Creative.Voxio` on both the main app target and the widget extension target. `UserDefaults(suiteName: "group.T-Creative.Voxio")` is the shared state container. Written by `Speaker` on every event and on `scenePhase == .background`. Read by the widget timeline provider. | P0 blocker for all widget state sharing. Without this entitlement, the widget extension cannot read any live playback data. Must be added to provisioning profiles before widget UI work begins. |
| App-not-running fallback | On `AudioPlaybackIntent` failure (app terminated), the intent's `perform()` writes `app_running: false` to the shared container and calls `WidgetCenter.shared.reloadAllTimelines()`. Widget re-renders with 50 % opacity + "Open Voxio" `Link` button. Detected reactively (Option A from design spec). | A one-failed-tap lag before the fallback UI appears is acceptable for a widget surface. Option B (heartbeat timestamp) adds complexity for minimal gain. |
| Stale state mitigation | Main app writes playback state to the shared container on every `Speaker` event AND writes a synthetic `playbackState: .paused` on `scenePhase == .background`. Widget renders this state honestly. Post-termination staleness of up to 60 seconds is an accepted known edge case. | On-background write catches the most common termination path. iOS does not guarantee delivery of `scenePhase == .background` before a force-quit; this edge case is documented. |
| Widget sizing | One widget definition (`VoxioPlayerWidget`), two supported family sizes: `systemSmall` and `systemMedium`. `systemLarge` is out of scope. | Single definition is the iOS convention. `systemLarge` information density does not justify the canvas for a playback remote. |
| Widget design tokens | New `WidgetButtonToken` namespace (paddingV: 8 pt, paddingH: 12 pt, iconGap: 6 pt, iconOnlySize: 36 pt). New `BeoType.widgetSpeakerName` (12 pt semibold), `BeoType.widgetTrack` (15 pt SF Pro Display regular), `BeoType.widgetCaption` (11 pt regular). `BeoColor.separator` exposed as `static let separator = Color("BeoSeparator")`. | `DarkGlassButtonTokens` padding values (10 pt / 16 pt) are too large for the widget canvas. Main app tokens are unchanged; widget tokens live in the same `DesignTokens.swift` file with clear inline comments distinguishing their use contexts. |
| Control Widget | `ControlWidgetButton` (play/pause via `AudioPlaybackIntent`) + `ControlWidgetToggle` (mute via `MuteIntent`). `AppIntentControlConfiguration` for per-speaker targeting. | `ControlWidgetButton` and `ControlWidgetToggle` are the iOS 18+ APIs for Control Center / lock screen. iOS 26 extends them to macOS and watchOS via paired iPhone automatically — no additional implementation required. |
| Gold accent in widgets | `BeoColor.accent` (`#C8A97E`) used on the play/pause button icon and on the `waveform` playing indicator when playback is active. NOT used on the mute toggle active state. | Consistent with the main app convention: gold signals active/positive playback. Mute is a suppression action; using gold there would be inconsistent. |
| Dynamic Type in widgets | Not supported. Widget text is rendered at fixed sizes per `BeoType.widget*` tokens. | WidgetKit does not support Dynamic Type. The fixed sizes are chosen for legibility at the widget's physical canvas dimensions. |
| Skip button | Omitted from v1.2. | Mozart source-agnostic skip endpoint availability across all active sources is not confirmed. BNR has `/BeoZone/Zone/Stream/Forward` but it is source-dependent. Deferred to v1.3. |
| DesignTokens sharing with widget extension | `BeoColor.swift` and `DesignTokens.swift` are added to the widget extension target's file membership (simplest path). No shared Swift Package is created in v1.2. | A shared package is the cleaner long-term solution but adds build complexity without clear v1.2 necessity. Flagged as an open question for v1.3. |
| Siri voice interaction | `AppShortcutsProvider` with `AudioPlaybackIntent`-conforming intents. Phrases in English and Danish. No microphone in widget — architecturally impossible. Siri is the only voice path from a widget surface. | Widgets run in a sandboxed process with no `AVAudioSession` recording capability. No iOS 26 exception exists. `AppShortcutsProvider` + `AudioPlaybackIntent` is the documented approach. |
| Group abstraction top-level entity | `Group` model holds `members: [SpeakerReference]`, `hostSpeaker: SpeakerReference`, `playbackState`, `volume`, `metadata`. UI and voice pipeline bind to `[Group]`. `Speaker` becomes a member type. | A group-of-1 is behaviourally and visually identical to the current single-speaker card. No UI regression for the common single-speaker case. Enables multi-speaker cards in a future design increment (design-spec-group-ui-voxio-1.2.md). |
| Group identity | `Group.id` is derived from sorted member JIDs/serials (concatenated, SHA-256 prefix optional). Stable across restarts as long as membership is unchanged. | Provides a stable key for the shared container widget state, speaker picker, and analytics. Reconstructed fresh on each launch from `GET /beolink/peers` + BNR sources. |
| GroupDiscovery — Mozart peers | After mDNS resolves all Mozart speakers, call `GET /beolink/peers` on each. Build a union-find graph: speakers sharing a peer edge are in the same group. The speaker with the active source is designated `hostSpeaker`. | `GET /beolink/peers` is already implemented in `MozartClient.getBeolinkPeers()`. No new REST call required. |
| GroupDiscovery — BNR speakers | After mDNS resolves each BNR speaker, call `GET /BeoZone/Zone/Sources`. A source with `multiroom: "listener"` indicates group membership as a follower. A source with `multiroom: "host"` or `borrowed: true` indicates the speaker is session host. Group identity is inferred heuristically — see Open Question 16. | BNR has no peers endpoint; session membership is inferred from source metadata. Partial accuracy is accepted (see Error States). |
| Join API — Mozart→Mozart | `beolinkExpand(jid: A.jid)` called on B's `MozartClient`. B pushes its session to A; A follows B's source. B stays host. | Explicit target avoids the ambiguity of `beolinkJoin()` when multiple sessions exist on the network. All Mozart multiroom methods are already present in `MozartClient` (lines 280–306). |
| Join API — BNR→Any | `POST /BeoZone/Zone/Device/OneWayJoin` called on A's `BNRClient`. A joins whatever Beolink experience is currently active. B must be the active session. | BNR has no `expand` equivalent; broadcast join is the only option. Best-effort when multiple sessions exist. |
| Join API — Mozart→BNR host | `beolinkJoin()` called on A's `MozartClient`. A joins B's active LAN session. Flagged as best-effort — requires B to be the only active session. | BNR cannot push to Mozart (no expand). Mozart `beolinkJoin()` is the only available path. Open question on reliability. |
| Leave API — Mozart | `POST /beolink/leave` on the leaving speaker's `MozartClient` (`beolinkLeave()`). | Already implemented. |
| Leave API — BNR | `DELETE /BeoZone/Zone/ActiveSources/primaryExperience` on the leaving speaker's `BNRClient`. | BNR-specific leave path; encapsulated inside `BNRClient.leave()`. |
| Join confirmation | Join uses the v1.1 auto-execute countdown (3-second countdown, voice cancel) before the API call executes. | Consistent with all other destructive voice commands. A 3-second window is appropriate given that join changes the playback context of two speakers. |
| Leave confirmation | Leave is immediate — no countdown required. | Leave restores the speaker to standalone playback; it is recoverable. Requiring confirmation for a recovery action would be counterproductive. |

---

## Goals

- A B&O user with an ASE-platform speaker (Beosound Stage, Beoplay M5, BeoLab 90, etc.) can discover and control their speaker identically to a Mozart speaker — same UI, same voice commands, same confirmation flow.
- The app layer (`Speaker`, `ContentView`, `SpeakerCardView`, and the voice pipeline) contains zero Mozart-specific or BNR-specific branches at compile time.
- `MozartClient` and `MozartEvents` compile against the new protocols with no logic changes to their implementations.
- The home-screen widget (`systemSmall` and `systemMedium`) displays live playback state — speaker name, track, source, playback status — and lets the user play/pause and adjust volume without opening the app.
- The Control Widget is reachable from Control Center and the lock screen in a single swipe and provides instant play/pause and mute controls.
- Siri can execute `PlaybackToggleIntent`, `SetVolumeIntent`, `AdjustVolumeIntent`, and `MuteIntent` via `AppShortcutsProvider` phrases in English and Danish while the app is running in the background.
- Widget buttons produce a visual state change (widget reload) within 3 seconds of the tap on a normal home network.
- All widget states are honest: loading, playing, paused, stopped, app-not-running, and no-speaker-found each have distinct, readable visual treatments.
- App Groups entitlement is configured in provisioning profiles before any widget UI work begins.
- On app launch, any existing Beolink multiroom session is automatically detected and represented as a `Group` containing the correct member speakers, with no user action required.
- The voice command "Voxio, [Speaker A] join [Speaker B]" causes Speaker A to follow Speaker B's source, with a 3-second countdown confirmation before executing.
- The voice command "Voxio, [Speaker A] leave the group" causes Speaker A to leave its current Beolink session and return to standalone playback, executing immediately (no countdown).
- All natural-language join and leave variant phrases (English and Danish) route to the same `joinSpeaker` and `leaveSpeaker` intents.
- A group of 1 produces visually and behaviourally identical output to the current single-speaker card — no regression for single-speaker users.
- Zero regression to existing Mozart speaker functionality, voice command recognition, confirmation flow, trigger word, visual layer, or accessibility behaviour.

---

## Out of Scope (v1.2)

- **Live Activity ("now playing")** — lock screen + Dynamic Island persistent card. Deferred to v1.3 per research findings.
- **`systemLarge` widget** — information density does not justify the canvas for a playback remote. Deferred indefinitely.
- **Widget for iPad** — portrait iPhone only. `systemMedium` on iPad would require a distinct layout re-evaluation.
- **Widget microphone button / waveform** — architecturally impossible. Widget extensions have no `AVAudioSession` recording capability. There is no workaround and no future path to enable this.
- **Favorite-selection in widget** — playing a specific favorite from a widget tap requires resolving the favorite name parameter, which is beyond the scope of this release. Deferred to v1.3.
- **Skip / next-track control in widget** — Mozart source-agnostic skip endpoint availability is not confirmed. BNR skip is source-dependent. Deferred to v1.3.
- **Now-playing album art in widget** — no album art in any widget in v1.2. The Liquid Glass aesthetic is sufficient at this canvas size.
- **watchOS native app** — the Control Widget appearing on watchOS via iOS 26 mirroring is the only watchOS surface in v1.2. No additional implementation is required or in scope.
- **macOS native app** — same: the Control Widget on macOS via iOS 26 mirroring is automatic.
- **BNR multiroom / Beolink join** — `POST /BeoZone/Zone/Device/OneWayJoin` is now in scope for the join/leave feature (E-32). v1.2 supports BNR→Any join via `OneWayJoin` and BNR leave via `DELETE /BeoZone/Zone/ActiveSources/primaryExperience`. Mozart→BNR host join is supported as best-effort (see E-32 and Open Question 13).
- **BNR play queue / content injection** — `POST /BeoZone/Zone/PlayQueue` content injection is out of scope. Playback control (play/pause/stop/volume/mute/source-selection) is the full feature set for v1.2.
- **Settings screen redesign** — out of scope; deferred in v1.0 and unchanged.
- **BNR TV endpoint support** — picture mode, stand position, and other TV-specific BNR endpoints are out of scope. v1.2 targets audio speaker functionality only.
- **Confirm-by-voice during countdown / variable countdown duration** — unchanged from v1.1 out-of-scope list.
- **Trigger-word personalisation** — unchanged from v1.1 out-of-scope list.

---

## User Stories

### Feature 1: ASE/BNR speaker support

---

**US-28 — ASE speakers are discovered automatically**
> As a user who owns a Bang & Olufsen ASE-platform speaker (Beosound Stage, Beoplay M5, BeoLab 90, etc.), I want the app to find my speaker on the local network automatically, just as it finds Mozart speakers, so that I do not need to do anything different to connect to it.

**Acceptance criteria:**
- The app browses both `_bangolufsen._tcp` and `_beoremote._tcp` mDNS service types simultaneously.
- When a BNR speaker announces itself on the network, it is resolved to an IP address, a `Speaker` is initialised via `BNRClient` + `BNREvents`, and it appears in the speaker list UI within the same timeframe as a Mozart speaker (≤ 5 seconds from announcement to card visible).
- When a BNR speaker leaves the network (service withdrawal or timeout), its card is removed from the speaker list, matching Mozart speaker removal behaviour exactly.
- If both Mozart and BNR speakers are on the same network simultaneously, they all appear in the speaker list with no ordering or visibility conflict.
- The speaker card for a BNR speaker is visually identical to the speaker card for a Mozart speaker — same layout, same tokens, no platform badge or indicator.

---

**US-29 — Playback state is shown for ASE speakers**
> As a user with a BNR speaker, I want to see the current track name, source, playback state, and volume in the app, so that I have the same live information I get with Mozart speakers.

**Acceptance criteria:**
- On `Speaker.initialize()` for a BNR speaker: `GET /BeoZone/Zone/Sound/Volume/Speaker`, `GET /BeoZone/Zone/ActiveSources`, and the device name from `GET /BeoDevice` are fetched in parallel.
- Volume is displayed as a 0–100 integer percentage (BNR raw values divided by `range.maximum` × 100, rounded to the nearest integer).
- Playback state (`play`, `pause`, `stop`, `buffering`) from `GET /BeoZone/Zone/ActiveSources` is mapped to the equivalent `SpeakerEvent.playbackState` value and reflected in the UI.
- Live updates arrive via the BNR long-poll `GET /BeoNotify/Notifications` event channel; `BNREvents` re-opens the connection immediately after each received event.
- `VOLUME` notification events update the on-screen volume within one widget-reload cycle (≤ 3 seconds) on the speaker card.
- `PROGRESS_INFORMATION` notification events update the playback state in the UI.
- `NOW_PLAYING_NET_RADIO` and `NOW_PLAYING_STORED_MUSIC` notification events update the track name and artist in the UI using the same metadata display slots as Mozart speakers.
- `SOURCE` notification events update the source name in the UI.
- Metadata field naming difference: BNR `NOW_PLAYING_STORED_MUSIC` uses `name`, `artist`, `album`; these map to the same `SpeakerEvent.metadata` fields as Mozart's equivalents (`trackTitle`, `artist`, `album`). No BNR-specific metadata path exists in the UI layer.

---

**US-30 — Voice commands work identically on ASE speakers**
> As a user with a BNR speaker, I want to issue the same voice commands I use with Mozart speakers — "Voxio, Beoplay M5 play", "Voxio, turn it up", "Voxio, mute" — and have them work correctly, so that I do not need to learn separate commands for my older speaker.

**Acceptance criteria:**
- Every voice command that works on a Mozart speaker also works on a BNR speaker: `play`, `pause`, `stop`, `adjustVolume(±N)`, `setVolume(N)`, `mute`, `unmute`, `playFavorite(index:)`, `playDefault`, `stopAll`.
- The confirmation flow (auto-execute countdown, voice cancel) is identical for BNR commands.
- Speaker addressing by name works for BNR speakers: "Voxio, Beoplay M5 in kitchen play" is resolved to the correct `Speaker` instance by the existing `dispatchTarget` logic in `Speaker.swift`. Speaker names come from `beoDevice.productFriendlyName.productFriendlyName` in the BNR `GET /BeoDevice` response.
- `play()` via `BNRClient` sends `POST /BeoZone/Zone/Stream/Play` followed by `POST /BeoZone/Zone/Stream/Play/Release` internally, and resolves as a single action from the caller's perspective.
- `pause()` via `BNRClient` sends the press+release pair for pause internally.
- `setVolume(N)` via `BNRClient` sends `PUT /BeoZone/Zone/Sound/Volume/Speaker/Level` with `level = N * range.maximum / 100`.
- `mute()` sends `PUT /BeoZone/Zone/Sound/Volume/Speaker/Muted` with `muted: true`.
- `playFavorite(index:)` resolves to the `index`-th source in the filtered source list (`inUse == true`, `borrowed == false`) and activates it via `POST /BeoZone/Zone/ActiveSources`.

---

**US-31 — BNR errors are surfaced consistently**
> As a user with a BNR speaker, I want to see the same error toasts as with a Mozart speaker when the speaker is unreachable or a command fails, so that the experience feels consistent.

**Acceptance criteria:**
- `URLError.timedOut` from a BNR request maps to `MozartError.timeout` (or an equivalent `SpeakerError.timeout`) and produces the same "Speaker not responding" toast as Mozart timeout errors.
- Connection refused / unreachable errors map to `SpeakerError.unreachable` and produce the same "Speaker unreachable" toast.
- BNR HTTP 501 on a write operation is treated as a soft warning: logged at INFO, not surfaced as a user-visible error toast. The operation is considered completed from the user's perspective.
- BNR HTTP 404 on a write operation maps to `SpeakerError.httpError(404)` and produces an error toast identical to a Mozart 404 error response.
- If the BNR long-poll connection drops (network error, 5-second reconnect), the UI does not show an error — the reconnect loop is silent. An error toast appears only if reconnection fails after three consecutive attempts with exponential backoff.

---

**US-32 — The app layer is free of API-specific branches**
> As a developer, I want `Speaker`, `ContentView`, and the voice pipeline to compile against protocols — not concrete API clients — so that adding a third speaker API in the future requires only a new client pair and a discovery factory update.

**Acceptance criteria (verifiable at code review):**
- `Speaker` holds `let client: any SpeakerClient` and `let eventSource: any SpeakerEventSource` — no `MozartClient` or `BNRClient` type references in `Speaker.swift`.
- `ContentView`, `SpeakerCardView`, and all views in `iOS/Voxio/Features/` hold no `import` or type reference to `MozartClient`, `MozartEvents`, `BNRClient`, or `BNREvents`.
- The `SpeakerClient` protocol defines at minimum: `func play() async throws`, `func pause() async throws`, `func stop() async throws`, `func setVolume(_ level: Int) async throws`, `func mute(_ muted: Bool) async throws`, `func getVolume() async throws -> Int`, `func getPlaybackState() async throws -> SpeakerEvent`, `func getSources() async throws -> [Favorite]`, `func activateSource(_ id: String) async throws`.
- The `SpeakerEventSource` protocol defines: `func events() -> AsyncStream<SpeakerEvent>`.
- `MozartClient` and `MozartEvents` conform to `SpeakerClient` and `SpeakerEventSource` respectively via retroactive conformances (extensions in `Core/Protocols/`) with no changes to their implementation files.
- `BNRClient` and `BNREvents` conform to the same protocols as their primary declaration.

---

### Feature 2: iOS widget and voice shortcuts

---

**US-33 — The user can add a Voxio widget to the Home Screen**
> As a Voxio user, I want to add a small or medium Voxio widget to my Home Screen, so that I can glance at what is playing and tap once to pause without unlocking my phone or finding the app.

**Acceptance criteria:**
- "Voxio" appears in the iOS widget gallery when the user long-presses the Home Screen and taps the "+" button.
- The user can place either `systemSmall` or `systemMedium` as a single widget definition (both sizes are supported under one widget entry point named "Voxio Player").
- After placement, the widget displays the most recently active speaker from the App Groups shared container, or the empty state (§1.5 of the design spec) if no speaker has ever been discovered.
- The user can long-press the placed widget and tap "Edit Widget" to select a specific speaker from a list or choose "Automatic (most recent)".
- After configuration, the widget reflects the selected speaker's current state from the shared container.
- The widget renders with the Liquid Glass background on iOS 26. Token palette (`BeoColor.labelPrimary`, `BeoColor.labelSecondary`, `BeoColor.accent`) matches the main app.

---

**US-34 — The systemSmall widget shows playback state and provides a play/pause button**
> As a user, I want the small widget to show me what is playing and let me tap once to play or pause, so that I can control my speaker without opening the app.

**Acceptance criteria:**
- `systemSmall` layout from top to bottom: speaker icon + speaker name row (12 pt semibold), track/station name (15 pt SF Pro Display regular, 2-line max), source label (11 pt regular), flexible spacer, play/pause button (full available width, 36 pt height).
- Widget edge padding: 12 pt all sides (`Spacing.s12`). Zone spacing: 4 pt.
- When playing: a static `waveform` SF Symbol at 14 pt in `BeoColor.accent` leads the track name; the button shows `pause.fill` icon in `BeoColor.accent` with label "Pause".
- When paused: no waveform symbol; the button shows `play.fill` icon in `BeoColor.labelSecondary` with label "Play".
- When stopped/idle: no waveform; track name is "—"; button shows `play.fill` in `BeoColor.labelSecondary`.
- When loading (app just launched, state not yet in shared container): button shows `ellipsis` icon, disabled.
- When app is not running: entire widget content at 50% opacity; button replaced by "Open Voxio" `Link` button that opens the app via URL scheme.
- When no speaker found (empty state): `hifispeaker.slash` SF Symbol at 24 pt in `BeoColor.labelSecondary`; "No speaker found" label at 11 pt; "Open Voxio" `Link` button.
- The play/pause button uses `Button(intent: AudioPlaybackIntent())` — a `DarkGlassButton`-equivalent surface with `.glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: Capsule())` and 0.5 pt hairline border, scaled to widget canvas via `WidgetButtonToken` padding values.
- Button vertical padding: 8 pt (`WidgetButtonToken.paddingV`); horizontal padding: 12 pt (`WidgetButtonToken.paddingH`).
- Accessibility labels: "Play [Speaker Name]" / "Pause [Speaker Name]" (en); "Afspil [Højttalernavn]" / "Sæt [Højttalernavn] på pause" (da).
- VoiceOver widget description: "[Speaker Name], [State], [Track Name]".

---

**US-35 — The systemMedium widget adds volume controls and richer track information**
> As a user, I want the medium widget to also show me the volume level and let me tap to raise or lower the volume, so that I have full quick-control without leaving the Home Screen.

**Acceptance criteria:**
- `systemMedium` layout: full-width speaker header row (icon + name, 22 pt height), then a two-column content area. Left column: track name (15 pt SF Pro Display, 2 lines), source + volume inline label ("Spotify · 74", 11 pt regular). Right column: play/pause button (full right-column width), volume control row (volume-down button + decorative speaker icon + volume-up button).
- Left column width: 55 % of content area. Right column: 45 %. Column gap: 12 pt. A hairline divider at `BeoColor.separator` opacity 0.15 separates the columns.
- Volume down button: `minus.circle.fill` icon, 36 pt circle, intent `AdjustVolumeIntent(delta: -10)`.
- Volume up button: `plus.circle.fill` icon, 36 pt circle, intent `AdjustVolumeIntent(delta: +10)`.
- Volume down is disabled (opacity 0.4) when volume is 0. Volume up is disabled at 100.
- Volume controls are disabled when app is not running or volume data is absent from shared container.
- Accessibility labels for volume buttons: "Volume up" / "Volume down" (en); "Skru op" / "Skru ned" (da). Volume buttons use `.frame(minWidth: 44, minHeight: 44)` to meet the minimum tap target requirement.
- App-not-running state: entire content at 50% opacity; an "Open to control" label at 11 pt centred; play/pause and volume rows replaced by an "Open Voxio" `Link` button spanning the full right column.
- Empty state: "No speaker found" centred across the full content area; "Open Voxio" button.
- States match `systemSmall` (playing, paused, stopped, loading, app-not-running, empty) with the same visual cues plus the source · volume inline label.

---

**US-36 — Widget taps execute in under 3 seconds and update the widget state**
> As a user, I want the widget to reflect the result of my tap quickly, so that the interaction feels live and not like a blind button press.

**Acceptance criteria:**
- Tapping a `Button(intent:)` in either widget size fires the corresponding `AudioPlaybackIntent`.
- `AudioPlaybackIntent.perform()` executes in the main app process (requires app to be running in background), makes the Mozart or BNR API call, writes updated state to the App Groups shared container, and calls `WidgetCenter.shared.reloadAllTimelines()`.
- From user tap to widget re-render with the new state: target ≤ 3 seconds on a typical home network (same NFR as the v1.0 voice command to speaker action requirement).
- iOS 26 provides native `Button(intent:)` press feedback (glass shimmer at pressedScale 0.95) — no custom animation is required inside the widget.
- If the API call fails (speaker unreachable, timeout), the intent writes the error condition to the shared container and reloads timelines. The widget re-renders showing the last-known state; the error is not surfaced as a separate toast (the widget is not the app UI).
- If the app is not running at intent execution time, the intent's `perform()` catches the error and sets `app_running: false` in the shared container, then reloads timelines. The widget re-renders with the app-not-running fallback.

---

**US-37 — The Control Widget provides instant play/pause and mute in Control Center**
> As a user, I want a Voxio tile in Control Center so that I can play/pause or mute my speaker with one tap from anywhere on my iPhone — lock screen, any app — without opening Voxio.

**Acceptance criteria:**
- "Voxio" appears in Control Center customisation (Settings → Control Center) after the widget extension is installed.
- After adding, the Control Widget tile shows two controls: a `ControlWidgetButton` (play/pause) and a `ControlWidgetToggle` (mute), vertically stacked with 8 pt spacing.
- Play/Pause button: icon `pause.fill` with `BeoColor.accent` tint when playing; icon `play.fill` with system default tint when paused.
- Mute toggle: icon `speaker.wave.2.fill` when unmuted; icon `speaker.slash.fill` when muted. Active (muted) tint is the system default — not gold. Inactive (unmuted) tint is system default.
- The tile label (displayed below the icon grid where the system shows it) is the configured speaker name when a specific speaker is selected, or "Voxio" when set to Automatic.
- The user can long-press the tile to configure a specific speaker (same speaker picker as the home-screen widget: list of discovered speakers + "Automatic (most recent)").
- When the app is not running: `isEnabled: false` on both controls; the system automatically dims the tile and may show "Requires Voxio". No custom fallback UI is needed — this is standard iOS behaviour.
- Control Widget is available on iOS 26 (macOS and watchOS via paired iPhone automatically — no additional implementation required).
- `ControlWidgetButton` accessibility label: "Voxio Play" (announced by Siri and VoiceOver on long-press).
- `ControlWidgetToggle` accessibility label: "Voxio Mute".

---

**US-38 — Siri can execute playback commands on speakers via voice**
> As a user, I want to say "Hey Siri, pause Voxio" or "Hey Siri, turn up the volume in Voxio" and have the command execute without me opening the app, so that I can control my speaker hands-free from any context.

**Acceptance criteria:**
- `AppShortcutsProvider` registers the following Siri invocation phrases:
  - English: "Play Voxio", "Pause Voxio", "Mute Voxio", "Turn up the volume in Voxio", "Turn down the volume in Voxio"
  - Danish: "Afspil Voxio", "Sæt Voxio på pause", "Slå Voxio fra", "Skru op for lyden i Voxio", "Skru ned for lyden i Voxio"
- Each phrase maps to an `AudioPlaybackIntent`-conforming intent (`PlaybackToggleIntent`, `MuteIntent`, `AdjustVolumeIntent`).
- On success: Siri provides a brief system-spoken confirmation. The 3-second auto-execute countdown from E-25 does NOT apply to Siri-invoked intents — Siri confirmation is implicit in the invocation.
- On failure (speaker unreachable): Siri speaks: "I couldn't reach [Speaker Name]. Make sure Voxio is running and the speaker is on the network."
- On failure (app not running): Siri speaks: "To control your speaker, open Voxio first."
- On Apple Intelligence-capable devices (A17 Pro+, iOS 26), Siri handles richer phrasing variants automatically via App Intents framework without additional implementation.
- The same intent implementations that widget buttons use are invoked by Siri — there is one code path.

---

**US-39 — Widget state stays fresh when the app is running**
> As a user with the app running in the background, I want the widget to show current playback state without me having to tap anything, so that the glance-value of the widget is maintained.

**Acceptance criteria:**
- On every `Speaker` event received (playback state change, metadata update, volume change, source change), the main app writes updated state to the App Groups shared container and calls `WidgetCenter.shared.reloadAllTimelines()`.
- The widget timeline provider reads from the shared container and generates a single-entry timeline (current state).
- Changes in playback state (e.g. a track change triggered by the speaker's own controls, or by another device on the network) are reflected in the widget within the WidgetKit refresh budget. On iOS 26, after the app calls `reloadAllTimelines()`, the widget typically re-renders within seconds. This is accepted as a best-effort constraint, not a hard guarantee.
- The main app writes `playback_state: .paused` to the shared container on `scenePhase == .background` to prevent showing a stale "playing" state after the app is backgrounded. Post-termination staleness of up to 60 seconds is an accepted known edge case documented in the spec.

---

**US-40 — Widget accessibility meets iOS standards**
> As a user with motor or visual impairments, I want the widget's interactive elements to be fully accessible, so that I can use Voxio widgets with VoiceOver and Switch Control.

**Acceptance criteria:**
- All `Button(intent:)` instances in both widget sizes have `.accessibilityLabel()` strings set per the string table below:
  - Play button: "Play [Speaker Name]" (en) / "Afspil [Højttalernavn]" (da)
  - Pause button: "Pause [Speaker Name]" (en) / "Sæt [Højttalernavn] på pause" (da)
  - Volume up: "Volume up" (en) / "Skru op" (da)
  - Volume down: "Volume down" (en) / "Skru ned" (da)
  - Mute toggle (unmuted): "Mute [Speaker Name]" (en) / "Slå [Højttalernavn] fra" (da)
  - Mute toggle (muted): "Unmute [Speaker Name]" (en) / "Slå [Højttalernavn] til igen" (da)
  - Open Voxio button (fallback): "Open Voxio" (en) / "Åbn Voxio" (da)
- VoiceOver reads elements top-left to bottom-right. Speaker name is the first VoiceOver focus element in the widget.
- Volume buttons in `systemMedium` use `.frame(minWidth: 44, minHeight: 44)` to meet the 44 × 44 pt minimum tap target, even though their visual size is 36 pt.
- The primary play/pause button in `systemSmall` fills the available width and is taller than 44 pt — compliant without modification.
- Control Widget labels ("Voxio Play", "Voxio Mute") are localised and announced by VoiceOver and Siri on long-press of the Control Center tile.
- Dynamic Type is not available in widgets — the fixed type sizes in `BeoType.widget*` tokens are chosen for legibility at default system text size and are not expected to scale.

---

### Feature 3: Group abstraction and speaker join/leave

---

**US-41 — Existing multiroom sessions are detected automatically on startup**
> As a user who has previously grouped speakers into a Beolink session using any B&O app or the speaker's own controls, I want Voxio to detect that group automatically when it launches, so that I see the correct group state without having to re-create it.

**Acceptance criteria:**
- After mDNS discovery completes, `GroupDiscovery` calls `GET /beolink/peers` on each discovered Mozart speaker.
- Speakers that share a peer edge in the response are placed into the same `Group` object via union-find on the JID graph.
- For each BNR speaker, `GET /BeoZone/Zone/Sources` is called. A source with `multiroom: "listener"` or `multiroom: "host"` indicates group membership; the speaker is assigned to a group accordingly.
- A speaker with no peers and no multiroom sources forms a group-of-1.
- The UI displays correctly grouped speakers within 5 seconds of all mDNS resolutions completing.
- If `GET /beolink/peers` times out for one speaker, that speaker is treated as a group-of-1 (partial reconstruction). No error toast is shown; the partial state is a graceful degradation.
- The `Group.id` is stable: derived from the sorted JIDs/serials of its members, it is the same value across app restarts for an unchanged session.

---

**US-42 — "Speaker A join Speaker B" voice command**
> As a user with two speakers, I want to say "Voxio, Beosound join Beoplay" and have Beosound start playing the same audio as Beoplay, so that I can create a multiroom session hands-free.

**Acceptance criteria:**
- The voice command `joinSpeaker(source: SpeakerIdentifier, target: SpeakerIdentifier)` is parsed from the utterance by the three-tier parsing pipeline.
- "source" is the speaker that will join and follow; "target" is the speaker whose source will be played.
- A 3-second auto-execute countdown confirmation (per E-25 flow) is shown before the API call executes. The user can cancel within the countdown.
- For Mozart source + Mozart target: `beolinkExpand(jid: source.jid)` is called on the target speaker's `MozartClient`.
- For BNR source + any target: `POST /BeoZone/Zone/Device/OneWayJoin` is called on the source speaker's `BNRClient`. Target must be the active LAN session.
- For Mozart source + BNR target: `beolinkJoin()` is called on the source speaker's `MozartClient`. Flagged as best-effort (see Open Question 13).
- On success: the two speakers' `Speaker` objects are merged into a single `Group` in the app state. The UI updates to show the new group within 3 seconds.
- On failure: an error toast is shown per the Error States table. No group change occurs.

---

**US-43 — All join phrase variants route to the same intent**
> As a user, I want to use any natural phrasing for "join" and have it work, so that I do not need to remember the exact command syntax.

**Acceptance criteria:**
- The following English phrases are all recognised and mapped to `joinSpeaker(source:target:)` by the NLP parsing layer:
  - "join": "Beosound join Beoplay"
  - "play with": "Beosound play with Beoplay"
  - "play the same as": "Beosound play the same as Beoplay"
  - "sync with": "Beosound sync with Beoplay"
  - "follow": "Beosound follow Beoplay"
  - "play along with": "Beosound play along with Beoplay"
  - "play together with": "Beosound play together with Beoplay"
  - "listen together with": "Beosound listen together with Beoplay"
- The following Danish phrases are all recognised and mapped to `joinSpeaker(source:target:)`:
  - "spil med": "Beosound spil med Beoplay"
  - "spil det samme som": "Beosound spil det samme som Beoplay"
  - "synkroniser med": "Beosound synkroniser med Beoplay"
  - "følg": "Beosound følg Beoplay"
- Speaker names are resolved from the recognised phrase using the existing `dispatchTarget` resolution logic.
- All variants pass through the same 3-second countdown confirmation before executing.

---

**US-44 — "Speaker A leave the group" voice command**
> As a user, I want to say "Voxio, Beosound leave the group" and have Beosound return to standalone playback, so that I can break a multiroom session without touching any physical controls.

**Acceptance criteria:**
- The voice command `leaveSpeaker(speaker: SpeakerIdentifier)` is parsed from the utterance.
- Leave is executed immediately — no countdown confirmation is shown.
- For a Mozart speaker: `beolinkLeave()` is called on the speaker's `MozartClient` (`POST /beolink/leave`).
- For a BNR speaker: `DELETE /BeoZone/Zone/ActiveSources/primaryExperience` is called on the speaker's `BNRClient`.
- On success: the speaker is removed from its `Group` in the app state. If the group had 2 members, the remaining speaker becomes a group-of-1. The UI updates within 3 seconds.
- On failure: an error toast is shown per the Error States table.
- If the speaker is not currently in a group (already standalone): an error toast "Beosound is not in a group" is shown. No API call is made.

---

**US-45 — All leave phrase variants route to the same intent**
> As a user, I want to use any natural phrasing for "leave" and have it work, so that I do not need to remember the exact command syntax.

**Acceptance criteria:**
- The following English phrases are all recognised and mapped to `leaveSpeaker(speaker:)`:
  - "leave the group": "Beosound leave the group"
  - "stop playing with": "Beosound stop playing with Beoplay"
  - "play alone": "Beosound play alone"
  - "disconnect from": "Beosound disconnect from Beoplay"
  - "leave": "Beosound leave"
- The following Danish phrases are all recognised and mapped to `leaveSpeaker(speaker:)`:
  - "forlad gruppen": "Beosound forlad gruppen"
  - "spil alene": "Beosound spil alene"
  - "stop med at spille med": "Beosound stop med at spille med Beoplay"
- Speaker name in the utterance is resolved using existing `dispatchTarget` resolution.
- All leave variants execute immediately without a countdown.

---

**US-46 — A group of one shows identical UI to the current speaker card**
> As a single-speaker user, I want the update to the Group abstraction to be invisible to me — the app should look and behave exactly as it does today, so that no regression is introduced by the v1.2.1 changes.

**Acceptance criteria:**
- A `Group` with exactly one member renders using the existing `SpeakerCardView` layout without modification.
- All existing speaker card fields (speaker name, track, source, volume, playback state, battery) are displayed identically to the pre-group-abstraction behaviour.
- All existing voice commands (play, pause, stop, volume, mute, favorites) continue to function on a group-of-1 with no change to UX.
- The group card for a group-of-1 does not show any member count, join button, or group-specific UI element.
- Zero visual or behavioural regression relative to the v1.2.0 single-speaker experience.

---

**US-47 — A group of two or more shows an expanded group card**
> As a user with an active multiroom session, I want to see all speakers in the group displayed together in a single card, so that I can understand the current group state at a glance.

**Acceptance criteria:**
- A `Group` with two or more members renders using the expanded group card layout defined in `design-spec-group-ui-voxio-1.2.md`.
- The group card displays the host speaker name prominently and lists all member speaker names.
- Playback state, track metadata, and volume shown on the group card reflect the `hostSpeaker`'s current state.
- Voice commands addressed to any member speaker of the group are routed to the correct `Speaker` instance within the group.
- The group card is accessible: VoiceOver reads the host speaker name first, then the member list.

---

**US-48 — Join and leave are invocable via Siri**
> As a user, I want to say "Hey Siri, Beosound join Beoplay in Voxio" and have the join command execute, so that I can manage multiroom sessions entirely hands-free.

**Acceptance criteria:**
- `JoinSpeakerIntent(source:target:)` and `LeaveSpeakerIntent(speaker:)` are `AudioPlaybackIntent`-conforming intents registered with `AppShortcutsProvider`.
- English Siri phrases registered: "[Speaker A] join [Speaker B] in Voxio", "join speakers in Voxio".
- Danish Siri phrases registered: "[Højttaler A] spil med [Højttaler B] i Voxio", "saml højttalere i Voxio".
- The 3-second auto-execute countdown does NOT apply to Siri-invoked join (Siri confirmation is implicit) — consistent with the existing behaviour for other Siri intents.
- On Siri-invoked leave: immediate execution, consistent with in-app leave behaviour.
- On failure (speaker unreachable, join fails): Siri speaks the relevant error string from the Error States table.

---

## Error States

| Scenario | Expected Behaviour |
|---|---|
| BNR speaker announces on `_beoremote._tcp` but `GET /BeoDevice` times out | `MdnsDiscovery` removes the speaker from the list (matches Mozart speaker removal on init failure). No error toast. |
| BNR `GET /BeoZone/Zone/Sound/Volume/Speaker` returns 404 | Logged at INFO; volume displayed as "—". The speaker card is shown with all available fields populated. |
| BNR write command returns HTTP 501 | Logged at INFO: `[BNRClient] 501 ignored on write`. Not surfaced to the user. Operation considered complete. |
| BNR write command returns HTTP 404 | `SpeakerError.httpError(404)` thrown. Error toast: "Command not supported on this speaker." (matches Mozart httpError toast behaviour.) |
| BNR long-poll connection drops | `BNREvents` enters exponential-backoff reconnect loop silently. No error toast until three consecutive failures. On third failure: "Speaker connection lost" toast (same as Mozart WebSocket drop toast). |
| BNR long-poll receives unknown notification type | Logged at VERBOSE; ignored. Stream continues without error. |
| BNR long-poll server returns a response with no parseable event body | Treated as a re-open signal (matches the spec: any response triggers re-open). Logged at VERBOSE. |
| `SpeakerClient` protocol method called on a deallocated `BNRClient` | Swift ARC prevents this by design. `BNRClient` lifetime is owned by `Speaker`. |
| `SpeakerEvent` enum case missing a required field (e.g. volume notification with no `level`) | Decoding fails gracefully; the event is dropped. Logged at INFO. The stream continues. |
| App Groups entitlement missing from the main app or widget extension target | Widget renders empty state on every render (shared container unreadable). Engineering error: entitlement must be configured before widget work begins. No user-visible error message — the empty state is shown. |
| `AudioPlaybackIntent.perform()` is invoked but the app is not running in the background | `perform()` returns an error. The intent writes `app_running: false` to the shared container and calls `WidgetCenter.shared.reloadAllTimelines()`. The widget re-renders at 50 % opacity with "Open Voxio" button. |
| `AudioPlaybackIntent.perform()` is invoked during app cold-start (< 2 s from launch) | Intent may succeed if the app initialises faster than the timeout. If not, the app-not-running error path above applies. |
| Widget `Button(intent:)` tap produces no visible feedback after 3 seconds | Network timeout. The intent writes the error to the shared container (e.g. `last_error: "timeout"`) and reloads timelines. Widget re-renders with last-known state; no additional toast in the widget. |
| `WidgetCenter.shared.reloadAllTimelines()` called but widget fails to re-render | iOS WidgetKit refresh budget enforcement. The widget will re-render at the next available budget slot. Accepted as a platform constraint. |
| Shared container `UserDefaults` data format version mismatch (after an app update) | `Speaker` writes a `data_version` key to the shared container. The widget reads it; if the version is unrecognised, the widget shows the loading/empty state and waits for the next write. |
| Control Widget `isEnabled: false` due to app not running | System automatically dims the tile and may show "Requires Voxio". No custom UI needed. Standard iOS 26 behaviour. |
| Siri intent fails because speaker is unreachable | Siri speaks: "I couldn't reach [Speaker Name]. Make sure Voxio is running and the speaker is on the network." Widget state is unchanged. |
| Siri intent fails because app is not running | Siri speaks: "To control your speaker, open Voxio first." |
| `AppShortcutsProvider` phrase not matched by Siri | Siri's default "I couldn't find a shortcut for that" response. No action taken in the app. |
| `BeoType.widgetTrack` or other widget token not found at compile time in the widget extension target | Build error. `DesignTokens.swift` and `BeoColor.swift` must be added to the widget extension target's file membership (E-30 prerequisite). |
| `BeoColor.separator` asset missing from `Assets.xcassets` | `Color("BeoSeparator")` renders as a clear colour. The column divider in `systemMedium` is invisible. Log `Logger.error("BeoSeparator asset missing")`. Not a crash. |
| Join fails — network error or speaker unreachable | `SpeakerError.timeout` or `.unreachable` thrown from `beolinkExpand` / `OneWayJoin`. Error toast: "Couldn't join [Speaker A] to [Speaker B]. Check the speaker is reachable." (en) / "Kunne ikke tilslutte [Højttaler A] til [Højttaler B]. Tjek, at højttaleren er tilgængelig." (da). No group state change occurs. |
| Join attempted on speaker already in the target group | `joinSpeaker(source:target:)` is a no-op if `source` and `target` are already members of the same `Group`. Toast: "Beosound is already playing with Beoplay." No API call is made. |
| Leave attempted on speaker not in a group | `leaveSpeaker(speaker:)` is a no-op if the speaker is already a group-of-1. Toast: "[Speaker Name] is not in a group." No API call is made. |
| BNR join is ambiguous — multiple active Beolink sessions on the network | `POST /BeoZone/Zone/Device/OneWayJoin` is issued on the BNR speaker. If the wrong session is joined, the user sees the BNR speaker following an unexpected source. Toast after join confirms which source is now active. No pre-flight ambiguity check is performed (BNR has no API to enumerate sessions). This is a known limitation — see Open Question 13. |
| Cross-platform join (Mozart→BNR host) fails because no active LAN session | `beolinkJoin()` called on the Mozart speaker returns an error (no active experience to join). Error toast: "Couldn't join [Speaker A] to [Speaker B]. Make sure [Speaker B] is playing." No group state change. |
| GroupDiscovery `GET /beolink/peers` times out for one speaker | That speaker is treated as a group-of-1 (partial reconstruction). No error toast — partial group state is logged at INFO. The app state is self-healing: on the next launch or manual refresh, the correct group is reconstructed if the speaker is reachable. |
| Host speaker goes offline mid-session | The remaining group members' `Speaker` instances continue to operate. `GroupDiscovery` detects the host removal (mDNS withdrawal or failed ping) and promotes the next available member to `hostSpeaker`, or downgrades the group to a group-of-1 if no other member can act as host. Toast: "[Host Speaker Name] went offline. Group disbanded." |
| Join or leave Siri intent fails because the named speaker is not found | Siri speaks: "I couldn't find a speaker called [Name] in Voxio. Make sure it's on the network." No action taken. |

---

## Non-Functional Requirements

- **Performance:** The BNR long-poll reconnect loop and the Mozart WebSocket reconnect loop both use exponential backoff. Neither reconnect loop should exceed 5 seconds of backoff on a third attempt. Initial connection established within 5 seconds of mDNS discovery, matching Mozart behaviour.
- **Memory:** `BNRClient` and `BNREvents` together consume no more memory than `MozartClient` and `MozartEvents`. The `AsyncStream`-based long-poll task holds at most one response buffer at a time. Total speaker-pair memory footprint ≤ 2 MB per speaker on a device with four concurrent speakers.
- **Latency:** BNR command round-trip (tap → API call → response) ≤ 2 seconds on a normal home network (within the 3-second overall NFR). BNR press+release double-POST must both complete before `perform()` returns. Widget button tap to widget re-render ≤ 3 seconds on a normal home network.
- **Widget refresh budget:** The app calls `WidgetCenter.shared.reloadAllTimelines()` on every `Speaker` event and on `scenePhase == .background`. iOS WidgetKit respects the system refresh budget; the app should not call `reloadAllTimelines()` at an interval faster than one call per speaker event (no polling loop). The widget must not make any direct network calls from the timeline provider or from the view — all state comes from the shared container.
- **Privacy:** Unchanged from v1.1. All voice parsing and trigger detection remain on-device. Widget intents make Mozart or BNR LAN API calls only — no third-party network traffic. `AppShortcutsProvider` metadata (intent titles, example phrases) is provided to the Siri system on-device. No transcript or audio leaves the device for the widget or shortcut path.
- **Accessibility:** All `Button(intent:)` widget controls have `.accessibilityLabel()` strings. Minimum tap targets: 44 × 44 pt for all controls. Volume buttons in `systemMedium` use `.frame(minWidth: 44, minHeight: 44)`. Control Widget labels are localised. VoiceOver order is top-left to bottom-right within the widget.
- **Localisation:** All new strings (widget labels, error messages, Siri phrases, accessibility labels) are provided in English (`en-US`) and Danish (`da-DK`). All new UI strings flow through `LanguageService` / `String(localized:)`. Siri phrases in both languages are registered with `AppShortcutsProvider`. No new localisation infrastructure required — the existing `LanguageService` is used.
- **Security:** No new authentication surface is introduced. BNR communicates over plain HTTP on the local network, matching the Mozart NSAppTransportSecurity allowance already in `Info.plist` (`NSAllowsLocalNetworking`). The `_beoremote._tcp` service type must be added to `NSBonjourServices` in `Info.plist`.
- **Backward compatibility:** All Mozart speaker functionality from v1.0 and v1.1 continues to work identically. `MozartClient` and `MozartEvents` logic is unchanged; their protocol conformances are additive.
- **Testability:** `SpeakerClient` and `SpeakerEventSource` protocols allow mock implementations in unit tests. `Speaker` can be initialised with a mock client pair for testing without network access. Widget timeline providers are unit-testable against mock shared container data. `AppShortcutsProvider` intent conformances are testable via XCTest.

---

## Epics and Tasks

Epics and tasks are broken down in the sibling document `epics-and-tasks-voxio-1.2.md`.

---

## Open Questions

1. **`SpeakerEvent` scope — battery event parity.** Owner: Engineering. Default assumption: BNR does not emit a dedicated battery notification type; the battery field is omitted for BNR speakers (displayed as "—"). Question: confirm whether any BNR device firmware emits battery information via the notification channel, and if so, whether to add a `BATTERY` notification type to the BNR normalisation layer.

2. **BNR favorites parity — index vs. ordered list.** Owner: Product. Default assumption: `playFavorite(index: N)` for BNR speakers activates the `N`-th source in the filtered list from `GET /BeoZone/Zone/Sources` (sorted by order of appearance in the response). Question: should the list be sorted alphabetically by `friendlyName` for consistency with Mozart's `/scenes` ordering, or is response-order acceptable?

3. **App Groups provisioning profile update process.** Owner: Engineering. Default assumption: the `group.T-Creative.Voxio` App Group identifier is registered on the Apple Developer Portal, added to both the main app and the widget extension provisioning profiles, and the Xcode project entitlements are updated before any widget UI work begins. Question: confirm the App Group identifier and document the provisioning update steps in a ticket before E-30 begins.

4. **`VoxioIntents` target sharing strategy.** Owner: Engineering. Default assumption: a new `VoxioIntents` Swift target (a framework or source-file-shared approach) is created so that intent declarations compile into both the main app target and the widget extension target. Question: should this be a standalone framework target, or is adding the intent source files to both target memberships sufficient for v1.2?

5. **Siri phrase locale coverage.** Owner: Product / Design. Default assumption: English (`en-US`) and Danish (`da-DK`) phrases are the full v1.2 scope, matching the app's language coverage. Question: are any other locales required for App Store submission or regional sales?

6. **Widget speaker selector picker data source.** Owner: Engineering. Default assumption: the speaker picker in widget configuration shows all speakers that the app has ever discovered and written to the shared container, persisted in a `[SpeakerRecord]` array keyed by host address. Question: what is the eviction policy? If a speaker has not been seen for 30 days, should it be removed from the picker list?

7. **Skip/next-track endpoint confirmation for v1.3.** Owner: Engineering / Product. Default assumption: skip is deferred. Question: before v1.3 planning, Engineering should confirm that a Mozart source-agnostic skip endpoint exists (or does not) and whether BNR `POST /BeoZone/Zone/Stream/Forward` works reliably across radio, streaming, and Bluetooth sources, to unblock v1.3 widget skip design.

8. **`DesignTokens.swift` + `BeoColor.swift` widget extension membership — shared package evaluation.** Owner: Engineering. Default assumption: in v1.2, both files are added to the widget extension target's file membership (simplest approach, per design spec §5.2 Token Conflicts). Question: evaluate migrating the `DesignSystem/` folder to a local Swift Package for v1.3 to eliminate file-membership duplication and avoid import ambiguity.

9. **`BeoType.widgetTrack` design variant — `.rounded` vs. `.default`** Owner: Design team. Default assumption: `BeoType.widgetTrack` uses `Font.system(size: 15, weight: .regular, design: .rounded)` per the design spec Appendix B. Question: confirm whether the `.rounded` design variant is intentional for the warm-at-small-size aesthetic, or whether `.default` is preferred for strict consistency with the main app type tokens.

10. **Post-termination stale state — accepted edge case documentation.** Owner: Engineering / Product. Default assumption: staleness up to 60 seconds after app termination is documented and accepted. Question: should a `last_written_at` timestamp be added to the shared container and displayed in the widget (e.g. "· 3 min ago") when the timestamp exceeds 5 minutes, as Option B in the design spec suggests?

11. **watchOS Control Widget rendering verification.** Owner: Engineering. Default assumption: the Control Widget renders acceptably on watchOS via iOS 26 paired-iPhone mirroring with no additional implementation. Question: verify with a watchOS simulator during implementation (E-31) and document any layout issues. If the two-icon stack does not render correctly at watchOS tile sizes, flag for v1.3.

12. **BNR `INFO.plist` `NSBonjourServices` addition.** Owner: Engineering. Default assumption: `_beoremote._tcp` is added to the `NSBonjourServices` array in `Info.plist` alongside the existing `_bangolufsen._tcp` entry. Question: confirm with QA that adding this entry does not trigger any additional App Store review flags for local network privacy prompts.

13. **Cross-platform join (Mozart→BNR host) reliability.** Owner: Engineering / Product. Default assumption: `beolinkJoin()` on a Mozart speaker joins the BNR host's active LAN session as best-effort. Question: confirm with B&O community testers whether `beolinkJoin()` on a Mozart device reliably joins a BNR host's session when both devices are on the same subnet. If reliability is insufficient, this join variant should be either removed from the NLP grammar or surfaced with a distinct "may not work" warning.

14. **Leave confirmation for voice commands.** Owner: Product / UX. Default assumption: leave executes immediately with no countdown, consistent with the spec. Question: should leave have a confirmation step? Argument for: "leave the group" is a potentially unexpected state change if the user misspoke. Argument against: leave is easily recoverable (re-join is a single voice command), and a confirmation countdown on a recovery action would be counterproductive.

15. **Group host goes offline mid-session — host promotion policy.** Owner: Engineering / Product. Default assumption: if the host speaker goes offline, the group is disbanded and the surviving speakers become groups-of-1. Question: should the app attempt to detect if one of the remaining Mozart speakers becomes the de facto session host (i.e. call `GET /beolink/peers` on survivors after host removal) and reconstruct the group with a new host? Or is silently disbanding the group the correct UX?

16. **BNR session identity without a peers endpoint — heuristic accuracy.** Owner: Engineering. Default assumption: BNR speakers with `multiroom: "listener"` in their source list are in "some" session; group identity is inferred by matching BNR listener speakers with Mozart host speakers on the same network. Question: quantify the false-positive and false-negative rate in practice. If two separate Beolink sessions are active on the same network, the heuristic may incorrectly merge BNR listeners into the wrong group. Accept this as a known limitation, or invest in a more robust heuristic (e.g. comparing the active source name between the BNR listener and the inferred Mozart host)?

---

## Resolved Decisions

| Question | Decision |
|---|---|
| Speaker abstraction approach — protocol, base class, or Combine? | Protocol + AsyncStream (research Rank 1). `SpeakerClient` + `SpeakerEventSource` protocols. No base class. No Combine. |
| BNR event delivery mechanism — long-poll or WebSocket? | BNR uses HTTP long-poll only. `BNREvents` wraps a `Task`-based long-poll loop yielding to an `AsyncStream<SpeakerEvent>`. |
| BNR 501 response treatment? | Soft warning. Log at INFO, do not throw. Operation considered complete. Confirmed by community implementations. |
| BNR long-poll timeout handling? | Any server response (event or close) triggers immediate re-open. Timeout duration is undocumented; no fixed-duration assumption is made. |
| Normalised event type — `BeoEvent` extended vs. new `SpeakerEvent`? | New `SpeakerEvent` enum. `BeoEvent` is Mozart-specific and carries types BNR does not emit. `SpeakerEvent` contains only the subset meaningful across both platforms. |
| Widget voice interaction — mic button, push-to-talk, or Siri? | Siri + `AppShortcutsProvider` only. Mic access in a widget is architecturally impossible (sandbox constraint, no iOS 26 exception). There is no workaround. |
| Widget touch control mechanism — OpenIntent deep-link vs. AudioPlaybackIntent? | `AudioPlaybackIntent`. `OpenIntent` defeats the no-app-open value proposition of a widget. `AudioPlaybackIntent.perform()` routes to the main app process for LAN network access. |
| App-not-running detection strategy — reactive (Option A) vs. heartbeat (Option B)? | Option A (reactive). On intent failure, write flag to shared container and reload timelines. One failed tap before fallback UI is acceptable. Option B adds complexity for minimal gain. |
| Widget sizing — one definition vs. two? | One widget definition (`VoxioPlayerWidget`) supporting `systemSmall` and `systemMedium`. iOS convention. |
| Gold accent on pause button? | Gold (`BeoColor.accent`) on the play/pause icon when playing state is active. Grey (`BeoColor.labelSecondary`) when paused/stopped. Consistent with main app convention. |
| Mute active state tint in Control Widget? | System default tint (NOT gold). Mute is suppression, not positive playback. Gold is reserved for active playback signals. |
| Skip button in v1.2? | Omitted. Mozart source-agnostic skip is unconfirmed. BNR skip is source-dependent. Deferred to v1.3. |
| `DesignTokens.swift` in widget extension — shared package vs. file membership? | File membership (simpler) for v1.2. Shared package evaluation deferred to v1.3 (Open Question 8). |
| `BeoColor.separator` exposure? | Add `static let separator = Color("BeoSeparator")` to `BeoColor.swift`. Non-breaking additive change. Asset already exists in `Assets.xcassets`. |
| Live Activity for v1.2? | Deferred to v1.3. Out of scope. |
| Join confirmation strategy | 3-second auto-execute countdown (per E-25 flow). Consistent with all other potentially destructive voice commands. Siri-invoked join skips the countdown (Siri confirmation is implicit). |
| Leave confirmation strategy | Immediate execution, no countdown. Leave restores standalone playback; it is recoverable with a single join command. A confirmation step on a recovery action would be counterproductive. |
| Join API choice — Mozart→Mozart | `beolinkExpand(jid: source.jid)` called on the target speaker. Deterministic targeting vs. the ambiguity of `beolinkJoin()` when multiple sessions exist. |
| Join API choice — BNR→Any | `POST /BeoZone/Zone/Device/OneWayJoin` on the source speaker. Only join option available on BNR; broadcast join is accepted as best-effort. |
| Top-level UI entity | `Group` (1–N speakers). A group-of-1 renders identically to the current speaker card — no UI regression for single-speaker users. |
| Group identity algorithm | Sorted-member JID/serial concatenation. Stable across restarts for unchanged sessions. Reconstructed fresh each launch via `GET /beolink/peers` and BNR sources. |

---

## References

- `Specification/Voxio 1.2/epics-and-tasks-voxio-1.2.md` — sibling document; v1.2 epic and task breakdown (E-27–E-32, tasks T-2701–T-2XXX).
- `Specification/Voxio 1.1/VoxioSpecification-1.1.md` — v1.1 functional specification.
- `Specification/Voxio 1.1/epics-and-tasks-voxio-1.1.md` — v1.1 epics and tasks (E-20–E-26, T-2001–T-2610).
- `Specification/Voxio 1.2/research-findings-voxio-1.2.md` — RESEARCHER findings on shared speaker abstraction and iOS widget/voice options.
- `Specification/Voxio 1.2/design-spec-widget-voxio-1.2.md` — DESIGNER widget UX/UI design specification.
- `Specification/Voxio 1.2/api-spec-beonetremote.md` — BNR API reference for ASE-platform speakers.
- `CLAUDE.md` — project-level architectural notes (iOS folder structure, Mozart API, deployment target).
- Apple: AudioPlaybackIntent — `https://developer.apple.com/documentation/appintents/audioplaybackintent`
- Apple: Adding interactivity to widgets and Live Activities — `https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities`
- Apple: Creating controls to perform actions across the system — `https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system`
- WWDC25: What's new in widgets (session 278) — `https://developer.apple.com/videos/play/wwdc2025/278/`
- WWDC24: Extend your app's controls across the system (session 10157) — `https://developer.apple.com/videos/play/wwdc2024/10157/`
- Swift AsyncStream proposal (SE-0314) — `https://github.com/swiftlang/swift-evolution/blob/main/proposals/0314-async-stream.md`
- `Specification/Voxio 1.2/design-spec-group-ui-voxio-1.2.md` — DESIGNER group card UX/UI design specification (multi-speaker card layout for groups of 2+).
- `iOS/Voxio/Core/Networking/MozartClient.swift` lines 280–306 — existing Beolink multiroom methods (`getBeolinkPeers`, `beolinkExpand`, `beolinkJoin`, `beolinkLeave`, `beolinkAllStandby`).
- `iOS/Voxio/Core/Models/BeolinkPeer.swift` — `BeolinkPeer` model (`jid: String`, `friendlyName: String?`).
