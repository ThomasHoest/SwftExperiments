import Foundation
import Observation

struct SpeakerMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var genre: String?
}

@Observable @MainActor
class Speaker: Identifiable {
    let id = UUID()
    let host: String
    var name: String
    var state = "unknown"
    var metadata: SpeakerMetadata?
    var volume: Int?
    var source: String?
    var batteryLevel: Int?

    var isPlaying: Bool { state == "playing" || state == "started" }

    var stateDisplay: String {
        switch state {
        case "playing", "started": return "Playing"
        case "paused":             return "Paused"
        case "buffering":          return "Buffering"
        default:                   return "Idle"
        }
    }

    var trackDisplay: String {
        guard isPlaying else { return "" }
        let parts = [metadata?.artist, metadata?.title].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " – ") }
        if let g = metadata?.genre,  !g.isEmpty { return g }
        if let a = metadata?.album,  !a.isEmpty { return a }
        return source ?? ""
    }

    var volumeDisplay: String  { volume.map      { "Vol \($0)" } ?? "" }
    var batteryDisplay: String { batteryLevel.map { "\($0)%" }   ?? "" }

    private let client: MozartClient
    private let events: MozartEvents

    init(host: String) {
        self.host   = host
        self.name   = host
        self.client = MozartClient(host: host)
        self.events = MozartEvents(host: host)
    }

    func initialize() async throws {
        Log.info("[\(host)] initializing")
        guard let identity = await client.get("/beolink/self") else {
            Log.error("[\(host)] failed to reach /beolink/self — discarding")
            throw URLError(.cannotConnectToHost)
        }
        if let n = identity["friendlyName"] as? String {
            name = n
            Log.info("[\(host)] identified as \(n)")
        }

        await withTaskGroup(of: Void.self) { g in
            g.addTask { await self.loadPlaybackState() }
            g.addTask { await self.loadVolume() }
            g.addTask { await self.loadBattery() }
            g.addTask { await self.loadActiveSource() }
        }
        Log.info("[\(name)] initial state — state:\(state) vol:\(volume.map(String.init) ?? "?") src:\(source ?? "?")")

        events.onEvent = { [weak self] type, data in
            Task { @MainActor in self?.handleEvent(eventType: type, data: data) }
        }
        events.connect()
    }

    private func loadPlaybackState() async {
        guard let d = await client.get("/playback/state"),
              let s = d["state"] as? String else { return }
        state = s
    }

    private func loadVolume() async {
        guard let d   = await client.get("/sound/volume"),
              let vol = d["volume"] as? [String: Any],
              let lev = vol["level"] as? Int else { return }
        volume = lev
    }

    private func loadBattery() async {
        guard let d   = await client.get("/battery"),
              let lev = d["batteryLevel"] as? Int else { return }
        let charging = d["isCharging"] as? Bool ?? false
        if lev > 0 || charging { batteryLevel = lev }
    }

    private func loadActiveSource() async {
        guard let d = await client.get("/playback/sources/active") else { return }
        let name = (d["friendlyName"] as? String) ?? (d["id"] as? String)
        if let name { source = name }
    }

    private func handleEvent(eventType: String, data: [String: Any]) {
        switch eventType {
        case "WebSocketEventPlaybackState":
            if let v = data["value"] as? String {
                Log.verbose("[\(name)] playback state → \(v)")
                state = v
            }

        case "WebSocketEventPlaybackMetadata":
            let title  = data["title"]      as? String
            let artist = data["artistName"] as? String
            Log.verbose("[\(name)] metadata → \(artist ?? "?") – \(title ?? "?")")
            metadata = SpeakerMetadata(
                title:  title,
                artist: artist,
                album:  data["albumName"] as? String,
                genre:  nil
            )

        case "WebSocketEventVolume":
            if let vol = data["volume"] as? [String: Any],
               let lev = vol["level"] as? Int {
                Log.verbose("[\(name)] volume → \(lev)")
                volume = lev
            }

        case "WebSocketEventBattery":
            if let lev = data["batteryLevel"] as? Int {
                let charging = data["isCharging"] as? Bool ?? false
                if lev > 0 || charging {
                    Log.verbose("[\(name)] battery → \(lev)% charging:\(charging)")
                    batteryLevel = lev
                }
            }

        case "WebSocketEventPlaybackSource":
            let src = (data["friendlyName"] as? String) ?? (data["id"] as? String)
            if let src {
                Log.verbose("[\(name)] source → \(src)")
                source = src
            }

        default:
            Log.verbose("[\(name)] unhandled event: \(eventType)")
        }
    }

    func dispose() { events.disconnect() }
}
