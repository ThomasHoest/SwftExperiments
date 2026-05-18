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

    // ── E-61 tap-to-remove strings (T-6105 / T-6106) ─────────────────────────
    /// Single-argument error toast for failed remove: "Couldn't remove %@" / "Kunne ikke fjerne %@"
    /// Args: (speakerName).
    var removeFailed: String
    /// VoiceOver announcement after successful remove: "%@ removed from group" / "%@ fjernet fra gruppe"
    /// Args: (speakerName).
    var a11yRemoved: String
    /// Accessibility label for a settled member chip: "%@, in group. Tap to remove."
    /// Args: (speakerName). EN: "%@, in group. Tap to remove." DA: "%@, i gruppe. Tryk for at fjerne."
    var chipMemberLabel: String
    /// Accessibility hint for a settled member chip.
    /// EN: "Removes this speaker from the group."  DA: "Fjerner denne højttaler fra gruppen."
    var chipMemberHint: String
    /// Name for the VoiceOver alternate join action on the session card (T-6106).
    /// EN: "Add speaker"  DA: "Tilføj højttaler"
    var a11yAddAction: String

    static let english = GroupingStrings(
        coachMark:              "Drag to join this session",
        joinFailed:             "Couldn't add %@ — %@",
        joinFailedGeneric:      "Couldn't add %@",
        joinFailedTimeout:      "connection timed out",
        joinFailedUnreachable:  "speaker unreachable",
        connectingFormat:       "Connecting %@…",
        removeFailed:           "Couldn't remove %@",
        a11yRemoved:            "%@ removed from group",
        chipMemberLabel:        "%@, in group. Tap to remove.",
        chipMemberHint:         "Removes this speaker from the group.",
        a11yAddAction:          "Add speaker"
    )

    static let danish = GroupingStrings(
        coachMark:              "Træk for at tilslutte",
        joinFailed:             "Kunne ikke tilslutte %@ — %@",
        joinFailedGeneric:      "Kunne ikke tilslutte %@",
        joinFailedTimeout:      "forbindelsen fik timeout",
        joinFailedUnreachable:  "højttaleren kan ikke nås",
        connectingFormat:       "Forbinder %@…",
        removeFailed:           "Kunne ikke fjerne %@",
        a11yRemoved:            "%@ fjernet fra gruppe",
        chipMemberLabel:        "%@, i gruppe. Tryk for at fjerne.",
        chipMemberHint:         "Fjerner denne højttaler fra gruppen.",
        a11yAddAction:          "Tilføj højttaler"
    )

    static func forLanguage(_ language: Language) -> GroupingStrings {
        language == .danish ? .danish : .english
    }
}
