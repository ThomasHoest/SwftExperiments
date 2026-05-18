import SwiftUI

/// Top-bar connectivity chip.
///
/// Rewritten for E-55 (T-5503): previously accepted a single `speakerCount` input and derived
/// online/offline from `speakerCount > 0`. Now accepts three independent inputs so it can
/// distinguish between "searching" (pre-settle), "offline" (no Wi-Fi), and "connected" (settled).
struct ConnectionStatusChip: View {
    var isOnWifi:   Bool
    var didSettle:  Bool
    var speakerCount: Int

    // MARK: - Private state machine

    private enum ChipState: Equatable {
        /// Wi-Fi present but discovery hasn't settled yet.
        case searching
        /// No Wi-Fi path available.
        case offline
        /// Wi-Fi present and discovery settled. Associated value is the speaker count (may be 0).
        case connected(Int)
    }

    private var chipState: ChipState {
        guard isOnWifi else { return .offline }
        guard didSettle else { return .searching }
        return .connected(speakerCount)
    }

    // MARK: - Strings

    private var strings: DiscoveryStrings {
        DiscoveryStrings.forLanguage(LanguageService.shared.activeLanguage)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(symbolColor)

            Text(chipLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(labelColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Computed display properties

    private var symbolName: String {
        switch chipState {
        case .offline:
            return "wifi.slash"
        case .searching, .connected:
            return "wifi"
        }
    }

    private var symbolColor: Color {
        switch chipState {
        case .connected:
            return .green
        case .searching, .offline:
            return BeoColor.muted
        }
    }

    private var chipLabel: String {
        switch chipState {
        case .searching:
            return strings.chipSearching
        case .offline:
            return strings.chipNoWifi
        case .connected(let n):
            return "\(n)"
        }
    }

    private var labelColor: Color {
        switch chipState {
        case .offline:
            return .secondary
        case .searching, .connected:
            return .primary
        }
    }

    private var accessibilityText: String {
        switch chipState {
        case .searching:
            return strings.a11y.chipSearching
        case .offline:
            return strings.a11y.chipOffline
        case .connected(let n):
            return "\(n) speaker\(n == 1 ? "" : "s") connected"
        }
    }
}
