import Foundation

class BNRClient {
    let host: String
    private let port: Int
    private let baseUrl: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    // Cached from the first volume fetch; default protects against races before first fetch.
    private var storedMaximum: Int = 9000
    private var maximumFetched = false

    // Captured from the Device-Jid response header on every successful response.
    // BNR products identify themselves via this header (see BNR API spec §Identity and Routing).
    private var cachedJid: String?

    init(host: String, port: Int = 8080) {
        self.host = host
        self.port = port
        baseUrl = "http://\(host):\(port)"
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        session = URLSession(configuration: config)
    }

    // Used in unit tests to inject a URLProtocol-backed session.
    init(host: String, port: Int = 8080, session: URLSession) {
        self.host = host
        self.port = port
        baseUrl = "http://\(host):\(port)"
        self.session = session
    }

    // MARK: - Private helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(path, method: "GET")
        do { return try decoder.decode(T.self, from: data) } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            Log.error("[BNR:\(host)] GET \(path) decode error: \(error) | raw: \(raw)")
            throw SpeakerError.invalidResponse
        }
    }

    private func postVoid(_ path: String, body: Data? = nil) async throws {
        _ = try await send(path, method: "POST", body: body)
    }

    private func putVoid(_ path: String, body: Data? = nil) async throws {
        _ = try await send(path, method: "PUT", body: body)
    }

    private func deleteVoid(_ path: String) async throws {
        _ = try await send(path, method: "DELETE")
    }

    private func send(_ path: String, method: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: baseUrl + path) else { throw SpeakerError.invalidResponse }
        Log.verbose("[BNR:\(host)] \(method) \(path)")
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await session.data(for: req)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if let jid = http?.value(forHTTPHeaderField: "Device-Jid"), !jid.isEmpty {
                cachedJid = jid
            }

            // 501 on write operations: soft warning, return empty data
            if status == 501 {
                Log.info("[BNR:\(host)] \(method) \(path) → 501 — treating as soft warning")
                return data
            }

            guard (200..<300).contains(status) else {
                Log.error("[BNR:\(host)] \(method) \(path) → \(status)")
                throw SpeakerError.httpError(status)
            }
            Log.verbose("[BNR:\(host)] \(method) \(path) → \(status)")
            return data
        } catch let error as SpeakerError {
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut:
                throw SpeakerError.timeout
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet,
                 .cannotFindHost, .dnsLookupFailed:
                throw SpeakerError.unreachable
            default:
                throw SpeakerError.unreachable
            }
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    // MARK: - Volume

    func getVolume() async throws -> Int {
        let response: BNRVolumeResponse = try await get("/BeoZone/Zone/Sound/Volume/Speaker")
        let maximum = response.speaker.range.maximum
        storedMaximum = maximum
        maximumFetched = true
        return response.speaker.level * 100 / Swift.max(maximum, 1)
    }

    func setVolume(_ level: Int) async throws {
        if !maximumFetched {
            let response: BNRVolumeResponse = try await get("/BeoZone/Zone/Sound/Volume/Speaker")
            storedMaximum = response.speaker.range.maximum
            maximumFetched = true
        }
        struct Body: Encodable { let level: Int }
        let raw = level * storedMaximum / 100
        try await putVoid("/BeoZone/Zone/Sound/Volume/Speaker/Level", body: try encode(Body(level: raw)))
    }

    func mute(_ muted: Bool) async throws {
        struct Body: Encodable { let muted: Bool }
        try await putVoid("/BeoZone/Zone/Sound/Volume/Speaker/Muted", body: try encode(Body(muted: muted)))
    }

    // MARK: - Playback commands

    func play() async throws {
        try await postVoid("/BeoZone/Zone/Stream/Play")
        try? await postVoid("/BeoZone/Zone/Stream/Play/Release")
    }

    func pause() async throws {
        try await postVoid("/BeoZone/Zone/Stream/Pause")
        try? await postVoid("/BeoZone/Zone/Stream/Pause/Release")
    }

    func stop() async throws {
        try await postVoid("/BeoZone/Zone/Stream/Stop")
        try? await postVoid("/BeoZone/Zone/Stream/Stop/Release")
    }

    func forward() async throws {
        try await postVoid("/BeoZone/Zone/Stream/Forward")
        try? await postVoid("/BeoZone/Zone/Stream/Forward/Release")
    }

    func backward() async throws {
        try await postVoid("/BeoZone/Zone/Stream/Backward")
        try? await postVoid("/BeoZone/Zone/Stream/Backward/Release")
    }

    // MARK: - Playback state

    func getBNRPlaybackState() async throws -> BNRPlaybackState {
        try await fetchActiveSources().state
    }

    /// Returns the active source as a unified `SpeakerSource`, derived from the
    /// same `/BeoZone/Zone/ActiveSources` call used for play state.
    func getBNRActiveSource() async throws -> SpeakerSource? {
        try await fetchActiveSources().source
    }

    private func fetchActiveSources() async throws -> (state: BNRPlaybackState, source: SpeakerSource?) {
        let raw = try await send("/BeoZone/Zone/ActiveSources", method: "GET")
        let response: BNRActiveSourcesResponse
        do { response = try decoder.decode(BNRActiveSourcesResponse.self, from: raw) }
        catch {
            let rawString = String(data: raw, encoding: .utf8) ?? "<non-utf8>"
            Log.error("[BNR:\(host)] decode ActiveSources failed: \(error) | raw: \(rawString)")
            throw SpeakerError.invalidResponse
        }
        let source = response.primaryExperience?.source
        // Resolve a SpeakerSource — id may live on source.id directly, or be
        // present as activeSources.primary when source.id is missing.
        let sourceID   = source?.id ?? response.activeSources?.primary
        let sourceName = source?.friendlyName
        let typeHint   = source?.sourceType?.type ?? source?.category
        let speakerSource: SpeakerSource? = sourceID.map {
            SpeakerSource(id: $0, friendlyName: sourceName, typeHint: typeHint)
        }

        // Prefer an explicit state if firmware returns it (api-spec shape).
        if let rawState = response.primaryExperience?.state {
            let mapped = mapBNRPlaybackState(rawState)
            Log.info("[BNR:\(host)] activeSources: REST state:\"\(rawState)\" source:\(sourceName ?? "nil") → \(mapped)")
            return (mapped, speakerSource)
        }

        // Heuristic fallback: real firmware doesn't include `state` in REST.
        let primary = response.activeSources?.primary ?? ""
        let isActive = (source?.inUse == true) || !primary.isEmpty
        let inferred: BNRPlaybackState = isActive ? .playing : .stopped
        Log.info("[BNR:\(host)] activeSources: no REST state, source.inUse=\(source?.inUse ?? false) primary=\"\(primary)\" source:\(sourceName ?? "nil") → \(inferred)")
        return (inferred, speakerSource)
    }

    private func mapBNRPlaybackState(_ raw: String) -> BNRPlaybackState {
        switch raw {
        case "play", "playing", "started": return .playing
        case "pause", "paused":             return .paused
        case "stop", "stopped":             return .stopped
        case "buffering":                   return .buffering
        case "completed", "ended":          return .stopped
        default:
            Log.info("[BNR:\(host)] mapBNRPlaybackState: unknown raw \"\(raw)\" → .stopped")
            return .stopped
        }
    }

    // MARK: - Identity

    func getName() async throws -> String {
        let response: BNRDeviceResponse = try await get("/BeoDevice")
        return response.beoDevice.productFriendlyName.productFriendlyName
    }

    /// Returns the JID captured from the `Device-Jid` response header.
    /// Issues a `/BeoDevice` request if the cache is empty, to populate it.
    func getJid() async throws -> String? {
        if cachedJid == nil {
            _ = try? await send("/BeoDevice", method: "GET")
        }
        return cachedJid
    }

    // MARK: - Sources

    func getSources() async throws -> [Favorite] {
        let response: BNRSourcesResponse = try await get("/BeoZone/Zone/Sources")
        let eligible = response.sources
            .map { $0.1 }
            .filter { $0.inUse && !$0.borrowed }
        return eligible.enumerated().map { index, src in
            Favorite(id: src.id, displayName: src.friendlyName, presetIndex: index)
        }
    }

    func activateSource(_ id: String) async throws {
        struct SourceRef: Encodable { let id: String }
        struct PrimaryExp: Encodable { let source: SourceRef }
        struct Body: Encodable { let primaryExperience: PrimaryExp }
        let body = Body(primaryExperience: PrimaryExp(source: SourceRef(id: id)))
        try await postVoid("/BeoZone/Zone/ActiveSources", body: try encode(body))
    }

    func getBattery() async throws -> Battery? {
        nil
    }

    // MARK: - Session management

    /// Master-side multi-room join: adds a listener to this device's primary experience.
    /// This device must be the broadcasting source; the listener is identified by their JID.
    /// Maps to the C# `BuildExpandExperienceRequest(listenerJid)` builder.
    func expandExperience(listenerJid: String) async throws {
        struct Body: Encodable { let jid: String }
        try await postVoid("/BeoZone/Zone/ActiveSources/primaryExperience",
                           body: try encode(Body(jid: listenerJid)))
    }

    /// Listener-side legacy "Join" button: this device joins whatever the network advertises
    /// as the active broadcast experience. No peer parameter — equivalent to pressing the
    /// physical Join key on a Beo remote. Kept for completeness; multi-room voice "join"
    /// goes through `expandExperience(listenerJid:)` instead.
    func legacyJoin() async throws {
        try await postVoid("/BeoZone/Zone/Device/OneWayJoin")
    }

    func leave() async throws {
        try await deleteVoid("/BeoZone/Zone/ActiveSources/primaryExperience")
    }
}

// MARK: - BNR-specific response types (private to this module)

private struct BNRVolumeResponse: Decodable {
    struct Speaker: Decodable {
        let level: Int
        let muted: Bool
        let range: BNRVolumeRange
    }
    let speaker: Speaker
}

/// Shape on real ASE firmware (verified BeoPlay A9, BeoSound Stage, BeoSound 1):
/// `primaryExperience` and `activeSources` are sibling top-level keys.
/// `primaryExperience.state` is NOT returned by REST — it only appears in
/// long-poll SOURCE/PROGRESS_INFORMATION notifications. The api-spec doc
/// shows them nested with `state`, but the firmware doesn't match that.
private struct BNRActiveSourcesResponse: Decodable {
    let primaryExperience: PrimaryExperience?
    let activeSources: ActiveSources?

    struct PrimaryExperience: Decodable {
        let source: SourceInfo?
        let state: String?      // present in spec, absent in observed REST responses
    }
    struct SourceInfo: Decodable {
        let id: String?
        let friendlyName: String?
        let category: String?
        let inUse: Bool?        // heuristic: true ⇒ source is currently active/playing
        let sourceType: SourceType?
    }
    struct SourceType: Decodable {
        let type: String?
    }
    struct ActiveSources: Decodable {
        let primary: String?
        let primaryJid: String?
    }
}

private struct BNRDeviceResponse: Decodable {
    struct BeoDevice: Decodable {
        let productFriendlyName: ProductFriendlyName
    }
    struct ProductFriendlyName: Decodable {
        let productFriendlyName: String
    }
    let beoDevice: BeoDevice
}

// Sources come back as an array of 2-element arrays: [[id, sourceObject], ...]
private struct BNRSourceObject: Decodable {
    let id: String
    let friendlyName: String
    let inUse: Bool
    let borrowed: Bool
    let sourceType: BNRSourceType?
    let category: String?
    let multiroom: String?
}

private struct BNRSourceType: Decodable {
    let type: String
}

// The outer "sources" value is [[Any]] — a heterogeneous array of arrays.
// Decode as [[JSONValue]] and then pull out the second element as BNRSourceObject.
private struct BNRSourcesResponse: Decodable {
    let sources: [(String, BNRSourceObject)]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPairs = try container.decode([[JSONValue]].self, forKey: .sources)
        sources = try rawPairs.compactMap { pair -> (String, BNRSourceObject)? in
            guard pair.count == 2,
                  case .string(let id) = pair[0] else { return nil }
            // Re-encode the second element and decode as BNRSourceObject
            let objData = try JSONEncoder().encode(pair[1])
            let obj = try JSONDecoder().decode(BNRSourceObject.self, from: objData)
            return (id, obj)
        }
    }

    private enum CodingKeys: String, CodingKey { case sources }
}

// Minimal JSON value type for heterogeneous array decoding
private enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self)          { self = .string(v); return }
        if let v = try? c.decode(Bool.self)             { self = .bool(v);   return }
        if let v = try? c.decode(Int.self)              { self = .int(v);    return }
        if let v = try? c.decode(Double.self)           { self = .double(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self)      { self = .array(v);  return }
        if c.decodeNil()                                { self = .null;      return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unexpected JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .null:          try c.encodeNil()
        }
    }
}
