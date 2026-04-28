import Foundation

class MozartClient {
    private let host: String
    private let baseUrl: String
    private let session: URLSession
    private let decoder = JSONDecoder()

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
            Log.error("[\(host)] GET \(path) decode error: \(error)")
            throw error
        }
    }

    private func postVoid(_ path: String, body: Data? = nil) async throws {
        _ = try await send(path, method: "POST", body: body)
    }

    private func putVoid(_ path: String, body: Data? = nil) async throws {
        _ = try await send(path, method: "PUT", body: body)
    }

    private func send(_ path: String, method: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: baseUrl + path) else { throw URLError(.badURL) }
        Log.info("[\(host)] \(method) \(path)")
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            Log.error("[\(host)] \(method) \(path) → \(status)")
            throw URLError(.badServerResponse)
        }
        Log.info("[\(host)] \(method) \(path) → \(status)")
        return data
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    // ── Identity ──────────────────────────────────────────────────────────────

    func getSelf() async throws -> BeoSelf {
        try await get("/beolink/self")
    }

    // ── Power ─────────────────────────────────────────────────────────────────

    func getPowerState() async throws -> PowerState {
        try await get("/state/power")
    }

    func standby() async throws {
        try await putVoid("/state/standby", body: try encode(EmptyBody()))
    }

    func reboot() async throws {
        try await putVoid("/state/reboot", body: try encode(EmptyBody()))
    }

    // ── Battery ───────────────────────────────────────────────────────────────

    func getBattery() async throws -> Battery {
        try await get("/battery")
    }

    // ── Playback ──────────────────────────────────────────────────────────────

    func getPlaybackState() async throws -> PlaybackState {
        try await get("/playback/state")
    }

    func getPlaybackMetadata() async throws -> PlaybackMetadata {
        try await get("/playback/metadata")
    }

    func getPlaybackProgress() async throws -> PlaybackProgress {
        try await get("/playback/progress")
    }

    func play() async throws {
        try await postVoid("/playback/command/play")
    }

    func pause() async throws {
        try await postVoid("/playback/command/pause")
    }

    func stop() async throws {
        try await postVoid("/playback/command/stop")
    }

    func next() async throws {
        try await postVoid("/playback/command/skip")
    }

    func previous() async throws {
        try await postVoid("/playback/command/prev")
    }

    func seek(positionMs: Int) async throws {
        struct Body: Encodable { let positionMs: Int }
        try await putVoid("/playback/seek", body: try encode(Body(positionMs: positionMs)))
    }

    func playUri(_ uri: String) async throws {
        struct Body: Encodable { let uri: String }
        try await postVoid("/playback/uri", body: try encode(Body(uri: uri)))
    }

    func getQueueSettings() async throws -> QueueSettings {
        try await get("/playback/queue/settings")
    }

    func clearQueue() async throws {
        try await postVoid("/playback/queue/clear")
    }

    // ── Volume ────────────────────────────────────────────────────────────────

    func getVolume() async throws -> VolumeResponse {
        try await get("/sound/volume")
    }

    func setVolume(_ level: Int) async throws {
        struct Body: Encodable { let volumeLevel: Int }
        try await putVoid("/sound/volume/level", body: try encode(Body(volumeLevel: level)))
    }

    func setMute(_ muted: Bool) async throws {
        struct Body: Encodable { let muted: Bool }
        try await putVoid("/sound/volume/mute", body: try encode(Body(muted: muted)))
    }

    // ── Sources ───────────────────────────────────────────────────────────────

    func getSources() async throws -> [Source] {
        try await get("/playback/sources")
    }

    func getActiveSource() async throws -> Source {
        try await get("/playback/sources/active")
    }

    func setSource(_ sourceId: String) async throws {
        let encoded = sourceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sourceId
        try await postVoid("/playback/sources/active/\(encoded)")
    }

    // ── Sound settings ────────────────────────────────────────────────────────

    func setListeningMode(_ id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        try await postVoid("/sound/listening-modes/\(encoded)/activate")
    }

    func setBass(_ level: Int) async throws {
        struct Body: Encodable { let value: Int }
        try await putVoid("/sound/settings/adjustments/bass", body: try encode(Body(value: level)))
    }

    func setTreble(_ level: Int) async throws {
        struct Body: Encodable { let value: Int }
        try await putVoid("/sound/settings/adjustments/treble", body: try encode(Body(value: level)))
    }

    func setLoudness(_ enabled: Bool) async throws {
        struct Body: Encodable { let enabled: Bool }
        try await putVoid("/sound/settings/adjustments/loudness", body: try encode(Body(enabled: enabled)))
    }

    // ── Beolink ───────────────────────────────────────────────────────────────

    func getBeolinkPeers() async throws -> [BeolinkPeer] {
        try await get("/beolink/peers")
    }

    func beolinkExpand(jid: String) async throws {
        let encoded = jid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jid
        try await postVoid("/beolink/expand/\(encoded)")
    }

    func beolinkJoin() async throws {
        try await postVoid("/beolink/join")
    }

    func beolinkLeave() async throws {
        try await postVoid("/beolink/leave")
    }

    func beolinkAllStandby() async throws {
        try await postVoid("/beolink/allstandby")
    }
}

private struct EmptyBody: Encodable {}
