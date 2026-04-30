#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation

/// Routes a speaker-stripped transcript through a three-tier parsing pipeline,
/// returning a `VoiceCommand`.
///
/// Tier 1: Foundation Models (A17 Pro+, Apple Intelligence required).
/// Tier 2: NLModel intent classifier (all devices — primary floor).
/// Tier 3: Keyword/regex `CommandParser` (deterministic safety net).
final class CommandParserRouter {

    let fallback = TwoStageFallbackParser()
    // Stored as Any to avoid @available restriction on stored properties.
    var foundationParser: Any?

    init() {
#if canImport(FoundationModels)
        if #available(iOS 26, *) {
            foundationParser = makeFoundationParser()
        }
#else
        Log.info("[CommandParserRouter] FoundationModels not available — using TwoStageFallbackParser")
#endif
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Parses a transcript string into a `VoiceCommand`.
    /// Tries Tier 1 → Tier 2 → Tier 3 in order, returning the first confident result.
    func parse(_ transcript: String) async -> VoiceCommand {
        Log.info("[CommandParserRouter] parsing: \"\(transcript)\"")
#if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if let result = await tryFoundationModel(transcript) { return result }
        }
#endif
        return parseFallback(transcript)
    }

    /// Pre-warms the Foundation Models session on launch. No-op on unsupported devices.
    func warmUp() async {
#if canImport(FoundationModels)
        if #available(iOS 26, *) { await warmUpFoundationModel() }
#endif
    }

    // ── ParsedCommand → VoiceCommand ─────────────────────────────────────────

    func toVoiceCommand(_ parsed: ParsedCommand) -> VoiceCommand {
        switch parsed.intent {
        case .playFavoriteByNumber: return .playFavorite(index: parsed.favoriteIndex ?? 1)
        case .playNamed:            return .playDefault
        case .playDefault:          return .playDefault
        case .listFavorites:        return .listFavorites
        case .stop:                 return .stop
        case .pause:                return .pause
        case .resume:               return .resume
        case .setVolume:            return .setVolume(parsed.volumeValue ?? 50)
        case .volumeUp:             return .adjustVolume(+(parsed.volumeDelta ?? 10))
        case .volumeDown:           return .adjustVolume(-(parsed.volumeDelta ?? 10))
        case .mute:                 return .mute
        case .unmute:               return .unmute
        case .confirm:              return .confirm
        case .cancel:               return .cancel
        case .unknown:              return .unknown(parsed.rawText ?? "")
        }
    }
}
