import WidgetKit
import Foundation

// MARK: - VoxioWidgetEntry

struct VoxioWidgetEntry: TimelineEntry {
    let date: Date
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
        speakerName: "Beosound Stage",
        trackTitle: "Jazz Radio",
        sourceName: "TuneIn",
        playbackState: "playing",
        volume: 40,
        isMuted: false,
        appRunning: true,
        isEmpty: false,
        lastWrittenAt: Date(),
        dataVersion: 1
    )

    static let empty = VoxioWidgetEntry(
        date: Date(),
        speakerName: "No speaker found",
        trackTitle: nil,
        sourceName: nil,
        playbackState: "stopped",
        volume: 0,
        isMuted: false,
        appRunning: false,
        isEmpty: true,
        lastWrittenAt: nil,
        dataVersion: 1
    )
}

// MARK: - VoxioWidgetProvider

struct VoxioWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = VoxioWidgetIntent
    typealias Entry = VoxioWidgetEntry

    private static let suiteName = "group.T-Creative.Voxio"
    private static let currentDataVersion = 1

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

        let dataVersion = defaults.integer(forKey: "widget_data_version")
        guard dataVersion == Self.currentDataVersion else {
            return .empty
        }

        guard let speakerName = defaults.string(forKey: "widget_speaker_name") else {
            return .empty
        }

        // If a specific speaker is configured (not "auto"), filter by host
        let configuredHost = configuration.speakerPicker?.id
        let storedHost = defaults.string(forKey: "widget_speaker_host") ?? ""
        if let host = configuredHost, host != "auto", host != storedHost {
            return .empty
        }

        let rawTimestamp = defaults.double(forKey: "widget_last_written_at")
        let lastWrittenAt = rawTimestamp > 0 ? Date(timeIntervalSince1970: rawTimestamp) : nil

        return VoxioWidgetEntry(
            date: Date(),
            speakerName: speakerName,
            trackTitle: defaults.string(forKey: "widget_track_title"),
            sourceName: defaults.string(forKey: "widget_source_name"),
            playbackState: defaults.string(forKey: "widget_playback_state") ?? "stopped",
            volume: defaults.integer(forKey: "widget_volume"),
            isMuted: defaults.bool(forKey: "widget_muted"),
            appRunning: defaults.bool(forKey: "widget_app_running"),
            isEmpty: false,
            lastWrittenAt: lastWrittenAt,
            dataVersion: dataVersion
        )
    }
}
