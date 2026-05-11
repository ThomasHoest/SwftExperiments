import SwiftUI

// MARK: - PlaybackBars
// Extracted from SpeakerCard.swift (T-5401). Shared between the session card (height: 20)
// and the bottom-bar pill (height: 10).

internal struct PlaybackBars: View {
    /// Full-height (20 pt) by default; pass 10 for the bottom-bar pill variant.
    /// Bar heights scale proportionally — at height: 10 bars are half the size of height: 20.
    var height: CGFloat = 20

    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let specs: [(lo: CGFloat, hi: CGFloat)] = [(6, 14), (14, 6), (10, 16)]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                if reduceMotion {
                    // Static bars at the midpoint of each bar's lo–hi range when Reduce Motion is on.
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "#C8A97E"))
                        .frame(width: 3, height: scaledMid(i))
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
            if !reduceMotion { animate = true }
        }
    }

    // MARK: - Proportional scaling helpers

    /// Scale factor relative to the reference 20 pt frame.
    private var scale: CGFloat { height / 20 }

    private func scaledLo(_ i: Int) -> CGFloat { specs[i].lo * scale }
    private func scaledHi(_ i: Int) -> CGFloat { specs[i].hi * scale }
    private func scaledMid(_ i: Int) -> CGFloat { (specs[i].lo + specs[i].hi) / 2 * scale }
}
