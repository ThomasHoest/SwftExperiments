#if canImport(FoundationModels)
import FoundationModels
import Foundation

/// On-device semantic parser using Apple's Foundation Models framework.
/// Only instantiated when `SystemLanguageModel.availability == .available`
/// (requires A17 Pro / M1 chip, iOS 26+, Apple Intelligence enabled).
@available(iOS 26, *)
final class FoundationModelParser {

    // ── Internal Generable response type ─────────────────────────────────────

    @Generable
    struct LLMCommand {
        /// One of the CommandIntent raw values (e.g. "stop", "volumeUp").
        var intent: String
        /// Spoken favorite name when intent is playNamed.
        var favoriteName: String?
        /// 1-based favorite position (1–4) when intent is playFavoriteByNumber.
        var favoriteIndex: Int?
        /// Absolute volume level 0–100 when intent is setVolume.
        var volumeValue: Int?
        /// Relative volume step when intent is volumeUp or volumeDown.
        var volumeDelta: Int?
    }

    // ── State ─────────────────────────────────────────────────────────────────

    private var session: LanguageModelSession?
    private var speakerNames:    [String] = []
    private var activeSpeaker:   String   = ""
    private var favoriteNames:   [String] = []

    // ── Public API ────────────────────────────────────────────────────────────

    /// Updates the session context whenever the active speaker or favorites change.
    /// Creates a new session if none exists; updates instructions on an existing one.
    func updateContext(speakers: [String], activeSpeaker: String, favorites: [String]) {
        let contextChanged = speakers != speakerNames
            || activeSpeaker != self.activeSpeaker
            || favorites != favoriteNames
        guard contextChanged else { return }

        speakerNames      = speakers
        self.activeSpeaker = activeSpeaker
        favoriteNames     = favorites
        session           = makeSession()
        Log.verbose("[FoundationModelParser] context updated — speaker=\(activeSpeaker), favorites=\(favorites.count)")
    }

    /// Pre-warms the model with a no-op prompt so the first real command is fast.
    func warmUp() async {
        guard session == nil else { return }
        session = makeSession()
        _ = try? await session?.respond(to: "ping", generating: LLMCommand.self)
        Log.info("[FoundationModelParser] warmed up")
    }

    /// Parses a transcript string into a `ParsedCommand` (speaker context not required).
    func parse(_ remainder: String) async throws -> ParsedCommand {
        Log.info("[FoundationModelParser] parsing: \"\(remainder)\"")
        guard let session else {
            Log.info("[FoundationModelParser] no session — returning unknown")
            return .unknown(remainder)
        }

        let response = try await session.respond(to: remainder, generating: LLMCommand.self)
        let cmd = response.content
        let intent = CommandIntent(rawValue: cmd.intent) ?? .unknown

        let result = ParsedCommand(
            intent:        intent,
            favoriteName:  cmd.favoriteName,
            favoriteIndex: cmd.favoriteIndex,
            volumeValue:   cmd.volumeValue.map { max(0, min(100, $0)) },
            volumeDelta:   cmd.volumeDelta,
            rawText:       remainder
        )
        Log.info("[FoundationModelParser] \"\(remainder)\" → \(result)")
        return result
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private func makeSession() -> LanguageModelSession {
        let intents  = CommandIntent.allCases.map(\.rawValue).joined(separator: ", ")
        let speakers = speakerNames.isEmpty ? "none" : speakerNames.joined(separator: ", ")
        let favs     = favoriteNames.isEmpty ? "none" : favoriteNames.joined(separator: ", ")

        return LanguageModelSession(instructions: """
            You are a command parser for a Bang & Olufsen speaker voice control app.
            Your only job is to extract a structured command from a spoken utterance.
            Do not answer questions or generate explanations.

            Valid intents: \(intents)
            Available speakers: \(speakers)
            Active speaker: \(activeSpeaker)
            Favorites on \(activeSpeaker): \(favs)

            Rules:
            - Set intent to the closest match from the valid intents list.
            - For playNamed, set favoriteName to the closest match from the favorites list.
            - For playFavoriteByNumber, set favoriteIndex to the spoken ordinal (1 for "one"/"en"/"et", 2 for "two"/"to", 3 for "three"/"tre", 4 for "four"/"fire"). Danish trigger words include "start" in addition to "afspil"/"spil".
            - For setVolume, extract volumeValue (0–100). For volumeUp/volumeDown, extract
              volumeDelta if a number is spoken; omit it if no number is given.
            - "Yes", "yeah", "correct", "ja", "jo" → confirm.
            - "No", "cancel", "nej", "annuller" → cancel.
            - If no clear intent is recognised, use "unknown".
            """)
    }
}
#endif
