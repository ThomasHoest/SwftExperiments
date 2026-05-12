import SwiftUI

// MARK: - SpeakerCard
//
// E-56 changes applied in this file:
//   T-5601 — cardContent now switches on speaker.playbackState (four-case enum).
//   T-5602 — transportRow computed view; DarkGlassIconButton(size: 52).
//   T-5603 — onPlayTapped() / onPauseTapped() implementations.
//   T-5604 — PlaybackBars receives playbackState: speaker.playbackState.
//   T-5605 — optional SpeakerGroup param; resolvedGroup computed property.
//   T-5606 — @Binding var errorMessage: String?; showErrorToast helper; stopped-state Play pill.
//   T-5607 — .accessibilityElement(children: .contain); summary moved to headerSection.
//   T-5609 — #Preview blocks for all four playback states.
//
// E-57 changes applied in this file:
//   T-5702 — @State dragVolume/lastLimitHaptic; InteractiveVolumeBar replaces volumeTrack call.
//   T-5703 — handleLimitHaptic(_:) — limit haptic + AccessibilityNotification, gated by lastLimitHaptic.
//   T-5705 — broadcastVolume(_:) async — fan-out via resolvedGroup.setVolumeOnAllMembers; partial-failure toast.
//
// E-58 changes applied in this file:
//   T-5801 — @State favorites: [Favorite]; .task async load via speaker.getFavorites().
//   T-5802 — favoritesRow @ViewBuilder; trailingFadeGradient; mounted in both cardContent branches.
//   T-5803 — onFavoriteTapped(fav:); UIStrings.couldNotStartFavorite error toast.
//   T-5804 — .accessibilityElement(children: .contain) on ScrollView; per-pill labels from DarkGlassButton.
//   T-5806 — #Preview blocks for favorites row (5 favorites playing, 0 favorites playing, 3 favorites stopped).
//
// CF-1 decision: @Binding var errorMessage: String? (SwiftUI symmetry, as ADR recommends).
// Every call site must supply errorMessage:. #Preview blocks use .constant(nil).

struct SpeakerCard: View {
    var speaker: Speaker
    var isExpanded: Bool
    var roll: Double
    var pitch: Double
    /// Non-host members of the speaker's group. Default empty keeps all pre-E-53 call sites valid.
    /// Populated by SessionStripView with group.members filtered to exclude the host.
    var groupMembers: [Speaker] = []   // E-53 T-5304

    /// Optional group for transport + volume dispatch (E-56 T-5605).
    /// When nil, solo card wraps speaker via SpeakerGroup.single(speaker) internally.
    /// F2 will pass real multi-member groups; all existing call sites pass nil (default).
    var group: SpeakerGroup? = nil     // E-56 T-5605

    /// Routes transport errors to the HomeView toast surface (E-56 T-5606).
    @Binding var errorMessage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorContrast

    // MARK: - Volume drag state (E-57 T-5702)

    /// Non-nil while the user is dragging the volume bar; overrides speaker.volume for display.
    /// Reset to nil on drag end after broadcastVolume fires.
    @State private var dragVolume: Int? = nil

    /// Tracks which limit (0 or 100) last fired a limitReached haptic within this drag,
    /// preventing repeated firing while held at a boundary.
    @State private var lastLimitHaptic: Int? = nil

    // MARK: - Favorites state (E-58 T-5801)

    /// Favorites loaded from speaker.getFavorites() on card appear.
    /// Empty array while loading, after failure, or when the speaker has no presets.
    @State private var favorites: [Favorite] = []

    // MARK: - Group-aware dispatch (T-5605)

    /// Resolves to the supplied group or a single-speaker group wrapping the card's speaker.
    /// Transport calls always go through resolvedGroup.hostSpeaker.
    private var resolvedGroup: SpeakerGroup { group ?? SpeakerGroup.single(speaker) }

    // MARK: - UIStrings

    private var ui: UIStrings { UIStrings.forLanguage(LanguageService.shared.activeLanguage) }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            cardContent
            if !reduceMotion { specularHighlight }
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: Radius.card))
        // Always-on hairline border so the card edge is visible on the dark background
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .stroke(Color.white.opacity(colorContrast == .increased ? 0.0 : 0.12), lineWidth: 0.5)
        )
        // T-2206 — Increase Contrast reactive border; BeoColor.muted (labelSecondary alias)
        .overlay(
            colorContrast == .increased
                ? RoundedRectangle(cornerRadius: Radius.card).stroke(BeoColor.muted, lineWidth: 1)
                : nil
        )
        .scaleEffect(reduceMotion ? 1.0 : (isExpanded ? 1.02 : 1.0))
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : BeoAnimation.cardExpand, value: isExpanded)
        // T-5607: loosened from .ignore to .contain so transport button is VoiceOver-reachable.
        // Card-level summary moved to headerSection's accessibilityLabel.
        .accessibilityElement(children: .contain)
        // E-58 T-5801: load favorites once on appear; silent failure (logged at info, no toast).
        .task {
            do {
                favorites = try await speaker.getFavorites()
            } catch {
                Log.info("[\(speaker.name)] getFavorites failed: \(error)")
                favorites = []
            }
        }
    }

    // MARK: - Chip data (E-53)

    /// Converts groupMembers to [ChipData], applying the overflow rule:
    /// - members.count > 3 → 2 member chips + 1 overflow chip (count - 2 remaining).
    /// - members.count <= 3 → one chip per member.
    /// - members.isEmpty → [].
    private var chipData: [ChipData] {
        if groupMembers.isEmpty { return [] }
        if groupMembers.count > 3 {
            let memberChips = groupMembers.prefix(2).map {
                ChipData(speakerName: $0.name, kind: .member)
            }
            // Overflow chip carries no name — the visible label is derived from .overflow(N), not speakerName.
            let overflowChip = ChipData(speakerName: "", kind: .overflow(groupMembers.count - 2))
            return memberChips + [overflowChip]
        } else {
            return groupMembers.map { ChipData(speakerName: $0.name, kind: .member) }
        }
    }

    // MARK: - Accessibility summary (T-5607: moved from card level to header level)

    private var accessibilityDescription: String {
        let p = speaker.nowPlaying
        var parts = [speaker.name, speaker.stateDisplay]
        if p.isPlaying {
            if let primary = p.primaryLine, !primary.isEmpty { parts.append(primary) }
            if let secondary = p.secondaryLine, !secondary.isEmpty { parts.append(secondary) }
            if let badge = p.sourceBadge, !badge.isEmpty { parts.append(badge) }
        }
        if let vol = speaker.volume { parts.append("Volume \(vol)") }
        // E-53 T-5305: append group members to accessibility description
        if !groupMembers.isEmpty {
            let strings = GroupChipStrings.forLanguage(LanguageService.shared.activeLanguage)
            let names = groupMembers.map(\.name).joined(separator: ", ")
            parts.append("\(strings.alsoPlaying): \(names)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Card content (T-5601: switched on playbackState)

    @ViewBuilder
    private var cardContent: some View {
        switch speaker.playbackState {
        case .playing, .paused, .buffering:
            // Playing branch: header + now-playing panel + volume bar + transport row + group chips
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                nowPlayingPanel
                // T-5702: InteractiveVolumeBar replaces the static volumeTrack.
                // dragVolume overrides speaker.volume while the user drags (WS events don't jump the bar).
                InteractiveVolumeBar(
                    value: Binding<Int>(
                        get: { dragVolume ?? speaker.volume ?? 0 },
                        set: { newValue in
                            dragVolume = newValue
                            handleLimitHaptic(newValue)
                        }
                    ),
                    onEditingChanged: { editing in
                        if !editing {
                            let final = dragVolume ?? speaker.volume ?? 0
                            Task { await broadcastVolume(final) }
                            dragVolume = nil
                            lastLimitHaptic = nil
                        }
                    }
                )
                .padding(.horizontal, Spacing.s24)
                .padding(.vertical, Spacing.s12)
                transportRow
                // E-58 T-5802: favorites row — absent when favorites is empty
                favoritesRow
                // E-53 T-5304: group chip row — only shown when host has non-host members
                if !groupMembers.isEmpty {
                    GroupChipRow(chips: chipData)
                        .padding(.horizontal, Spacing.s24)
                        .padding(.bottom, Spacing.s16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .stopped:
            // Stopped branch: header + full-width Play pill + favorites row.
            // E-58 T-5802: favoritesRow is mounted below stoppedPlayPill.
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                stoppedPlayPill
                // E-58 T-5802: favorites row — absent when favorites is empty
                favoritesRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header section (T-5607: carries card-level summary accessibilityLabel)

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(speaker.name)
                    .font(BeoType.speakerName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(speaker.stateDisplay)
                    .font(BeoType.body)
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)

            Spacer()

            if let badge = speaker.nowPlaying.sourceBadge, !badge.isEmpty {
                Text(badge)
                    .font(BeoType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.07), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, speaker.isPlaying ? 16 : 28)
        // T-5607: card-level summary now lives here so VoiceOver reads it first,
        // then moves on to the individually-reachable transport button.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Now playing panel

    private var nowPlayingPanel: some View {
        let p = speaker.nowPlaying
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let primary = p.primaryLine, !primary.isEmpty {
                    Text(primary)
                        .font(BeoType.nowPlaying)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                if let secondary = p.secondaryLine, !secondary.isEmpty {
                    Text(secondary)
                        .font(BeoType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // T-5604: pass current playbackState so bars freeze when paused/stopped.
            PlaybackBars(playbackState: speaker.playbackState)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Limit haptic (E-57 T-5703)
    // Fires once per boundary crossing within a drag; resets when value returns to mid-range.

    private func handleLimitHaptic(_ value: Int) {
        if value == 0 && lastLimitHaptic != 0 {
            HapticEngine.shared.limitReached()
            AccessibilityNotification.Announcement("Volume at minimum").post()
            lastLimitHaptic = 0
        } else if value == 100 && lastLimitHaptic != 100 {
            HapticEngine.shared.limitReached()
            AccessibilityNotification.Announcement("Volume at maximum").post()
            lastLimitHaptic = 100
        } else if value > 0 && value < 100 {
            lastLimitHaptic = nil
        }
    }

    // MARK: - Group volume broadcast (E-57 T-5705)
    // Dispatched on drag end; partial failures surface via showErrorToast.

    private func broadcastVolume(_ level: Int) async {
        let results = await resolvedGroup.setVolumeOnAllMembers(level)
        let failed = results.filter {
            if case .failure = $0.result { return true } else { return false }
        }
        guard !failed.isEmpty else { return }
        for item in failed {
            if case .failure(let error) = item.result {
                Log.error("[\(item.speaker.name)] setVolume(\(level)) failed: \(error)")
            }
        }
        let suffix = failed.count == 1 ? "speaker" : "speakers"
        showErrorToast("Volume failed on \(failed.count) \(suffix)")
        HapticEngine.shared.errorOccurred()
    }

    // MARK: - Transport row (T-5602)
    // Centred single button: pause.fill when playing/buffering, play.fill (gold) when paused.
    // Layout per design-spec §1.2: h-pad s24, v-pad s16 top, s20 bottom.

    @ViewBuilder
    private var transportRow: some View {
        HStack {
            Spacer()
            switch speaker.playbackState {
            case .playing, .buffering:
                DarkGlassIconButton(
                    systemImage: "pause.fill",
                    role: .default,
                    accessibilityLabel: ui.pause,
                    size: 52,
                    action: onPauseTapped
                )
            case .paused:
                DarkGlassIconButton(
                    systemImage: "play.fill",
                    role: .confirm,
                    accessibilityLabel: ui.play,
                    size: 52,
                    action: onPlayTapped
                )
            case .stopped:
                EmptyView()
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.s24)
        .padding(.top, Spacing.s16)
        .padding(.bottom, Spacing.s20)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Stopped-state Play pill (T-5606)
    // Full-width DarkGlassButton with play.fill icon and .confirm (gold) role.

    private var stoppedPlayPill: some View {
        DarkGlassButton(
            label: ui.play,
            systemImage: "play.fill",
            role: .confirm,
            action: onPlayTapped
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.s24)
        .padding(.top, Spacing.s20)
        .padding(.bottom, Spacing.s20)
    }

    // MARK: - Favorites row (E-58 T-5802, T-5803, T-5804)
    // Horizontally-scrolling pill row. Absent (zero height) when favorites is empty.
    // CF-1: All pills use .default role — NEVER .confirm. No active-favorite highlight (UQ-1).
    // CF-2: Uses fav.presetIndex — NOT ForEach enumeration offset.

    @ViewBuilder
    private var favoritesRow: some View {
        if favorites.isEmpty == false {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s8) {
                    ForEach(favorites) { fav in
                        DarkGlassButton(label: fav.displayName, role: .default) {
                            onFavoriteTapped(fav: fav)
                        }
                        .fixedSize()
                    }
                }
                .padding(.horizontal, Spacing.s24)
            }
            .mask(trailingFadeGradient)
            .padding(.top, Spacing.s8)
            .padding(.bottom, Spacing.s20)
            // T-5804: contain so VoiceOver navigates each pill individually.
            .accessibilityElement(children: .contain)
        }
        // Empty → EmptyView() — zero height, no placeholder (spec US-72).
    }

    /// Trailing fade gradient that signals scrollability (design-spec §4.2).
    private var trailingFadeGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: 0.85),
                .init(color: .clear,  location: 1.0)
            ],
            startPoint: .leading,
            endPoint:   .trailing
        )
    }

    /// Tap handler for a favorites pill.
    /// CF-2: uses fav.presetIndex (stored on the Favorite model), NOT ForEach enumeration offset.
    private func onFavoriteTapped(fav: Favorite) {
        HapticEngine.shared.commandRecognised()
        Task {
            do {
                try await speaker.playFavorite(presetIndex: fav.presetIndex)
            } catch {
                Log.error("[\(speaker.name)] playFavorite(\(fav.presetIndex)) failed: \(error)")
                showErrorToast(ui.couldNotStartFavorite)
                HapticEngine.shared.errorOccurred()
            }
        }
    }

    // MARK: - Specular highlight

    private var specularHighlight: some View {
        LinearGradient(
            colors: [.white.opacity(0.16), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .offset(x: roll * 28)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    // MARK: - Transport tap handlers (T-5603 + T-5605)

    private func onPlayTapped() {
        HapticEngine.shared.commandRecognised()
        Task { @MainActor in
            do {
                try await resolvedGroup.hostSpeaker.play()
            } catch {
                showErrorToast(errorText(for: error))
                HapticEngine.shared.errorOccurred()
            }
        }
    }

    private func onPauseTapped() {
        HapticEngine.shared.commandRecognised()
        Task { @MainActor in
            do {
                try await resolvedGroup.hostSpeaker.pause()
            } catch {
                showErrorToast(errorText(for: error))
                HapticEngine.shared.errorOccurred()
            }
        }
    }

    // MARK: - Error toast helper (T-5606)
    // Sets the @Binding errorMessage so HomeView's onChange creates the Toast.
    // E-57 and E-58 reuse this helper unchanged.

    private func showErrorToast(_ message: String) {
        errorMessage = message
    }

    private func errorText(for error: Error) -> String {
        if let speakerError = error as? SpeakerError {
            switch speakerError {
            case .timeout:
                return "Speaker timed out"
            case .unreachable:
                return "Speaker unreachable"
            default:
                return "Could not reach \(speaker.name)"
            }
        }
        return "Could not reach \(speaker.name)"
    }
}

// MARK: - Previews (T-5609)
// All four playback states. errorMessage uses .constant(nil) per CF-1 decision (@Binding choice).
// Preview stubs are lightweight — only the minimum protocol surface is implemented.

#if DEBUG

// MARK: Preview stubs (main-target only, not exported to test target)

private final class PreviewSpeakerClient: SpeakerClient {
    /// Favorites returned by getSources() — configurable per-preview (T-5806).
    var stubFavorites: [Favorite] = []

    func play() async throws {}
    func pause() async throws {}
    func stop() async throws {}
    func setVolume(_ level: Int) async throws {}
    func mute(_ muted: Bool) async throws {}
    func getVolume() async throws -> Int { 50 }
    func getPlaybackState() async throws -> SpeakerPlaybackState { .stopped }
    func getSources() async throws -> [Favorite] { stubFavorites }
    func activateSource(_ id: String) async throws {}
    func getBattery() async throws -> Battery? { nil }
    func getName() async throws -> String { "Preview" }
    func getJid() async throws -> String? { nil }
    func getPeers() async throws -> [BeolinkPeer] { [] }
    func join(peer: SpeakerIdentifier) async throws {}
    func leave() async throws {}
}

private final class PreviewSpeakerEventSource: SpeakerEventSource {
    func events() -> AsyncStream<SpeakerEvent> {
        AsyncStream { $0.finish() }
    }
}

@MainActor
private func makePreviewSpeaker(
    playbackValue: PlaybackValue,
    volumeLevel: Int? = 55,
    favorites: [Favorite] = []
) -> Speaker {
    let client = PreviewSpeakerClient()
    client.stubFavorites = favorites
    let spk = Speaker(
        host: "192.168.1.10",
        client: client,
        eventSource: PreviewSpeakerEventSource(),
        platform: .mozart
    )
    spk.name = "Beosound Balance"
    spk.state = playbackValue
    spk.volume = volumeLevel
    if playbackValue != .unknown && playbackValue != .stopped {
        // Provide metadata for non-stopped states via JSON decode round-trip (avoids memberwise init)
        let json = """
        {"title":"Space Oddity","artist":"David Bowie","album":"Space Oddity"}
        """.data(using: .utf8)!
        spk.metadata = try? JSONDecoder().decode(PlaybackMetadata.self, from: json)
    }
    return spk
}

/// Five sample favorites used in E-58 preview blocks (T-5806).
private let previewFavorites5: [Favorite] = [
    Favorite(id: "fav-1", displayName: "Radio 24syv",   presetIndex: 1),
    Favorite(id: "fav-2", displayName: "Jazz FM",        presetIndex: 2),
    Favorite(id: "fav-3", displayName: "Morning Playlist", presetIndex: 3),
    Favorite(id: "fav-4", displayName: "Chill Vibes",   presetIndex: 4),
    Favorite(id: "fav-5", displayName: "Evening News",  presetIndex: 5),
]

/// Three sample favorites used in E-58 stopped-state preview (T-5806).
private let previewFavorites3: [Favorite] = [
    Favorite(id: "fav-1", displayName: "Radio 24syv",   presetIndex: 1),
    Favorite(id: "fav-2", displayName: "Jazz FM",        presetIndex: 2),
    Favorite(id: "fav-3", displayName: "Morning Playlist", presetIndex: 3),
]

#Preview("SpeakerCard — Playing") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .playing),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

#Preview("SpeakerCard — Paused") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .paused, volumeLevel: 40),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

#Preview("SpeakerCard — Buffering") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .buffering, volumeLevel: 60),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

#Preview("SpeakerCard — Stopped") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .unknown, volumeLevel: nil),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

// MARK: - E-58 Favorites row previews (T-5806)

#Preview("SpeakerCard — Playing + 5 Favorites") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .playing, favorites: previewFavorites5),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

#Preview("SpeakerCard — Stopped + 3 Favorites") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .unknown, volumeLevel: nil, favorites: previewFavorites3),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

#Preview("SpeakerCard — Playing + 0 Favorites") {
    @Previewable @State var errorMessage: String? = nil
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        SpeakerCard(
            speaker: makePreviewSpeaker(playbackValue: .playing, favorites: []),
            isExpanded: false,
            roll: 0,
            pitch: 0,
            errorMessage: $errorMessage
        )
        .padding(20)
    }
    .preferredColorScheme(.dark)
}

#endif
