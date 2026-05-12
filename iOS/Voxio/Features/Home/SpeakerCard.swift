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
            // Playing branch: header + now-playing panel + volume track + transport row + group chips
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                nowPlayingPanel
                if let vol = speaker.volume {
                    volumeTrack(level: vol)
                }
                transportRow
                // E-53 T-5304: group chip row — only shown when host has non-host members
                if !groupMembers.isEmpty {
                    GroupChipRow(chips: chipData)
                        .padding(.horizontal, Spacing.s24)
                        .padding(.bottom, Spacing.s16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .stopped:
            // Stopped branch: header + full-width Play pill (no now-playing panel, volume, or transport row).
            // E-58 will add a favorites row below the Play pill.
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                stoppedPlayPill
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

    // MARK: - Volume track

    private func volumeTrack(level: Int) -> some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.12))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color(hex: "#C8A97E"))
                        .frame(width: geo.size.width * CGFloat(level) / 100, height: 4)
                        .animation(.easeOut(duration: 0.3), value: level)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 4)

            Text("\(level)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
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
    func play() async throws {}
    func pause() async throws {}
    func stop() async throws {}
    func setVolume(_ level: Int) async throws {}
    func mute(_ muted: Bool) async throws {}
    func getVolume() async throws -> Int { 50 }
    func getPlaybackState() async throws -> SpeakerPlaybackState { .stopped }
    func getSources() async throws -> [Favorite] { [] }
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
private func makePreviewSpeaker(playbackValue: PlaybackValue, volumeLevel: Int? = 55) -> Speaker {
    let spk = Speaker(
        host: "192.168.1.10",
        client: PreviewSpeakerClient(),
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

#endif
