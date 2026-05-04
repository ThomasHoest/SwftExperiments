import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration intent (long-press tile → speaker picker)

struct VoxioControlConfigurationIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Configure Voxio Control"
    static var description = IntentDescription("Choose which B&O speaker this control targets.")

    @Parameter(title: "Speaker", default: WidgetSpeakerEntity(id: "auto", name: "Automatic (most recent)"))
    var speakerPicker: WidgetSpeakerEntity?
}

// MARK: - Value the controls render against

struct VoxioControlValue {
    let host: String?
    let speakerName: String
    let isPlaying: Bool
    let isMuted: Bool
    let appRunning: Bool

    static let placeholder = VoxioControlValue(
        host: nil, speakerName: "Voxio", isPlaying: false, isMuted: false, appRunning: false
    )
}

// MARK: - Value provider — reuses VoxioWidgetProvider's selection model

struct VoxioControlValueProvider: AppIntentControlValueProvider {
    private static let suiteName = "group.T-Creative.Voxio"
    private static let dataVersion = 2

    func previewValue(configuration: VoxioControlConfigurationIntent) -> VoxioControlValue {
        .placeholder
    }

    func currentValue(configuration: VoxioControlConfigurationIntent) async throws -> VoxioControlValue {
        guard let defaults = UserDefaults(suiteName: Self.suiteName),
              defaults.integer(forKey: WidgetStateKeys.dataVersion) == Self.dataVersion
        else { return .placeholder }

        let configured = configuration.speakerPicker?.id
        let host: String
        if let configured, configured != "auto" {
            host = configured
        } else if let auto = pickAutoHost(in: defaults) {
            host = auto
        } else {
            return .placeholder
        }

        let name  = defaults.string(forKey: WidgetStateKeys.name(host)) ?? "Voxio"
        let state = defaults.string(forKey: WidgetStateKeys.playbackState(host)) ?? "stopped"
        return VoxioControlValue(
            host:        host,
            speakerName: name,
            isPlaying:   state == "playing",
            isMuted:     defaults.bool(forKey: WidgetStateKeys.muted(host)),
            appRunning:  defaults.bool(forKey: WidgetStateKeys.appRunning)
        )
    }

    /// Same priority as VoxioWidgetProvider.pickAutoHost: any playing → most recent; else most recent overall.
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

// MARK: - Play / Pause control

struct VoxioPlayPauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: "VoxioPlayPauseControl",
            provider: VoxioControlValueProvider()
        ) { value in
            ControlWidgetButton(action: playbackToggle(host: value.host)) {
                Label(
                    value.isPlaying ? "Pause" : "Play",
                    systemImage: value.isPlaying ? "pause.fill" : "play.fill"
                )
            }
            .tint(value.isPlaying ? BeoColor.accent : nil)
            .disabled(!value.appRunning)
        }
        .displayName("Voxio Play/Pause")
        .description("Play or pause your B&O speaker.")
    }

    private func playbackToggle(host: String?) -> PlaybackToggleIntent {
        let intent = PlaybackToggleIntent()
        intent.targetHost = host
        return intent
    }
}

// MARK: - Mute control

struct VoxioMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: "VoxioMuteControl",
            provider: VoxioControlValueProvider()
        ) { value in
            ControlWidgetButton(action: muteToggle(host: value.host)) {
                Label(
                    value.isMuted ? "Muted" : "Mute",
                    systemImage: value.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                )
            }
            .disabled(!value.appRunning)
        }
        .displayName("Voxio Mute")
        .description("Mute or unmute your B&O speaker.")
    }

    private func muteToggle(host: String?) -> MuteIntent {
        let intent = MuteIntent()
        intent.targetHost = host
        return intent
    }
}
