import Foundation

extension MozartClient: SpeakerClient {

    func play() async throws {
        do { try await mozartPlay() }
        catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func pause() async throws {
        do { try await mozartPause() }
        catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func stop() async throws {
        do { try await mozartStop() }
        catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func setVolume(_ level: Int) async throws {
        do { try await mozartSetVolume(level) }
        catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func mute(_ muted: Bool) async throws {
        do { try await setMute(muted) }
        catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func getVolume() async throws -> Int {
        do {
            let resp = try await (self as MozartClient).getMozartVolume()
            return resp.volume.level
        } catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func getPlaybackState() async throws -> SpeakerPlaybackState {
        do {
            let ps = try await getMozartPlaybackState()
            switch ps.value {
            case .playing, .started: return .playing
            case .paused:            return .paused
            case .stopped, .unknown: return .stopped
            case .buffering:         return .buffering
            }
        } catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func getSources() async throws -> [Favorite] {
        do { return try await getFavorites() }
        catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func activateSource(_ id: String) async throws {
        do { try await setSource(id) }
        catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func getBattery() async throws -> Battery? {
        return try? await getMozartBattery()
    }

    func getName() async throws -> String {
        do {
            let s = try await getSelf()
            return s.friendlyName ?? host
        } catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func getJid() async throws -> String? {
        do { return try await getSelf().jid }
        catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func getPeers() async throws -> [BeolinkPeer] {
        do { return try await getBeolinkPeers() }
        catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func join(peer: SpeakerIdentifier) async throws {
        do {
            if let jid = peer.jid {
                try await beolinkExpand(jid: jid)
            } else {
                try await beolinkJoin()
            }
        } catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func leave() async throws {
        do { try await beolinkLeave() }
        catch let e as MozartError { throw SpeakerError.from(e) }
    }
}
