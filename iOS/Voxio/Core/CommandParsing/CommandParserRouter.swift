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
    private var personalisationParser: PersonalisationParser
    private(set) var lastParserPath: String?

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
        let t0 = Date()
        let text = transcript.trimmingCharacters(in: .whitespaces).lowercased()

        let tPers = Date()
        if let personalised = personalisationParser.parse(text, speakerId: speakerId) {
            let result = toVoiceCommand(personalised)
            let path = personalisationParser.lastPath ?? "PersonalisationAlias"
            Log.info("[CommandParserRouter] result: \(result) (\(path)) [pers:\(ms(tPers))ms total:\(ms(t0))ms]")
            lastParserPath = path
            return result
        }
        let persMs = ms(tPers)

        let tKw = Date()
        if let fast = fallback.parseStage1(text, raw: transcript) {
            let result = toVoiceCommand(fast)
            Log.info("[CommandParserRouter] result: \(result) (KeywordRegex) [pers:\(persMs)ms kw:\(ms(tKw))ms total:\(ms(t0))ms]")
            lastParserPath = "KeywordRegex"
            return result
        }
        let kwMs = ms(tKw)

#if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let tFM = Date()
            if let result = await tryFoundationModel(transcript) {
                Log.info("[CommandParserRouter] result: \(result) (FoundationModels) [pers:\(persMs)ms kw:\(kwMs)ms fm:\(ms(tFM))ms total:\(ms(t0))ms]")
                lastParserPath = "FoundationModels"
                return result
            }
            let fmMs = ms(tFM)
            let tNL = Date()
            let fallbackResult = parseFallback(transcript)
            Log.info("[Timing][CommandParserRouter] pers:\(persMs)ms kw:\(kwMs)ms fm:\(fmMs)ms nl:\(ms(tNL))ms total:\(ms(t0))ms")
            lastParserPath = "NLModel"
            return fallbackResult
        }
#endif
        let tNL = Date()
        let fallbackResult = parseFallback(transcript)
        Log.info("[Timing][CommandParserRouter] pers:\(persMs)ms kw:\(kwMs)ms nl:\(ms(tNL))ms total:\(ms(t0))ms")
        lastParserPath = "NLModel"
        return fallbackResult
    }

    private func ms(_ start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }

    /// Returns the broadcast `VoiceCommand` if `text` matches a Stage 1 broadcast pattern,
    /// without running speaker resolution or personalisation. Called before `discovery.resolve()`
    /// in HomeView so SpeakerMatcher cannot consume words from broadcast phrases.
    func parseBroadcast(_ text: String) -> VoiceCommand? {
        let lower = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard let parsed = fallback.parseStage1(lower, raw: text) else { return nil }
        let cmd = toVoiceCommand(parsed)
        switch cmd {
        case .stopAll, .pauseAll, .resumeAll, .adjustVolumeAll, .muteAll, .unmuteAll:
            return cmd
        default:
            return nil
        }
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
