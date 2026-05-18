import Foundation

/// Four-state machine for the home screen card area (E-55 T-5505).
///
/// Derived from `(network.isOnWifi, discovery.didSettle, discoveredSpeakerCount)`.
/// Priority: `!isOnWifi` wins over everything; `speakerCount > 0` wins over settle state.
///
/// Promoted to `internal` (separate file) per ADR-E55 CF-6 so that `DiscoveryStateView`
/// and unit tests can reference it without depending on `HomeView` internals.
enum HomeState: Equatable {
    /// No Wi-Fi path available.
    case offline
    /// Wi-Fi present, discovery hasn't settled, and no speakers found yet.
    case discovering
    /// Wi-Fi present, discovery settled, but zero speakers found.
    case noSpeakersFound
    /// At least one speaker discovered (Wi-Fi present, speakerCount > 0).
    case hasContent

    /// String key used to drive `.animation(_, value: homeState.layoutKey)` in `cardArea`.
    var layoutKey: String {
        switch self {
        case .offline:         return "offline"
        case .discovering:     return "discovering"
        case .noSpeakersFound: return "noSpeakersFound"
        case .hasContent:      return "hasContent"
        }
    }
}
