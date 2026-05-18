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

## Specification structure (`Specification/`)

Applies from v1.4 onwards. Strict no-overlap between master spec and per-feature spec.

### Document types

| File | Purpose |
|---|---|
| `VoxioSpecification-1.X.md` | Master index — version-level context + feature stubs with links |
| `spec-<topic>.md` | Full feature spec — all detail for one feature |
| `design-spec-<topic>.md` | UI/UX spec — screens, components, tokens, strings |
| `epics-and-tasks-<topic>.md` | Implementation breakdown — epics, tasks, dependency graph |
| `research-<topic>.md` | Pre-decision investigation — feeds into spec + ADR |
| `ADR-NNN-<topic>.md` | Architecture decision record — validates a spec |

### Ownership rules

**Master spec** owns: Introduction · Technical Context (cross-feature) · Goals (version-level) · Out of Scope (version-level) · one-paragraph stub per feature with links to its spec/design/epics docs · Open Questions/Resolved Decisions spanning >1 feature.

**Per-feature spec** owns (nothing duplicated in master): Overview · Technical Context · Goals · Out of Scope · User Stories + acceptance criteria · Flows/behaviour · Error States · Non-Functional Requirements · feature-specific Open Questions/Resolved Decisions.

**Edge case:** small feature with no per-feature spec → embed the full per-feature template inline in master under that feature's heading.

### Document flow
`research` → `spec` → `ADR` → `design-spec` → `epics-and-tasks` → implementation

### Numbering conventions

**Epics** — `E-XX` (two-digit, version-agnostic, monotonically increasing across all releases).
**Tasks** — `T-XXYY` where `XX` is the parent epic number and `YY` is the task sequence within that epic (01-based). Example: T-5901 = first task of E-59.
**User stories** — `US-XX` (two-digit, assigned per feature block, continuous across versions).

Current counter state (do not reuse these numbers):

| Counter | Last used | Notes |
|---|---|---|
| Epic | E-61 | E-52–E-55 = F3 Home Screen Redesign; E-56–E-58 = F1 Touch Playback Controls; E-59–E-61 = F2 Multiroom Grouping |
| User story | US-84 | US-60–US-66 = F3; US-70–US-73 = F1; US-80–US-84 = F2 |

### v1.4 document inventory (`Specification/Voxio 1.4/`)

| File | Type | Feature |
|---|---|---|
| `VoxioSpecification-1.4.md` | Master spec | All |
| `spec-home-screen-redesign.md` | Feature spec | F3 |
| `spec-touch-playback-controls.md` | Feature spec | F1 |
| `spec-multiroom-grouping.md` | Feature spec | F2 |
| `design-spec-home-screen-redesign.md` | Design spec | F3 |
| `design-spec-touch-playback-controls.md` | Design spec | F1 |
| `design-spec-multiroom-grouping.md` | Design spec | F2 |
| `epics-and-tasks-home-screen-redesign.md` | Epics/tasks | F3 (E-52–E-55) |
| `epics-and-tasks-touch-playback-controls.md` | Epics/tasks | F1 (E-56–E-58) |
| `epics-and-tasks-multiroom-grouping.md` | Epics/tasks | F2 (E-59–E-61) |
| `ADR-002-voxio-1.4-ios.md` | ADR | All iOS |
| `mockup-home-screen-redesign.svg` | Mockup | F3 |
| `mockup-multiroom-grouping.svg` | Mockup | F2 |

### Implementation notes

- `HapticEngine.swift` requires three new methods: `dragLifted()`, `dragEnteredDropZone()`, `dragCancelled()` — tracked as T-5901 (E-59). These are referenced throughout `design-spec-multiroom-grouping.md` and must exist before any F2 drag code compiles.

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
