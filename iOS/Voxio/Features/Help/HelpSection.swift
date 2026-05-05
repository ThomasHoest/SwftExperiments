import Foundation

// MARK: — keep in sync with VoiceCommand

struct HelpRow {
    let actionEN: String
    let actionDA: String
    let phraseEN: String
    let phraseDA: String
}

struct HelpSection {
    let titleEN: String
    let titleDA: String
    let rows: [HelpRow]

    static func all(speakerA: String?, speakerB: String?) -> [HelpSection] {
        let a = speakerA ?? "[Speaker]"
        let b = speakerB ?? "[Speaker B]"
        return [singleSpeaker(speaker: a), grouping(speakerA: a, speakerB: b), systemActions]
    }

    // MARK: — Section 1: Single speaker (12 rows — US-65 Table 1)

    private static func singleSpeaker(speaker: String) -> HelpSection {
        HelpSection(
            titleEN: "Single speaker",
            titleDA: "Enkelt højttaler",
            rows: [
                HelpRow(
                    actionEN: "Play",
                    actionDA: "Afspil",
                    phraseEN: "\(speaker), play",
                    phraseDA: "\(speaker), afspil"
                ),
                HelpRow(
                    actionEN: "Pause",
                    actionDA: "Pause",
                    phraseEN: "\(speaker), pause",
                    phraseDA: "\(speaker), pause"
                ),
                HelpRow(
                    actionEN: "Stop",
                    actionDA: "Stop",
                    phraseEN: "\(speaker), stop",
                    phraseDA: "\(speaker), stop"
                ),
                HelpRow(
                    actionEN: "Resume",
                    actionDA: "Fortsæt",
                    phraseEN: "\(speaker), resume",
                    phraseDA: "\(speaker), fortsæt"
                ),
                HelpRow(
                    actionEN: "Volume",
                    actionDA: "Lydstyrke",
                    phraseEN: "\(speaker), volume 50",
                    phraseDA: "\(speaker), lydstyrke 50"
                ),
                HelpRow(
                    actionEN: "Volume up",
                    actionDA: "Skru op",
                    phraseEN: "\(speaker), volume up",
                    phraseDA: "\(speaker), skru op"
                ),
                HelpRow(
                    actionEN: "Volume up by",
                    actionDA: "Skru op med",
                    phraseEN: "\(speaker), volume up 20",
                    phraseDA: "\(speaker), skru op 20"
                ),
                HelpRow(
                    actionEN: "Volume down",
                    actionDA: "Skru ned",
                    phraseEN: "\(speaker), volume down",
                    phraseDA: "\(speaker), skru ned"
                ),
                HelpRow(
                    actionEN: "Mute",
                    actionDA: "Tavs",
                    phraseEN: "\(speaker), mute",
                    phraseDA: "\(speaker), tavs"
                ),
                HelpRow(
                    actionEN: "Unmute",
                    actionDA: "Lyd til",
                    phraseEN: "\(speaker), unmute",
                    phraseDA: "\(speaker), slå lyden til"
                ),
                HelpRow(
                    actionEN: "Play favourite",
                    actionDA: "Afspil favorit",
                    phraseEN: "\(speaker), play favorite one",
                    phraseDA: "\(speaker), afspil favorit et"
                ),
                HelpRow(
                    actionEN: "List favourites",
                    actionDA: "Vis favoritter",
                    phraseEN: "\(speaker), what are my favorites?",
                    phraseDA: "\(speaker), hvad er mine favoritter?"
                ),
            ]
        )
    }

    // MARK: — Section 2: Grouping (2 rows — US-65 Table 2)

    private static func grouping(speakerA: String, speakerB: String) -> HelpSection {
        HelpSection(
            titleEN: "Grouping",
            titleDA: "Gruppering",
            rows: [
                HelpRow(
                    actionEN: "Join",
                    actionDA: "Tilslut",
                    phraseEN: "\(speakerA), join \(speakerB)",
                    phraseDA: "\(speakerA), tilslut \(speakerB)"
                ),
                HelpRow(
                    actionEN: "Leave group",
                    actionDA: "Forlad gruppe",
                    phraseEN: "\(speakerA), leave the group",
                    phraseDA: "\(speakerA), forlad gruppen"
                ),
            ]
        )
    }

    // MARK: — Section 3: System actions / all speakers (7 rows — US-65 Table 3)

    private static var systemActions: HelpSection {
        HelpSection(
            titleEN: "All speakers",
            titleDA: "Alle højttalere",
            rows: [
                HelpRow(
                    actionEN: "Stop all",
                    actionDA: "Stop alle",
                    phraseEN: "stop everything",
                    phraseDA: "stop alt"
                ),
                HelpRow(
                    actionEN: "Pause all",
                    actionDA: "Pause alle",
                    phraseEN: "pause all",
                    phraseDA: "pause alle"
                ),
                HelpRow(
                    actionEN: "Resume all",
                    actionDA: "Genoptag alle",
                    phraseEN: "resume all",
                    phraseDA: "genoptag alt"
                ),
                HelpRow(
                    actionEN: "Volume down all",
                    actionDA: "Skru ned alle",
                    phraseEN: "volume down everywhere",
                    phraseDA: "skru ned overalt"
                ),
                HelpRow(
                    actionEN: "Volume up all",
                    actionDA: "Skru op alle",
                    phraseEN: "volume up everywhere",
                    phraseDA: "skru op overalt"
                ),
                HelpRow(
                    actionEN: "Mute all",
                    actionDA: "Mute alle",
                    phraseEN: "mute everything",
                    phraseDA: "mute alt"
                ),
                HelpRow(
                    actionEN: "Unmute all",
                    actionDA: "Unmute alle",
                    phraseEN: "unmute everything",
                    phraseDA: "unmute alle"
                ),
            ]
        )
    }
}
