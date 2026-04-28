import Foundation

/// Parses a raw speech transcription string into a typed ``VoiceCommand``.
///
/// The parser operates on the normalised (lowercased, trimmed) transcript.
/// Speaker-name stripping is handled upstream (E-04); this type receives
/// the portion of the transcript that follows the speaker token.
struct CommandParser {

    // ── T-0306: spoken number words for play-favorite ─────────────────────────
    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4
    ]

    // ── T-0307: default volume step when no number is spoken ──────────────────
    private static let defaultVolumeStep = 10

    func parse(_ transcript: String) -> VoiceCommand {
        let raw   = transcript.trimmingCharacters(in: .whitespaces).lowercased()
        let words = raw.split(separator: " ").map(String.init)
        guard !words.isEmpty else {
            Log.info("[CommandParser] empty transcript → unknown")
            return .unknown(transcript)
        }

        Log.verbose("[CommandParser] input: \"\(raw)\" words=\(words)")

        // Evaluation order matters — more specific patterns first.
        if let cmd = parsePlayFavorite(words)     { Log.info("[CommandParser] → \(cmd)"); return cmd }
        if let cmd = parseListFavorites(raw)       { Log.info("[CommandParser] → \(cmd)"); return cmd }
        if let cmd = parseConfirmCancel(words)    { Log.info("[CommandParser] → \(cmd)"); return cmd }
        if let cmd = parseVolume(words, raw: raw) { Log.info("[CommandParser] → \(cmd)"); return cmd }
        if let cmd = parseSimple(words, raw: raw) { Log.info("[CommandParser] → \(cmd)"); return cmd }
        if words.contains("play") {
            Log.info("[CommandParser] → playDefault (bare 'play' fallback)")
            return .playDefault
        }

        Log.info("[CommandParser] → unknown(\"\(transcript)\")")
        return .unknown(transcript)
    }

    // ── T-0306 ─────────────────────────────────────────────────────────────────

    /// Recognises "play favorite [one|two|three|four]".
    /// Digit variants ("play favorite 1") intentionally fall through to `.unknown`.
    private func parsePlayFavorite(_ words: [String]) -> VoiceCommand? {
        guard words.count >= 3,
              words[0] == "play",
              words[1] == "favorite" || words[1] == "favourite",
              let index = CommandParser.numberWords[words[2]]
        else { return nil }
        return .playFavorite(index: index)
    }

    // ── T-0308 (list) ──────────────────────────────────────────────────────────

    private func parseListFavorites(_ raw: String) -> VoiceCommand? {
        let triggers = ["list favorite", "list favourite",
                        "show favorite", "show favourite",
                        "what are my favorite", "what are my favourite"]
        return triggers.contains(where: { raw.hasPrefix($0) }) ? .listFavorites : nil
    }

    // ── T-0309 ─────────────────────────────────────────────────────────────────

    private func parseConfirmCancel(_ words: [String]) -> VoiceCommand? {
        let confirms = ["yes", "yeah", "yep", "correct", "sure", "okay", "ok"]
        let cancels  = ["no", "nope", "cancel", "nevermind", "never"]

        if let first = words.first {
            if confirms.contains(first) { return .confirm }
            if cancels.contains(first)  { return .cancel  }
        }
        return nil
    }

    // ── T-0307 ─────────────────────────────────────────────────────────────────

    private func parseVolume(_ words: [String], raw: String) -> VoiceCommand? {
        let hasVolume = words.contains("volume") || words.contains("vol")
        let number    = extractNumber(from: words)

        // Relative — direction words take priority over any number present.
        let upKeywords   = ["louder", "higher", "increase"]
        let downKeywords = ["quieter", "softer", "lower", "decrease"]

        let isUp   = hasVolume && (words.contains("up") || words.contains("higher"))
                     || upKeywords.contains(where: { words.first == $0 })
        let isDown = hasVolume && (words.contains("down") || words.contains("lower"))
                     || downKeywords.contains(where: { words.first == $0 })

        if isUp   { return .adjustVolume(+(number ?? CommandParser.defaultVolumeStep)) }
        if isDown { return .adjustVolume(-(number ?? CommandParser.defaultVolumeStep)) }

        // Absolute — requires a number and either "set"/"to" or bare "volume N".
        if hasVolume, let n = number {
            let clamped = max(0, min(100, n))
            return .setVolume(clamped)
        }

        // Relative without "volume" keyword: "up 20" / "down 10"
        if let n = number {
            if words.first == "up"   { return .adjustVolume(+n) }
            if words.first == "down" { return .adjustVolume(-n) }
        }

        return nil
    }

    // ── T-0308 ─────────────────────────────────────────────────────────────────

    private func parseSimple(_ words: [String], raw: String) -> VoiceCommand? {
        if words.contains("stop")                                    { return .stop    }
        if words.contains("pause")                                   { return .pause   }
        if words.contains("resume") || words.contains("continue")    { return .resume  }
        if raw.contains("unmute") || raw.contains("un mute")        { return .unmute  }
        if words.contains("mute")                                    { return .mute    }
        return nil
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private func extractNumber(from words: [String]) -> Int? {
        words.compactMap { Int($0) }.first
    }
}
