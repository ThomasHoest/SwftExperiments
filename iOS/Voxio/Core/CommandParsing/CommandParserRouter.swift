#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation

/// Routes a speaker-stripped transcript to the appropriate parser.
///
/// On Apple Intelligence-capable devices (iOS 26+) `FoundationModelParser`
/// is used. On all other devices — or if Apple Intelligence is unavailable —
/// `TwoStageFallbackParser` handles the request. Errors from
/// `FoundationModelParser` are NOT caught and re-routed; they propagate to
/// the call site, which surfaces a `.voiceNotRecognised` error.
final class CommandParserRouter {

    private let fallback = TwoStageFallbackParser()

    // Stored as Any to avoid @available restriction on stored properties.
    private var foundationParser: Any?

    init() {
#if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let model = SystemLanguageModel.default
            if model.availability == .available {
                foundationParser = FoundationModelParser()
                Log.info("[CommandParserRouter] Apple Intelligence available — FoundationModelParser active")
            } else {
                Log.info("[CommandParserRouter] Apple Intelligence unavailable — using TwoStageFallbackParser")
            }
        }
#else
        Log.info("[CommandParserRouter] FoundationModels not available — using TwoStageFallbackParser")
#endif
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Parses a speaker-stripped remainder string into a `ParsedCommand`.
    /// - Parameters:
    ///   - remainder: Transcript with the speaker name token already removed.
    ///   - addressedSpeaker: The resolved target speaker.
    ///   - allSpeakers: All discovered speaker names (LLM context).
    ///   - favoriteNames: Display names of the addressed speaker's favorites (LLM context).
    func parse(
        _ remainder: String,
        addressedSpeaker: Speaker,
        allSpeakers:   [String] = [],
        favoriteNames: [String] = []
    ) async -> ParsedCommand {
#if canImport(FoundationModels)
        if #available(iOS 26, *), let fp = foundationParser as? FoundationModelParser {
            fp.updateContext(
                speakers:      allSpeakers,
                activeSpeaker: addressedSpeaker.name,
                favorites:     favoriteNames
            )
            if let result = try? await fp.parse(remainder, speaker: addressedSpeaker) {
                return result
            }
            Log.info("[CommandParserRouter] FoundationModel failed — falling back to TwoStageFallbackParser")
        }
#endif
        return fallback.parse(remainder)
    }

    /// Pre-warms the Foundation Models session on launch. No-op on unsupported devices.
    func warmUp() async {
#if canImport(FoundationModels)
        if #available(iOS 26, *), let fp = foundationParser as? FoundationModelParser {
            await fp.warmUp()
        }
#endif
    }
}
