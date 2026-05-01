# Epics & Tasks: Voxio v1.2
**Version:** 1.2.1  
**Status:** Draft  
**Date:** 2026-05-01  
**References:** VoxioSpecification-1.2.md, epics-and-tasks-voxio-1.1.md (E-20–E-26, T-2001–T-2610), research-findings-voxio-1.2.md, design-spec-widget-voxio-1.2.md, design-spec-group-ui-voxio-1.2.md, api-spec-beonetremote.md, CLAUDE.md  
**Languages:** English (`en-US`) and Danish (`da-DK`) — both fully supported

---

## Overview

This document breaks the Voxio v1.2 functional specification into epics and their constituent tasks. Each epic maps to a coherent area of the v1.2 release. v1.2 adds six new epics (E-27 through E-32), continuing the numbering from v1.1's E-26. Task IDs begin at T-2701, continuing from the v1.1 high-watermark of T-2610. Amendment 1.2.1 adds E-32 (Group abstraction and speaker join/leave) and extends E-27 and E-29.

---

## Epic Index

| # | Epic | User Stories | Feature Area |
|---|---|---|---|
| E-27 | Shared Speaker Abstraction + Group Model | US-32, US-41, US-46, US-47 | ASE/BNR support — protocols, normalisation, Group abstraction |
| E-28 | BNRClient + BNREvents | US-28, US-29, US-30, US-31 | ASE/BNR support — new API client |
| E-29 | App Intents Declarations | US-38, US-48 | Widget + voice — Siri integration (incl. join/leave intents) |
| E-30 | Home-Screen Widget | US-33, US-34, US-35, US-36, US-39, US-40 | Widget + voice — WidgetKit extension |
| E-31 | Control Widget | US-37, US-40 | Widget + voice — Control Center / lock screen |
| E-32 | Speaker Join / Leave | US-42, US-43, US-44, US-45, US-48 | Group management — voice command join/leave |

---

## E-27 — Shared Speaker Abstraction + Group Model

Introduce two Swift protocols (`SpeakerClient` and `SpeakerEventSource`) in a new `Core/Protocols/` folder. Refactor `Speaker` to hold existential protocol types instead of concrete `MozartClient` and `MozartEvents` references. Add retroactive protocol conformances to `MozartClient` and `MozartEvents`. Define the normalised `SpeakerEvent` enum. Extend `MdnsDiscovery` with a second browser for `_beoremote._tcp` and a client factory. Add `join(peer:)` and `leave()` to `SpeakerClient`. Introduce the `Group` model, `GroupDiscovery`, and refactor the app layer to bind to `[Group]` instead of `[Speaker]`.

**Depends on:** none — purely additive at the protocol and discovery layer  
**Unlocks:** E-28 (BNRClient must conform to the same protocols defined here), E-32 (join/leave commands call `SpeakerClient.join(peer:)` and `.leave()`)

---

### Protocols and normalised event type

- [ ] **T-2701** Create `iOS/Voxio/Core/Protocols/` folder. Add `SpeakerClient.swift` declaring the `SpeakerClient` protocol with the following async throwing requirements:
  ```
  func play() async throws
  func pause() async throws
  func stop() async throws
  func setVolume(_ level: Int) async throws
  func mute(_ muted: Bool) async throws
  func getVolume() async throws -> Int
  func getPlaybackState() async throws -> SpeakerPlaybackState
  func getSources() async throws -> [Favorite]
  func activateSource(_ id: String) async throws
  func getBattery() async throws -> BatteryState?
  func getName() async throws -> String
  func join(peer: SpeakerIdentifier) async throws
  func leave() async throws
  ```
  `SpeakerPlaybackState` is an enum `{ playing, paused, stopped, buffering }` (a subset of the current Mozart/BNR states). `BatteryState` is a simple struct with `level: Int?` and `charging: Bool?` — already defined in v1.0 `Core/Models/`; reuse it. `Favorite` is the existing `Core/Models/Favorite` type. `getName()` provides the device-friendly name from the API (BNR: `productFriendlyName`; Mozart: from `GET /beolink/self`).

  `SpeakerIdentifier` is a new value type in `Core/Models/SpeakerIdentifier.swift`:
  ```swift
  struct SpeakerIdentifier: Hashable, Codable {
      let host: String        // IP address or hostname
      let jid: String?        // Mozart JID (nil for BNR speakers)
      let platform: SpeakerPlatform  // .mozart | .bnr
  }
  enum SpeakerPlatform: String, Codable { case mozart, bnr }
  ```
  `join(peer:)` semantics: for Mozart, calls `beolinkExpand(jid: peer.jid)` on the target client (this client expands TO the peer); for BNR, calls `POST /BeoZone/Zone/Device/OneWayJoin` on this client. `leave()` semantics: for Mozart, calls `beolinkLeave()`; for BNR, sends `DELETE /BeoZone/Zone/ActiveSources/primaryExperience`.
  *No dependencies. Prerequisite for T-2703, T-2704, T-2706, T-2744.*

- [ ] **T-2702** Add `SpeakerEventSource.swift` to `iOS/Voxio/Core/Protocols/` declaring the `SpeakerEventSource` protocol:
  ```
  func events() -> AsyncStream<SpeakerEvent>
  ```
  `SpeakerEvent` is a new enum defined in `iOS/Voxio/Core/Models/SpeakerEvent.swift` with cases:
  - `.playbackState(SpeakerPlaybackState)` — maps from BNR `PROGRESS_INFORMATION` and from Mozart `WebSocketEventPlaybackState`
  - `.metadata(title: String?, artist: String?, album: String?)` — maps from BNR `NOW_PLAYING_NET_RADIO` / `NOW_PLAYING_STORED_MUSIC` and from Mozart `WebSocketEventPlaybackMetadata`
  - `.volume(level: Int, muted: Bool)` — maps from BNR `VOLUME` and from Mozart `WebSocketEventVolume`. Volume is always expressed as a 0–100 integer percentage at this layer (normalisation is the client's responsibility).
  - `.battery(BatteryState)` — maps from Mozart `WebSocketEventBattery`. BNR does not emit battery events; BNR `BNREvents` never yields this case.
  - `.source(name: String?, id: String?)` — maps from BNR `SOURCE` and from Mozart `WebSocketEventPlaybackSource`.
  Document each case with an inline comment indicating the platform event it maps from.
  *No dependencies. Prerequisite for T-2703, T-2704, T-2705, T-2706.*

- [ ] **T-2703** Add retroactive `SpeakerClient` conformance to `MozartClient` in a new extension file `iOS/Voxio/Core/Networking/MozartClient+SpeakerClient.swift`. Each protocol method maps to the existing `MozartClient` method with the same semantics. `getVolume()` returns the current volume as a 0–100 integer (Mozart volume is already 0–100). `getName()` calls the existing `getBeolinkSelf()` or equivalent and returns the speaker's friendly name. `getBattery()` calls `getBattery()`. No logic changes to `MozartClient.swift` itself.
  *Depends on: T-2701, T-2702.*

- [ ] **T-2704** Add retroactive `SpeakerEventSource` conformance to `MozartEvents` in a new extension file `iOS/Voxio/Core/Networking/MozartEvents+SpeakerEventSource.swift`. `events()` returns an `AsyncStream<SpeakerEvent>` that wraps the existing `MozartEvents` WebSocket event stream, translating each `BeoEvent` case into the corresponding `SpeakerEvent` case. The translation table:
  - `BeoEvent.playbackState(let s)` → `.playbackState(…)` — map Mozart state string to `SpeakerPlaybackState` (note: Mozart `"started"` == `"playing"`)
  - `BeoEvent.metadata(let m)` → `.metadata(title: m.trackTitle ?? m.track, artist: m.artistName ?? m.artist, album: m.albumName ?? m.album)` — the WS shape uses `artistName`/`albumName`; REST uses `artist`/`album` (per CLAUDE.md)
  - `BeoEvent.volume(let v)` → `.volume(level: v.volume, muted: v.muted)` — Mozart volume is already 0–100
  - `BeoEvent.battery(let b)` → `.battery(BatteryState(level: b.level, charging: b.charging))`
  - `BeoEvent.source(let s)` → `.source(name: s.friendlyName, id: s.id)`
  No logic changes to `MozartEvents.swift` itself.
  *Depends on: T-2702, T-2703.*

### Speaker refactor

- [ ] **T-2705** Refactor `Speaker.swift` to hold `let client: any SpeakerClient` and `let eventSource: any SpeakerEventSource` instead of `let client: MozartClient` and `let events: MozartEvents`. Add a new designated initialiser: `init(host: String, client: any SpeakerClient, eventSource: any SpeakerEventSource)`. The existing `init(host:)` convenience initialiser (if present) is replaced by factory usage in `MdnsDiscovery` (T-2708). All call sites of `client.play()`, `client.setVolume()`, etc. remain syntactically unchanged — they now resolve against the protocol surface rather than the concrete type. Replace all `events.onEvent` callback-based consumption with `for await event in eventSource.events()` task loop, yielding `SpeakerEvent` values to the existing handler logic (renamed from `handleBeoEvent(_:)` to `handleEvent(_:)`). `handleEvent` maps each `SpeakerEvent` case to the same `@Published` / `@Observable` property mutations as the existing handler. No behavioural change to the `Speaker` observable state machine.
  *Depends on: T-2703, T-2704.*

- [ ] **T-2706** Verify that `ContentView.swift`, `SpeakerCardView.swift`, and all views in `iOS/Voxio/Features/` have zero direct references to `MozartClient`, `MozartEvents`, `BNRClient`, or `BNREvents` after T-2705 lands. Add a lint rule (a `grep`-based CI check or a SwiftLint custom rule) that fails the build if any of these four type names appear in `iOS/Voxio/Features/` or in `iOS/Voxio/Core/` outside of `Core/Networking/` and `Core/Protocols/`. Document the check in `iOS/.swiftlint.yml` or equivalent.
  *Depends on: T-2705.*

### Discovery extension

- [ ] **T-2707** Add a second `NetServiceBrowser` instance to `MdnsDiscovery` browsing `_beoremote._tcp.local.` on port 8080. The second browser runs alongside the existing `_bangolufsen._tcp` browser; both share the same delegate queue. On resolution, the resolved host and port are passed to a new factory function (T-2708). Discovery and removal logic is the same as for Mozart speakers — on service removal, the corresponding `Speaker` is removed from the list.
  `Info.plist` update: add `_beoremote._tcp` to the `NSBonjourServices` array alongside `_bangolufsen._tcp` (required for iOS Local Network privacy permission).
  *Depends on: T-2705.*

- [ ] **T-2708** Add a `SpeakerClientFactory` function (or static method on `MdnsDiscovery`) that inspects the resolved `serviceType` string and returns `(any SpeakerClient, any SpeakerEventSource)`:
  - `_bangolufsen._tcp` → `(MozartClient(host:), MozartEvents(host:))`
  - `_beoremote._tcp` → `(BNRClient(host:port:), BNREvents(host:port:))` (BNRClient and BNREvents from E-28, which depends on E-27)
  `Speaker.init(host:client:eventSource:)` from T-2705 is called with the factory's output. If `Speaker.initialize()` throws for a BNR speaker, the speaker is removed from the list (same as Mozart speaker init failure).
  *Depends on: T-2707. Unlocks E-28.*

### Verification

- [ ] **T-2709** Unit tests: add `MockSpeakerClient` and `MockSpeakerEventSource` protocol implementations in `iOS/VoxioTests/Mocks/`. `MockSpeakerClient` records all method calls and returns configurable responses. `MockSpeakerEventSource` yields a configurable `[SpeakerEvent]` sequence from `events()`. Tests live in `iOS/VoxioTests/SpeakerAbstractionTests.swift`. Verify: (a) `Speaker` initialised with mocks populates its observable state correctly from event stream; (b) `Speaker.play()` delegates to `client.play()`; (c) `Speaker` handles `eventSource.events()` stream completion gracefully.
  *Depends on: T-2705.*

- [ ] **T-2710** Regression pass: run the full existing v1.1 test suite against the refactored codebase. All v1.1 tests must pass. Specifically verify: Mozart speaker discovery, init, command dispatch, event handling, and error toasts are functionally identical before and after the refactor. Document the test run result in the PR description.
  *Depends on: T-2705, T-2706, T-2707, T-2708.*

### Group model and discovery (added in v1.2.1)

- [ ] **T-2744** Create `iOS/Voxio/Core/Models/Group.swift`. Define the `Group` model as an `@Observable @MainActor` class:
  ```swift
  @Observable @MainActor
  final class Group: Identifiable {
      let id: String                        // derived: sorted member JIDs/serials, joined, SHA-256 first 16 chars
      var members: [Speaker]                // 1+ speakers; order: host first, then followers alphabetically
      var hostSpeaker: Speaker              // the speaker whose source is playing
      // Derived from hostSpeaker (published automatically via @Observable):
      var playbackState: SpeakerPlaybackState { hostSpeaker.playbackState }
      var volume: Int { hostSpeaker.volume }
      var metadata: TrackMetadata? { hostSpeaker.metadata }
  }
  ```
  `Group.id` is computed once on init: collect `speaker.identifier.jid ?? speaker.identifier.host` for all members, sort lexicographically, join with `","`, take a 16-character hex prefix of the SHA-256 digest (or simply join the sorted string if crypto is undesirable — consistent choice required, document in the code).
  A static factory `Group.single(_ speaker: Speaker) -> Group` creates a group-of-1 for newly discovered standalone speakers.
  *Depends on: T-2701, T-2705.*

- [ ] **T-2745** Create `iOS/Voxio/Core/Discovery/GroupDiscovery.swift`. `GroupDiscovery` is an `@Observable @MainActor` class that owns `var groups: [Group]` — the source of truth for the entire app. It replaces the `[Speaker]` array that `MdnsDiscovery` currently publishes to the UI.

  Startup reconstruction algorithm:
  1. `MdnsDiscovery` discovers speakers and calls `GroupDiscovery.speakerDiscovered(_ speaker: Speaker)`.
  2. After a configurable settle window (500 ms default — waiting for all mDNS announcements), `GroupDiscovery` calls `reconstructGroups()`.
  3. `reconstructGroups()`:
     a. For each Mozart speaker: call `speaker.client.getBeolinkPeers()` (or expose `getPeers()` as a separate `SpeakerClient` method — see note). Collect `(speaker, [BeolinkPeer])` tuples.
     b. Run union-find: for each peer edge `(speakerA, jidB)`, find `speakerB` in the discovered set by matching `identifier.jid`. Union A and B into the same group.
     c. For each BNR speaker: call `GET /BeoZone/Zone/Sources` via `BNRClient.getSources()`. If any source has `multiroom != nil` (listener or host), the speaker is in a session. Attempt to associate it with a Mozart group using heuristics (matching active source name). If no match found, treat as group-of-1.
     d. Speakers not assigned to any peer group form groups-of-1.
  4. Yield the final `[Group]` array to `self.groups`.

  Ongoing maintenance:
  - On mDNS speaker withdrawal: remove the speaker from its group. If the group becomes empty, remove the group. If the removed speaker was `hostSpeaker`, promote the next available member (alphabetically by name) to host, or disband if only one member remains.
  - On `speakerDiscovered` after initial reconstruction: check if the new speaker's peers match an existing group; add it to that group or create a new group-of-1.

  *Depends on: T-2744, T-2707, T-2708.*

  Note on `getPeers()`: `MozartClient.getBeolinkPeers()` is already implemented (lines 283–285 of `MozartClient.swift`). Add `func getPeers() async throws -> [BeolinkPeer]` to `SpeakerClient` (update T-2701 definition) with a default implementation returning `[]` for BNR speakers that have no peers endpoint.

- [ ] **T-2746** Add `func getPeers() async throws -> [BeolinkPeer]` to the `SpeakerClient` protocol in `SpeakerClient.swift`. Provide a default implementation that returns `[]` (suitable for BNR speakers). Add the retroactive conformance mapping to `MozartClient+SpeakerClient.swift` (from T-2703): `getPeers()` calls `getBeolinkPeers()` on `MozartClient`. `BNRClient` uses the default `[]` implementation.
  *Depends on: T-2701, T-2703.*

- [ ] **T-2747** Refactor `HomeView` / speaker list binding to use `[Group]` from `GroupDiscovery` instead of `[Speaker]` from `MdnsDiscovery`. `ContentView` and the speaker list observe `GroupDiscovery.shared.groups`. `SpeakerCardView` accepts a `Group` and renders: (a) if `group.members.count == 1`, renders identically to the current single-speaker card — no layout change; (b) if `group.members.count > 1`, renders the expanded group card layout defined in `design-spec-group-ui-voxio-1.2.md`. All voice command dispatch logic (`dispatchTarget`) is updated to resolve speaker names against `GroupDiscovery.shared.groups.flatMap(\.members)`.
  *Depends on: T-2744, T-2745.*

- [ ] **T-2748** Unit tests for `Group` and `GroupDiscovery` in `iOS/VoxioTests/GroupTests.swift`. Use `MockSpeakerClient` (from T-2709) configured with peer responses. Tests cover: (a) two Mozart speakers with mutual peer edges form a single group of 2; (b) three speakers — two sharing a peer, one isolated — form one group-of-2 and one group-of-1; (c) BNR speaker with `multiroom: "listener"` is placed in a group; (d) BNR speaker with no multiroom source forms a group-of-1; (e) removing a non-host speaker from a group leaves the host as group-of-1; (f) removing the host speaker promotes the next member; (g) `Group.id` is stable for the same member set across re-computation.
  *Depends on: T-2745, T-2746.*

---

## E-28 — BNRClient + BNREvents

Implement `BNRClient: SpeakerClient` and `BNREvents: SpeakerEventSource` for the BNR (BeoNetRemote) REST + long-poll API. Encapsulate the press+release playback command pattern, 0–`range.maximum` volume normalisation, and long-poll reconnect loop. ASE-platform speakers discovered via `_beoremote._tcp` are fully controllable through these types.

**Depends on:** E-27 (protocols and factory)

---

### BNRClient

- [ ] **T-2711** Create `iOS/Voxio/Core/Networking/BNRClient.swift`. This type conforms to `SpeakerClient`. Properties: `host: String`, `port: Int` (default 8080), a `URLSession` with 5-second timeout matching `MozartClient`'s pattern. Base URL: `http://{host}:{port}`. All requests use `Content-Type: application/json`. All `URLError.timedOut` errors map to `MozartError.timeout` (or `SpeakerError.timeout` if a unified error type is introduced). Connection errors map to `SpeakerError.unreachable`. Non-2xx responses other than 501 map to `SpeakerError.httpError(statusCode)`. HTTP 501 on write operations: log at INFO, do not throw.
  *Depends on: T-2701.*

- [ ] **T-2712** Implement volume read/write in `BNRClient`. On initialisation (or first `getVolume()` call), fetch `GET /BeoZone/Zone/Sound/Volume/Speaker` and store `range.maximum`. Subsequent writes use `level = percentage * storedMaximum / 100` rounded to nearest integer. `getVolume()` returns `speaker.level * 100 / storedMaximum` rounded. `setVolume(_ level: Int)` sends `PUT /BeoZone/Zone/Sound/Volume/Speaker/Level` with `{ "level": level * maximum / 100 }`. `mute(_ muted: Bool)` sends `PUT /BeoZone/Zone/Sound/Volume/Speaker/Muted` with `{ "muted": muted }`. If `range.maximum` has not been fetched yet, fetch it synchronously before proceeding with the write.
  *Depends on: T-2711.*

- [ ] **T-2713** Implement playback commands in `BNRClient` using the press+release double-POST pattern. `play()` sends `POST /BeoZone/Zone/Stream/Play` then `POST /BeoZone/Zone/Stream/Play/Release` in sequence; if the second POST fails the method still returns without throwing (the press was delivered). Similarly for `pause()` and `stop()`. Each press/release pair is awaited sequentially inside the method before it returns. Total round-trip for a play/pause command must complete in ≤ 2 seconds on a normal home network.
  *Depends on: T-2711.*

- [ ] **T-2714** Implement `getPlaybackState()` in `BNRClient`. Calls `GET /BeoZone/Zone/ActiveSources` and maps `activeSources.primaryExperience.state` to `SpeakerPlaybackState`: `"play"` → `.playing`, `"pause"` → `.paused`, `"stop"` → `.stopped`, `"buffering"` → `.buffering`. Returns `.stopped` if `primaryExperience` is absent.
  *Depends on: T-2711.*

- [ ] **T-2715** Implement `getName()` in `BNRClient`. Calls `GET /BeoDevice` and returns `beoDevice.productFriendlyName.productFriendlyName`. This string is used as the `Speaker.name` property and for voice command speaker addressing.
  *Depends on: T-2711.*

- [ ] **T-2716** Implement `getSources()` and `activateSource()` in `BNRClient`. `getSources()` calls `GET /BeoZone/Zone/Sources`, filters the response array to entries where `inUse == true` and `borrowed == false`, and maps each to a `Favorite(id: source.id, name: source.friendlyName)`. The result is ordered by position in the API response array. `activateSource(_ id: String)` calls `POST /BeoZone/Zone/ActiveSources` with `{ "primaryExperience": { "source": { "id": id } } }`. `getBattery()` returns `nil` for BNR speakers (BNR does not expose battery information via REST).
  *Depends on: T-2711.*

### BNREvents

- [ ] **T-2717** Create `iOS/Voxio/Core/Networking/BNREvents.swift`. This type conforms to `SpeakerEventSource`. `events()` returns an `AsyncStream<SpeakerEvent>` backed by a `Task` that runs a long-poll loop:
  ```
  while !Task.isCancelled {
      do {
          let event = try await fetchNextNotification()
          continuation.yield(normalise(event))
      } catch {
          try? await Task.sleep(nanoseconds: backoffNanoseconds())
      }
  }
  continuation.finish()
  ```
  `fetchNextNotification()` sends `GET http://{host}:{port}/BeoNotify/Notifications` and decodes the response body as a `BNRNotification` (a Codable struct matching the `{ "notification": { "type": ..., "data": ... } }` shape from the BNR API spec). Any response — event, empty body, or server close — is treated as a complete response and the connection is immediately re-opened (the server-side timeout duration is undocumented). Exponential backoff applies only on network errors, not on successful responses. Initial backoff: 1 second; maximum backoff: 30 seconds. `continuation.onTermination` cancels the background `Task`.
  *Depends on: T-2702.*

- [ ] **T-2718** Implement `normalise(_ notification: BNRNotification) -> SpeakerEvent` in `BNREvents`. Translation table:
  - `type == "VOLUME"` → `.volume(level: speaker.level * 100 / speaker.range.maximum, muted: speaker.muted)`
  - `type == "SOURCE"` → `.source(name: data.primaryExperience.source.friendlyName, id: data.primaryExperience.source.id)`
  - `type == "PROGRESS_INFORMATION"` → `.playbackState(mapState(data.state))` where `mapState` maps `"play"` → `.playing`, `"pause"` → `.paused`, `"stop"` → `.stopped`, `"buffering"` → `.buffering`, `"completed"` → `.stopped`
  - `type == "NOW_PLAYING_NET_RADIO"` → `.metadata(title: data.name, artist: data.liveDescription, album: nil)`
  - `type == "NOW_PLAYING_STORED_MUSIC"` → `.metadata(title: data.name, artist: data.artist, album: data.album)`
  - Unknown `type` value → log at VERBOSE and return `nil` (the caller drops `nil` events and does not yield them to the stream).
  `BNRNotification` and its nested `BNRNotificationData` types are `Codable` structs defined in the same file or a sibling `BNRModels.swift` in `Core/Networking/`.
  *Depends on: T-2717.*

### Initialization wiring

- [ ] **T-2719** Wire `Speaker.initialize()` for BNR speakers. `Speaker.initialize()` already runs parallel REST calls via `async let`. For a BNR speaker, the parallel calls are: `async let name = client.getName()`, `async let volume = client.getVolume()`, `async let state = client.getPlaybackState()`, `async let sources = client.getSources()`. Assign results to the corresponding `@Observable` properties. After parallel init completes, start the `for await event in eventSource.events()` loop on a detached `Task`. The loop assigns each `SpeakerEvent` to the matching property via `handleEvent(_:)` (from T-2705). `getBattery()` is not called during BNR init — returns `nil` immediately.
  *Depends on: T-2705, T-2712, T-2714, T-2715, T-2716, T-2717.*

### Verification

- [ ] **T-2720** Unit tests for `BNRClient` in `iOS/VoxioTests/BNRClientTests.swift`. Use `URLProtocol` mocking to intercept HTTP requests. Tests cover: volume read (`getVolume()` correctly converts raw to percentage), volume write (`setVolume(50)` sends `level = maximum / 2`), mute write, play command sends both press and release POSTs, 501 response on play does not throw, 404 response on play throws `SpeakerError.httpError(404)`, timeout maps to `.timeout`, `getSources()` filters `borrowed == true` sources correctly.
  *Depends on: T-2711, T-2712, T-2713, T-2714, T-2715, T-2716.*

- [ ] **T-2721** Unit tests for `BNREvents` in `iOS/VoxioTests/BNREventsTests.swift`. Use a mock HTTP server (or `URLProtocol`) to inject notification payloads. Tests cover: `VOLUME` event normalises to correct percentage, `PROGRESS_INFORMATION` `"play"` maps to `.playing`, `"completed"` maps to `.stopped`, `NOW_PLAYING_NET_RADIO` maps `name` to `title` and `liveDescription` to `artist`, unknown notification type is dropped (stream continues), network error triggers reconnect after backoff, `events()` stream terminates cleanly on task cancellation.
  *Depends on: T-2717, T-2718.*

- [ ] **T-2722** Manual integration test on a physical BNR speaker. Connect a B&O ASE-platform device (any supported model from the api-spec device list) to the same local network as the development device. Verify: speaker appears in the app speaker list within 5 seconds; friendly name matches the device's configured name; playback state, volume, and source display correctly; play/pause/volume/mute commands execute correctly; track metadata updates in real time during music playback. Document the device model, firmware version, and any deviations in `Specification/Voxio 1.2/bnr-integration-test.md`.
  *Depends on: T-2719.*

---

## E-29 — App Intents Declarations

Declare `AudioPlaybackIntent`-conforming intents for play/pause toggle, volume adjustment, mute toggle, speaker join, and speaker leave. Register an `AppShortcutsProvider` with Siri invocation phrases in English and Danish. These declarations are compiled into both the main app target and the widget extension target (shared file membership). The intents are invoked by widget `Button(intent:)` controls (E-30, E-31), by Siri, and by the voice command pipeline (E-32).

**Depends on:** E-27 (speaker protocol abstraction — intents call `Speaker` methods via the protocol; `JoinSpeakerIntent` and `LeaveSpeakerIntent` depend on `SpeakerClient.join(peer:)` and `.leave()` from T-2701)  
**Unlocks:** E-30 (widget buttons reference these intents), E-31 (Control Widget controls reference these intents), E-32 (join/leave voice pipeline calls these intents)

---

- [ ] **T-2723** Create `iOS/Voxio/Core/Intents/VoxioIntents.swift`. Declare the following `AudioPlaybackIntent`-conforming types (each is a struct conforming to `AppIntent` and `AudioPlaybackIntent`):
  - `PlaybackToggleIntent` — toggles play/pause on the active speaker. `title: LocalizedStringResource = "Play/Pause Voxio"`. `perform()` reads the active speaker from `SpeakerStore.shared` (or the App Groups shared container) and calls `speaker.client.play()` if paused or `speaker.client.pause()` if playing.
  - `AdjustVolumeIntent` — adjusts volume by a fixed delta. Parameter: `delta: Int` (positive = up, negative = down; default magnitudes ±10). `title: LocalizedStringResource = "Adjust Volume in Voxio"`. `perform()` calls `speaker.client.getVolume()` then `speaker.client.setVolume(clamped)`.
  - `MuteIntent` — toggles mute state. `title: LocalizedStringResource = "Mute Voxio"`. `perform()` reads current mute state from shared container and calls `speaker.client.mute(!currentMuted)`.
  - `JoinSpeakerIntent` — joins speaker A to speaker B's session. Parameters: `source: SpeakerEntity` (the speaker that will follow), `target: SpeakerEntity` (the speaker whose source is played). `title: LocalizedStringResource = "Join Speakers in Voxio"`. `perform()` resolves both speakers from `GroupDiscovery`, then calls `target.client.join(peer: source.identifier)` for Mozart→Mozart (expand call on the target), or `source.client.join(peer: target.identifier)` for BNR→Any (OneWayJoin on the source). See E-32 T-2758 for platform dispatch logic. Returns a confirmation dialog on success: "Joined [Source] to [Target]." (en) / "Tilsluttede [Kilde] til [Mål]." (da).
  - `LeaveSpeakerIntent` — causes a speaker to leave its group. Parameter: `speaker: SpeakerEntity`. `title: LocalizedStringResource = "Leave Group in Voxio"`. `perform()` calls `speaker.client.leave()`. Returns confirmation: "[Speaker] is now playing alone." (en) / "[Højttaler] spiller nu alene." (da). If speaker is not in a group, returns error dialog: "[Speaker] is not in a group." (en).
  Add the file to both the main app target and the widget extension target's file membership (the widget extension target is created in E-30; add membership after E-30's T-2729).
  *Depends on: T-2701, T-2744.*

- [ ] **T-2724** Implement `AppShortcutsProvider` in `iOS/Voxio/Core/Intents/VoxioShortcutsProvider.swift`. Declare `AppShortcut` entries for:
  - `PlaybackToggleIntent` (play): phrases `"Play \(.applicationName)"` (en), `"Afspil \(.applicationName)"` (da)
  - `PlaybackToggleIntent` (pause): phrases `"Pause \(.applicationName)"` (en), `"Sæt \(.applicationName) på pause"` (da)
  - `MuteIntent`: phrases `"Mute \(.applicationName)"` (en), `"Slå \(.applicationName) fra"` (da)
  - `AdjustVolumeIntent(delta: +10)`: phrases `"Turn up the volume in \(.applicationName)"` (en), `"Skru op for lyden i \(.applicationName)"` (da)
  - `AdjustVolumeIntent(delta: -10)`: phrases `"Turn down the volume in \(.applicationName)"` (en), `"Skru ned for lyden i \(.applicationName)"` (da)
  - `JoinSpeakerIntent`: phrases `"Join speakers in \(.applicationName)"` (en), `"Saml højttalere i \(.applicationName)"` (da)
  - `LeaveSpeakerIntent`: phrases `"Leave group in \(.applicationName)"` (en), `"Forlad gruppe i \(.applicationName)"` (da)
  `AppShortcutsProvider.updateAppShortcutsParameters()` is called from `VoxioApp.init()`. The `\(.applicationName)` substitution is the WidgetKit / App Intents standard placeholder for the app name string "Voxio".
  *Depends on: T-2723.*

- [ ] **T-2725** Add a `SpeakerStore` singleton (or App Groups `UserDefaults`-backed accessor) that `AudioPlaybackIntent.perform()` uses to find the active speaker's client. `SpeakerStore.shared.activeSpeaker` returns the currently active `Speaker` (or the configured speaker for a specific widget configuration). This store is populated by `MdnsDiscovery` as speakers are found and initialised, and updated when the user switches active speakers. It is backed by in-memory state for the main app process; widget intents access speaker state via the shared container (E-30 T-2731).
  *Depends on: T-2723.*

- [ ] **T-2726** Add error responses for Siri intent failures. When `perform()` throws a `SpeakerError.timeout` or `.unreachable`, the intent constructs an `IntentResultDialog` with the string: "I couldn't reach [Speaker Name]. Make sure Voxio is running and the speaker is on the network." (en) / "Jeg kunne ikke nå [Højttalernavn]. Sørg for, at Voxio kører og højttaleren er på netværket." (da). When `perform()` cannot reach the app process (app not running), the dialog is: "To control your speaker, open Voxio first." (en) / "Åbn Voxio for at styre din højttaler." (da). For join/leave intents, when the named speaker is not found in `GroupDiscovery`: "I couldn't find a speaker called [Name] in Voxio. Make sure it's on the network." (en) / "Jeg kunne ikke finde en højttaler ved navn [Navn] i Voxio. Sørg for, at den er på netværket." (da). All strings flow through `LanguageService` / `String(localized:)`.
  *Depends on: T-2724.*

- [ ] **T-2727** Verify App Intents declarations compile and appear in Shortcuts app. On a device, confirm "Voxio" appears in the Shortcuts app shortcut list with all seven phrase variants (existing five + join + leave). Confirm Siri can invoke "Pause Voxio" from a voice invocation (app running in background). Confirm "Sæt Voxio på pause" works in a da-DK locale. Confirm "Join speakers in Voxio" appears in the Shortcuts list. Document the test device, iOS version, and result in the PR description.
  *Depends on: T-2724, T-2725, T-2726.*

---

## E-30 — Home-Screen Widget

Create the WidgetKit extension with `systemSmall` and `systemMedium` widget sizes. Build the timeline provider reading from the App Groups shared container. Build both widget views. Wire `Button(intent:)` controls to the intents from E-29. Add new design tokens to `DesignTokens.swift` and `BeoColor.swift`. Configure the App Groups entitlement.

**Depends on:** E-27 (shared container written by Speaker), E-29 (intents referenced by Button(intent:))  
**P0 prerequisite:** App Groups entitlement must be configured before this epic begins (T-2728)

---

### Entitlement setup (P0 prerequisite)

- [ ] **T-2728** Configure the `group.T-Creative.Voxio` App Group entitlement on both the main app target (`iOS/Voxio.xcodeproj`) and the widget extension target (created in T-2729). Steps:
  1. Register `group.T-Creative.Voxio` in the Apple Developer Portal → Identifiers → App Groups.
  2. Update the main app's App ID to include the App Groups capability.
  3. Regenerate the main app provisioning profile.
  4. Add `com.apple.security.application-groups` to `iOS/Voxio/Voxio.entitlements` with value `["group.T-Creative.Voxio"]`.
  5. After T-2729 creates the widget extension target, repeat steps 2–4 for the extension.
  Document the exact steps and profile names in `Specification/Voxio 1.2/app-groups-setup.md`.
  **This task must complete before T-2730 (shared container write) and T-2731 (timeline provider read) can be developed.** It is the P0 blocker for the entire widget feature.
  *No dependencies. Prerequisite for T-2730, T-2731.*

### Widget extension target

- [ ] **T-2729** Add a new WidgetKit extension target `VoxioWidget` to `iOS/Voxio.xcodeproj`. Minimum deployment target: iOS 26. The extension contains: `VoxioWidgetBundle.swift` (the `@main` entry point, `WidgetBundle` conformance), `VoxioPlayerWidget.swift` (the `Widget` definition), `VoxioWidgetProvider.swift` (timeline provider), `VoxioWidgetSmallView.swift`, `VoxioWidgetMediumView.swift`, and a `WidgetConfiguration` supporting `.systemSmall` and `.systemMedium`. Add `DesignTokens.swift` and `BeoColor.swift` to the widget extension target file membership. Add the intents file `VoxioIntents.swift` (E-29 T-2723) to the widget extension target file membership. Add App Groups entitlement to the extension after T-2728 completes.
  *Depends on: T-2728, T-2723.*

### Design tokens

- [ ] **T-2730** Add new design tokens to `DesignTokens.swift` and `BeoColor.swift`:
  - In `DesignTokens.swift`, add `BeoType` extensions:
    ```swift
    extension BeoType {
        static let widgetSpeakerName = Font.system(size: 12, weight: .semibold, design: .default)
        static let widgetTrack       = Font.system(size: 15, weight: .regular, design: .rounded)
        static let widgetCaption     = Font.system(size: 11, weight: .regular, design: .default)
    }
    enum WidgetButtonToken {
        static let paddingV:     CGFloat = 8
        static let paddingH:     CGFloat = 12
        static let iconGap:      CGFloat = 6
        static let iconOnlySize: CGFloat = 36
    }
    ```
  - In `BeoColor.swift`, add:
    ```swift
    static let separator = Color("BeoSeparator")
    ```
  Inline comment on each `BeoType.widget*` token: "Widget extension only — not used in the main app target." Inline comment on `WidgetButtonToken`: "Widget canvas-sized button padding — do not use in main app. See DarkGlassButtonTokens for main app values."
  Confirm that the existing `BeoSeparator` asset is present in `Assets.xcassets`. If absent, add it with a light/dark adaptive colour matching its use in `SpeakerCardView`'s divider.
  *Depends on: T-2729.*

### Shared container — write side (main app)

- [ ] **T-2731** Add a `WidgetStateWriter` struct (or extend `Speaker`) to write speaker state to `UserDefaults(suiteName: "group.T-Creative.Voxio")` on every `Speaker` event and on `scenePhase == .background`. Written keys:
  - `widget_speaker_name: String` — display name
  - `widget_speaker_host: String` — host address (for speaker targeting)
  - `widget_track_title: String?` — current track or station name
  - `widget_source_name: String?` — source friendly name
  - `widget_playback_state: String` — "playing" | "paused" | "stopped" | "loading"
  - `widget_volume: Int` — 0–100
  - `widget_muted: Bool`
  - `widget_app_running: Bool` — `true` when written from a live session; written as `false` in the `scenePhase == .background` handler (synthetic paused state)
  - `widget_last_written_at: Double` — Unix timestamp for staleness detection
  - `widget_data_version: Int` — increment if the schema changes (v1.2 = 1)
  - `widget_discovered_speakers: Data` — JSON-encoded `[SpeakerRecord]` for the widget configuration picker. `SpeakerRecord` is a `Codable` struct with `host`, `name`, `platform` ("mozart" | "bnr").
  After each write, call `WidgetCenter.shared.reloadAllTimelines()`. Register the `scenePhase` observer in `VoxioApp.swift`'s `WindowGroup` body via `.onChange(of: scenePhase)`.
  *Depends on: T-2728.*

### Timeline provider and widget model

- [ ] **T-2732** Build `VoxioWidgetProvider` in `iOS/Voxio/Widget/VoxioWidgetProvider.swift`. Conforms to `TimelineProvider`. `getSnapshot(_:context:completion:)` and `getTimeline(_:context:completion:)` both read from `UserDefaults(suiteName: "group.T-Creative.Voxio")` and construct a `VoxioWidgetEntry` value type containing all display fields. Timeline contains a single entry (current state) with a `next` date of `Date.distantFuture` — the timeline is refreshed via `WidgetCenter.shared.reloadAllTimelines()` from the main app, not by a scheduled deadline. `VoxioWidgetEntry` includes: `speakerName`, `trackTitle`, `sourceName`, `playbackState`, `volume`, `isMuted`, `appRunning`, `isEmpty` (no speaker), `lastWrittenAt`, `dataVersion`. If `dataVersion` is unrecognised, `isEmpty = true`.
  *Depends on: T-2729, T-2730, T-2731.*

### Widget configuration

- [ ] **T-2733** Build the widget configuration UI for speaker selection. `VoxioPlayerWidget` uses `AppIntentConfiguration` with a custom `VoxioWidgetIntent: AppIntent` that exposes a `speakerPicker: SpeakerEntity` parameter. `SpeakerEntity` is an `AppEntity` whose `query` reads `widget_discovered_speakers` from the shared container. The entity list is the speakers written by T-2731 plus an "Automatic (most recent)" option (entity id: `"auto"`). When the user edits the widget, the iOS widget configuration sheet shows this picker. The timeline provider uses the configured `speakerPicker` to filter which speaker's state to display. If `"auto"` is selected, the most recently written speaker state is shown.
  *Depends on: T-2732.*

### systemSmall view

- [ ] **T-2734** Build `VoxioWidgetSmallView.swift`. Layout from top to bottom (all within a `VStack(alignment: .leading, spacing: 4)` with 12 pt edge padding via `containerBackground`):
  1. Speaker header HStack: `Image(systemName: "hifispeaker.fill")` at 12 pt in `BeoColor.labelSecondary` + `Text(entry.speakerName)` in `BeoType.widgetSpeakerName`.
  2. Track name HStack (when playing): `Image(systemName: "waveform")` at 14 pt in `BeoColor.accent` + `Text(entry.trackTitle ?? "—")` in `BeoType.widgetTrack`, 2-line limit.
  3. Track name (when not playing): `Text(entry.trackTitle ?? "—")` in `BeoType.widgetTrack`, 2-line limit, no waveform.
  4. `Text(entry.sourceName ?? "—")` in `BeoType.widgetCaption` in `BeoColor.labelSecondary`.
  5. `Spacer()`.
  6. Primary action button: `Button(intent: PlaybackToggleIntent()) { … }` with `.glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: Capsule())`, 0.5 pt `Capsule().strokeBorder(Color.white.opacity(0.15))` overlay, `WidgetButtonToken.paddingV` / `WidgetButtonToken.paddingH` padding. Icon: `play.fill` (paused/stopped) or `pause.fill` (playing). Icon tint: `BeoColor.accent` when playing, `BeoColor.labelSecondary` when paused/stopped. Label: "Play" / "Pause". Button fills available width.
  State variants: playing (waveform + gold pause icon), paused (no waveform + grey play icon), stopped ("—" track + grey play icon), loading (`ellipsis` disabled button), app-not-running (50% opacity + "Open Voxio" Link), empty (`hifispeaker.slash` + "No speaker found" + "Open Voxio" Link).
  Accessibility labels on the button per US-40. VoiceOver description: `accessibilityElement(children: .combine)` with combined label.
  *Depends on: T-2730, T-2732, T-2733.*

### systemMedium view

- [ ] **T-2735** Build `VoxioWidgetMediumView.swift`. Layout: full-width speaker header row (identical to small, 22 pt height), then a two-column `HStack` below it (left 55%, column gap 12 pt, right 45%), with a `Rectangle().frame(width: 0.5).foregroundColor(BeoColor.separator.opacity(0.15))` divider between columns.
  Left column (`VStack(alignment: .leading, spacing: 4)`):
  - Playing indicator + track title (same as small view, `BeoType.widgetTrack`, 2-line)
  - Source + volume inline: `Text("\(entry.sourceName ?? "—") · \(entry.volume)")` in `BeoType.widgetCaption` in `BeoColor.labelSecondary`
  Right column (`VStack(spacing: 8)`):
  - Play/pause `Button(intent:)` (same glass treatment as small, full right-column width)
  - Volume row `HStack(spacing: 8)`: `Button(intent: AdjustVolumeIntent(delta: -10)) { Image(systemName: "minus.circle.fill") }` at 36 pt + decorative `Image(systemName: "speaker.wave.2.fill")` at 16 pt + `Button(intent: AdjustVolumeIntent(delta: +10)) { Image(systemName: "plus.circle.fill") }` at 36 pt. Volume buttons use `.hierarchical` rendering mode, `.frame(minWidth: 44, minHeight: 44)`, and are disabled when `entry.volume == 0` (down) / `entry.volume == 100` (up) / `!entry.appRunning`.
  App-not-running state: entire content at 50% opacity via `.opacity(entry.appRunning ? 1.0 : 0.5)`. Right column replaced by "Open Voxio" `Link`. "Open to control" label at `BeoType.widgetCaption` centred in the left column.
  Empty state: `hifispeaker.slash` + "No speaker found" centred across full content area + "Open Voxio" Link.
  Accessibility labels per US-40.
  *Depends on: T-2730, T-2732, T-2733.*

### Widget definition

- [ ] **T-2736** Complete `VoxioPlayerWidget` in `VoxioWidgetBundle.swift`. Declare `VoxioPlayerWidget: Widget` with `body` returning `AppIntentConfiguration(kind: "VoxioPlayerWidget", intent: VoxioWidgetIntent.self, provider: VoxioWidgetProvider())` and `.configurationDisplayName("Voxio Player")` and `.description("Control your B&O speaker from your Home Screen.")`. The `entryView` switches on `context.family`: `.systemSmall` → `VoxioWidgetSmallView(entry:)`, `.systemMedium` → `VoxioWidgetMediumView(entry:)`, default → `VoxioWidgetSmallView(entry:)`. Supported families: `[.systemSmall, .systemMedium]`.
  *Depends on: T-2734, T-2735.*

### Verification

- [ ] **T-2737** Widget snapshot tests. Add `VoxioWidgetSnapshotTests.swift` in `iOS/VoxioTests/`. Snapshot the `systemSmall` and `systemMedium` views (using `WidgetPreviewContext`) in all six states: playing, paused, stopped, loading, app-not-running, empty. Also snapshot in dark mode + Increase Contrast for both sizes. All snapshots must pass on the iPhone 15 Pro simulator frame. Reference snapshots are committed alongside the test file.
  *Depends on: T-2736.*

- [ ] **T-2738** Manual integration test: place `systemSmall` and `systemMedium` widgets on the Home Screen with a speaker running. Verify: (a) playback state updates within 3 seconds of playing/pausing via the app; (b) tapping the play/pause button executes the command and the widget updates; (c) tapping the volume up/down buttons in `systemMedium` changes the volume and the widget reflects it; (d) killing the app and tapping a widget button transitions to the app-not-running fallback; (e) relaunch restores the interactive state. Document the test device and iOS version.
  *Depends on: T-2737.*

---

## E-31 — Control Widget

Build the Control Widget (`ControlWidgetButton` for play/pause and `ControlWidgetToggle` for mute) using the `AppIntentControlConfiguration` API. The Control Widget appears in Control Center and on the lock screen. Per-speaker targeting uses the same speaker picker as the home-screen widget.

**Depends on:** E-29 (intents), E-30 (App Groups entitlement, shared container write side, `SpeakerEntity` from T-2733)

---

- [ ] **T-2739** Create `VoxioControlWidget.swift` in the `VoxioWidget` extension target. Declare a `ControlWidget` conformance named `VoxioPlayPauseControl`:
  ```swift
  struct VoxioPlayPauseControl: ControlWidget {
      var body: some ControlWidgetConfiguration {
          AppIntentControlConfiguration(
              kind: "VoxioPlayPause",
              intent: PlaybackToggleIntent.self
          ) { template in
              ControlWidgetButton(action: template) {
                  let state = readPlaybackState()
                  Label(
                      state == .playing ? "Pause" : "Play",
                      systemImage: state == .playing ? "pause.fill" : "play.fill"
                  )
              }
              .tint(readPlaybackState() == .playing ? BeoColor.accent : nil)
          }
          .displayName("Voxio Play")
          .description("Play or pause your B&O speaker.")
      }
  }
  ```
  `readPlaybackState()` reads from the App Groups shared container via `UserDefaults(suiteName: "group.T-Creative.Voxio")`. `isEnabled` is `false` when `widget_app_running == false`. Register the control widget in `VoxioWidgetBundle` alongside `VoxioPlayerWidget`.
  *Depends on: T-2729, T-2731, T-2723.*

- [ ] **T-2740** Add `VoxioMuteControl: ControlWidget` to the same file or a sibling file. Uses `ControlWidgetToggle` backed by `MuteIntent`. Icon: `speaker.wave.2.fill` when unmuted, `speaker.slash.fill` when muted. Active (muted) tint: system default — do NOT use `BeoColor.accent`. Label: "Voxio Mute". `isOn` binding reads `widget_muted` from the shared container. `isEnabled`: `false` when `widget_app_running == false`.
  *Depends on: T-2739.*

- [ ] **T-2741** Add per-speaker configuration to both control widgets via `AppIntentControlConfiguration`. The `intent` parameter exposes the same `speakerPicker: SpeakerEntity` parameter from T-2733. When the user long-presses the Control Center tile, iOS presents the speaker picker. Default: "Automatic (most recent)" — reads the most recently written speaker from the shared container.
  Tile display name (shown below the icon grid in Control Center, on supported devices): speaker name when a specific speaker is configured; "Voxio" when set to Automatic.
  *Depends on: T-2739, T-2740, T-2733.*

- [ ] **T-2742** Accessibility and localisation for the Control Widget. Add `accessibilityLabel` to each control:
  - Play/pause button: "Voxio Play" (en) / "Voxio Afspil" (da)
  - Mute toggle: "Voxio Mute" (en) / "Voxio Slå fra" (da)
  These strings are announced by Siri and VoiceOver on long-press of the Control Center tile. They must flow through `String(localized:)` with the appropriate `LocalizedStringResource` keys. Confirm on a Danish-locale device that the correct strings are announced.
  *Depends on: T-2739, T-2740.*

- [ ] **T-2743** Manual integration test: add both Control Widget controls to Control Center. Verify: (a) tile appears in Control Center after addition; (b) tapping the play/pause button toggles playback (app in background) and the tile icon updates; (c) tapping the mute toggle mutes/unmutes and the icon updates; (d) with app killed, both tiles dim and show system-provided "Requires Voxio" (or equivalent) treatment; (e) long-pressing a tile shows the speaker picker; (f) configuring a specific speaker targets that speaker on tap. Document device model and iOS version. Optionally: verify the tile appears on a paired Apple Watch and Mac (iOS 26 mirroring).
  *Depends on: T-2741, T-2742.*

---

## E-32 — Speaker Join / Leave

Implement the voice command pipeline for `joinSpeaker(source:target:)` and `leaveSpeaker(speaker:)`. Extend the three-tier NLP parser with all join and leave variant phrases in English and Danish. Wire the parsed commands through the auto-execute countdown (join only) to the appropriate `SpeakerClient.join(peer:)` and `.leave()` calls. Update `GroupDiscovery` to reflect the resulting group state change. Add `JoinSpeakerIntent` and `LeaveSpeakerIntent` as Siri-invocable intents (declared in E-29 T-2723; the NLP parser and confirmation wiring are in this epic).

**Depends on:** E-27 (Group model, `SpeakerClient.join(peer:)` and `.leave()` from T-2701, `GroupDiscovery` from T-2745), E-28 (BNRClient `join` and `leave` implementations), E-29 (`JoinSpeakerIntent` and `LeaveSpeakerIntent` declared in T-2723)  
**User Stories:** US-42, US-43, US-44, US-45, US-48

---

### NLP parser extension

- [ ] **T-2749** Add `joinSpeaker(source: SpeakerIdentifier, target: SpeakerIdentifier)` and `leaveSpeaker(speaker: SpeakerIdentifier)` cases to the `VoiceCommand` enum in `Core/Voice/` (or wherever the enum is defined). Update `CommandParserRouter` to route new cases. These are Tier-1 (regex/keyword) commands.
  *Depends on: T-2701, T-2744.*

- [ ] **T-2750** Implement Tier-1 regex/keyword detection for join phrases in the NLP parser. Patterns to match (case-insensitive, speaker names as capture groups using the existing speaker name token logic):

  English join verbs/phrases:
  - `join`
  - `play with`
  - `play the same as`
  - `sync with`
  - `follow`
  - `play along with`
  - `play together with`
  - `listen together with`

  Danish join verbs/phrases:
  - `spil med`
  - `spil det samme som`
  - `synkroniser med`
  - `følg`

  Pattern structure: `[source speaker name] <join phrase> [target speaker name]`. Speaker name resolution uses the existing `dispatchTarget` mechanism against `GroupDiscovery.shared.groups.flatMap(\.members)`.
  *Depends on: T-2749, T-2747.*

- [ ] **T-2751** Implement Tier-1 regex/keyword detection for leave phrases in the NLP parser. Patterns to match:

  English leave phrases:
  - `leave the group`
  - `stop playing with [target name]`
  - `play alone`
  - `disconnect from [target name]`
  - `leave`

  Danish leave phrases:
  - `forlad gruppen`
  - `spil alene`
  - `stop med at spille med [target name]`

  Pattern structure: `[speaker name] <leave phrase>`. `[target name]` is optional — if present, it is captured but not used for the API call (leave is unconditional from the leaving speaker's perspective). Speaker name resolution uses `dispatchTarget`.
  *Depends on: T-2749, T-2747.*

- [ ] **T-2752** Add Tier-2 (NLTagger/NLModel) intent classification for join and leave. Training hint: utterances containing the join verb set or leave verb set with two speaker names should classify as `.joinSpeaker` / `.leaveSpeaker`. If Tier-1 pattern matching fails (e.g. unusual word order, abbreviation), Tier-2 classification provides a fallback. Tier-3 (LLM/on-device model) is the final fallback as per the existing E-24 three-tier architecture — no new Tier-3 training is required for v1.2.
  *Depends on: T-2750, T-2751.*

### Confirmation and command execution

- [ ] **T-2753** Wire `joinSpeaker` through the E-25 auto-execute countdown. When `joinSpeaker(source:target:)` is parsed, the confirmation orb displays:
  - English: "Joining [Source] to [Target] in 3…" countdown
  - Danish: "Tilslutter [Kilde] til [Mål] om 3…" countdown
  The user can cancel by saying "cancel" or tapping the orb (per E-25 behaviour). After the countdown, dispatch the join API call (T-2758). The `JoinSpeakerIntent` path (Siri) bypasses this countdown.
  *Depends on: T-2749, T-2750.*

- [ ] **T-2754** Wire `leaveSpeaker` to execute immediately with no countdown. When `leaveSpeaker(speaker:)` is parsed, dispatch the leave API call (T-2759) immediately. No confirmation orb countdown is shown. A brief haptic feedback (success/failure) is the only acknowledgement.
  *Depends on: T-2749, T-2751.*

### Join API dispatch

- [ ] **T-2755** Guard: before executing any join, check if source and target are already members of the same `Group`. If so, return early and show toast: "[Source] is already playing with [Target]." (en) / "[Kilde] spiller allerede med [Mål]." (da). No API call is made.
  *Depends on: T-2744, T-2747.*

- [ ] **T-2756** Guard: before executing leave, check if the speaker is a group-of-1. If so, return early and show toast: "[Speaker] is not in a group." (en) / "[Højttaler] er ikke i en gruppe." (da). No API call is made.
  *Depends on: T-2744, T-2747.*

- [ ] **T-2757** Implement join API dispatch for Mozart→Mozart. Call `target.client.join(peer: source.identifier)` which maps to `beolinkExpand(jid: source.identifier.jid!)` on the `MozartClient+SpeakerClient` conformance extension (update T-2703 to add the `join(peer:)` mapping — `join(peer:)` on a Mozart client sends `POST /beolink/expand/{jid}` where jid is `peer.jid`).

  On success: call `GroupDiscovery.shared.mergeIntoGroup(source: source, target: target)` to update the app's group state. The UI updates as `groups` changes.
  On failure (`SpeakerError.timeout` or `.unreachable`): show toast: "Couldn't join [Source] to [Target]. Check the speaker is reachable." (en). Do not modify group state.
  *Depends on: T-2703, T-2744, T-2745, T-2755.*

- [ ] **T-2758** Implement join API dispatch for BNR→Any. Call `source.client.join(peer: target.identifier)` which maps to `POST /BeoZone/Zone/Device/OneWayJoin` on the `BNRClient` (implement `join(peer:)` in `BNRClient` — the `peer` argument is available for logging but BNR join is broadcast-only). On success: update group state via `GroupDiscovery.shared.mergeIntoGroup(source: source, target: target)`. On failure: toast as per T-2757.
  *Depends on: T-2711, T-2744, T-2745, T-2755.*

- [ ] **T-2759** Implement join API dispatch for Mozart→BNR host (best-effort path). Call `source.client.join(peer: target.identifier)` — for Mozart client, when `peer.platform == .bnr`, call `beolinkJoin()` (no jid argument) on the Mozart client. Log at INFO: `[JoinDispatch] Mozart→BNR join: calling beolinkJoin() on \(source.identifier.host). This is best-effort.` On success: update group state. On failure or when no active session is detected: toast: "Couldn't join [Source] to [Target]. Make sure [Target] is playing." (en). Flag this task's PR with a comment referencing Open Question 13 for post-ship evaluation.
  *Depends on: T-2703, T-2744, T-2745, T-2755.*

### Leave API dispatch

- [ ] **T-2760** Implement leave API dispatch. For a Mozart speaker: call `speaker.client.leave()` which maps to `beolinkLeave()` on `MozartClient+SpeakerClient` (add the mapping in the conformance extension from T-2703: `leave()` → `beolinkLeave()`). For a BNR speaker: `leave()` maps to `DELETE /BeoZone/Zone/ActiveSources/primaryExperience` (implement in `BNRClient`).

  On success: call `GroupDiscovery.shared.removeMember(speaker)`. If the group had 2 members, the remaining speaker becomes a group-of-1.
  On failure: toast: "Couldn't leave the group. Check the speaker is reachable." (en) / "Kunne ikke forlade gruppen. Tjek, at højttaleren er tilgængelig." (da).
  *Depends on: T-2703, T-2711, T-2744, T-2745, T-2756.*

### GroupDiscovery state mutations

- [ ] **T-2761** Add `mergeIntoGroup(source: Speaker, target: Speaker)` and `removeMember(_ speaker: Speaker)` methods to `GroupDiscovery`. `mergeIntoGroup` places source and target into the same `Group`, recomputing `Group.id` from the new member set and designating `target` as `hostSpeaker`. `removeMember` removes the speaker from its group; if the group becomes empty it is removed; if only one member remains it becomes the host. Both methods run on `@MainActor` and update `self.groups` atomically, triggering UI updates via `@Observable`.
  *Depends on: T-2744, T-2745.*

### Verification

- [ ] **T-2762** Unit tests for join/leave voice parsing in `iOS/VoxioTests/JoinLeaveParserTests.swift`. Tests cover: (a) each of the 8 English join phrases correctly produces `joinSpeaker(source:target:)` with correct speaker resolution; (b) each of the 4 Danish join phrases correctly produces `joinSpeaker`; (c) each of the 5 English leave phrases correctly produces `leaveSpeaker(speaker:)`; (d) each of the 3 Danish leave phrases produces `leaveSpeaker`; (e) an utterance with an unknown speaker name produces a `.speakerNotFound` error, not a crash; (f) join on already-grouped speakers produces an early-exit (no API call in the mock).
  *Depends on: T-2750, T-2751, T-2752, T-2755, T-2756.*

- [ ] **T-2763** Unit tests for join/leave API dispatch in `iOS/VoxioTests/JoinLeaveDispatchTests.swift`. Use `MockSpeakerClient`. Tests cover: (a) Mozart→Mozart join calls `expand` on the target and not on the source; (b) BNR→Any join calls `OneWayJoin` on the source; (c) Mozart→BNR join calls `beolinkJoin()` on the source; (d) leave calls `beolinkLeave()` for Mozart; (e) leave calls `DELETE /BeoZone/Zone/ActiveSources/primaryExperience` for BNR; (f) join failure does not modify `GroupDiscovery.groups`; (g) leave failure does not modify `GroupDiscovery.groups`; (h) successful join updates `GroupDiscovery.groups` to reflect the merged group.
  *Depends on: T-2757, T-2758, T-2759, T-2760, T-2761.*

- [ ] **T-2764** Manual integration test on physical speakers: two Mozart speakers (or one Mozart + one BNR) on the same local network. Verify: (a) "Voxio, [Mozart A] join [Mozart B]" causes A to follow B's source within 5 seconds (countdown + API round-trip); (b) "Voxio, [Speaker A] leave the group" causes A to return to standalone within 3 seconds; (c) re-joining after leaving works correctly; (d) all 8 English join phrase variants produce a successful join; (e) "spil med" Danish variant works in da-DK locale; (f) join on already-grouped speakers shows the "already playing with" toast. Document device models, firmware versions, and any deviations.
  *Depends on: T-2757, T-2758, T-2759, T-2760, T-2761, T-2762, T-2763.*

---

## Recommended Implementation Order

1. **T-2728 (App Groups entitlement) first** — this is the P0 blocker for all widget state sharing and must be resolved before E-30 or E-31 widget UI work begins. It can run in parallel with all code tasks.

2. **E-27 protocols and normalisation in parallel** — `SpeakerClient`, `SpeakerEventSource`, `SpeakerEvent` (T-2701, T-2702) have no dependencies and are the foundation for both E-28 and E-29.
   - Sub-order: T-2701, T-2702 in parallel → T-2703, T-2704 in parallel → T-2705 → T-2706, T-2707 in parallel → T-2708.

3. **E-28 BNRClient build in parallel with E-27 speaker refactor** — T-2711 through T-2718 depend only on T-2701/T-2702 and can begin immediately. T-2719 (initialization wiring) waits for both T-2705 (Speaker refactor) and T-2715–T-2716 (BNRClient REST methods).
   - Sub-order: T-2711 → T-2712, T-2713, T-2714, T-2715, T-2716 in parallel → T-2717 → T-2718 → T-2719.

4. **E-29 App Intents in parallel with E-27 refactor** — T-2723 depends on T-2701 only and can begin once `SpeakerClient` exists. T-2724 and T-2725 follow T-2723. `JoinSpeakerIntent` and `LeaveSpeakerIntent` in T-2723 depend also on T-2744 (Group model) — complete T-2744 before declaring those two intent types.
   - Sub-order: T-2723 → T-2724, T-2725 in parallel → T-2726 → T-2727.

5. **E-27 Group model and GroupDiscovery** — T-2744 depends on T-2701 and T-2705; T-2745 depends on T-2744 and T-2707/T-2708; T-2746 depends on T-2701/T-2703; T-2747 (HomeView refactor) depends on T-2744/T-2745. T-2748 (tests) after T-2745/T-2746.
   - Sub-order: T-2744 → T-2745, T-2746 in parallel → T-2747 → T-2748.

6. **E-27 verification** — T-2709 (mock tests) after T-2705; T-2710 (regression) after T-2708; T-2748 (Group tests) after T-2745, T-2746.

7. **E-28 verification** — T-2720, T-2721 (unit tests) in parallel after T-2711–T-2718; T-2722 (manual BNR integration) after T-2719.

8. **E-32 Speaker Join / Leave** — depends on T-2744/T-2745/T-2747 (Group model + GroupDiscovery + HomeView), T-2723 (join/leave intents declared), E-28 (BNRClient). Voice parsing tasks (T-2749–T-2752) can begin as soon as T-2747 lands. Dispatch tasks (T-2757–T-2760) can begin after both Mozart and BNR conformances for `join`/`leave` exist.
   - Sub-order: T-2749 → T-2750, T-2751 in parallel → T-2752 → T-2753, T-2754 in parallel. Dispatch: T-2755, T-2756 (guards) in parallel → T-2757, T-2758, T-2759, T-2760 in parallel → T-2761 → T-2762, T-2763 in parallel → T-2764.

9. **E-30 design tokens and shared container (T-2730, T-2731)** can begin after T-2728. The widget extension target setup (T-2729) also starts after T-2728.

10. **E-30 timeline provider and configuration** — T-2732, T-2733 after T-2731 (shared container is readable).

11. **E-30 views** — T-2734, T-2735 in parallel after T-2730, T-2732, T-2733. T-2736 (widget definition) after T-2734, T-2735.

12. **E-31 Control Widget** — T-2739, T-2740 after T-2729 (extension target) and T-2731 (shared container). T-2741 after T-2733 (speaker picker entity). T-2742 after T-2739, T-2740.

13. **Verification last** — T-2737 (widget snapshots) and T-2738 (manual widget test) after T-2736. T-2743 (Control Widget manual test) after T-2742. E-28 T-2722 (BNR physical device test) should be scheduled concurrently with E-30 development, not as a final gate. E-32 T-2764 (join/leave manual test) requires physical speakers and should run alongside E-28 T-2722.

A reasonable team sequence (one iOS engineer + part-time access to physical B&O speakers):

```
Week 1:   T-2728 (App Groups — start immediately, may need portal admin)
          T-2701, T-2702 (protocols + SpeakerEvent, incl. join/leave on SpeakerClient)
          T-2703, T-2704 (Mozart retroactive conformances)
          T-2711 (BNRClient skeleton)

Week 2:   T-2705 (Speaker refactor)
          T-2712–T-2716 (BNRClient REST methods, incl. join/leave implementations)
          T-2717, T-2718 (BNREvents long-poll + normalisation)
          T-2723 (App Intents declarations — base intents; join/leave stubs added after T-2744)

Week 3:   T-2706 (no-platform-type-in-features lint check)
          T-2707, T-2708 (dual discovery + factory)
          T-2719 (BNR init wiring)
          T-2744 (Group model)
          T-2745, T-2746 (GroupDiscovery + SpeakerClient.getPeers)
          T-2724, T-2725, T-2726 (Shortcuts provider + SpeakerStore + error strings)
          T-2729 (widget extension target, after App Groups confirmed)
          T-2730 (design tokens)

Week 4:   T-2747 (HomeView refactor → Group binding)
          T-2723 updated with JoinSpeakerIntent, LeaveSpeakerIntent (now T-2744 exists)
          T-2731 (shared container write side)
          T-2732, T-2733 (timeline provider + widget configuration)
          T-2709, T-2710 (E-27 protocol tests + regression)
          T-2748 (Group unit tests)
          T-2720, T-2721 (E-28 unit tests)
          T-2727 (App Intents Siri verification)

Week 5:   T-2749–T-2752 (E-32 NLP parser extension)
          T-2753, T-2754 (join countdown + leave immediate wiring)
          T-2755, T-2756 (join/leave guards)
          T-2757–T-2760 (join/leave API dispatch)
          T-2761 (GroupDiscovery state mutations)
          T-2734, T-2735 (small and medium widget views)
          T-2736 (widget definition)
          T-2739, T-2740, T-2741, T-2742 (Control Widget)
          T-2722 (BNR physical device manual test)

Week 6:   T-2762, T-2763 (E-32 unit tests)
          T-2737 (widget snapshot tests)
          T-2738 (manual widget integration test)
          T-2743 (Control Widget manual test)
          T-2764 (join/leave physical speaker manual test)
          Final regression pass on full E-27 + E-28 + E-29 + E-30 + E-31 + E-32 surface
```

---

## Task Summary

| Epic | Tasks | Notes |
|---|---|---|
| E-27 Shared Speaker Abstraction + Group Model | 15 | T-2701–T-2710 (original 10) + T-2744–T-2748 (Group model, GroupDiscovery, HomeView refactor). `join(peer:)` and `leave()` added to T-2701. |
| E-28 BNRClient + BNREvents | 12 | T-2711–T-2722. Press+release encapsulated in BNRClient. BNR 501 is a soft warning. |
| E-29 App Intents Declarations | 5 | T-2723–T-2727. Now includes JoinSpeakerIntent and LeaveSpeakerIntent. English + Danish Siri phrases. |
| E-30 Home-Screen Widget | 12 | T-2728–T-2738. T-2728 (App Groups entitlement) is the P0 blocker for the epic. systemSmall + systemMedium. |
| E-31 Control Widget | 5 | T-2739–T-2743. Play/pause + mute. Per-speaker configuration. |
| E-32 Speaker Join / Leave | 16 | T-2749–T-2764. NLP parser extension (join + leave variants, English + Danish), confirmation wiring, API dispatch (Mozart→Mozart, BNR→Any, Mozart→BNR), GroupDiscovery mutations, unit tests, manual integration test. |
| **Total (v1.2 only)** | **64** | Cumulative project total: 255 (v1.0 + v1.1) + 64 = **319**. |

---

## Amendment History

| Date | Source | Change |
|---|---|---|
| 2026-05-01 | Initial draft | First version of v1.2 epics and tasks (E-27–E-31, T-2701–T-2743). |
| 2026-05-01 | v1.2.1 amendment | Added E-32 (Speaker Join / Leave, T-2749–T-2764). Extended E-27 with Group model and GroupDiscovery tasks (T-2744–T-2748). Updated T-2701 to add `join(peer:)`, `leave()`, and `getPeers()` to `SpeakerClient`. Extended T-2723 (E-29) to include `JoinSpeakerIntent` and `LeaveSpeakerIntent`. Updated Epic Index, Recommended Implementation Order, weekly schedule, and Task Summary. |
