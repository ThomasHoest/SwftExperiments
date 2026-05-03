import Foundation
import WidgetKit

// MARK: - SpeakerRecord

struct SpeakerRecord: Codable {
    let host: String
    let name: String
    let platform: String  // "mozart" | "bnr"
}

// MARK: - WidgetStateWriter

@MainActor
struct WidgetStateWriter {
    private static let suiteName = "group.T-Creative.Voxio"

    static func write(speaker: Speaker, appRunning: Bool) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }

        defaults.set(speaker.name, forKey: "widget_speaker_name")
        defaults.set(speaker.host, forKey: "widget_speaker_host")
        defaults.set(speaker.metadata?.title, forKey: "widget_track_title")
        defaults.set(speaker.source, forKey: "widget_source_name")
        defaults.set(playbackStateString(for: speaker), forKey: "widget_playback_state")
        defaults.set(speaker.volume ?? 0, forKey: "widget_volume")
        defaults.set(speaker.isMuted, forKey: "widget_muted")
        defaults.set(appRunning, forKey: "widget_app_running")
        defaults.set(Date().timeIntervalSince1970, forKey: "widget_last_written_at")
        defaults.set(1, forKey: "widget_data_version")

        WidgetCenter.shared.reloadAllTimelines()
    }

    static func writeDiscoveredSpeakers(_ speakers: [Speaker]) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let records = speakers.map { SpeakerRecord(host: $0.host,
                                                    name: $0.name,
                                                    platform: $0.identifier.platform.rawValue) }
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: "widget_discovered_speakers")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Private

    private static func playbackStateString(for speaker: Speaker) -> String {
        switch speaker.playbackState {
        case .playing:   return "playing"
        case .paused:    return "paused"
        case .stopped:   return "stopped"
        case .buffering: return "loading"
        }
    }
}
