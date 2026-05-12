import Foundation

// MARK: - SpeakerGroup
//
// E-57 changes applied in this file:
//   T-5704 — setVolumeOnAllMembers(_:) concurrent fan-out via withTaskGroup.

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

// MARK: - Volume broadcast (E-57 T-5704)

extension SpeakerGroup {
    /// Broadcasts a volume level to all group members concurrently.
    /// Returns per-member results so the caller can surface partial failures.
    /// - Parameter level: Volume level 0–100.
    /// - Returns: An array of (speaker, Result) pairs — one per member, in arrival order.
    func setVolumeOnAllMembers(_ level: Int) async -> [(speaker: Speaker, result: Result<Void, Error>)] {
        await withTaskGroup(of: (Speaker, Result<Void, Error>).self) { taskGroup in
            for member in members {
                taskGroup.addTask {
                    do {
                        try await member.setVolume(level)
                        return (member, .success(()))
                    } catch {
                        return (member, .failure(error))
                    }
                }
            }
            var results: [(speaker: Speaker, result: Result<Void, Error>)] = []
            for await (spk, res) in taskGroup {
                results.append((speaker: spk, result: res))
            }
            return results
        }
    }
}
