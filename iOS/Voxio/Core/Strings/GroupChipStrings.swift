import Foundation

/// Language-keyed strings for the session card group chip row (E-53).
struct GroupChipStrings {
    // ── Member chip accessibility label ──────────────────────────────────────
    /// "Also playing" prefix for each member chip's accessibility label.
    /// Full label: "\(alsoPlaying): \(speakerName)"
    var alsoPlaying: String

    // ── Overflow chip display label ───────────────────────────────────────────
    /// Format string for the overflow chip label. Use String(format:, N) at the call site.
    /// English: "+%d more"  Danish: "+%d flere"
    var overflowFormat: String

    // ── Overflow chip accessibility label ─────────────────────────────────────
    /// Format string for the overflow chip accessibility label. Use String(format:, N).
    /// English: "%d more speakers in this group"  Danish: "%d flere højttalere i denne gruppe"
    var overflowAccessibilityFormat: String

    static let english = GroupChipStrings(
        alsoPlaying:                 "Also playing",
        overflowFormat:              "+%d more",
        overflowAccessibilityFormat: "%d more speakers in this group"
    )

    static let danish = GroupChipStrings(
        alsoPlaying:                 "Spiller også",
        overflowFormat:              "+%d flere",
        overflowAccessibilityFormat: "%d flere højttalere i denne gruppe"
    )

    static func forLanguage(_ language: Language) -> GroupChipStrings {
        language == .danish ? .danish : .english
    }
}
