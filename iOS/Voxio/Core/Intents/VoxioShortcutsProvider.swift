import AppIntents

struct VoxioShortcutsProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlaybackToggleIntent(),
            phrases: [
                "Play \(.applicationName)",
                "Afspil \(.applicationName)",
                "Pause \(.applicationName)",
                "Sæt \(.applicationName) på pause"
            ],
            shortTitle: "Play/Pause",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: MuteIntent(),
            phrases: [
                "Mute \(.applicationName)",
                "Slå \(.applicationName) fra"
            ],
            shortTitle: "Mute",
            systemImageName: "speaker.slash.fill"
        )
        AppShortcut(
            intent: AdjustVolumeIntent(),
            phrases: [
                "Turn up the volume in \(.applicationName)",
                "Skru op for lyden i \(.applicationName)",
                "Turn down the volume in \(.applicationName)",
                "Skru ned for lyden i \(.applicationName)"
            ],
            shortTitle: "Adjust Volume",
            systemImageName: "speaker.wave.2.fill"
        )
        AppShortcut(
            intent: JoinSpeakerIntent(),
            phrases: [
                "Join speakers in \(.applicationName)",
                "Saml højttalere i \(.applicationName)"
            ],
            shortTitle: "Join Speakers",
            systemImageName: "person.2.fill"
        )
        AppShortcut(
            intent: LeaveSpeakerIntent(),
            phrases: [
                "Leave group in \(.applicationName)",
                "Forlad gruppe i \(.applicationName)"
            ],
            shortTitle: "Leave Group",
            systemImageName: "person.fill.xmark"
        )
    }
}
