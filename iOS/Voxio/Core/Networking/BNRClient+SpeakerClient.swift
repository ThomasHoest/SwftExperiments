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

    /// Master-side join: this BNR device adds `peer` as a listener of its primary experience.
    /// Requires the listener to expose a JID (Mozart and BNR speakers both qualify).
    func join(peer: SpeakerIdentifier) async throws {
        guard let listenerJid = peer.jid else {
            Log.error("[BNR:\(host)] join: peer \(peer.host) has no JID — cannot expand")
            throw SpeakerError.invalidResponse
        }
        Log.info("[BNR:\(host)] join → expandExperience listener:\(listenerJid)")
        do {
            try await expandExperience(listenerJid: listenerJid)
            Log.info("[BNR:\(host)] join OK")
        } catch {
            Log.error("[BNR:\(host)] join failed: \(error)")
            throw error
        }
    }
}
