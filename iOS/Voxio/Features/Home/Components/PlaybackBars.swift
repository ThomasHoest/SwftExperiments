import SwiftUI

// MARK: - PlaybackBars
// Extracted from SpeakerCard.swift (T-5401). Shared between the session card (height: 20)
// and the bottom-bar pill (height: 10).
//
// E-56 T-5604: added `playbackState` parameter.
// Bars animate only when state is .playing or .buffering; static at lo height for .paused/.stopped.

internal struct PlaybackBars: View {
    /// Full-height (20 pt) by default; pass 10 for the bottom-bar pill variant.
    /// Bar heights scale proportionally — at height: 10 bars are half the size of height: 20.
    var height: CGFloat = 20

    /// E-56 T-5604 — controls animation gate. Default .playing preserves all pre-E-56 call sites.
    var playbackState: SpeakerPlaybackState = .playing

    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let specs: [(lo: CGFloat, hi: CGFloat)] = [(6, 14), (14, 6), (10, 16)]

    /// Bars animate only when actively playing or buffering.
    private var shouldAnimate: Bool {
        playbackState == .playing || playbackState == .buffering
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                if reduceMotion || !shouldAnimate {
                    // Static bars at lo height when Reduce Motion is on or playback is paused/stopped.
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "#C8A97E"))
                        .frame(width: 3, height: scaledLo(i))
                } else {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "#C8A97E"))
                        .frame(width: 3, height: animate ? scaledHi(i) : scaledLo(i))
                        .animation(
                            .easeInOut(duration: 0.38 + Double(i) * 0.06)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.12),
                            value: animate
                        )
                }
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
        .onAppear {
            if !reduceMotion && shouldAnimate { animate = true }
        }
        .onChange(of: playbackState) { _, newState in
            let nowShouldAnimate = newState == .playing || newState == .buffering
            if nowShouldAnimate && !animate && !reduceMotion {
                animate = true
            } else if !nowShouldAnimate && animate {
                animate = false
            }
        }
    }

    // MARK: - Proportional scaling helpers

    /// Scale factor relative to the reference 20 pt frame.
    private var scale: CGFloat { height / 20 }

    private func scaledLo(_ i: Int) -> CGFloat { specs[i].lo * scale }
    private func scaledHi(_ i: Int) -> CGFloat { specs[i].hi * scale }
    private func scaledMid(_ i: Int) -> CGFloat { (specs[i].lo + specs[i].hi) / 2 * scale }
}
