import SwiftUI

/// Renders the three non-content home-screen states: `.offline`, `.discovering`, and
/// `.noSpeakersFound`. The `.hasContent` case is handled by the existing E-52 `cardArea` body
/// and is never passed to this view.
///
/// **Orb placement:** the orb lives inside this view (per the Z-layout in each branch), with
/// `PulseRingsView` layered behind it in the `.discovering` branch.
///
/// **A11y announcements (T-5508):** state changes post `AccessibilityNotification.Announcement`
/// via a `lastAnnouncedState` guard to avoid duplicate announcements on re-renders.
struct DiscoveryStateView: View {

    // MARK: - Inputs

    /// Current home state. Only `.offline`, `.discovering`, and `.noSpeakersFound` are used.
    let state:          HomeState
    /// Called when the user taps "Search again". Ignored unless `state == .noSpeakersFound`.
    let onSearchAgain:  () -> Void

    // MARK: - State

    @State private var stillLookingShown:  Bool       = false
    @State private var isSearching:        Bool       = false
    @State private var lastAnnouncedState: HomeState? = nil

    // MARK: - Dependencies

    @ObservedObject private var langService = LanguageService.shared
    private var strings: DiscoveryStrings {
        DiscoveryStrings.forLanguage(langService.activeLanguage)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: Spacing.s24) {
            switch state {
            case .discovering:
                discoveringBody
            case .noSpeakersFound:
                noSpeakersBody
            case .offline:
                offlineBody
            case .hasContent:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s24)
        // T-5508 — announcement task: fires on state change, posts once per unique state.
        .task(id: state) {
            postAccessibilityAnnouncementIfNeeded()
            // "Still looking…" sub-label: appears after 10 s in .discovering
            stillLookingShown = false
            isSearching = false
            if state == .discovering {
                try? await Task.sleep(for: .seconds(10))
                if !Task.isCancelled && state == .discovering {
                    stillLookingShown = true
                }
            }
        }
    }

    // MARK: - Branch views

    /// Pre-settle scanning state: pulse rings + orb + "Searching…" label.
    @ViewBuilder
    private var discoveringBody: some View {
        ZStack {
            PulseRingsView()
            OrbView(opacity: 1.0, isPulsing: true)
        }

        VStack(spacing: Spacing.s8) {
            Text(strings.searching)
                .font(BeoType.body)
                .foregroundStyle(BeoColor.muted)
                .multilineTextAlignment(.center)

            if stillLookingShown {
                Text(strings.stillLooking)
                    .font(BeoType.caption)
                    .foregroundStyle(BeoColor.muted.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .animation(BeoAnimation.toast, value: stillLookingShown)
            }
        }
    }

    /// Post-settle, no speakers found: dim orb + title + body + "Search again" button.
    @ViewBuilder
    private var noSpeakersBody: some View {
        OrbView(opacity: 0.4, isPulsing: false)

        Text(strings.noSpeakersTitle)
            .font(BeoType.nowPlaying)
            .foregroundStyle(BeoColor.text)
            .multilineTextAlignment(.center)

        Text(strings.noSpeakersBody)
            .font(BeoType.body)
            .foregroundStyle(BeoColor.muted)
            .multilineTextAlignment(.center)

        if isSearching {
            ProgressView()
                .tint(BeoColor.muted)
        } else {
            DarkGlassButton(label: strings.searchAgain) {
                isSearching = true
                onSearchAgain()
            }
            .accessibilityLabel(strings.a11y.searchAgainButton)
        }
    }

    /// Offline state: very dim orb + title + body + auto-recovery sub-label. No button.
    @ViewBuilder
    private var offlineBody: some View {
        OrbView(opacity: 0.2, isPulsing: false)

        Text(strings.offlineTitle)
            .font(BeoType.nowPlaying)
            .foregroundStyle(BeoColor.text)
            .multilineTextAlignment(.center)

        Text(strings.offlineBody)
            .font(BeoType.body)
            .foregroundStyle(BeoColor.muted)
            .multilineTextAlignment(.center)

        Text(strings.offlineAutoRecovery)
            .font(BeoType.caption)
            .foregroundStyle(BeoColor.muted.opacity(0.6))
            .multilineTextAlignment(.center)
    }

    // MARK: - A11y announcements (T-5508)

    private func postAccessibilityAnnouncementIfNeeded() {
        guard state != lastAnnouncedState else { return }
        defer { lastAnnouncedState = state }

        let message: String?
        switch (lastAnnouncedState, state) {
        case (_, .offline):
            message = strings.a11y.offline
        case (.offline, .discovering):
            message = strings.a11y.wifiRestored
        case (nil, .discovering):
            message = strings.a11y.searching
        default:
            message = nil
        }

        guard let text = message else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}
