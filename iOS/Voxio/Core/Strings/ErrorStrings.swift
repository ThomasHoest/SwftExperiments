import Foundation

/// Language-keyed spoken and display strings for every `AppError` case.
/// Strings match the exact wording in functional-spec-bo-voice-control v1.3.
struct ErrorStrings {
    var noSpeakerSpoken:    (_ available: [String]) -> String
    var speakerNotFound:    (_ spoken: String, _ available: [String]) -> String
    var favoriteNotFound:   (_ name: String, _ speaker: String, _ available: [String]) -> String
    var speakerUnreachable: (_ speaker: String) -> String
    var nothingPlaying:     (_ speaker: String) -> String
    var volumeAtLimit:      (_ speaker: String, _ atMax: Bool) -> String
    var pauseNotSupported:  (_ speaker: String) -> String
    var alreadyMuted:       (_ speaker: String) -> String
    var voiceNotRecognised: String
    var apiTimeout:         String

    static let english = ErrorStrings(
        noSpeakerSpoken: { available in
            let list = available.isEmpty ? "none found" : available.joined(separator: ", ")
            return "Please start your command with a speaker name. Available speakers are: \(list)"
        },
        speakerNotFound: { spoken, available in
            "\(spoken) was not found. Available speakers are: \(available.joined(separator: ", "))"
        },
        favoriteNotFound: { name, speaker, available in
            let list = available.isEmpty ? "none" : available.joined(separator: ", ")
            return "\(name) was not found on \(speaker). Available favorites are: \(list)"
        },
        speakerUnreachable: { speaker in
            "\(speaker) could not be reached. Please check the speaker is powered on and connected to the network"
        },
        nothingPlaying: { speaker in
            "\(speaker) is not currently playing anything"
        },
        volumeAtLimit: { speaker, atMax in
            "\(speaker) is already at \(atMax ? "maximum" : "minimum") volume"
        },
        pauseNotSupported: { speaker in
            "\(speaker) does not support pause for this source. Say \(speaker), stop to stop instead"
        },
        alreadyMuted: { speaker in
            "\(speaker) is already muted"
        },
        voiceNotRecognised: "Sorry, I didn't catch that. Please repeat your command",
        apiTimeout: "Could not reach the Bang & Olufsen service. Please try again"
    )

    static let danish = ErrorStrings(
        noSpeakerSpoken: { available in
            let list = available.isEmpty ? "ingen fundet" : available.joined(separator: ", ")
            return "Start din kommando med et højttalernavn. Tilgængelige højttalere er: \(list)"
        },
        speakerNotFound: { spoken, available in
            "\(spoken) blev ikke fundet. Tilgængelige højttalere er: \(available.joined(separator: ", "))"
        },
        favoriteNotFound: { name, speaker, available in
            let list = available.isEmpty ? "ingen" : available.joined(separator: ", ")
            return "\(name) blev ikke fundet på \(speaker). Tilgængelige favoritter er: \(list)"
        },
        speakerUnreachable: { speaker in
            "\(speaker) kunne ikke nås. Kontroller at højttaleren er tændt og forbundet til netværket"
        },
        nothingPlaying: { speaker in
            "\(speaker) afspiller ikke noget i øjeblikket"
        },
        volumeAtLimit: { speaker, atMax in
            "\(speaker) er allerede ved \(atMax ? "maksimal" : "minimal") lydstyrke"
        },
        pauseNotSupported: { speaker in
            "\(speaker) understøtter ikke pause for denne kilde. Sig \(speaker), stop for at stoppe i stedet"
        },
        alreadyMuted: { speaker in
            "\(speaker) er allerede slået fra"
        },
        voiceNotRecognised: "Undskyld, jeg forstod ikke det. Gentag venligst din kommando",
        apiTimeout: "Kunne ikke nå Bang & Olufsen servicen. Prøv venligst igen"
    )

    static func forLanguage(_ language: Language) -> ErrorStrings {
        language == .danish ? .danish : .english
    }
}
