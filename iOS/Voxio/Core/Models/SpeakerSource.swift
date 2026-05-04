import Foundation

/// Unified, platform-agnostic representation of the active source on a speaker.
/// Returned by `SpeakerClient.getActiveSource()`. Both Mozart and ASE clients
/// map their respective wire shapes (Mozart `Source`, BNR `BNRSourceRef` +
/// `ActiveSources.primary`) into this type — no platform-specific types leak
/// through `SpeakerClient`.
struct SpeakerSource: Equatable {
    /// Wire identifier — typically `<category>:<jid>@products.bang-olufsen.com`
    /// for both BNR and Mozart, occasionally `TV|<app>:<jid>` on TV products.
    var id: String

    /// Human-readable display name ("B&O Radio", "Spotify", "Bluetooth").
    var friendlyName: String?

    /// Optional pre-categorised hint from the wire (BNR `sourceType.type`,
    /// Mozart `Source.type`/category if available). Used by the presenter
    /// as a fallback signal — id-prefix detection is primary.
    var typeHint: String?
}
