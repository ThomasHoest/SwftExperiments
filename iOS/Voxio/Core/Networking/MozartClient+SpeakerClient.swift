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
            case .playing:           return .playing
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

    func getActiveSource() async throws -> SpeakerSource? {
        do {
            let s = try await getMozartActiveSource()
            Log.info("[\(host)] Mozart active source: id=\(s.id ?? "nil") name=\(s.friendlyName ?? "nil") type=\(s.sourceType ?? "nil")")
            guard let id = s.id else { return nil }
            return SpeakerSource(id: id,
                                 friendlyName: s.friendlyName,
                                 typeHint: s.sourceType)
        } catch let e as MozartError {
            Log.info("[\(host)] getActiveSource MozartError: \(e)")
            return nil
        } catch {
            Log.error("[\(host)] getActiveSource unknown error: \(error)")
            return nil
        }
    }

    func getPeers() async throws -> [BeolinkPeer] {
        do { return try await getBeolinkPeers() }
        catch let e as MozartError { throw SpeakerError.from(e) }
    }

    func join(peer: SpeakerIdentifier) async throws {
        do {
            if let jid = peer.jid {
                Log.info("[\(host)] join → expand to jid:\(jid)")
                try await beolinkExpand(jid: jid)
            } else {
                Log.info("[\(host)] join → beolinkJoin (no jid for peer \(peer.host))")
                try await beolinkJoin()
            }
            Log.info("[\(host)] join OK")
        } catch let e as MozartError {
            Log.error("[\(host)] join failed: \(e)")
            throw SpeakerError.from(e)
        }
    }

    func leave() async throws {
        do {
            Log.info("[\(host)] leave → beolinkLeave")
            try await beolinkLeave()
            Log.info("[\(host)] leave OK")
        } catch let e as MozartError {
            Log.error("[\(host)] leave failed: \(e)")
            throw SpeakerError.from(e)
        }
    }
}
