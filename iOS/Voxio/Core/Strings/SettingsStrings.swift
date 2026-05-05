import Foundation

/// Language-keyed strings for the Settings, Learned Phrases, and Aliases screens.
struct SettingsStrings {

    // ── SettingsView ──────────────────────────────────────────────────────────
    var title: String
    var done: String
    var sectionVoiceControl: String
    var personalisation: String
    var aliases: String
    var learnedPhrases: String
    var sectionLanguage: String
    var languageEnglish: String
    var languageDanish: String
    var sectionPrivacy: String
    var telemetryToggle: String
    var telemetryFooter: String

    // ── LearnedPhrasesView ────────────────────────────────────────────────────
    var learnedPhrasesTitle: String
    var learnedPhrasesIntro: String
    var clearAll: String
    var clearAllAlertTitle: String
    var clearAllAlertMessage: String
    var cancel: String
    var delete: String
    var deleteAlertTitle: String
    private var _deleteAlertMessageTemplate: String      // "This will permanently remove \"%@\"."
    var emptyTitle: String
    var emptySubtitle: String
    var usedOnce: String
    private var _usedTimesTemplate: String               // "Used %lld times"

    func deleteAlertMessage(phrase: String) -> String {
        String(format: _deleteAlertMessageTemplate, phrase)
    }

    func usedTimes(count: Int64) -> String {
        String(format: _usedTimesTemplate, count)
    }

    // ── Command intent labels (used in LearnedPhrasesView rows) ───────────────
    func intentLabel(for intent: CommandIntent) -> String {
        switch intent {
        case .playNamed:            return _intentPlayNamed
        case .playFavoriteByNumber: return _intentPlayByNumber
        case .playDefault:          return _intentPlay
        case .setVolume:            return _intentSetVolume
        case .volumeUp:             return _intentVolumeUp
        case .volumeDown:           return _intentVolumeDown
        case .mute:                 return _intentMute
        case .unmute:               return _intentUnmute
        case .stop:                 return _intentStop
        case .pause:                return _intentPause
        case .resume:               return _intentResume
        case .joinSpeaker:          return _intentJoinSpeaker
        case .leaveSpeaker:         return _intentLeaveGroup
        case .listFavorites:        return _intentListFavourites
        case .confirm:              return _intentConfirm
        case .cancel:               return _intentCancel
        case .stopAll:              return _intentStopAll
        case .pauseAll:             return _intentPauseAll
        case .resumeAll:            return _intentResumeAll
        case .volumeUpAll:          return _intentVolumeUpAll
        case .volumeDownAll:        return _intentVolumeDownAll
        case .muteAll:              return _intentMuteAll
        case .unmuteAll:            return _intentUnmuteAll
        case .unknown:              return _intentUnknown
        }
    }

    private var _intentPlayNamed: String
    private var _intentPlayByNumber: String
    private var _intentPlay: String
    private var _intentSetVolume: String
    private var _intentVolumeUp: String
    private var _intentVolumeDown: String
    private var _intentMute: String
    private var _intentUnmute: String
    private var _intentStop: String
    private var _intentPause: String
    private var _intentResume: String
    private var _intentJoinSpeaker: String
    private var _intentLeaveGroup: String
    private var _intentListFavourites: String
    private var _intentConfirm: String
    private var _intentCancel: String
    private var _intentStopAll: String
    private var _intentPauseAll: String
    private var _intentResumeAll: String
    private var _intentVolumeUpAll: String
    private var _intentVolumeDownAll: String
    private var _intentMuteAll: String
    private var _intentUnmuteAll: String
    private var _intentUnknown: String

    // MARK: - Static instances

    static let english = SettingsStrings(
        title:                       "Settings",
        done:                        "Done",
        sectionVoiceControl:         "Voice control",
        personalisation:             "Personalisation",
        aliases:                     "Aliases",
        learnedPhrases:              "Learned phrases",
        sectionLanguage:             "Language",
        languageEnglish:             "English",
        languageDanish:              "Danish",
        sectionPrivacy:              "Privacy",
        telemetryToggle:             "Help improve Voxio",
        telemetryFooter:             "Sends anonymised voice command data to help improve recognition accuracy. No personal audio is stored.",
        learnedPhrasesTitle:         "Learned Phrases",
        learnedPhrasesIntro:         "Voxio remembers voice commands you confirm. These learned phrases help improve recognition accuracy for each speaker over time.",
        clearAll:                    "Clear all",
        clearAllAlertTitle:          "Clear all learned phrases?",
        clearAllAlertMessage:        "This will permanently remove all learned phrases. This cannot be undone.",
        cancel:                      "Cancel",
        delete:                      "Delete",
        deleteAlertTitle:            "Delete phrase?",
        _deleteAlertMessageTemplate: "This will permanently remove \"%@\".",
        emptyTitle:                  "No learned phrases yet",
        emptySubtitle:               "Voxio remembers commands you confirm. They'll appear here after you use voice control.",
        usedOnce:                    "Used once",
        _usedTimesTemplate:          "Used %lld times",
        _intentPlayNamed:            "Play favourite",
        _intentPlayByNumber:         "Play by number",
        _intentPlay:                 "Play",
        _intentSetVolume:            "Set volume",
        _intentVolumeUp:             "Volume up",
        _intentVolumeDown:           "Volume down",
        _intentMute:                 "Mute",
        _intentUnmute:               "Unmute",
        _intentStop:                 "Stop",
        _intentPause:                "Pause",
        _intentResume:               "Resume",
        _intentJoinSpeaker:          "Join speaker",
        _intentLeaveGroup:           "Leave group",
        _intentListFavourites:       "List favourites",
        _intentConfirm:              "Confirm",
        _intentCancel:               "Cancel",
        _intentStopAll:              "Stop all",
        _intentPauseAll:             "Pause all",
        _intentResumeAll:            "Resume all",
        _intentVolumeUpAll:          "Volume up all",
        _intentVolumeDownAll:        "Volume down all",
        _intentMuteAll:              "Mute all",
        _intentUnmuteAll:            "Unmute all",
        _intentUnknown:              "Unknown"
    )

    static let danish = SettingsStrings(
        title:                       "Indstillinger",
        done:                        "Færdig",
        sectionVoiceControl:         "Stemmekommandoer",
        personalisation:             "Personalisering",
        aliases:                     "Aliasser",
        learnedPhrases:              "Lærte sætninger",
        sectionLanguage:             "Sprog",
        languageEnglish:             "Engelsk",
        languageDanish:              "Dansk",
        sectionPrivacy:              "Privatliv",
        telemetryToggle:             "Hjælp med at forbedre Voxio",
        telemetryFooter:             "Sender anonymiserede stemmekommandodata for at forbedre genkendelsesnøjagtighed. Ingen personlig lyd gemmes.",
        learnedPhrasesTitle:         "Lærte sætninger",
        learnedPhrasesIntro:         "Voxio husker stemmekommandoer, du bekræfter. Disse lærte sætninger hjælper med at forbedre genkendelsesnøjagtigheden for hver højttaler over tid.",
        clearAll:                    "Ryd alt",
        clearAllAlertTitle:          "Ryd alle lærte sætninger?",
        clearAllAlertMessage:        "Dette sletter permanent alle lærte sætninger. Det kan ikke fortrydes.",
        cancel:                      "Annuller",
        delete:                      "Slet",
        deleteAlertTitle:            "Slet sætning?",
        _deleteAlertMessageTemplate: "Dette sletter permanent \"%@\".",
        emptyTitle:                  "Ingen lærte sætninger endnu",
        emptySubtitle:               "Voxio husker kommandoer, du bekræfter. De vises her, når du bruger stemmestyring.",
        usedOnce:                    "Brugt én gang",
        _usedTimesTemplate:          "Brugt %lld gange",
        _intentPlayNamed:            "Afspil favorit",
        _intentPlayByNumber:         "Afspil efter nummer",
        _intentPlay:                 "Afspil",
        _intentSetVolume:            "Indstil lydstyrke",
        _intentVolumeUp:             "Skru op",
        _intentVolumeDown:           "Skru ned",
        _intentMute:                 "Slå lyd fra",
        _intentUnmute:               "Slå lyd til",
        _intentStop:                 "Stop",
        _intentPause:                "Pause",
        _intentResume:               "Genoptag",
        _intentJoinSpeaker:          "Tilslut højttaler",
        _intentLeaveGroup:           "Forlad gruppe",
        _intentListFavourites:       "Vis favoritter",
        _intentConfirm:              "Bekræft",
        _intentCancel:               "Annuller",
        _intentStopAll:              "Stop alle",
        _intentPauseAll:             "Pause alle",
        _intentResumeAll:            "Genoptag alle",
        _intentVolumeUpAll:          "Skru op for alle",
        _intentVolumeDownAll:        "Skru ned for alle",
        _intentMuteAll:              "Slå lyd fra for alle",
        _intentUnmuteAll:            "Slå lyd til for alle",
        _intentUnknown:              "Ukendt"
    )

    static func forLanguage(_ language: Language) -> SettingsStrings {
        language == .danish ? .danish : .english
    }
}
