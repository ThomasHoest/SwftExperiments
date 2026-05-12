import Foundation

/// Language-keyed strings for the multiroom grouping coach mark (E-59 T-5909).
/// Follows the GroupChipStrings pattern (CF-5): a Swift struct in Core/Strings/,
/// NOT a .strings catalogue file.
struct GroupingStrings {
    // ── Coach mark text ───────────────────────────────────────────────────────
    /// Primary instruction shown in the coach mark overlay.
    var coachMark: String

    static let english = GroupingStrings(
        coachMark: "Drag to join this session"
    )

    static let danish = GroupingStrings(
        coachMark: "Træk for at tilslutte"
    )

    static func forLanguage(_ language: Language) -> GroupingStrings {
        language == .danish ? .danish : .english
    }
}
