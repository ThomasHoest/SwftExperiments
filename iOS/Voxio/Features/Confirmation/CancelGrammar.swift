import Foundation

/// T-2506 — Detects cancel intent in voice transcripts during an active countdown.
/// Does NOT route through CommandParserRouter — this is a fast, local match.
enum CancelGrammar {
    /// Cancel tokens recognised in both English and Danish.
    private static let cancelTokens: Set<String> = ["cancel", "no", "nej", "annuller"]

    /// Returns `true` if `transcript` contains a whole-word cancel token.
    /// Matching is case-insensitive. Tokens are delimited by whitespace or punctuation.
    static func matches(_ transcript: String) -> Bool {
        let words = transcript
            .lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines
                .union(.punctuationCharacters))
            .filter { !$0.isEmpty }
        return words.contains { cancelTokens.contains($0) }
    }
}
