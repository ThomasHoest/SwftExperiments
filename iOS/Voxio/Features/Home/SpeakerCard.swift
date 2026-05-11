import SwiftUI

struct SpeakerCard: View {
    var speaker: Speaker
    var isExpanded: Bool
    var roll: Double
    var pitch: Double
    /// Non-host members of the speaker's group. Default empty keeps all pre-E-53 call sites valid.
    /// Populated by SessionStripView (T-5306) with group.members filtered to exclude the host.
    var groupMembers: [Speaker] = []   // E-53 T-5304

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorContrast

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

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

    // ── Card content ──────────────────────────────────────────────────────────

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            if speaker.isPlaying {
                nowPlayingPanel
                if let vol = speaker.volume {
                    volumeTrack(level: vol)
                }
                // E-53 T-5304: group chip row — only shown when host has non-host members
                if !groupMembers.isEmpty {
                    GroupChipRow(chips: chipData)
                        .padding(.horizontal, Spacing.s24)
                        .padding(.bottom, Spacing.s16)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
    }

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

            // PlaybackBars is defined in Components/PlaybackBars.swift (T-5401/T-5402).
            // Default height: 20 preserves the original card appearance.
            PlaybackBars()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

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

    // ── Specular highlight ────────────────────────────────────────────────────

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
}
