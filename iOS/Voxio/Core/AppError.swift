import Foundation

enum AppError: Error {
    case noSpeakerSpoken(available: [String])
    case speakerNotFound(spoken: String, available: [String])
    case favoriteNotFound(name: String, speaker: String, available: [String])
    case favoriteIndexOutOfRange(index: Int, speaker: String, available: [String])
    case speakerUnreachable(speaker: String)
    case nothingPlaying(speaker: String)
    case volumeAtLimit(speaker: String, atMax: Bool)
    case pauseNotSupported(speaker: String)
    case alreadyMuted(speaker: String)
    case voiceNotRecognised
    case apiTimeout
}
