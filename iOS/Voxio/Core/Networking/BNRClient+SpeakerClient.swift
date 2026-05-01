import Foundation

extension BNRClient: SpeakerClient {
    func getPlaybackState() async throws -> SpeakerPlaybackState {
        let s = try await getBNRPlaybackState()
        switch s {
        case .playing:   return .playing
        case .paused:    return .paused
        case .stopped:   return .stopped
        case .buffering: return .buffering
        }
    }

    func join(peer: SpeakerIdentifier) async throws {
        try await join()
    }
}
