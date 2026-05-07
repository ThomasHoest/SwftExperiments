import Foundation

/// Scrubs personally-identifiable or environment-specific data from a log line
/// before it leaves the device. Four ordered rules are applied in sequence.
public struct LogAnonymiser {

    // MARK: - Compiled regexes (allocated once, reused per call)

    private static let ipv4Regex: NSRegularExpression = {
        // Matches bare IPv4 addresses: 1.2.3.4 through 999.999.999.999
        try! NSRegularExpression(
            pattern: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#,
            options: []
        )
    }()

    private static let uuidRegex: NSRegularExpression = {
        // RFC-4122 UUID, case-insensitive
        try! NSRegularExpression(
            pattern: #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#,
            options: .caseInsensitive
        )
    }()

    private static let jidRegex: NSRegularExpression = {
        // Tokens containing ".jid." between alphanumeric prefix and dotted suffix
        try! NSRegularExpression(
            pattern: #"\b[A-Za-z0-9]+\.jid\.[A-Za-z0-9.-]+\b"#,
            options: []
        )
    }()

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Applies four ordered anonymisation rules and returns the scrubbed line.
    public func anonymise(_ line: String) -> String {
        var result = line

        // Rule 1 — IPv4 addresses
        result = Self.ipv4Regex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "[IP]"
        )

        // Rule 2 — UUIDs
        result = Self.uuidRegex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "[UUID]"
        )

        // Rule 3 — JID strings
        result = Self.jidRegex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "[JID]"
        )

        // Rule 4 — Transcription content
        // Strip everything after "[CommandParserRouter] parsing:" (inclusive of trailing
        // whitespace and quoted text) and append the sentinel token.
        let marker = "[CommandParserRouter] parsing:"
        if let markerRange = result.range(of: marker) {
            let prefix = String(result[result.startIndex ..< markerRange.upperBound])
            result = prefix + " [TRANSCRIPTION]"
        }

        return result
    }
}
