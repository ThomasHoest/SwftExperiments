import Foundation

@Observable @MainActor
final class SpeakerGroup: Identifiable {
    var id: String
    var members: [Speaker]
    var hostSpeaker: Speaker

    var playbackState: SpeakerPlaybackState { hostSpeaker.playbackState }
    var volume: Int? { hostSpeaker.volume }
    var metadata: PlaybackMetadata? { hostSpeaker.metadata }
    var name: String { hostSpeaker.name }

    init(members: [Speaker], hostSpeaker: Speaker) {
        precondition(!members.isEmpty)
        self.members     = members
        self.hostSpeaker = hostSpeaker
        self.id          = SpeakerGroup.makeId(for: members)
    }

    static func single(_ speaker: Speaker) -> SpeakerGroup {
        SpeakerGroup(members: [speaker], hostSpeaker: speaker)
    }

    // Stable ID: sort member keys, join, use as ID directly (no crypto dependency)
    static func makeId(for members: [Speaker]) -> String {
        members
            .map { $0.identifier.jid ?? $0.identifier.host }
            .sorted()
            .joined(separator: ",")
    }
}
