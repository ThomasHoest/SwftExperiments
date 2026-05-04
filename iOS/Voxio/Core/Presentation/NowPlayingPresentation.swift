import Foundation

/// Source category derived from the active source ID prefix (with `typeHint`
/// as a fallback). Covers every source family the supported B&O hardware
/// exposes today; new sources are added here without touching client code.
enum SourceCategory: String, Equatable {
    // Radio — single stream, station name + free-form live description.
    case beoRadio
    case netRadio

    // Streaming services — full track / artist / album metadata.
    case spotify
    case tidal
    case deezer
    case appleMusic

    // Cast / push protocols — metadata when the sender provides it.
    case airplay
    case googleCast
    case dlna
    case qplay

    // Local media.
    case usb
    case storedMusic

    // Passthrough — no track-level metadata.
    case bluetooth
    case lineIn
    case toslink
    case hdmi
    case tv

    // Special.
    case alarm
    case encore

    case unknown
}

/// The resolved, card-ready presentation for a speaker's current playback.
/// Built by `NowPlayingPresenter.make` — never mutated directly.
struct NowPlayingPresentation: Equatable {
    /// Primary headline: station for radio, track title for music, nil when
    /// nothing meaningful can be shown.
    var primaryLine: String?

    /// Secondary line: live program text for radio, artist name for music,
    /// nil for passthrough sources or when the field isn't available.
    var secondaryLine: String?

    /// Top-right badge: human-readable source name. Nil only when source is
    /// completely unknown.
    var sourceBadge: String?

    /// Whether the speaker is actively playing or buffering. Gates the panel.
    var isPlaying: Bool

    /// Resolved category — drives icon / tint selection in the view.
    var category: SourceCategory
}
