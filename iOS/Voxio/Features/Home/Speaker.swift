import Foundation
import Observation

@Observable @MainActor
class Speaker: Identifiable {
    let id = UUID()
    let host: String
    var name: String
    var state: PlaybackValue = .unknown
    var metadata: PlaybackMetadata?
    var volume: Int?
    var source: String?
    var batteryLevel: Int?

    var isPlaying: Bool { state == .playing || state == .started }

    var stateDisplay: String {
        switch state {
        case .playing, .started: return "Playing"
        case .paused:            return "Paused"
        case .buffering:         return "Buffering"
        default:                 return "Idle"
        }
    }

    var trackDisplay: String {
        guard isPlaying else { return "" }
        let parts = [metadata?.artist, metadata?.title].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " – ") }
        if let g = metadata?.genre, !g.isEmpty { return g }
        if let a = metadata?.album, !a.isEmpty { return a }
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
        let identity = try await client.getSelf()
        if let n = identity.friendlyName {
            name = n
            Log.info("[\(host)] identified as \(n)")
        }

        await withTaskGroup(of: Void.self) { g in
            g.addTask { await self.loadPlaybackState() }
            g.addTask { await self.loadVolume() }
            g.addTask { await self.loadBattery() }
            g.addTask { await self.loadActiveSource() }
        }
        Log.info("[\(name)] initial state — state:\(state.rawValue) vol:\(volume.map(String.init) ?? "?") src:\(source ?? "?")")

        events.onEvent = { [weak self] event in
            Task { @MainActor in self?.handleEvent(event) }
        }
        events.connect()
    }

    private func loadPlaybackState() async {
        guard let ps = try? await client.getPlaybackState() else { return }
        state = ps.value
    }

    private func loadVolume() async {
        guard let vol = try? await client.getVolume() else { return }
        volume = vol.volume.level
    }

    private func loadBattery() async {
        guard let bat = try? await client.getBattery() else { return }
        if bat.batteryLevel > 0 || bat.isCharging { batteryLevel = bat.batteryLevel }
    }

    private func loadActiveSource() async {
        guard let src = try? await client.getActiveSource() else { return }
        source = src.displayName
    }

    private func handleEvent(_ event: BeoEvent) {
        switch event {
        case .playbackState(let e):
            Log.verbose("[\(name)] playback state → \(e.value.rawValue)")
            state = e.value

        case .playbackMetadata(let e):
            Log.verbose("[\(name)] metadata → \(e.artistName ?? "?") – \(e.title ?? "?")")
            metadata = PlaybackMetadata(
                title:      e.title,
                artist:     e.artistName,
                album:      e.albumName,
                genre:      e.genre,
                artworkUrl: nil,
                durationMs: nil
            )

        case .volume(let e):
            Log.verbose("[\(name)] volume → \(e.volume.level)")
            volume = e.volume.level

        case .battery(let e):
            if e.batteryLevel > 0 || e.isCharging {
                Log.verbose("[\(name)] battery → \(e.batteryLevel)% charging:\(e.isCharging)")
                batteryLevel = e.batteryLevel
            }

        case .playbackSource(let e):
            Log.verbose("[\(name)] source → \(e.displayName ?? "?")")
            if let src = e.displayName { source = src }

        case .power(let e):
            Log.verbose("[\(name)] power → \(e.state.rawValue)")

        case .progress:
            break

        case .unknown(let type):
            Log.verbose("[\(name)] unhandled event: \(type)")
        }
    }

    func dispose() { events.disconnect() }

    // ── Commands ──────────────────────────────────────────────────────────────

    func ping() async -> Bool {
        (try? await client.getSelf()) != nil
    }

    func play() async throws    { try await client.play() }
    func pause() async throws   { try await client.pause() }
    func stop() async throws    { try await client.stop() }

    func setVolume(_ level: Int) async throws {
        try await client.setVolume(level)
        volume = level
    }

    func adjustVolume(_ delta: Int) async throws {
        let newLevel = max(0, min(100, (volume ?? 50) + delta))
        try await client.setVolume(newLevel)
        volume = newLevel
    }

    func mute() async throws   { try await client.setMute(true) }
    func unmute() async throws { try await client.setMute(false) }

    func getFavorites() async throws -> [Favorite] {
        try await client.getFavorites()
    }

    func playFavorite(presetIndex: Int) async throws {
        try await client.playFavorite(presetIndex: presetIndex)
    }
}
