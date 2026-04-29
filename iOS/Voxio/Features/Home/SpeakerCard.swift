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
        .overlay(
            colorContrast == .increased
                ? RoundedRectangle(cornerRadius: Radius.card).stroke(Color.secondary.opacity(0.6), lineWidth: 1)
                : nil
        )
        .scaleEffect(reduceMotion ? 1.0 : (isExpanded ? 1.02 : 1.0))
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : BeoAnimation.cardExpand, value: isExpanded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = [speaker.name, speaker.stateDisplay]
        if speaker.isPlaying, !speaker.trackDisplay.isEmpty { parts.append(speaker.trackDisplay) }
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
        VStack(alignment: .leading, spacing: 6) {
            Text(speaker.name)
                .font(BeoType.speakerName)
                .foregroundStyle(.primary)

            Text(speaker.stateDisplay)
                .font(BeoType.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, speaker.isPlaying ? 16 : 28)
    }

    private var nowPlayingPanel: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if !speaker.trackDisplay.isEmpty {
                    Text(speaker.trackDisplay)
                        .font(BeoType.nowPlaying)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                if let src = speaker.source, !src.isEmpty {
                    Text(src)
                        .font(BeoType.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

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

// ── Playback indicator ────────────────────────────────────────────────────────

private struct PlaybackBars: View {
    @State private var animate = false

    private let specs: [(lo: CGFloat, hi: CGFloat)] = [(6, 14), (14, 6), (10, 16)]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(hex: "#C8A97E"))
                    .frame(width: 3, height: animate ? specs[i].hi : specs[i].lo)
                    .animation(
                        .easeInOut(duration: 0.38 + Double(i) * 0.06)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.12),
                        value: animate
                    )
            }
        }
        .frame(height: 20, alignment: .bottom)
        .onAppear { animate = true }
    }
}
