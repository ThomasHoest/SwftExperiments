import Foundation

// ── WS event payloads (field names differ from REST counterparts) ──────────────

struct PlaybackStateEvent: Decodable {
    let value: PlaybackValue
}

struct PlaybackMetadataEvent: Decodable {
    let title: String?
    let artistName: String?   // WS uses artistName; REST uses artist
    let albumName: String?    // WS uses albumName;  REST uses album
    let genre: String?
}

struct PlaybackProgressEvent: Decodable {
    let position: Int?
    let totalDuration: Int?
}

// ── Discriminated union of all event types ─────────────────────────────────────

enum BeoEvent {
    case playbackState(PlaybackStateEvent)
    case playbackMetadata(PlaybackMetadataEvent)
    case volume(VolumeResponse)
    case battery(Battery)
    case playbackSource(Source)
    case power(PowerState)
    case progress(PlaybackProgressEvent)
    /// Beolink (multiroom) topology change hint. Mozart fires
    /// WebSocketEventBeolinkExperiencesResult / WebSocketEventBeolinkPeersResult
    /// when listeners or peer relationships change. Payload not parsed — receivers
    /// re-query GET /beolink/listeners to learn the new state.
    case beolinkChanged
    case unknown(String)
}
