# Research Findings — Voxio 1.2
**Version:** 1.1  
**Status:** Final  
**Date:** 2026-05-01  
**Author:** RESEARCHER agent  

---

## Recommended Approach Summary

**Topic A (Shared Speaker Abstraction):** Introduce two Swift protocols — `SpeakerClient` (async command methods) and `SpeakerEventSource` (returns `AsyncStream<SpeakerEvent>`) — in a new `Core/Protocols/` folder. `MozartClient` and `MozartEvents` gain retroactive conformances with no logic changes. A new `BNRClient` and `BNREvents` implement the same protocols, encapsulating the press+release double-POST pattern, volume 0–9000 normalisation, and long-poll reconnect loop. `Speaker` is refactored to hold `any SpeakerClient` / `any SpeakerEventSource`. `MdnsDiscovery` browses both `_bangolufsen._tcp` and `_beoremote._tcp` and instantiates the correct client pair via a factory.

**Topic B (Widget + Voice):** No iOS widget can access the microphone — this is an architectural sandbox constraint with no iOS 26 exception. Voice interaction from a widget must go through Siri + App Intents (`AppShortcutsProvider`). Touch-based controls backed by `AudioPlaybackIntent`-conforming intents execute in the main app process and can make LAN network calls. Recommended surfaces: home-screen widget (`systemSmall` / `systemMedium`) with `Button(intent:)` controls, and a Control Widget in Control Center. Live Activity "now playing" is deferred to v1.3.

---

## Topic A: Shared Speaker Abstraction (Mozart + BNR)

### Codebase Baseline

- `iOS/Voxio/Core/Networking/MozartClient.swift` — concrete class, 30+ async methods, no protocol boundary today.
- `iOS/Voxio/Core/Networking/MozartEvents.swift` — concrete class wrapping `URLSessionWebSocketTask` with exponential-backoff reconnect; calls `onEvent: ((BeoEvent) -> Void)?` callback.
- `iOS/Voxio/Features/Home/Speaker.swift` — `@Observable @MainActor class Speaker` holds `let client: MozartClient` and `let events: MozartEvents` directly.
- `CLAUDE.md` §Discovery — `MdnsDiscovery` browses `_bangolufsen._tcp` only today.

### Key BNR vs. Mozart Divergences

| Concern | BNR | Mozart |
|---|---|---|
| Volume scale | 0–9000 (÷100 for %) | 0–100 (direct %) |
| Playback commands | Press + Release double-POST | Single POST |
| Event channel | Long-poll HTTP GET, re-open per event | WebSocket, persistent |
| Favorites | Sources list, no dedicated endpoint | `/scenes` dedicated endpoint |
| Discovery service type | `_beoremote._tcp`, port 8080 | `_bangolufsen._tcp`, port 80 |

### Options Considered

**Rank 1 — Protocol + AsyncStream (recommended)**

Define `protocol SpeakerClient` and `protocol SpeakerEventSource` in `iOS/Voxio/Core/Protocols/`. `MozartClient` and `MozartEvents` gain retroactive conformances with no logic changes. New `BNRClient: SpeakerClient` and `BNREvents: SpeakerEventSource`. `Speaker` refactored to hold `any SpeakerClient` / `any SpeakerEventSource` — Swift 5.7+ existential syntax, no type-erasure wrapper needed. `MdnsDiscovery` extended with `_beoremote._tcp` browsing and a client factory. A new normalised `SpeakerEvent` enum replaces `BeoEvent` across the app.

**Rank 2 — Combine AnyPublisher (not recommended)**  
Would require replacing `@Observable` with `ObservableObject`/`@Published`. The existing codebase has zero Combine usage; introducing it for one abstraction boundary creates a mixed concurrency model.

**Rank 3 — Base class (avoid)**  
Swift's single-inheritance constraint and the `@MainActor @Observable` stack make this fragile.

### Implementation Notes

**AsyncStream for BNR long-poll:**
```swift
func events() -> AsyncStream<SpeakerEvent> {
    AsyncStream { continuation in
        let task = Task {
            while !Task.isCancelled {
                do {
                    let event = try await fetchNextNotification() // blocks until server replies
                    continuation.yield(normalise(event))
                } catch {
                    try? await Task.sleep(nanoseconds: backoffNanoseconds())
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

**Volume normalisation** belongs inside `BNRClient` — read: `level / 100`; write: `level * 100`. Use `range.maximum` from the API response for precision: `(level * 100) / range.maximum`.

**Press+release** is encapsulated in `BNRClient` — the `play() async throws` protocol requirement fires both POSTs internally.

**BNR favorites** — filter `GET /BeoZone/Zone/Sources` by `inUse == true, borrowed == false`, map to `[Favorite]`, activate via `POST /BeoZone/Zone/ActiveSources`.

**Discovery** — two `NetServiceBrowser` instances (one per service type). A factory function inspects `serviceType` and returns `(any SpeakerClient, any SpeakerEventSource)`. `Speaker` gains a new designated initialiser: `init(host:client:eventSource:)`.

### Caveats and Open Questions

- **BNR long-poll timeout**: Server-side timeout duration is undocumented; treat any response (event or server close) as a signal to re-open immediately.
- **BNR 501 soft-failure**: Treat 501 on write operations as a soft warning (log, don't throw) per the API spec note.
- **Favorites parity**: BNR sources can function as favorites but are not persisted presets in the Mozart sense. Spec should clarify UX parity.
- **`SpeakerEvent` scope**: `BeoEvent` carries Mozart-specific event types (e.g. `.progress`). The normalised `SpeakerEvent` should include only the subset meaningful for both platforms.

---

## Topic B: iOS Widget Capabilities and Voice Interaction

### The Hard Constraint

**Widgets cannot access the microphone.** Widget extensions run in a sandboxed process separate from the host app with no `AVAudioSession` recording capability, no `SFSpeechRecognizer`, and no microphone entitlement pathway. No WWDC25 session announced any change to this constraint. A mic-button-in-widget interaction model is architecturally impossible.

### Voice Interaction Options

**Option 1 — Siri + App Intents (the only real voice path)**

Declare `AppIntent` conformances and register via `AppShortcutsProvider` (iOS 16.4+). Invocable by Siri without the app being in the foreground. Intents map to: `PlayIntent`, `PauseIntent`, `StopIntent`, `SetVolumeIntent`, `AdjustVolumeIntent`, `MuteIntent`, `UnmuteIntent`, `PlayFavoriteIntent`. With Apple Intelligence (A17 Pro+, iOS 26), Siri handles richer phrasing automatically — no additional implementation required.

**Critical: AudioPlaybackIntent for network calls.** Standard `AppIntent.perform()` runs in the widget extension sandbox — no URLSession to LAN. `AudioPlaybackIntent.perform()` routes to the **main app process**, enabling `MozartClient`/`BNRClient` calls. This is the key enabler. Caveat: if the app is fully terminated, the intent may not reach the app process — the spec should require the app to be running for widget actions, with a graceful "open app" fallback.

**Option 2 — Open app via URL deep-link (not recommended for pure voice)**  
Technically works via `OpenIntent` but defeats the widget's no-app-open value proposition.

### Touch Interaction Surfaces

**Home-screen widget (WidgetKit, iOS 17+ interactive)**
- Sizes: `systemSmall`, `systemMedium`, `systemLarge`
- `Button(_:intent:)` and `Toggle(_:isOn:intent:)` with `AudioPlaybackIntent` conformances
- `systemSmall`: play/pause + track name; `systemMedium`: adds volume, speaker selector
- Timeline updated via `WidgetCenter.shared.reloadAllTimelines()` on `Speaker.handleEvent()`

**Control Widget (iOS 18+) — best surface for persistent quick actions**
- Appears in Control Center and lock screen — always one swipe away
- `ControlWidgetButton` for play/pause; `ControlWidgetToggle` for mute
- `AppIntentControlConfiguration` for per-speaker targeting
- iOS 26: available on macOS and watchOS via paired iPhone (no action needed)

**Live Activity — now playing (recommended for v1.3)**
- Lock screen and Dynamic Island persistent card
- Updated from `Speaker.handleEvent()` on every metadata/state change
- Expanded view can include `Button(intent:)` for play/pause, skip
- iOS 26: appears in CarPlay and macOS menu bar automatically

### iOS 26 Widget-Specific Changes

- **Liquid Glass rendering**: automatic for iOS 26 targets
- **`WidgetPushHandler` / APNs updates**: not needed for Voxio (app already receives WS/long-poll events and can call `Activity.update()` directly)
- **No new voice API, no microphone access added**
- **SpeechAnalyzer**: new iOS 26 framework for main app voice pipeline (potential future replacement for `SFSpeechRecognizer`); not relevant to widgets

### Recommended Approach

**Phase 1 — Voxio 1.2:**
1. **App Intents declarations** — `VoxioIntents.swift` (shared target: main app + widget extension). Declare `AudioPlaybackIntent`-conforming intents. `AppShortcutsProvider` with English + Danish Siri phrases.
2. **Home-screen widget** — `systemSmall` and `systemMedium`. Current speaker, track, play/pause + volume via `Button(intent:)`. Reloaded on speaker events.
3. **Control Widget** — `ControlWidgetButton` for play/pause, `ControlWidgetToggle` for mute. Per-speaker configuration.

**Phase 2 — Voxio 1.3 (evaluate):**
4. **Live Activity "now playing"** — started on playback begin, updated on every metadata/state event.

**What not to build:** A widget mic-tap button that opens Voxio and activates the trigger-word listener. Architecturally possible via `OpenIntent` but defeats the widget's purpose; users can tap the app icon instead.

### Caveats and Open Questions

- **AudioPlaybackIntent process routing**: Requires app to be running; spec should define graceful fallback when app is terminated.
- **Speaker selection in widget**: Requires `App Groups` entitlement (shared container) to pass active speaker host + playback state to the widget extension. Not currently present in the codebase — new entitlement required.
- **App Groups entitlement**: New requirement for the Xcode project and provisioning profiles.
- **Danish Siri phrases**: `IntentPhrase` with locale variants needed for `da-DK` ("Sæt Voxio på pause", "Skru op for lyden i Voxio").

---

## Sources

| Source | URL |
|---|---|
| WWDC25: What's new in widgets (session 278) | https://developer.apple.com/videos/play/wwdc2025/278/ |
| WWDC24: Extend your app's controls across the system (session 10157) | https://developer.apple.com/videos/play/wwdc2024/10157/ |
| WWDC24: App Intents core features (session 10210) | https://developer.apple.com/videos/play/wwdc2024/10210/ |
| Apple: Adding interactivity to widgets and Live Activities | https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities |
| Apple: AudioPlaybackIntent | https://developer.apple.com/documentation/appintents/audioplaybackintent |
| Apple: Creating controls to perform actions across the system | https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system |
| defn.io: Performing Widget Intents in-app on iOS (April 2025) | https://defn.io/2025/04/13/performing-widget-intents-in-ios-app/ |
| Apple Developer Forums: iOS18 AudioPlaybackIntent | https://developer.apple.com/forums/thread/761677 |
| iOS 26 Live Activities — 9to5Mac | https://9to5mac.com/2025/12/04/ios-26-made-live-activities-even-better-on-iphone-heres-whats-new/ |
| iOS 26 SpeechAnalyzer Guide | https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide |
| Swift AsyncStream proposal (SE-0314) | https://github.com/swiftlang/swift-evolution/blob/main/proposals/0314-async-stream.md |

---

## Topic C: Speaker Join / Group / Peers API

**Source:** Verified directly from `iOS/Voxio/Core/Networking/MozartClient.swift` (lines 280–306) and `iOS/Voxio/Core/Models/BeolinkPeer.swift`, cross-referenced against `Specification/Voxio 1.2/api-spec-beonetremote.md`.

---

### Mozart Open API (post-2020 speakers)

All four multiroom operations are already implemented in `MozartClient`:

| Operation | Method + Path | Notes |
|---|---|---|
| List peers | `GET /beolink/peers` | Returns `[BeolinkPeer]` — `jid: String`, `friendlyName: String?` |
| Expand to device | `POST /beolink/expand/{jid}` | Caller pushes its session to the target; target becomes a listener of caller's source |
| Join active session | `POST /beolink/join` | Caller joins the currently active Beolink experience on the network (no target arg) |
| Leave session | `POST /beolink/leave` | Caller leaves the multiroom session and returns to standalone playback |
| All standby | `POST /beolink/allstandby` | All connected devices go to standby simultaneously |

**Key distinction — expand vs. join:**

- `beolinkExpand(jid: A.jid)` called on **B** → B pushes its session to A. A follows B's source. B stays host.
- `beolinkJoin()` called on **A** → A joins whatever session is currently the active Beolink experience on the network. If B is the host, A follows B.

For the voice command **"Speaker A join Speaker B"** (A follows B's source), the correct call sequence is:
1. Call `beolinkExpand(jid: A.jid)` **on B** — B adds A to its session.

This is preferred over calling `beolinkJoin()` on A because `expand` explicitly targets A→B without ambiguity about which session is "active" if multiple sessions exist on the network.

**Session detection on startup:**

Call `GET /beolink/peers` on each discovered speaker. A non-empty response indicates that speaker has active Beolink peers. The `jid` field in each `BeolinkPeer` identifies the peer; cross-reference with the speaker list to build `Group` objects. A speaker with no peers is its own group-of-1.

---

### BNR API (ASE-platform speakers)

| Operation | Method + Path | Notes |
|---|---|---|
| Join active session | `POST /BeoZone/Zone/Device/OneWayJoin` | Empty body. Joins the currently active Beolink experience on the network. No target argument — broadcast join. |
| Leave session | `DELETE /BeoZone/Zone/ActiveSources/primaryExperience` | Deactivates the current source and leaves the Beolink experience / stops multiroom participation. |
| Session detection | `GET /BeoZone/Zone/Sources` | Sources with `multiroom: "listener"` indicate this device is a listener in a session. `multiroom: "host"` or `borrowed: true` sources indicate multiroom participation. |

**BNR has no peers endpoint.** There is no `/BeoDevice/peers` or equivalent. Session membership must be inferred from the sources list: a device with any source where `multiroom != null` (i.e. `"listener"` or `"host"`) is in a multiroom session. The identity of the host is not directly exposed — only the device's own role.

**BNR join is broadcast-only.** `OneWayJoin` has no target argument; it joins whatever Beolink experience is currently active on the LAN. For the voice command "Speaker A join Speaker B", the sequence is:
1. Ensure B is playing (has an active source).
2. Call `POST /BeoZone/Zone/Device/OneWayJoin` on A.

This works only if B's session is the active Beolink experience on the network. If multiple sessions exist, BNR cannot guarantee A joins B specifically.

---

### Recommended Group Abstraction

**`Group` model fields:**

```
Group
  id: String                    // derived: sorted jid/serial concatenation for stable identity
  members: [SpeakerReference]   // 1+ speakers
  hostSpeaker: SpeakerReference // the speaker whose source is playing
  playbackState: PlaybackState  // from the host speaker
  volume: Int                   // from the host speaker (0–100 normalised)
  metadata: TrackMetadata?      // from the host speaker
```

**Startup reconstruction:**

1. Discover all speakers via mDNS (`_bangolufsen._tcp` + `_beoremote._tcp`).
2. For each Mozart speaker: call `GET /beolink/peers`. Speakers that share peers are in the same group. Build groups by union-find on the jid graph.
3. For each BNR speaker: call `GET /BeoZone/Zone/Sources`. A `multiroom: "listener"` source indicates group membership. Group identity must be inferred heuristically (if BNR speaker A is listener and Mozart speaker B is host, they share a session if A joined B's network session).
4. Speakers with no peers / no multiroom sources form groups of 1.

**Join flow — "Speaker A join Speaker B":**

| A platform | B platform | Call |
|---|---|---|
| Mozart | Mozart | `beolinkExpand(jid: A.jid)` called on B's `MozartClient` |
| BNR | Mozart | `POST /BeoZone/Zone/Device/OneWayJoin` on A; B must be the active network session |
| Mozart | BNR | Not cleanly supported — BNR has no expand; B cannot push to A. Workaround: A calls `beolinkJoin()` when B is the active session. Flagged as open question. |
| BNR | BNR | `POST /BeoZone/Zone/Device/OneWayJoin` on A; B must be the active network session |

**Leave flow:**

| Platform | Call |
|---|---|
| Mozart | `POST /beolink/leave` on the leaving speaker's `MozartClient` |
| BNR | `DELETE /BeoZone/Zone/ActiveSources/primaryExperience` on the leaving speaker's `BNRClient` |

---

### Caveats and Open Questions

- **Cross-platform join (Mozart→BNR host):** BNR has no `expand` endpoint. A Mozart speaker cannot be pushed into a BNR session by the BNR device. The only path is Mozart calling `beolinkJoin()` when the BNR device is the active LAN session. Reliability is uncertain — flag as open question in the spec.
- **BNR session identity:** Without a peers endpoint, the app cannot definitively know which BNR devices share a session. The `multiroom` field in sources only describes the device's own role (listener/host), not the identity of the other participants.
- **BNR multiple sessions:** `OneWayJoin` on a BNR device always joins "the active" session — if multiple Beolink sessions are on the network, the target is ambiguous. In practice most home networks have at most one active session.
- **Mozart `beolinkJoin()` vs `beolinkExpand()`:** The spec should choose one canonical "join" implementation per platform and document the call site clearly. Recommended: always use `expand` for Mozart-to-Mozart (deterministic target); use `join` for BNR-to-any (only option available).
- **Group identity across restarts:** The `Group.id` derived from member JIDs/serials will be stable as long as membership doesn't change between sessions. The app reconstructs groups fresh on each launch.
