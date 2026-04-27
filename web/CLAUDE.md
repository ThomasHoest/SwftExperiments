# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Start the dev server (HTTPS on port 3000)
node server.js

# The server logs both URLs on startup:
# [Server] https://localhost:3000
# [Server] https://192.168.0.213:3000
```

No build step, no bundler, no test runner. The codebase is plain ES modules served directly by `server.js`.

The TLS cert lives in `certs/` (gitignored). If it's missing, regenerate with:
```bash
openssl req -x509 -newkey rsa:2048 -keyout certs/key.pem -out certs/cert.pem -days 825 -nodes -config certs/san.cnf
```
Then accept the self-signed cert warning in the browser on first visit.

## Architecture

The app is a voice-controlled Bang & Olufsen speaker interface. The browser talks to a local Node.js server which proxies all speaker API calls — the speakers don't send CORS headers so direct browser requests are blocked.

### Server (`server.js`)
- HTTPS static file server + two proxies
- **REST proxy**: `GET/POST/PUT /proxy/<host>/api/v1/...` → forwards to `http://<host>/api/v1/...` on port 80
- **WebSocket proxy**: `wss://server/ws-proxy/<host>/` → bridges to `ws://<host>:9339/` (plain WS — speakers don't support WSS)
- The WS proxy is needed because HTTPS pages block insecure `ws://` connections

### Speaker model (`environment/`)
- `Speaker` — represents one device. `initialize()` fetches REST state then opens a WebSocket event stream. All properties (`state`, `volume`, `metadata`, `battery`, `source`) are updated in-place as events arrive. Callers register `onStateChange(fn)` to react to updates.
- `House` — keyed collection of `Speaker` instances, indexed by IP. Prevents duplicates.
- `Discovery` — client-side LAN scanner: WebRTC ICE → local subnet → HTTP ping → `Speaker.initialize()` to confirm B&O. Currently disabled in favour of hardcoded `DEV_SPEAKERS` in `UI/pages/speak.js`.

### API layer (`api/`)
- `mozart-client.js` — REST client. All requests go through `/proxy/<host>` so CORS is handled server-side.
- `mozart-events.js` — WebSocket client. Connects to `wss://server/ws-proxy/<host>/`. Exports `BeoEventType` constants and `BeoEvents` class with exponential-backoff reconnect.

### UI (`UI/`)
- `UI/pages/speak.js` — main page script: mic + audio analysis (drives the orb), speech recognition, speaker discovery wiring
- `UI/components/speakercard.js` — creates and live-updates speaker cards via `speaker.onStateChange`

### Logging (`logger.js`)
Three levels: `VERBOSE`, `INFO`, `ERROR`. Change `CURRENT_LEVEL` in `logger.js` to adjust output. WebSocket events are logged at `VERBOSE`; REST calls at `INFO`.

### Key constraints
- **HTTPS required** for microphone access (`navigator.mediaDevices` is undefined on HTTP from a LAN IP)
- **Speakers never send CORS headers** — all REST calls must go through the server proxy
- **Port 9339** is the Mozart WebSocket event stream (separate from REST on port 80)
- `"started"` playback state is normalised to `"playing"` in `_applyPlaybackState`
- Battery returns zeros on mains-powered speakers — `_applyBattery` ignores `{ batteryLevel: 0, isCharging: false }`
