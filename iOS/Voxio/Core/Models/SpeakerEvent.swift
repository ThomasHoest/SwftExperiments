import Foundation

enum SpeakerEvent {
    case playbackState(SpeakerPlaybackState)
    case metadata(title: String?, artist: String?, album: String?)
    case volume(level: Int, muted: Bool)
    case battery(Battery)
    case source(name: String?, id: String?)
}
