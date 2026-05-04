import Foundation

@MainActor
final class MockSpeakerClient: SpeakerClient {
    var playCallCount = 0
    var pauseCallCount = 0
    var stopCallCount = 0
    var setVolumeLastCall: Int?
    var muteLastCall: Bool?
    var nameToReturn = "Mock Speaker"
    var jidToReturn: String? = nil
    var volumeToReturn = 50
    var playbackStateToReturn: SpeakerPlaybackState = .stopped
    var shouldThrow: SpeakerError? = nil
    var peersToReturn: [BeolinkPeer] = []
    var joinCallCount = 0
    var leaveCallCount = 0

    private func maybeThrow() throws {
        if let e = shouldThrow { throw e }
    }

    func play() async throws          { try maybeThrow(); playCallCount += 1 }
    func pause() async throws         { try maybeThrow(); pauseCallCount += 1 }
    func stop() async throws          { try maybeThrow(); stopCallCount += 1 }
    func setVolume(_ level: Int) async throws { try maybeThrow(); setVolumeLastCall = level }
    func mute(_ muted: Bool) async throws     { try maybeThrow(); muteLastCall = muted }
    func getVolume() async throws -> Int      { try maybeThrow(); return volumeToReturn }
    func getPlaybackState() async throws -> SpeakerPlaybackState { try maybeThrow(); return playbackStateToReturn }
    func getSources() async throws -> [Favorite] { try maybeThrow(); return [] }
    func activateSource(_ id: String) async throws { try maybeThrow() }
    func getBattery() async throws -> Battery? { nil }
    func getName() async throws -> String      { try maybeThrow(); return nameToReturn }
    func getJid() async throws -> String?      { jidToReturn }
    func getPeers() async throws -> [BeolinkPeer] { peersToReturn }
    func join(peer: SpeakerIdentifier) async throws { try maybeThrow(); joinCallCount += 1 }
    func leave() async throws          { try maybeThrow(); leaveCallCount += 1 }
}
