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
    var source: String?            // human-readable source name ("B&O Radio")
    var sourceID: String?          // raw wire id ("beoradio:JID@..."); drives category detection
    var sourceTypeHint: String?    // BNR sourceType.type or Mozart Source.type, when available
    var batteryLevel: Int?

    /// Stable cross-session identifier. Uses the hardware JID when resolved; falls back to host IP.
    var stableId: String { identifier.jid ?? identifier.host }

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

    /// Source-aware now-playing presentation. Card and widget consume this.
    var nowPlaying: NowPlayingPresentation {
        NowPlayingPresenter.make(
            state:      playbackState,
            metadata:   metadata,
            sourceID:   sourceID,
            sourceName: source,
            typeHint:   sourceTypeHint
        )
    }

    /// Deprecated single-line display kept until SpeakerCard migrates fully.
    @available(*, deprecated, message: "Use nowPlaying.primaryLine / nowPlaying.secondaryLine")
    var trackDisplay: String {
        guard isPlaying else { return "" }
        return nowPlaying.primaryLine ?? source ?? ""
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
            g.addTask { await self.loadSource() }
        }
        startEventLoop()
        Log.info("[\(name)] initial state — state:\(state.rawValue) vol:\(volume.map(String.init) ?? "?")")
        WidgetStateWriter.write(speaker: self)
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
        do {
            guard let ps = try await client.getPlaybackState() else { return }
            switch ps {
            case .playing:   state = .playing
            case .paused:    state = .paused
            case .stopped:   state = .stopped
            case .buffering: state = .buffering
            }
        } catch {
            Log.error("[\(host)] loadPlaybackState failed: \(error)")
        }
    }

    private func loadVolume() async {
        do {
            guard let vol = try await client.getVolume() else { return }
            volume = vol
            // MozartClient exposes the mute flag via getMozartVolume(); cast to access it.
            if let mozartClient = client as? MozartClient,
               let volResp = try? await mozartClient.getMozartVolume() {
                isMuted = volResp.volume.muted ?? false
            }
        } catch {
            Log.error("[\(host)] loadVolume failed: \(error)")
        }
    }

    private func loadBattery() async {
        do {
            guard let bat = try await client.getBattery() else { return }
            if bat.batteryLevel > 0 || bat.isCharging { batteryLevel = bat.batteryLevel }
        } catch {
            Log.error("[\(host)] loadBattery failed: \(error)")
        }
    }

    private func loadSource() async {
        do {
            guard let s = try await client.getActiveSource() else {
                Log.info("[\(host)] loadSource: nil")
                return
            }
            sourceID       = s.id
            sourceTypeHint = s.typeHint
            if let name = s.friendlyName, !name.isEmpty { source = name }
            Log.info("[\(host)] loadSource: id=\(s.id) name=\(s.friendlyName ?? "nil") hint=\(s.typeHint ?? "nil")")
        } catch {
            Log.error("[\(host)] loadSource failed: \(error)")
        }
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
        case .source(let sourceName, let id):
            Log.verbose("[\(name)] source → \(sourceName ?? "?") id:\(id ?? "?")")
            // Source change invalidates current track metadata.
            if id != sourceID { metadata = nil }
            if let n = sourceName { source = n }
            sourceID = id
        }
        WidgetStateWriter.write(speaker: self)
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
