import Foundation

/// Structured output from the E-18 command parsing pipeline.
/// Produced by both `FoundationModelParser` and `TwoStageFallbackParser`;
/// consumed by the HomeView dispatch layer.
struct ParsedCommand: Codable, Equatable {
    let intent:       CommandIntent
    let favoriteName: String?   // spoken favorite name for .playNamed
    let volumeValue:  Int?      // absolute target 0–100 for .setVolume
    let volumeDelta:  Int?      // relative step for .volumeUp/.volumeDown; nil = default
    let rawText:      String?   // preserved for .unknown

    init(
        intent:       CommandIntent,
        favoriteName: String? = nil,
        volumeValue:  Int?    = nil,
        volumeDelta:  Int?    = nil,
        rawText:      String? = nil
    ) {
        self.intent       = intent
        self.favoriteName = favoriteName
        self.volumeValue  = volumeValue
        self.volumeDelta  = volumeDelta
        self.rawText      = rawText
    }

    static func unknown(_ text: String) -> ParsedCommand {
        ParsedCommand(intent: .unknown, rawText: text)
    }
}

enum CommandIntent: String, CaseIterable, Codable, Equatable {
    case playNamed      // "play Jazz Radio"
    case playDefault    // "play music" / "afspil musik"
    case listFavorites  // "what are my favorites?"
    case stop
    case pause
    case resume
    case setVolume      // "set volume to 50"
    case volumeUp       // "volume up [amount]"
    case volumeDown     // "volume down [amount]"
    case mute
    case unmute
    case confirm        // "Yes" / "Ja"
    case cancel         // "No" / "Nej"
    case unknown
}

extension ParsedCommand: CustomStringConvertible {
    var description: String {
        switch intent {
        case .playNamed:     return "playNamed(\"\(favoriteName ?? "")\")"
        case .playDefault:   return "playDefault"
        case .listFavorites: return "listFavorites"
        case .stop:          return "stop"
        case .pause:         return "pause"
        case .resume:        return "resume"
        case .setVolume:     return "setVolume(\(volumeValue ?? 0))"
        case .volumeUp:      return "volumeUp(\(volumeDelta.map { "+\($0)" } ?? "default"))"
        case .volumeDown:    return "volumeDown(\(volumeDelta.map { "-\($0)" } ?? "default"))"
        case .mute:          return "mute"
        case .unmute:        return "unmute"
        case .confirm:       return "confirm"
        case .cancel:        return "cancel"
        case .unknown:       return "unknown(\"\(rawText ?? "")\")"
        }
    }
}
