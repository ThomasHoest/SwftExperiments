import SwiftUI

struct SpeakerCard: View {
    var speaker: Speaker
    var isExpanded: Bool
    var roll: Double
    var pitch: Double

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

    private var accessibilityDescription: String {
        let p = speaker.nowPlaying
        var parts = [speaker.name, speaker.stateDisplay]
        if p.isPlaying {
            if let primary = p.primaryLine, !primary.isEmpty { parts.append(primary) }
            if let secondary = p.secondaryLine, !secondary.isEmpty { parts.append(secondary) }
            if let badge = p.sourceBadge, !badge.isEmpty { parts.append(badge) }
        }
        if let vol = speaker.volume { parts.append("Volume \(vol)") }
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
