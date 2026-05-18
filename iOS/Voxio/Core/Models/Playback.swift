import Foundation

enum PlaybackValue: String, Decodable {
    case playing   = "playing"
    case paused    = "paused"
    case stopped   = "stopped"
    case buffering = "buffering"
    case unknown   = "unknown"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Mozart devices emit "started" for the active playing state; collapse to .playing.
        if raw == "started" { self = .playing; return }
        self = PlaybackValue(rawValue: raw) ?? .unknown
    }
}

struct PlaybackState: Decodable {
    let value: PlaybackValue
}

// /playback/state returns a wrapper: { "state": {"value": "..."}, "metadata": {...}, ... }
struct PlaybackResponse: Decodable {
    let state: PlaybackState
}

struct PlaybackMetadata: Decodable {
    let title: String?
    let artist: String?
    let album: String?
    let genre: String?
    let artworkUrl: String?
    let durationMs: Int?
}

struct PlaybackProgress: Decodable {
    let position: Int
    let totalDuration: Int?
}

struct QueueSettings: Decodable {
    let shuffle: Bool?
    let `repeat`: String?
}
