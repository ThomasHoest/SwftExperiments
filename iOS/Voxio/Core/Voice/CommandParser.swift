import Foundation

/// Parses a raw speech transcription string into a typed ``VoiceCommand``.
///
/// The parser operates on the normalised (lowercased, trimmed) transcript.
/// Speaker-name stripping is handled upstream (E-04); this type receives
/// the portion of the transcript that follows the speaker token.
/// Both English and Danish keywords are supported; the active language
/// is supplied at init so the correct number-word table is used.
struct CommandParser {

    // ── T-0307: default volume step when no number is spoken ──────────────────
    private static let defaultVolumeStep = 10

    // ── T-0306 / T-1703,T-1704: spoken number words per language ─────────────
    private static let numberWordsEN: [String: Int] = ["one": 1, "two": 2, "three": 3, "four": 4]
    private static let numberWordsDA: [String: Int] = ["en": 1,  "to": 2,  "tre": 3,  "fire": 4]

    private let language: Language
    private let numberWords: [String: Int]

    init(language: Language = LanguageService.shared.activeLanguage) {
        self.language = language
        numberWords = (language == .danish) ? CommandParser.numberWordsDA : CommandParser.numberWordsEN
    }

    func parse(_ transcript: String) -> VoiceCommand {
        let raw   = transcript.trimmingCharacters(in: .whitespaces).lowercased()
        let words = raw.split(separator: " ").map(String.init)
        guard !words.isEmpty else {
            Log.info("[CommandParser] empty transcript → unknown")
            return .unknown(transcript)
        }

        Log.verbose("[CommandParser] [\(language.localeIdentifier)] input: \"\(raw)\" words=\(words)")

        if let cmd = parsePlayFavorite(words)     { Log.info("[CommandParser] → \(cmd)"); return cmd }
        if let cmd = parseListFavorites(raw)       { Log.info("[CommandParser] → \(cmd)"); return cmd }
        if let cmd = parseConfirmCancel(words)    { Log.info("[CommandParser] → \(cmd)"); return cmd }
        if let cmd = parseVolume(words, raw: raw) { Log.info("[CommandParser] → \(cmd)"); return cmd }
        if let cmd = parseSimple(words, raw: raw) { Log.info("[CommandParser] → \(cmd)"); return cmd }
        if words.contains("play") || words.contains("afspil") || words.contains("spil") {
            Log.info("[CommandParser] → playDefault (bare play fallback)")
            return .playDefault
        }

        Log.info("[CommandParser] → unknown(\"\(transcript)\")")
        return .unknown(transcript)
    }

    // ── T-0306 / T-1703 ───────────────────────────────────────────────────────

    /// Recognises:
    /// EN: "play favorite [one|two|three|four]"
    /// DA: "afspil favorit [en|to|tre|fire]" / "spil favorit [en|to|tre|fire]"
    private func parsePlayFavorite(_ words: [String]) -> VoiceCommand? {
        let playTriggers     = ["play", "afspil", "spil"]
        let favoriteTriggers = ["favorite", "favourite", "favorit"]

        guard words.count >= 3,
              playTriggers.contains(words[0]),
              favoriteTriggers.contains(words[1]),
              let index = numberWords[words[2]]
        else { return nil }
        return .playFavorite(index: index)
    }

    // ── T-0308 (list) / T-1703 ────────────────────────────────────────────────

    private func parseListFavorites(_ raw: String) -> VoiceCommand? {
        let triggers = [
            // English
            "list favorite", "list favourite",
            "show favorite", "show favourite",
            "what are my favorite", "what are my favourite",
            // Danish
            "list favoritter", "vis favoritter",
            "hvad er mine favoritter",
        ]
        return triggers.contains(where: { raw.hasPrefix($0) }) ? .listFavorites : nil
    }

    // ── T-0309 / T-1704 ───────────────────────────────────────────────────────

    private func parseConfirmCancel(_ words: [String]) -> VoiceCommand? {
        let confirms = ["yes", "yeah", "yep", "correct", "sure", "okay", "ok",
                        "ja", "jo"]
        let cancels  = ["no", "nope", "cancel", "nevermind", "never",
                        "nej", "annuller"]

        if let first = words.first {
            if confirms.contains(first) { return .confirm }
            if cancels.contains(first)  { return .cancel  }
        }
        return nil
    }

    // ── T-0307 / T-1703 ───────────────────────────────────────────────────────

    private func parseVolume(_ words: [String], raw: String) -> VoiceCommand? {
        let hasVolume = words.contains("volume") || words.contains("vol")
                     || words.contains("lydstyrke")
        let number    = extractNumber(from: words)

        let upKeywords   = ["louder", "higher", "increase", "højere"]
        let downKeywords = ["quieter", "softer", "lower", "decrease", "lavere"]

        // "skru op [N]" / "skru ned [N]"
        let isSkruOp  = words.first == "skru" && words.dropFirst().first == "op"
        let isSkruNed = words.first == "skru" && words.dropFirst().first == "ned"

        let isUp   = (hasVolume && (words.contains("up") || words.contains("op")))
                     || upKeywords.contains(where: { words.first == $0 })
                     || isSkruOp
        let isDown = (hasVolume && (words.contains("down") || words.contains("ned")))
                     || downKeywords.contains(where: { words.first == $0 })
                     || isSkruNed

        if isUp   { return .adjustVolume(+(number ?? CommandParser.defaultVolumeStep)) }
        if isDown { return .adjustVolume(-(number ?? CommandParser.defaultVolumeStep)) }

        // Absolute — requires a number and a volume keyword.
        if hasVolume, let n = number {
            return .setVolume(max(0, min(100, n)))
        }

        // Bare direction + number: "up 20" / "down 10" / "op 20" / "ned 10"
        if let n = number {
            if words.first == "up"   || words.first == "op"  { return .adjustVolume(+n) }
            if words.first == "down" || words.first == "ned" { return .adjustVolume(-n) }
        }

        return nil
    }

    // ── T-0308 / T-1703 ───────────────────────────────────────────────────────

    private func parseSimple(_ words: [String], raw: String) -> VoiceCommand? {
        if words.contains("stop")                                                            { return .stop   }
        if words.contains("pause")                                                           { return .pause  }
        if words.contains("resume") || words.contains("continue")
            || words.contains("fortsæt") || words.contains("genoptag")                      { return .resume }
        if raw.contains("unmute") || raw.contains("un mute")
            || raw.contains("slå lyden til")                                                { return .unmute }
        if words.contains("mute") || raw.contains("slå lyden fra")
            || words.contains("tavs")                                                        { return .mute   }
        return nil
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private func extractNumber(from words: [String]) -> Int? {
        words.compactMap { Int($0) }.first
    }
}
