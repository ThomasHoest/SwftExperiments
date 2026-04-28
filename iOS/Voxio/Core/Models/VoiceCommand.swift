import Foundation

/// A structured intent parsed from a raw speech transcription.
enum VoiceCommand: Equatable {
    /// Play a specific favorite by 1-based position (1–4).
    case playFavorite(index: Int)
    /// Start or resume playback of the last-played or default favorite.
    case playDefault
    /// List all available favorites for the addressed speaker.
    case listFavorites
    /// Stop playback entirely.
    case stop
    /// Pause playback (resumable).
    case pause
    /// Resume paused playback.
    case resume
    /// Set volume to an absolute level (0–100).
    case setVolume(Int)
    /// Adjust volume by a relative delta; positive = louder, negative = quieter.
    case adjustVolume(Int)
    /// Mute the speaker.
    case mute
    /// Unmute the speaker.
    case unmute
    /// Affirmative response to a pending confirmation prompt.
    case confirm
    /// Negative response or explicit cancellation of a pending prompt.
    case cancel
    /// Transcription did not match any known pattern.
    case unknown(String)
}

extension VoiceCommand: CustomStringConvertible {
    var description: String {
        switch self {
        case .playFavorite(let i): return "playFavorite(\(i))"
        case .playDefault:         return "playDefault"
        case .listFavorites:       return "listFavorites"
        case .stop:                return "stop"
        case .pause:               return "pause"
        case .resume:              return "resume"
        case .setVolume(let v):    return "setVolume(\(v))"
        case .adjustVolume(let d): return "adjustVolume(\(d > 0 ? "+\(d)" : "\(d)"))"
        case .mute:                return "mute"
        case .unmute:              return "unmute"
        case .confirm:             return "confirm"
        case .cancel:              return "cancel"
        case .unknown(let s):      return "unknown(\"\(s)\")"
        }
    }
}
