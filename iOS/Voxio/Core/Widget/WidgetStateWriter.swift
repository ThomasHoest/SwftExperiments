import Foundation
import WidgetKit

struct SpeakerRecord: Codable {
    let host: String
    let name: String
    let platform: String
}

@MainActor
struct WidgetStateWriter {
    private static let suiteName    = "group.T-Creative.Voxio"
    private static let dataVersion  = 2

    /// Write current state for one speaker. Other speakers' keys are untouched.
    static func write(speaker: Speaker) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let host = speaker.host

        defaults.set(speaker.name,                       forKey: K.name(host))
        defaults.set(speaker.metadata?.title,            forKey: K.trackTitle(host))
        defaults.set(speaker.source,                     forKey: K.sourceName(host))
        defaults.set(playbackStateString(for: speaker),  forKey: K.playbackState(host))
        defaults.set(speaker.volume ?? 0,                forKey: K.volume(host))
        defaults.set(speaker.isMuted,                    forKey: K.muted(host))
        defaults.set(Date().timeIntervalSince1970,       forKey: K.writtenAt(host))

        addKnownHost(host, in: defaults)
        defaults.set(true,        forKey: K.appRunning)
        defaults.set(dataVersion, forKey: K.dataVersion)

        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Remove every key for `host`. Called from SpeakerDiscoveryService when mDNS removes a speaker.
    static func removeSpeaker(host: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        for key in [K.name(host), K.trackTitle(host), K.sourceName(host),
                    K.playbackState(host), K.volume(host), K.muted(host), K.writtenAt(host)] {
            defaults.removeObject(forKey: key)
        }
        removeKnownHost(host, in: defaults)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Toggle the global app-running flag from `scenePhase` transitions.
    static func markAppRunning(_ running: Bool) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(running, forKey: K.appRunning)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Persist the discovered speaker list for the widget configuration picker.
    static func writeDiscoveredSpeakers(_ speakers: [Speaker]) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let records = speakers.map {
            SpeakerRecord(host: $0.host, name: $0.name, platform: $0.identifier.platform.rawValue)
        }
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: K.discoveredSpeakers)
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

    private static func addKnownHost(_ host: String, in defaults: UserDefaults) {
        var hosts = (defaults.array(forKey: K.knownHosts) as? [String]) ?? []
        if !hosts.contains(host) {
            hosts.append(host)
            defaults.set(hosts, forKey: K.knownHosts)
        }
    }

    private static func removeKnownHost(_ host: String, in defaults: UserDefaults) {
        var hosts = (defaults.array(forKey: K.knownHosts) as? [String]) ?? []
        hosts.removeAll { $0 == host }
        defaults.set(hosts, forKey: K.knownHosts)
    }
}

/// Keys exposed so the widget extension can read them with the same names.
enum WidgetStateKeys {
    static let appRunning         = "widget_app_running"
    static let dataVersion        = "widget_data_version"
    static let knownHosts         = "widget_known_hosts"
    static let discoveredSpeakers = "widget_discovered_speakers"

    static func name(_ host: String)          -> String { "widget_speaker_\(host)_name" }
    static func trackTitle(_ host: String)    -> String { "widget_speaker_\(host)_track_title" }
    static func sourceName(_ host: String)    -> String { "widget_speaker_\(host)_source_name" }
    static func playbackState(_ host: String) -> String { "widget_speaker_\(host)_playback_state" }
    static func volume(_ host: String)        -> String { "widget_speaker_\(host)_volume" }
    static func muted(_ host: String)         -> String { "widget_speaker_\(host)_muted" }
    static func writtenAt(_ host: String)     -> String { "widget_speaker_\(host)_written_at" }
}

private typealias K = WidgetStateKeys
