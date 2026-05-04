# ADR-002 — Now Playing Presentation Layer

**Status:** PROCEED (open questions resolved 2026-05-04)
**Date:** 2026-05-04
**Author:** ARCHITECT agent (voxio-1.2 team)
**Applies to:** iOS platform only (`iOS/Voxio/`)
**References:** ADR-001-v1.2-speaker-abstraction-and-widget.md, CLAUDE.md, `iOS/Voxio/Features/Home/SpeakerCard.swift`, `iOS/Voxio/Features/Home/Speaker.swift`, `iOS/Voxio/Core/Models/Playback.swift`, `iOS/Voxio/Core/Models/Source.swift`, `iOS/Voxio/Core/Models/SpeakerEvent.swift`, `iOS/Voxio/Core/Networking/BNRModels.swift`, `iOS/Voxio/Core/Networking/BNREvents+SpeakerEventSource.swift`, `iOS/Voxio/Core/Networking/MozartEvents+SpeakerEventSource.swift`

---

## Context

`Speaker.trackDisplay` is a computed `String` that joins `[artist, title]` with `" – "`. `SpeakerCard` renders this single string as one line of `.nowPlaying` typography, with `speaker.source` shown below it as a `.caption`. This design breaks down in three real-world cases that already exist in production logs:

**Net radio (BNR):** `NOW_PLAYING_NET_RADIO` delivers `name` = `"DR P6 BEAT"` (station) and `liveDescription` = `"Forhåbningsholms Allé - / Superjeg"` (live program text). `BNREvents+SpeakerEventSource.swift` maps `liveDescription` into the `artist` field of `SpeakerEvent.metadata`. `trackDisplay` then emits `"Forhåbningsholms Allé - / Superjeg – DR P6 BEAT"` — the free-form program description is presented as an artist, which is semantically incorrect and visually confusing.

**Bluetooth / line-in:** These sources produce no metadata at all. `metadata` is `nil`; `trackDisplay` falls back to `source ?? ""`. The source name therefore appears in the `.nowPlaying` font slot — the largest text on the card — when it should be secondary context, not a headline.

**Stored music / Spotify:** The three-field join works correctly here but the card cannot display artist and title as separate typographic elements because they arrive as a pre-joined string. The requested design (artist on one line, title on another) is impossible without unpacking the string.

**Platform shape divergence:** Mozart WS delivers `artistName`/`albumName`; REST delivers `artist`/`album`; BNR delivers `liveDescription` as a pseudo-artist. Both bridges flatten these into the identical `SpeakerEvent.metadata(title:artist:album:)` tuple without encoding what kind of content `artist` actually holds. The card has no way to distinguish "this is a real performer name" from "this is a live radio program description".

The current card also stores and re-reads `speaker.source` (a raw `String?`) from the same panel it shows `trackDisplay`, with no awareness of whether the source is an idle state, a named Bluetooth connection, or a structured B&O Radio entry.

---

## Decision

Introduce a new value type `NowPlayingPresentation` that encodes the fully resolved, source-aware presentation for a single speaker at a single moment. A pure free function `NowPlayingPresenter.make(state:metadata:sourceID:sourceName:)` produces it. `Speaker` exposes it as a computed property. `SpeakerCard` consumes only this value type — it reads no other presentation fields from `Speaker`.

### New type: `SpeakerSource` (replaces `getActiveSourceName`)

File: `iOS/Voxio/Core/Models/SpeakerSource.swift`

A unified, platform-agnostic value type that both clients return from a new `SpeakerClient.getActiveSource() -> SpeakerSource?`. Replaces the narrower `getActiveSourceName() -> String?` introduced earlier in v1.2.

```swift
struct SpeakerSource: Equatable {
    /// Wire identifier — typically `<category>:<jid>@products.bang-olufsen.com`
    /// for both BNR and Mozart, occasionally `TV|<app>:<jid>` on TV products.
    var id: String
    /// Human-readable display name ("B&O Radio", "Spotify", "Bluetooth").
    var friendlyName: String?
    /// Optional pre-categorised hint from the wire (e.g. BNR's
    /// `sourceType.type` or Mozart's `Source.type`/category). The presenter
    /// uses this only as a hint — primary categorisation is by `id` prefix.
    var typeHint: String?
}
```

Both `MozartClient+SpeakerClient` and `BNRClient+SpeakerClient` map their wire-shape responses into this type. `SpeakerClient` knows nothing about `BNRSourceRef` or Mozart's `Source` decoder — only the unified value type. The earlier-introduced `getActiveSourceName()` is removed; callers migrate to `getActiveSource()?.friendlyName`.

### New type: `NowPlayingPresentation`

File: `iOS/Voxio/Core/Presentation/NowPlayingPresentation.swift`

```swift
/// Source category, derived from the SpeakerSource id prefix (with typeHint
/// as a fallback). Covers every source the supported B&O hardware exposes
/// today; future additions go in this enum without touching client code.
enum SourceCategory {
    // Radio — single stream, station name + free-form live description.
    case beoRadio        // "beoradio:…"
    case netRadio        // "radio:…" (TuneIn-backed)

    // Streaming services — full track/artist/album metadata.
    case spotify         // "spotify:…"
    case tidal           // "tidal:…", "tidalconnect:…"
    case deezer          // "deezer:…"
    case appleMusic      // "music:…", "applemusic:…"

    // Cast / push protocols — metadata when the sender provides it.
    case airplay         // "airplay:…"
    case googleCast      // "googlecast:…"
    case dlna            // "dlna:…"
    case qplay           // "qplay:…"

    // Local media — track metadata when reading tags.
    case usb             // "usb:…"
    case storedMusic     // catch-all for local-music IDs without a more specific match

    // Passthrough — no track-level metadata.
    case bluetooth       // "bluetooth:…"
    case lineIn          // "linein:…"
    case toslink         // "toslink:…" (optical)
    case hdmi            // "HDMI_A:…", "HDMI_B:…"
    case tv              // "tv:…", "TV|<app>:…" on TV products

    // Special.
    case alarm           // "alarm:…"
    case encore          // "encore:…" (B&O proprietary)

    case unknown         // unrecognised — render source badge only
}

/// The resolved, card-ready presentation for a speaker's current playback.
struct NowPlayingPresentation: Equatable {
    /// The primary headline: station name for radio, track title for music,
    /// nil when nothing meaningful can be shown.
    var primaryLine: String?
    /// The secondary line: live program text for radio, artist name for music,
    /// nil for Bluetooth/line-in/idle.
    var secondaryLine: String?
    /// Top-right badge: always the human-readable source name ("B&O Radio",
    /// "Spotify", "Bluetooth"). Nil only when source is completely unknown.
    var sourceBadge: String?
    /// Whether the speaker is actively playing (gates the whole now-playing panel).
    var isPlaying: Bool
    /// Resolved category — lets the card apply source-specific icon or tint
    /// without re-parsing the source ID.
    var category: SourceCategory
}
```

### New function: `NowPlayingPresenter.make`

File: `iOS/Voxio/Core/Presentation/NowPlayingPresenter.swift`

```swift
enum NowPlayingPresenter {
    static func make(
        state: SpeakerPlaybackState,
        metadata: PlaybackMetadata?,
        sourceID: String?,
        sourceName: String?
    ) -> NowPlayingPresentation
}
```

`make` is a pure function with no stored state. It:

1. Derives `SourceCategory` from `sourceID` by inspecting the prefix before the first `":"` character, falling back to a case-insensitive match against known `sourceType.type` strings (`"BEO RADIO"`, `"BLUETOOTH"`, `"SPOTIFY"`, `"LINE IN"`, `"TV"`). This requires no new HTTP endpoints — both BNR source IDs (`"beoradio:JID@…"`) and Mozart `Source.id` fields (`"spotify:…"`) already carry the category as a prefix.

2. Resolves `primaryLine` and `secondaryLine` according to source category. Three behaviour groups:

   **Radio-like** (`.beoRadio`, `.netRadio`): `primaryLine = metadata?.title` (station name); `secondaryLine = metadata?.artist` (live program description — free-form text, never labelled "Artist" in the UI).

   **Track-aware** (`.spotify`, `.tidal`, `.deezer`, `.appleMusic`, `.airplay`, `.googleCast`, `.dlna`, `.qplay`, `.usb`, `.storedMusic`, `.encore`): `primaryLine = metadata?.title`; `secondaryLine = metadata?.artist`. If `metadata` is nil the panel shows the source badge alone — track-aware sources can momentarily lack metadata between events.

   **Passthrough** (`.bluetooth`, `.lineIn`, `.toslink`, `.hdmi`, `.tv`, `.alarm`): `primaryLine = nil`; `secondaryLine = nil`. Source badge alone is sufficient — these protocols don't carry track metadata. (TV apps are an exception: when the source badge already names the app, e.g. "Netflix", that's enough.)

   **Unknown** (`.unknown`): best-effort fallback — `primaryLine = metadata?.title ?? metadata?.genre ?? metadata?.album`; `secondaryLine = metadata?.artist`.

3. Sets `sourceBadge = sourceName ?? categoryFallbackName(category)`, where `categoryFallbackName` returns a hardcoded string (`"Bluetooth"`, `"Line In"`, etc.) when the friendly name from the wire is absent.

4. Sets `isPlaying = (state == .playing || state == .buffering)`.

### `SpeakerClient` change

Replace `func getActiveSourceName() async throws -> String?` with:

```swift
func getActiveSource() async throws -> SpeakerSource?
```

Default returns `nil`. `MozartClient+SpeakerClient` and `BNRClient+SpeakerClient` map their respective wire shapes (`Source` for Mozart, `BNRSourceRef` + `ActiveSources.primary` for BNR) into `SpeakerSource`. `SpeakerClient` no longer has any platform-specific shape leaking through.

### `Speaker` updates

```swift
// Speaker.swift
var sourceID: String?           // raw wire id; new
var source: String?             // friendlyName; existing, semantics unchanged

var nowPlaying: NowPlayingPresentation {
    NowPlayingPresenter.make(
        state: playbackState,
        metadata: metadata,
        sourceID: sourceID,
        sourceName: source
    )
}

private func loadSource() async {        // replaces loadSourceName()
    guard let s = try? await client.getActiveSource() else { return }
    sourceID = s.id
    if let name = s.friendlyName, !name.isEmpty { source = name }
}
```

`handleEvent` for `.source(name:id:)` now captures both `name` (into `source`) and `id` (into `sourceID`). The `id` was previously discarded.

`trackDisplay` is kept as a deprecated passthrough (`var trackDisplay: String { nowPlaying.primaryLine ?? "" }`) until `SpeakerCard` migrates, then removed.

### `SpeakerCard` consumption

`SpeakerCard.nowPlayingPanel` and `accessibilityDescription` switch from reading `speaker.trackDisplay`, `speaker.source` to reading a single let-binding:

```swift
let p = speaker.nowPlaying
```

The card then renders `p.primaryLine`, `p.secondaryLine`, `p.sourceBadge`, and gates the panel on `p.isPlaying`. No source-parsing logic inside the view.

### `WidgetStateWriter` change

The widget extension does not run the presenter at render time. Instead, the main app's `WidgetStateWriter.write(speaker:)` builds a `NowPlayingPresentation` and writes its rendered fields into the App Group `UserDefaults` per host. New keys (added to `WidgetStateKeys`):

- `widget_speaker_<host>_primary_line`     (was `widget_speaker_<host>_track_title`)
- `widget_speaker_<host>_secondary_line`   (new)
- `widget_speaker_<host>_source_badge`     (replaces the existing `widget_speaker_<host>_source_name`)
- `widget_speaker_<host>_category`         (new — raw enum case name, e.g. `"beoRadio"`, for icon/tint selection)

`VoxioWidgetEntry` exposes `primaryLine`, `secondaryLine`, `sourceBadge`, `category`. `VoxioWidgetSmallView` and `VoxioWidgetMediumView` render verbatim — no presenter dependency in the widget target. This avoids duplicating `NowPlayingPresenter` across targets and keeps the widget bundle minimal. `widget_data_version` bumps from 2 to 3 to invalidate any stale cache from before the schema change.

---

## Options Considered

| Option | Verdict |
|---|---|
| **A (chosen): `NowPlayingPresentation` value type + pure `make` function** | No `Speaker` state changes, pure and unit-testable, card is fully dumb, zero per-platform coupling. |
| B (rejected): Expand `Speaker` with individual computed vars (`var artistLine`, `var titleLine`, `var sourceBadge`) | Scatters source-routing logic across multiple computed properties. Hard to test in isolation. Card still reads multiple properties and must coordinate them. |
| C (rejected): Subclass `PlaybackMetadata` per source type | `PlaybackMetadata` is a Decodable value type. Per-source subclassing requires class hierarchy, breaking Codable and Equatable. Incompatible with `SpeakerEvent.metadata` tuple shape. |
| D (rejected): Move routing logic into bridge files (`BNREvents+SpeakerEventSource`, `MozartEvents+SpeakerEventSource`) | Would require per-platform presentation logic in networking code — violates the separation already established in v1.2. Bridge files must remain oblivious to UI presentation. |
| E (rejected): Add `sourceCategory` enum case to `SpeakerEvent.source` | Correct direction but insufficient alone. The card still needs to combine state + metadata + source into a single rendering value at call time. |

---

## Consequences

### What changes

- **New files:** `iOS/Voxio/Core/Presentation/NowPlayingPresentation.swift`, `iOS/Voxio/Core/Presentation/NowPlayingPresenter.swift`
- **`Speaker.swift`:** adds `var sourceID: String?`; updates `handleEvent` case `.source` to capture `id`; updates `loadSourceName()` to also persist `sourceID`; adds `var nowPlaying: NowPlayingPresentation` computed property; marks `trackDisplay` deprecated
- **`SpeakerCard.swift`:** `nowPlayingPanel` and `accessibilityDescription` bind to `speaker.nowPlaying` instead of `speaker.trackDisplay` + `speaker.source`
- **`SpeakerEvent.swift`:** no changes needed — `.source(name:id:)` already carries both fields; `id` was previously discarded in `handleEvent`
- **Per-platform clients and bridges:** no changes required

### What stays

- `Speaker` remains the single `@Observable @MainActor` source of truth
- `PlaybackMetadata`, `Source`, `SpeakerEvent` are unchanged
- `MozartClient`, `BNRClient`, both bridge files are unaffected
- `WidgetStateWriter` continues to read from `Speaker`; it can adopt `speaker.nowPlaying` in a follow-up task

### Migration cost

Low. `NowPlayingPresenter.make` is a free function; it can be written and unit-tested before `SpeakerCard` migrates. The `trackDisplay` deprecation shim keeps the card compiling during the transition.

### Risks

- **`sourceID` retention on source-change events:** BNR `SOURCE` notifications fire on every source switch. If `sourceID` is updated before `metadata` is cleared, the category resolver may produce a stale category for one event cycle. Mitigation: clear `metadata` in `handleEvent` when a `.source` event arrives, before updating `sourceID`.
- **Prefix-based category detection is a heuristic:** Mozart source IDs are not guaranteed to keep the `"spotify:"` / `"beoradio:"` prefix scheme across firmware versions. `sourceName` fallback covers the case where the prefix is absent, but `category` would resolve to `.unknown`. The card must render correctly (source badge only) for `.unknown` category.
- **BNR net-radio secondary line is semantically ambiguous:** `liveDescription` is free-form operator text. For `.beoRadio`, `secondaryLine` should never be labelled "Artist" in the UI — the design spec must document this explicitly. This is a design spec concern, not a data model concern.

---

## Resolved Decisions (2026-05-04)

| # | Question | Resolution |
|---|---|---|
| OQ-1 | Should `SpeakerClient.getActiveSourceName` be widened? | **Yes — full source.** Replaced with `getActiveSource() -> SpeakerSource?` returning a unified value type with `id`, `friendlyName`, and `typeHint`. Both clients map to it. The narrower `getActiveSourceName` is removed. |
| OQ-2 | Should BNR's `sourceType.type` leak into `SpeakerClient`? | **No — kept generic.** The `SpeakerSource.typeHint: String?` field is platform-agnostic; each client populates it from whatever pre-categorised string is on its wire (BNR's `sourceType.type`, Mozart's `Source.type` if present). Presenter uses it as a hint only — id-prefix detection remains primary. No `BNR…` types appear anywhere in `SpeakerClient` or `Speaker`. |
| OQ-3 | Where does the widget run the presenter? | **Main app side.** `WidgetStateWriter` calls the presenter and writes pre-rendered `primaryLine`, `secondaryLine`, `sourceBadge`, `category` to the App Group. The widget target reads strings only — no presenter dependency in the widget bundle. `widget_data_version` bumps to 3. |

## Open Questions

None remaining.

---

## Platform Constraint Violations

None. `NowPlayingPresentation` and `NowPlayingPresenter` are pure Swift value types with no framework dependencies. They compile on any Swift 5.9+ target including the widget extension.

---

## References

- `iOS/Voxio/Features/Home/SpeakerCard.swift` — current card; `nowPlayingPanel` reads `speaker.trackDisplay` and `speaker.source`
- `iOS/Voxio/Features/Home/Speaker.swift` — `trackDisplay`, `handleEvent` `.source` case, `loadSourceName()`
- `iOS/Voxio/Core/Models/SpeakerEvent.swift` — `.source(name:id:)` already carries `id`; `id` was previously discarded
- `iOS/Voxio/Core/Networking/BNRModels.swift` — `NOW_PLAYING_NET_RADIO` maps `liveDescription` → `artist`; `BNRSourceRef.category` available on wire but not forwarded
- `iOS/Voxio/Core/Networking/BNREvents+SpeakerEventSource.swift` — `.source` translation passes `id` through
- `iOS/Voxio/Core/Networking/MozartEvents+SpeakerEventSource.swift` — `.playbackSource` passes `id` through
- `iOS/Voxio/Core/Models/Source.swift` — `Source.id` and `Source.friendlyName`
- `iOS/Voxio/Core/Models/BeoEvent.swift` — `PlaybackMetadataEvent` WS field names (`artistName`, `albumName`)
- `Specification/Voxio 1.2/ADR-001-v1.2-speaker-abstraction-and-widget.md` — format reference and v1.2 architectural baseline
