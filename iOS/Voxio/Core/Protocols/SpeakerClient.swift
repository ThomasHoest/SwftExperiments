import Foundation

enum SpeakerPlaybackState: String, Equatable {
    case playing, paused, stopped, buffering
}

protocol SpeakerClient: AnyObject {
    func play() async throws
    func pause() async throws
    func stop() async throws
    func setVolume(_ level: Int) async throws
    func mute(_ muted: Bool) async throws
    func getVolume() async throws -> Int
    func getPlaybackState() async throws -> SpeakerPlaybackState
    func getSources() async throws -> [Favorite]
    func activateSource(_ id: String) async throws
    func getBattery() async throws -> Battery?
    func getName() async throws -> String
    func getJid() async throws -> String?
    func getPeers() async throws -> [BeolinkPeer]
    func getActiveSource() async throws -> SpeakerSource?
    func join(peer: SpeakerIdentifier) async throws
    func leave() async throws
}

extension SpeakerClient {
    func getJid() async throws -> String? { nil }
    func getPeers() async throws -> [BeolinkPeer] { [] }
    /// Optional: returns the current active source as a unified value type.
    /// Used by `Speaker.initialize()` to populate `speaker.source`/`sourceID`
    /// before any push event arrives. Default returns nil — implementors that
    /// have a REST surface for this should override.
    func getActiveSource() async throws -> SpeakerSource? { nil }
}
