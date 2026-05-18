import Foundation

/// Language-keyed strings for E-55 discovery and offline states.
///
/// Follows the `GroupChipStrings` / `UIStrings` pattern: static `english` and `danish`
/// instances selected via `forLanguage(_:)`. All keys correspond to design spec Appendix B
/// entries not already present in `UIStrings`.
struct DiscoveryStrings {

    // MARK: - Labels

    /// Pre-settle scanning label (below orb). E.g. "Searching for speakers…"
    var searching:           String

    /// Sub-label that appears after 10 s still in pre-settle. E.g. "Still looking…"
    var stillLooking:        String

    /// Title for the no-speakers-found state. E.g. "No speakers found"
    var noSpeakersTitle:     String

    /// Body copy for the no-speakers-found state.
    var noSpeakersBody:      String

    /// Label on the "Search again" button.
    var searchAgain:         String

    /// Title for the offline state. E.g. "No Wi-Fi"
    var offlineTitle:        String

    /// Body copy for the offline state.
    var offlineBody:         String

    /// Sub-label below the offline body. E.g. "Recovers automatically when Wi-Fi reconnects"
    var offlineAutoRecovery: String

    /// `ConnectionStatusChip` label when searching (pre-settle). E.g. "Searching…"
    var chipSearching:       String

    /// `ConnectionStatusChip` label when offline. E.g. "No Wi-Fi"
    var chipNoWifi:          String

    // MARK: - Accessibility

    struct A11y {
        /// VoiceOver announcement when entering the offline state.
        var offline:           String
        /// VoiceOver announcement when Wi-Fi is restored.
        var wifiRestored:      String
        /// VoiceOver announcement when entering the pre-settle (searching) state.
        var searching:         String
        /// `ConnectionStatusChip` accessibilityLabel in searching state.
        var chipSearching:     String
        /// `ConnectionStatusChip` accessibilityLabel in offline state.
        var chipOffline:       String
        /// `accessibilityLabel` for the "Search again" button.
        var searchAgainButton: String
    }
    var a11y: A11y

    // MARK: - Static instances

    static let english = DiscoveryStrings(
        searching:           "Searching for speakers\u{2026}",
        stillLooking:        "Still looking\u{2026}",
        noSpeakersTitle:     "No speakers found",
        noSpeakersBody:      "Make sure your B&O speaker is on and on the same Wi-Fi network.",
        searchAgain:         "Search again",
        offlineTitle:        "No Wi-Fi",
        offlineBody:         "Connect to the same Wi-Fi network as your B&O speakers to get started.",
        offlineAutoRecovery: "Recovers automatically when Wi-Fi reconnects",
        chipSearching:       "Searching\u{2026}",
        chipNoWifi:          "No Wi-Fi",
        a11y: A11y(
            offline:           "No Wi-Fi connection",
            wifiRestored:      "Wi-Fi connected, searching for speakers",
            searching:         "Searching for speakers",
            chipSearching:     "Searching for speakers",
            chipOffline:       "No Wi-Fi connection",
            searchAgainButton: "Search again for speakers"
        )
    )

    static let danish = DiscoveryStrings(
        searching:           "S\u{00F8}ger efter h\u{00F8}jttalere\u{2026}",
        stillLooking:        "Leder stadig\u{2026}",
        noSpeakersTitle:     "Ingen h\u{00F8}jttalere fundet",
        noSpeakersBody:      "S\u{00F8}rg for, at din B&O h\u{00F8}jttaler er t\u{00E6}ndt og p\u{00E5} samme Wi-Fi-netv\u{00E6}rk.",
        searchAgain:         "S\u{00F8}g igen",
        offlineTitle:        "Ingen Wi-Fi",
        offlineBody:         "Opret forbindelse til det samme Wi-Fi-netv\u{00E6}rk som dine B&O h\u{00F8}jttalere for at komme i gang.",
        offlineAutoRecovery: "Genopretter automatisk forbindelsen, n\u{00E5}r Wi-Fi er tilg\u{00E6}ngeligt",
        chipSearching:       "S\u{00F8}ger\u{2026}",
        chipNoWifi:          "Ingen Wi-Fi",
        a11y: A11y(
            offline:           "Ingen Wi-Fi-forbindelse",
            wifiRestored:      "Wi-Fi forbundet, s\u{00F8}ger efter h\u{00F8}jttalere",
            searching:         "S\u{00F8}ger efter h\u{00F8}jttalere",
            chipSearching:     "S\u{00F8}ger efter h\u{00F8}jttalere",
            chipOffline:       "Ingen Wi-Fi-forbindelse",
            searchAgainButton: "S\u{00F8}g efter h\u{00F8}jttalere igen"
        )
    )

    static func forLanguage(_ language: Language) -> DiscoveryStrings {
        language == .danish ? .danish : .english
    }
}
