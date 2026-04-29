#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation

/// Routes a speaker-stripped transcript to the appropriate parser.
///
/// On Apple Intelligence-capable devices (iOS 26+) `FoundationModelParser`
/// is used. On all other devices — or if Apple Intelligence is unavailable —
/// `TwoStageFallbackParser` handles the request.
final class CommandParserRouter {

    // Internal so extensions in sibling files can access them.
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

    /// Parses a speaker-stripped remainder string into a `ParsedCommand`.
    func parse(
        _ remainder: String,
        addressedSpeaker: Speaker,
        allSpeakers:   [String] = [],
        favoriteNames: [String] = []
    ) async -> ParsedCommand {
        Log.info("[CommandParserRouter] parsing: \"\(remainder)\" for speaker: \(addressedSpeaker.name)")
#if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if let result = await tryFoundationModel(
                remainder, speaker: addressedSpeaker,
                allSpeakers: allSpeakers, favoriteNames: favoriteNames
            ) { return result }
        }
#endif
        return parseFallback(remainder)
    }

    /// Pre-warms the Foundation Models session on launch. No-op on unsupported devices.
    func warmUp() async {
#if canImport(FoundationModels)
        if #available(iOS 26, *) { await warmUpFoundationModel() }
#endif
    }
}
