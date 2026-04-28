# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Voice-controlled Bang & Olufsen speaker interface. Three platforms share the same concept: discover B&O Mozart speakers on the local network, show live playback state, and accept voice commands via microphone.

| Platform | Folder | Language |
|----------|--------|----------|
| Web      | `web/` | Node.js + vanilla ES modules |
| Windows  | `win/` | C# / WPF (.NET 8) |
| iOS      | `iOS/` | Swift / SwiftUI |

---

## Web (`web/`)

### Running
```bash
node server.js   # HTTPS on port 3000 (required for mic access)
```
No build step. Plain ES modules served directly. TLS cert lives in `certs/` (gitignored). Regenerate with:
```bash
openssl req -x509 -newkey rsa:2048 -keyout certs/key.pem -out certs/cert.pem -days 825 -nodes -config certs/san.cnf
```

### Architecture
- **`server.js`** — HTTPS server + REST proxy (`/proxy/<host>/...` → `http://<host>/api/v1/...`) + WebSocket bridge (`/ws-proxy/<host>/` → `ws://<host>:9339/`). Both proxies are needed because speakers lack CORS headers and don't support WSS.
- **`api/mozart-client.js`** — REST client (all calls go through the proxy).
- **`api/mozart-events.js`** — WebSocket client (`wss://server/ws-proxy/<host>/`), exponential-backoff reconnect, exports `BeoEventType` constants.
- **`environment/speaker.js`** — `Speaker` model. `initialize()` fetches REST state then subscribes to WS events. Properties (`state`, `volume`, `metadata`, `battery`, `source`) update in-place.
- **`UI/pages/speak.js`** — main page: mic setup, orb animation, speech recognition, wires discovery → speaker cards.
- **`UI/components/speakercard.js`** — card render + live updates.
- **`logger.js`** — three levels: `VERBOSE / INFO / ERROR`. Change `CURRENT_LEVEL` to adjust. WS events are VERBOSE; REST calls are INFO.

### Key constraints
- HTTPS is required for `navigator.mediaDevices` (undefined on HTTP from a LAN IP).
- Port **9339** is the Mozart WebSocket event stream; REST is on port **80**.
- `"started"` state is treated as playing.
- Battery returns zeros on mains-powered speakers — ignored when `{ batteryLevel: 0, isCharging: false }`.

---

## Windows (`win/`)

### Building & running
```bash
cd win
dotnet build
dotnet run --configuration Debug
```
Or open `win/SwftExperiments.Win.csproj` and press F5 (VS Code launch config is at `.vscode/launch.json`).

### Architecture
- **`Discovery/MdnsDiscovery.cs`** — `Zeroconf` NuGet (v3.6.11) browses `_bangolufsen._tcp.local.` with a 5-second scan, repeats every 15 s.
- **`Api/MozartClient.cs`** — direct `HttpClient` to `http://<host>/api/v1/...` (no proxy needed on desktop).
- **`Api/MozartEvents.cs`** — `ClientWebSocket` to `ws://<host>:9339/`, exponential-backoff reconnect.
- **`Models/Speaker.cs`** — `INotifyPropertyChanged`, parallel REST init, WS event handler.
- **`MainWindow.xaml`** — orb with breathing `Storyboard`, speaker `DataTemplate`, dark B&O theme.
- **`MainWindow.xaml.cs`** — wires discovery → `ObservableCollection`, NAudio mic level → orb scale/glow, `SpeechRecognitionEngine` → transcript.
- **`Converters/StringToVisibilityConverter.cs`** — used by card bindings.

### NuGet packages
- `Zeroconf` 3.6.11 — mDNS discovery (replaced Makaretu which had Windows multicast issues).
- `NAudio` 2.2.1 — microphone level for orb animation.
- `System.Speech` 8.0.0 — speech recognition / transcript.

---

## iOS (`iOS/`)

Xcode project: `iOS/VoiceItAll.xcodeproj`  
Source folder: `iOS/VoiceItAll/`  
Target/bundle: `VoiceItAll` / `T-Creative.VoiceItAll`

The project uses **`PBXFileSystemSynchronizedRootGroup`** (Xcode 16+) — any `.swift` file dropped into `iOS/VoiceItAll/` is automatically compiled; no pbxproj editing needed.

### Folder structure

```
iOS/VoiceItAll/
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
└── VoiceItAllApp.swift                  — @main entry point
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
- Key REST endpoints: `/beolink/self`, `/playback/state`, `/sound/volume`, `/battery`, `/playback/sources/active`, `/content/favorites`
- Favorites: `GET /content/favorites` returns `[Favorite]`; `POST /content/favorites/{id}` activates one
- WS event types: `WebSocketEventPlaybackState`, `WebSocketEventPlaybackMetadata`, `WebSocketEventVolume`, `WebSocketEventBattery`, `WebSocketEventPlaybackSource`
- Metadata WS shape differs from REST: uses `artistName` / `albumName` instead of `artist` / `album`
- `"started"` playback state is equivalent to `"playing"`
