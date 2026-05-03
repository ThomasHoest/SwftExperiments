import WidgetKit
import Foundation

// MARK: - VoxioWidgetEntry

struct VoxioWidgetEntry: TimelineEntry {
    let date: Date
    let host: String?           // The speaker host the widget is currently displaying
    let speakerName: String
    let trackTitle: String?
    let sourceName: String?
    let playbackState: String   // "playing" | "paused" | "stopped" | "loading"
    let volume: Int
    let isMuted: Bool
    let appRunning: Bool
    let isEmpty: Bool           // true when no speaker state is in the shared container
    let lastWrittenAt: Date?
    let dataVersion: Int

    static let placeholder = VoxioWidgetEntry(
        date: Date(),
        host: nil,
        speakerName: "Beosound Stage",
        trackTitle: "Jazz Radio",
        sourceName: "TuneIn",
        playbackState: "playing",
        volume: 40,
        isMuted: false,
        appRunning: true,
        isEmpty: false,
        lastWrittenAt: Date(),
        dataVersion: 2
    )

    static let empty = VoxioWidgetEntry(
        date: Date(),
        host: nil,
        speakerName: "No speaker found",
        trackTitle: nil,
        sourceName: nil,
        playbackState: "stopped",
        volume: 0,
        isMuted: false,
        appRunning: false,
        isEmpty: true,
        lastWrittenAt: nil,
        dataVersion: 2
    )
}

// MARK: - VoxioWidgetProvider

struct VoxioWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = VoxioWidgetIntent
    typealias Entry = VoxioWidgetEntry

    private static let suiteName = "group.T-Creative.Voxio"
    private static let currentDataVersion = 2

    func placeholder(in context: Context) -> VoxioWidgetEntry {
        .placeholder
    }

    func snapshot(for configuration: VoxioWidgetIntent, in context: Context) async -> VoxioWidgetEntry {
        readEntry(for: configuration)
    }

    func timeline(for configuration: VoxioWidgetIntent, in context: Context) async -> Timeline<VoxioWidgetEntry> {
        let entry = readEntry(for: configuration)
        return Timeline(entries: [entry], policy: .never)
    }

    // MARK: - Private

    private func readEntry(for configuration: VoxioWidgetIntent) -> VoxioWidgetEntry {
        guard let defaults = UserDefaults(suiteName: Self.suiteName) else {
            return .empty
        }

        let dataVersion = defaults.integer(forKey: WidgetStateKeys.dataVersion)
        guard dataVersion == Self.currentDataVersion else {
            return .empty
        }

        let configuredId = configuration.speakerPicker?.id
        let host: String
        if let configuredId, configuredId != "auto" {
            host = configuredId
        } else if let auto = pickAutoHost(in: defaults) {
            host = auto
        } else {
            return .empty
        }

        guard let name = defaults.string(forKey: WidgetStateKeys.name(host)) else {
            return .empty
        }

        let writtenAt = defaults.double(forKey: WidgetStateKeys.writtenAt(host))
        let lastWrittenAt = writtenAt > 0 ? Date(timeIntervalSince1970: writtenAt) : nil

        return VoxioWidgetEntry(
            date: Date(),
            host: host,
            speakerName: name,
            trackTitle: defaults.string(forKey: WidgetStateKeys.trackTitle(host)),
            sourceName: defaults.string(forKey: WidgetStateKeys.sourceName(host)),
            playbackState: defaults.string(forKey: WidgetStateKeys.playbackState(host)) ?? "stopped",
            volume: defaults.integer(forKey: WidgetStateKeys.volume(host)),
            isMuted: defaults.bool(forKey: WidgetStateKeys.muted(host)),
            appRunning: defaults.bool(forKey: WidgetStateKeys.appRunning),
            isEmpty: false,
            lastWrittenAt: lastWrittenAt,
            dataVersion: dataVersion
        )
    }

    /// Pick the best speaker to display when the widget is set to "Automatic".
    /// Priority: any speaker currently playing → most recently written.
    /// Tie-break by most recent `written_at` timestamp.
    private func pickAutoHost(in defaults: UserDefaults) -> String? {
        let hosts = (defaults.array(forKey: WidgetStateKeys.knownHosts) as? [String]) ?? []
        guard !hosts.isEmpty else { return nil }

        let playing = hosts.filter {
            defaults.string(forKey: WidgetStateKeys.playbackState($0)) == "playing"
        }
        let candidates = playing.isEmpty ? hosts : playing
        return candidates.max {
            defaults.double(forKey: WidgetStateKeys.writtenAt($0))
                < defaults.double(forKey: WidgetStateKeys.writtenAt($1))
        }
    }
}
