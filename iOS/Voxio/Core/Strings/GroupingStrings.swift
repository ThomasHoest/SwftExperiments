import Foundation

/// Language-keyed strings for the multiroom grouping coach mark (E-59 T-5909)
/// and join error toasts (E-60 T-6001 / T-6002).
/// Follows the GroupChipStrings pattern (CF-5): a Swift struct in Core/Strings/,
/// NOT a .strings catalogue file.
struct GroupingStrings {
    // ── Coach mark text ───────────────────────────────────────────────────────
    /// Primary instruction shown in the coach mark overlay.
    var coachMark: String

    // ── Join error toast strings (E-60 T-6001 / T-6002) ──────────────────────
    /// Two-argument format: "Couldn't add %@ — %@" / "Kunne ikke tilslutte %@ — %@"
    /// Args: (speakerName, reason). Use when a specific failure reason is available.
    var joinFailed: String
    /// Single-argument format: "Couldn't add %@" / "Kunne ikke tilslutte %@"
    /// Args: (speakerName). Used when no specific reason is available.
    var joinFailedGeneric: String
    /// Reason suffix for timeout: "connection timed out" / "forbindelsen fik timeout"
    var joinFailedTimeout: String
    /// Reason suffix for unreachable: "speaker unreachable" / "højttaleren kan ikke nås"
    var joinFailedUnreachable: String
    /// Loading chip accessibility label format: "Connecting %@…" / "Forbinder %@…"
    /// Args: (speakerName).
    var connectingFormat: String

    static let english = GroupingStrings(
        coachMark:              "Drag to join this session",
        joinFailed:             "Couldn't add %@ — %@",
        joinFailedGeneric:      "Couldn't add %@",
        joinFailedTimeout:      "connection timed out",
        joinFailedUnreachable:  "speaker unreachable",
        connectingFormat:       "Connecting %@…"
    )

    static let danish = GroupingStrings(
        coachMark:              "Træk for at tilslutte",
        joinFailed:             "Kunne ikke tilslutte %@ — %@",
        joinFailedGeneric:      "Kunne ikke tilslutte %@",
        joinFailedTimeout:      "forbindelsen fik timeout",
        joinFailedUnreachable:  "højttaleren kan ikke nås",
        connectingFormat:       "Forbinder %@…"
    )

    static func forLanguage(_ language: Language) -> GroupingStrings {
        language == .danish ? .danish : .english
    }
}
