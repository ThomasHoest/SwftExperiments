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

## Backend (`backend/`)

Next.js 15 app deployed to Azure Static Web Apps. Database: Neon (PostgreSQL serverless via `@neondatabase/serverless`).

### Folder structure

```
backend/
├── app/api/
│   ├── health/                  — GET /api/health
│   ├── telemetry/
│   │   ├── batch/               — POST /api/telemetry/batch  (iOS event upload)
│   │   └── [deviceId]/          — DELETE /api/telemetry/:deviceId
│   ├── incidents/
│   │   └── report/              — POST /api/incidents/report  (iOS crash ingest)
│   ├── agent/
│   │   └── incidents/           — GET /api/agent/incidents (list, cursor-paginated)
│   │       └── [fingerprint]/   — GET + PATCH /api/agent/incidents/:fingerprint
│   └── admin/                   — admin-only routes (SWA role: "admin")
├── src/lib/
│   ├── db.ts                    — query<T>(text, params) over Neon serverless
│   ├── logger.ts                — logInfo / logWarn / logError (JSON lines)
│   ├── auth.ts                  — requireApiKey(request) — reads x-api-key vs TELEMETRY_API_KEY
│   ├── telemetry-key.ts         — requireTelemetryKey(request) — reads x-telemetry-key vs TELEMETRY_API_KEY
│   └── agent-auth.ts            — requireAgentKey(request) — reads x-agent-key vs AGENT_API_KEY
├── migrations/                  — node-pg-migrate TypeScript migrations (run via pnpm migrate:up)
│   ├── 1746350000000_create_devices.ts
│   ├── 1746350001000_create_events.ts
│   ├── 1746350002000_create_labels.ts
│   └── 1746350003000_incident_tables.ts   — incidents + incident_occurrences (E-51)
└── agent/scripts/
    └── open-incident-pr.ts      — standalone script: fetches open incidents, opens GitHub draft PR
```

### Auth conventions
Three separate auth helpers — do not confuse them:
- `requireApiKey` — `x-api-key` header — used by admin and telemetry-delete routes
- `requireTelemetryKey` — `x-telemetry-key` header — used by `POST /api/incidents/report` and telemetry batch
- `requireAgentKey` — `x-agent-key` header — used by all `/api/agent/*` routes

### Key tables
- `devices` / `events` / `labels` — telemetry pipeline (E-43/E-45)
- `incidents` — one row per unique error fingerprint; tracks status, pr_url, pr_number
- `incident_occurrences` — one row per iOS report; capped at 50 rows per fingerprint (pruned on ingest)

### Accumulated telemetry intents
Command intents flow: iOS `TelemetryBuffer` → `POST /api/telemetry/batch` (header: `x-telemetry-key`) → `events` table. Each row stores `intent`, `transcription_anonymised`, `parser_path`, `outcome`, `locale`, `app_version`.

To query accumulated intents directly:
```sql
SELECT intent, outcome, parser_path, COUNT(*) as n
  FROM events
 GROUP BY intent, outcome, parser_path
 ORDER BY n DESC;
```

### E-49 — corpus export (not yet implemented)
E-49 (`Specification/Voxio 1.3/epics-and-tasks-agent-api.md`) adds agent routes for labelling events and exporting a training corpus (CSV/JSONL). It was blocked by E-48 (now resolved via E-51). Auth: `requireAgentKey`. Next tasks: T-4901–T-4910.

### CI/CD
`.github/workflows/backend-ci-cd.yml` — lint → unit → build → deploy (Azure SWA) → migrate → e2e.
- Migrations run on `push` to `main`/`develop` only (not `workflow_dispatch`, not PRs).
- `DATABASE_URL` secret → production Neon; `STAGING_DATABASE_URL` secret → staging Neon.
- `pnpm migrate:up` to run locally (requires `DATABASE_URL` env var).

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
