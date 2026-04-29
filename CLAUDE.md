# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Voice-controlled Bang & Olufsen speaker interface for iOS. Discovers B&O Mozart speakers on the local network, shows live playback state, and accepts voice commands via microphone.

---

## iOS (`iOS/`)

Xcode project: `iOS/Voxio.xcodeproj`  
Source folder: `iOS/Voxio/`  
Target/bundle: `Voxio` / `T-Creative.Voxio`

The project uses **`PBXFileSystemSynchronizedRootGroup`** (Xcode 16+) — any `.swift` file dropped into `iOS/Voxio/` is automatically compiled; no pbxproj editing needed.

### Folder structure

```
iOS/Voxio/
├── Core/
│   ├── Discovery/MdnsDiscovery.swift   — NetServiceBrowser → Speaker init
│   ├── Models/                          — Codable value types (Playback, Volume, Source, BeoEvent, Favorite…)
│   ├── Networking/
│   │   ├── MozartClient.swift           — URLSession HTTP client; maps URLError → MozartError
│   │   ├── MozartError.swift            — timeout / unreachable / httpError / invalidResponse
│   │   └── MozartEvents.swift           — URLSessionWebSocketTask, exponential-backoff reconnect
│   ├── Voice/AVService.swift + VoiceToText.swift — mic, SFSpeechRecognizer, RMS callback
│   └── Logger.swift                     — VERBOSE/INFO/ERROR, change currentLevel to filter
├── DesignSystem/
│   ├── BeoColor.swift                   — named Color() resolved from Assets.xcassets (light/dark adaptive)
│   └── DesignTokens.swift               — Spacing, Radius, BeoAnimation, BeoType enums
├── Features/Home/
│   ├── Speaker.swift                    — @Observable @MainActor view model; initializes from REST+WS
│   ├── ContentView.swift                — single screen: orb, transcript, speaker list
│   └── SpeakerCardView.swift            — card UI using design tokens
└── VoxioApp.swift                  — @main entry point
```

`PBXFileSystemSynchronizedRootGroup` (Xcode 16+) — every `.swift` file in the tree is auto-compiled; no pbxproj edits needed.

### Architecture
- **`MdnsDiscovery`** — `NetServiceBrowser` browsing `_bangolufsen._tcp.`, resolves to IPv4, initializes `Speaker` and calls `speaker.initialize()`. Removes the speaker if init throws.
- **`MozartClient`** — all `URLError.timedOut` → `MozartError.timeout`; connection errors → `MozartError.unreachable`; non-2xx → `MozartError.httpError(Int)`. 5-second timeout on every request.
- **`Speaker`** — `@Observable @MainActor`, parallel REST init (`getPlaybackState`, `getVolume`, `getBattery`, `getActiveSource`), then subscribes to WS events via `BeoEvent` enum.
- **`BeoColor`** — resolves named colors from `Assets.xcassets`; all colors have light + dark variants. `Color(hex:)` helper available for gradients.
- **`DesignTokens`** — `Spacing`, `Radius`, `BeoAnimation`, `BeoType` match design-spec v1.0 exactly.

### Info.plist keys required
`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `NSLocalNetworkUsageDescription`, `NSBonjourServices` (`_bangolufsen._tcp`), `NSAppTransportSecurity → NSAllowsLocalNetworking` (permits plain HTTP to LAN addresses).

---

## B&O Mozart Open API notes

- REST base: `http://<speaker-ip>/api/v1/`
- WebSocket events: `ws://<speaker-ip>:9339/`
- mDNS service type: `_bangolufsen._tcp`
- Key REST endpoints: `/beolink/self`, `/playback/state`, `/sound/volume`, `/battery`, `/playback/sources/active`, `/scenes`
- Favorites/Scenes: `GET /scenes` returns `[Favorite]`; `POST /playback/preset/{id}/trigger` activates one
- WS event types: `WebSocketEventPlaybackState`, `WebSocketEventPlaybackMetadata`, `WebSocketEventVolume`, `WebSocketEventBattery`, `WebSocketEventPlaybackSource`
- Metadata WS shape differs from REST: uses `artistName` / `albumName` instead of `artist` / `album`
- `"started"` playback state is equivalent to `"playing"`
