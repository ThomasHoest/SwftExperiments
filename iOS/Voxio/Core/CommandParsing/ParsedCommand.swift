import Foundation

/// Structured output from the E-18 command parsing pipeline.
/// Produced by both `FoundationModelParser` and `TwoStageFallbackParser`;
/// consumed by the HomeView dispatch layer.
struct ParsedCommand: Codable, Equatable {
    let intent:             CommandIntent
    let favoriteName:       String?   // spoken favorite name for .playNamed
    let favoriteIndex:      Int?      // 1-based position for .playFavoriteByNumber
    let volumeValue:        Int?      // absolute target 0–100 for .setVolume
    let volumeDelta:        Int?      // relative step for .volumeUp/.volumeDown; nil = default
    let targetSpeakerName:  String?   // spoken target speaker name for .joinSpeaker
    let rawText:            String?   // preserved for .unknown

    init(
        intent:             CommandIntent,
        favoriteName:       String? = nil,
        favoriteIndex:      Int?    = nil,
        volumeValue:        Int?    = nil,
        volumeDelta:        Int?    = nil,
        targetSpeakerName:  String? = nil,
        rawText:            String? = nil
    ) {
        self.intent             = intent
        self.favoriteName       = favoriteName
        self.favoriteIndex      = favoriteIndex
        self.volumeValue        = volumeValue
        self.volumeDelta        = volumeDelta
        self.targetSpeakerName  = targetSpeakerName
        self.rawText            = rawText
    }

    static func unknown(_ text: String) -> ParsedCommand {
        ParsedCommand(intent: .unknown, rawText: text)
    }
}

enum CommandIntent: String, CaseIterable, Codable, Equatable {
    case playNamed              // "play Jazz Radio"
    case playFavoriteByNumber   // "play favorite one"
    case playDefault            // "play music" / "afspil musik"
    case listFavorites          // "what are my favorites?"
    case stop
    case pause
    case resume
    case setVolume      // "set volume to 50"
    case volumeUp       // "volume up [amount]"
    case volumeDown     // "volume down [amount]"
    case mute
    case unmute
    case joinSpeaker    // "join [speaker] to [target]"
    case leaveSpeaker   // "[speaker] leave group"
    case confirm        // "Yes" / "Ja"
    case cancel         // "No" / "Nej"
    case unknown

    // ── Broadcast intents ─────────────────────────────────────────────────────
    case stopAll        // "stop everything" / "stop alt"
    case pauseAll       // "pause all" / "pause alting"
    case resumeAll      // "resume all" / "genoptag alt"
    case volumeUpAll    // "volume up all [amount]" / "skru op for alt"
    case volumeDownAll  // "volume down all [amount]" / "skru ned for alt"
    case muteAll        // "mute all" / "slå alt fra"
    case unmuteAll      // "unmute all" / "slå alt til"
}

// Defined here (not in VoiceCommand.swift) so CommandIntent stays in the same compilation unit —
// VoiceCommand.swift is shared with VoxioWidget which does not compile CommandParsing files.
extension VoiceCommand {
    func toCommandIntent() -> CommandIntent {
        switch self {
        case .playFavorite:              return .playFavoriteByNumber
        case .playDefault:               return .playDefault
        case .listFavorites:             return .listFavorites
        case .stop:                      return .stop
        case .pause:                     return .pause
        case .resume:                    return .resume
        case .setVolume:                 return .setVolume
        case .adjustVolume(let d):       return d >= 0 ? .volumeUp : .volumeDown
        case .mute:                      return .mute
        case .unmute:                    return .unmute
        case .joinSpeaker:               return .joinSpeaker
        case .leaveSpeaker:              return .leaveSpeaker
        case .confirm:                   return .confirm
        case .cancel:                    return .cancel
        case .unknown:                   return .unknown
        case .stopAll:                   return .stopAll
        case .pauseAll:                  return .pauseAll
        case .resumeAll:                 return .resumeAll
        case .adjustVolumeAll(let d):    return d >= 0 ? .volumeUpAll : .volumeDownAll
        case .muteAll:                   return .muteAll
        case .unmuteAll:                 return .unmuteAll
        }
    }
}

extension ParsedCommand: CustomStringConvertible {
    var description: String {
        switch intent {
        case .playNamed:            return "playNamed(\"\(favoriteName ?? "")\")"
        case .playFavoriteByNumber: return "playFavoriteByNumber(\(favoriteIndex ?? 0))"
        case .playDefault:          return "playDefault"
        case .listFavorites: return "listFavorites"
        case .stop:          return "stop"
        case .pause:         return "pause"
        case .resume:        return "resume"
        case .setVolume:     return "setVolume(\(volumeValue ?? 0))"
        case .volumeUp:      return "volumeUp(\(volumeDelta.map { "+\($0)" } ?? "default"))"
        case .volumeDown:    return "volumeDown(\(volumeDelta.map { "-\($0)" } ?? "default"))"
        case .mute:          return "mute"
        case .unmute:        return "unmute"
        case .joinSpeaker:   return "joinSpeaker(\"\(targetSpeakerName ?? "")\")"
        case .leaveSpeaker:  return "leaveSpeaker"
        case .confirm:       return "confirm"
        case .cancel:        return "cancel"
        case .unknown:       return "unknown(\"\(rawText ?? "")\")"
        case .stopAll:       return "stopAll"
        case .pauseAll:      return "pauseAll"
        case .resumeAll:     return "resumeAll"
        case .volumeUpAll:   return "volumeUpAll(\(volumeDelta.map { "+\($0)" } ?? "default"))"
        case .volumeDownAll: return "volumeDownAll(\(volumeDelta.map { "-\($0)" } ?? "default"))"
        case .muteAll:       return "muteAll"
        case .unmuteAll:     return "unmuteAll"
        }
    }
}
