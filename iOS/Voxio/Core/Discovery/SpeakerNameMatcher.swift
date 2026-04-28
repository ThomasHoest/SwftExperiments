import Foundation

/// Matches the leading token(s) of a transcript against a list of known speakers
/// using case-insensitive prefix and Levenshtein fuzzy matching (distance ≤ 2).
struct SpeakerNameMatcher {

    /// Tries 1-, 2-, and 3-word prefixes of `words` against each speaker's name.
    /// - Returns: The best-matching speaker and the number of words consumed, or `nil`.
    func match(words: [String], in speakers: [Speaker]) -> (Speaker, tokensConsumed: Int)? {
        guard !speakers.isEmpty, !words.isEmpty else { return nil }

        var best: (speaker: Speaker, tokens: Int, distance: Int)?

        for tokenCount in 1...min(3, words.count) {
            let candidate = words.prefix(tokenCount).joined(separator: " ")
            for speaker in speakers {
                let d = levenshtein(candidate, speaker.name.lowercased())
                guard d <= 2 else { continue }
                if best == nil || d < best!.distance {
                    best = (speaker, tokenCount, d)
                }
            }
            // Exact match — no need to try more tokens
            if let b = best, b.distance == 0 { break }
        }

        return best.map { ($0.speaker, $0.tokens) }
    }

    // ── Levenshtein distance ──────────────────────────────────────────────────

    func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                dp[i][j] = a[i-1] == b[j-1]
                    ? dp[i-1][j-1]
                    : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            }
        }
        return dp[m][n]
    }
}
