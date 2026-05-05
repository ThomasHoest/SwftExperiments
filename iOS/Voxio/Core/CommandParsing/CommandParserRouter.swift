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
    private let personalisationParser: PersonalisationParser

    init(personalisationStore: PersonalisationStore) {
        personalisationParser = PersonalisationParser(store: personalisationStore)
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
    /// Tier 0 personalisation (alias + confirmed-command) runs first — a hit short-circuits immediately.
    /// Stage 1 regex runs next on all devices — if it matches, returns without touching Foundation Models.
    /// Unmatched utterances proceed to Tier 1 (Foundation Models) → Tier 2 (NLModel) → Tier 3 (regex full pass).
    func parse(_ transcript: String, speakerId: String) async -> VoiceCommand {
        Log.info("[CommandParserRouter] parsing: \"\(transcript)\"")
        let text = transcript.trimmingCharacters(in: .whitespaces).lowercased()
        if let personalised = personalisationParser.parse(text, speakerId: speakerId) {
            let result = toVoiceCommand(personalised)
            Log.info("[CommandParserRouter] result: \(result) (PersonalisationTier)")
            return result
        }
        if let fast = fallback.parseStage1(text, raw: transcript) {
            let result = toVoiceCommand(fast)
            Log.info("[CommandParserRouter] result: \(result) (Stage1-fast)")
            return result
        }
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
        case .joinSpeaker:          return .joinSpeaker(targetName: parsed.targetSpeakerName ?? "")
        case .leaveSpeaker:         return .leaveSpeaker
        case .confirm:              return .confirm
        case .cancel:               return .cancel
        case .unknown:              return .unknown(parsed.rawText ?? "")
        case .stopAll:              return .stopAll
        case .pauseAll:             return .pauseAll
        case .resumeAll:            return .resumeAll
        case .volumeUpAll:          return .adjustVolumeAll(+(parsed.volumeDelta ?? 10))
        case .volumeDownAll:        return .adjustVolumeAll(-(parsed.volumeDelta ?? 10))
        case .muteAll:              return .muteAll
        case .unmuteAll:            return .unmuteAll
        }
    }
}
