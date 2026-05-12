import Foundation

// MARK: - SpeakerGroup
//
// E-57 changes applied in this file:
//   T-5704 — setVolumeOnAllMembers(_:) concurrent fan-out via withTaskGroup.

@Observable @MainActor
final class SpeakerGroup: Identifiable {
    /// Stable across member additions/removals — derived from the host speaker
    /// only. ForEach uses `Identifiable.id` for diffing, and if `id` changed
    /// when members did (the previous behaviour), every drag-to-join would
    /// trigger a remove+insert of the entire SpeakerCard subtree instead of
    /// an in-place update. That tore down the optimistic merge before SwiftUI
    /// could surface the new chip. The host's stable identifier (jid or host
    /// IP) is the natural anchor: a group is "Badeværelse's session"
    /// regardless of who else has joined it.
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
        self.id          = SpeakerGroup.makeId(forHost: hostSpeaker)
    }

    static func single(_ speaker: Speaker) -> SpeakerGroup {
        SpeakerGroup(members: [speaker], hostSpeaker: speaker)
    }

    /// Host-anchored, member-independent group ID. See `id` doc-comment.
    static func makeId(forHost host: Speaker) -> String {
        host.identifier.jid ?? host.identifier.host
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
