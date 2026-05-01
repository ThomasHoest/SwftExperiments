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
    func join(peer: SpeakerIdentifier) async throws
    func leave() async throws
}

extension SpeakerClient {
    func getJid() async throws -> String? { nil }
    func getPeers() async throws -> [BeolinkPeer] { [] }
}
