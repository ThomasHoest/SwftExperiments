import Foundation

/// REST client for the Bang & Olufsen Mozart Open API.
///
/// All Mozart-platform speakers (Beolab 28, Beosound A5, A9, Balance, Level,
/// Emerge, Theatre, Premiere, Beoconnect Core, etc.) expose this HTTP API
/// directly on the local network — no cloud, no authentication required.
///
/// Spec:   https://bang-olufsen.github.io/mozart-open-api/
/// GitHub: https://github.com/bang-olufsen/mozart-open-api
class MozartClient {
    let host: String
    private let baseUrl: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    /// - Parameter host: IP address of the speaker, e.g. `"192.168.1.50"`.
    init(host: String) {
        self.host  = host
        baseUrl    = "http://\(host)/api/v1"
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        session    = URLSession(configuration: config)
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(path, method: "GET")
        do { return try decoder.decode(T.self, from: data) } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            Log.error("[\(host)] GET \(path) decode error: \(error) | raw: \(raw)")
            throw MozartError.invalidResponse
        }
    }

    private func postVoid(_ path: String, body: Data? = nil) async throws {
        _ = try await send(path, method: "POST", body: body)
    }

    private func putVoid(_ path: String, body: Data? = nil) async throws {
        _ = try await send(path, method: "PUT", body: body)
    }

    private func send(_ path: String, method: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: baseUrl + path) else { throw MozartError.invalidResponse }
        Log.verbose("[\(host)] \(method) \(path)")
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await session.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { throw MozartError.notFound }
            guard (200..<300).contains(status) else {
                Log.error("[\(host)] \(method) \(path) → \(status)")
                throw MozartError.httpError(status)
            }
            Log.verbose("[\(host)] \(method) \(path) → \(status)")
            return data
        } catch let error as MozartError {
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut:
                throw MozartError.timeout
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet,
                 .cannotFindHost, .dnsLookupFailed:
                throw MozartError.unreachable
            default:
                throw MozartError.unreachable
            }
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    // ── Identity ──────────────────────────────────────────────────────────────

    /// Returns the device's Beolink identity: friendly name, JID, type, and serial number.
    func getSelf() async throws -> BeoSelf {
        try await get("/beolink/self")
    }

    // ── Power ─────────────────────────────────────────────────────────────────

    /// Returns the current power state (`on`, `standby`, `networkStandby`, `shutdown`, `storage`).
    func getPowerState() async throws -> PowerState {
        try await get("/state/power")
    }

    /// Puts the speaker into network standby. The device remains reachable on the network.
    func standby() async throws {
        try await putVoid("/state/standby", body: try encode(EmptyBody()))
    }

    /// Reboots the speaker. The API will be unavailable for ~30 seconds.
    func reboot() async throws {
        try await putVoid("/state/reboot", body: try encode(EmptyBody()))
    }

    // ── Battery ───────────────────────────────────────────────────────────────

    /// Returns battery state for portable devices (e.g. Beosound A1).
    /// Mains-powered speakers return `batteryLevel: 0, isCharging: false` — callers should ignore that case.
    func getMozartBattery() async throws -> Battery {
        try await get("/battery")
    }

    // ── Playback ──────────────────────────────────────────────────────────────

    /// Returns the current playback state (`playing`, `paused`, `stopped`, `buffering`, `unknown`).
    /// Note: real devices may also emit `started`, which is treated as equivalent to `playing`.
    func getMozartPlaybackState() async throws -> PlaybackState {
        let response: PlaybackResponse = try await get("/playback/state")
        return response.state
    }

    /// Returns metadata for the currently playing track (title, artist, album, artwork URL, duration).
    /// Field names use `artist`/`album` — distinct from the WebSocket event, which uses `artistName`/`albumName`.
    func getPlaybackMetadata() async throws -> PlaybackMetadata {
        try await get("/playback/metadata")
    }

    /// Returns playback progress for the current track.
    /// - Returns: `position` and `totalDuration`, both in milliseconds.
    func getPlaybackProgress() async throws -> PlaybackProgress {
        try await get("/playback/progress")
    }

    /// Starts or resumes playback on the active source.
    func mozartPlay() async throws {
        try await postVoid("/playback/command/play")
    }

    /// Pauses playback. Resumable with ``mozartPlay()``.
    func mozartPause() async throws {
        try await postVoid("/playback/command/pause")
    }

    /// Stops playback and clears the active stream.
    func mozartStop() async throws {
        try await postVoid("/playback/command/stop")
    }

    /// Skips to the next track in the queue.
    func next() async throws {
        try await postVoid("/playback/command/skip")
    }

    /// Returns to the previous track in the queue.
    func previous() async throws {
        try await postVoid("/playback/command/prev")
    }

    /// Seeks to a position in the current track.
    /// - Parameter positionMs: Target position in milliseconds.
    func seek(positionMs: Int) async throws {
        struct Body: Encodable { let positionMs: Int }
        try await putVoid("/playback/seek", body: try encode(Body(positionMs: positionMs)))
    }

    /// Plays a URI directly, e.g. a radio stream URL or a local media URI.
    /// - Parameter uri: The URI to play.
    func playUri(_ uri: String) async throws {
        struct Body: Encodable { let uri: String }
        try await postVoid("/playback/uri", body: try encode(Body(uri: uri)))
    }

    /// Returns the current queue settings (shuffle, repeat mode).
    func getQueueSettings() async throws -> QueueSettings {
        try await get("/playback/queue/settings")
    }

    /// Clears all tracks from the playback queue.
    func clearQueue() async throws {
        try await postVoid("/playback/queue/clear")
    }

    // ── Favorites / Presets ───────────────────────────────────────────────────

    /// Returns the list of scenes (favorites) stored on this speaker, sorted alphabetically.
    /// `GET /scenes` returns a `[String: SceneResponse]` dictionary keyed by UUID.
    /// Each `Favorite.presetIndex` is its 0-based position in the sorted list.
    /// Display name falls back to "Favorite N" when the scene has no label.
    func getFavorites() async throws -> [Favorite] {
        let scenes: [String: SceneResponse] = try await get("/scenes")
        let sorted = scenes
            .map { id, scene in (id: id, label: scene.label?.trimmingCharacters(in: .whitespaces)) }
            .sorted { ($0.label ?? "").localizedCompare($1.label ?? "") == .orderedAscending }
        return sorted.enumerated().map { offset, entry in
            let name = entry.label.flatMap { $0.isEmpty ? nil : $0 } ?? "Favorite \(offset + 1)"
            return Favorite(id: entry.id, displayName: name, presetIndex: offset + 1)
        }
    }

    /// Triggers a preset by its 0-based index (favorite 1 = index 0, favorite 2 = index 1, …).
    /// - Parameter presetIndex: 0-based position as stored in `Favorite.presetIndex`.
    func playFavorite(presetIndex: Int) async throws {
        try await postVoid("/playback/preset/\(presetIndex)/trigger")
    }

    // ── Volume ────────────────────────────────────────────────────────────────

    /// Returns the current volume state, including level, maximum, and mute status.
    func getMozartVolume() async throws -> VolumeResponse {
        try await get("/sound/volume")
    }

    /// Sets the volume level.
    /// - Parameter level: Integer 0–100.
    func mozartSetVolume(_ level: Int) async throws {
        struct Body: Encodable { let level: Int }
        try await putVoid("/sound/volume/level", body: try encode(Body(level: level)))
    }

    /// Mutes or unmutes the speaker without changing the stored volume level.
    /// - Parameter muted: `true` to mute, `false` to unmute.
    func setMute(_ muted: Bool) async throws {
        struct Body: Encodable { let muted: Bool }
        try await putVoid("/sound/volume/mute", body: try encode(Body(muted: muted)))
    }

    // ── Sources ───────────────────────────────────────────────────────────────

    /// Returns all available input sources on this device
    /// (Spotify, Deezer, Bluetooth, AirPlay, HDMI, Optical, Line-in, etc.).
    func getSources() async throws -> [Source] {
        try await get("/playback/sources")
    }

    /// Returns the currently active input source.
    func getMozartActiveSource() async throws -> Source {
        let data = try await send("/playback/sources/active", method: "GET")
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        Log.info("[\(host)] /playback/sources/active raw: \(raw)")
        do { return try decoder.decode(Source.self, from: data) }
        catch {
            Log.error("[\(host)] decode Source failed: \(error)")
            throw MozartError.invalidResponse
        }
    }

    /// Activates a specific source by its ID.
    /// - Parameter sourceId: Source identifier as returned by ``getSources()``, e.g. `"bluetooth"`, `"spotify"`.
    func setSource(_ sourceId: String) async throws {
        let encoded = sourceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sourceId
        try await postVoid("/playback/sources/active/\(encoded)")
    }

    // ── Sound settings ────────────────────────────────────────────────────────

    /// Activates a listening mode by its ID (e.g. stereo, spatialised, mono).
    /// Available IDs are device-specific; retrieve them from the sound features endpoint.
    /// - Parameter id: Listening mode identifier.
    func setListeningMode(_ id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        try await postVoid("/sound/listening-modes/\(encoded)/activate")
    }

    /// Sets the bass adjustment level.
    /// - Parameter level: Signed integer; typical range is −6 to +6 dB (device-dependent).
    func setBass(_ level: Int) async throws {
        struct Body: Encodable { let value: Int }
        try await putVoid("/sound/settings/adjustments/bass", body: try encode(Body(value: level)))
    }

    /// Sets the treble adjustment level.
    /// - Parameter level: Signed integer; typical range is −6 to +6 dB (device-dependent).
    func setTreble(_ level: Int) async throws {
        struct Body: Encodable { let value: Int }
        try await putVoid("/sound/settings/adjustments/treble", body: try encode(Body(value: level)))
    }

    /// Enables or disables loudness compensation (bass/treble boost at low volumes).
    /// - Parameter enabled: `true` to enable, `false` to disable.
    func setLoudness(_ enabled: Bool) async throws {
        struct Body: Encodable { let enabled: Bool }
        try await putVoid("/sound/settings/adjustments/loudness", body: try encode(Body(enabled: enabled)))
    }

    // ── Beolink (multi-room) ──────────────────────────────────────────────────

    /// Returns all Beolink-capable devices discovered on the same network.
    func getBeolinkPeers() async throws -> [BeolinkPeer] {
        try await get("/beolink/peers")
    }

    /// Expands the current audio experience to another Beolink device, making it play in sync.
    /// - Parameter jid: The JID of the target device, as returned by ``getBeolinkPeers()``.
    func beolinkExpand(jid: String) async throws {
        let encoded = jid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jid
        try await postVoid("/beolink/expand/\(encoded)")
    }

    /// Joins another device's active Beolink experience, playing in sync with the host.
    func beolinkJoin() async throws {
        try await postVoid("/beolink/join")
    }

    /// Leaves the current Beolink multi-room session. This device returns to standalone playback.
    func beolinkLeave() async throws {
        try await postVoid("/beolink/leave")
    }

    /// Sends all Beolink-connected devices to standby simultaneously.
    func beolinkAllStandby() async throws {
        try await postVoid("/beolink/allstandby")
    }
}

private struct EmptyBody: Encodable {}
