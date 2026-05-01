import Foundation
import Observation

@Observable @MainActor
class Speaker: Identifiable {
    let id = UUID()
    let host: String
    var name: String
    var identifier: SpeakerIdentifier
    var state: PlaybackValue = .unknown
    var metadata: PlaybackMetadata?
    var volume: Int?
    var isMuted: Bool = false
    var source: String?
    var batteryLevel: Int?

    var isPlaying: Bool { state == .playing || state == .started }

    var playbackState: SpeakerPlaybackState {
        switch state {
        case .playing, .started: return .playing
        case .paused:            return .paused
        case .buffering:         return .buffering
        default:                 return .stopped
        }
    }

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

    let client: any SpeakerClient
    private let eventSource: any SpeakerEventSource
    private var eventTask: Task<Void, Never>?

    init(host: String, client: any SpeakerClient, eventSource: any SpeakerEventSource, platform: SpeakerPlatform) {
        self.host        = host
        self.name        = host
        self.client      = client
        self.eventSource = eventSource
        self.identifier  = SpeakerIdentifier(host: host, jid: nil, platform: platform)
    }

    func initialize() async throws {
        Log.info("[\(host)] initializing")
        async let nameTask = client.getName()
        async let jidTask  = client.getJid()
        let resolvedName = (try? await nameTask) ?? host
        let resolvedJid  = try? await jidTask
        name = resolvedName
        identifier = SpeakerIdentifier(host: host, jid: resolvedJid, platform: identifier.platform)
        Log.info("[\(host)] identified as \(resolvedName) jid:\(resolvedJid ?? "nil")")

        await withTaskGroup(of: Void.self) { g in
            g.addTask { await self.loadPlaybackState() }
            g.addTask { await self.loadVolume() }
            g.addTask { await self.loadBattery() }
        }
        startEventLoop()
        Log.info("[\(name)] initial state — state:\(state.rawValue) vol:\(volume.map(String.init) ?? "?")")
    }

    private func startEventLoop() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.eventSource.events() {
                self.handleEvent(event)
            }
        }
    }

    private func loadPlaybackState() async {
        guard let ps = try? await client.getPlaybackState() else { return }
        switch ps {
        case .playing:   state = .playing
        case .paused:    state = .paused
        case .stopped:   state = .stopped
        case .buffering: state = .buffering
        }
    }

    private func loadVolume() async {
        guard let vol = try? await client.getVolume() else { return }
        volume = vol
        // MozartClient exposes the mute flag via getMozartVolume(); cast to access it.
        if let mozartClient = client as? MozartClient,
           let volResp = try? await mozartClient.getMozartVolume() {
            isMuted = volResp.volume.muted ?? false
        }
    }

    private func loadBattery() async {
        guard let bat = try? await client.getBattery() else { return }
        if bat.batteryLevel > 0 || bat.isCharging { batteryLevel = bat.batteryLevel }
    }

    private func handleEvent(_ event: SpeakerEvent) {
        switch event {
        case .playbackState(let ps):
            Log.verbose("[\(name)] playback state → \(ps)")
            switch ps {
            case .playing:   state = .playing
            case .paused:    state = .paused
            case .stopped:   state = .stopped
            case .buffering: state = .buffering
            }
        case .metadata(let title, let artist, let album):
            Log.verbose("[\(name)] metadata → \(artist ?? "?") – \(title ?? "?")")
            metadata = PlaybackMetadata(title: title, artist: artist, album: album,
                                        genre: nil, artworkUrl: nil, durationMs: nil)
        case .volume(let level, let muted):
            Log.verbose("[\(name)] volume → \(level) muted:\(muted)")
            volume  = level
            isMuted = muted
        case .battery(let b):
            if b.batteryLevel > 0 || b.isCharging {
                Log.verbose("[\(name)] battery → \(b.batteryLevel)%")
                batteryLevel = b.batteryLevel
            }
        case .source(let sourceName, _):
            Log.verbose("[\(name)] source → \(sourceName ?? "?")")
            if let n = sourceName { source = n }
        }
    }

    func dispose() {
        eventTask?.cancel()
        eventTask = nil
        // eventSource.events() continuation termination handler invokes disconnect()
    }

    // ── Commands ──────────────────────────────────────────────────────────────

    func ping() async -> Bool { (try? await client.getName()) != nil }

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

    func mute() async throws {
        try await client.mute(true)
        isMuted = true
    }

    func unmute() async throws {
        try await client.mute(false)
        isMuted = false
    }

    func getFavorites() async throws -> [Favorite] {
        try await client.getSources()
    }

    func playFavorite(presetIndex: Int) async throws {
        // Mozart presets are triggered by index via a dedicated endpoint.
        // BNR uses activateSource with a source ID; pass the index as a string for BNR compat.
        if let mozartClient = client as? MozartClient {
            try await mozartClient.playFavorite(presetIndex: presetIndex)
        } else {
            try await client.activateSource(presetIndex.description)
        }
    }
}
