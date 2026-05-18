import SwiftUI

/// Radial-gradient orb used in the pre-settle discovery, no-speakers-found, and offline states
/// (E-55 T-5507 / CF-3).
///
/// `opacity` is controlled by the caller to communicate state:
///   - `.discovering`     → 1.0, `isPulsing` true
///   - `.noSpeakersFound` → 0.4, `isPulsing` false
///   - `.offline`         → 0.2, `isPulsing` false
///
/// `isPulsing` drives a gentle idle-pulse animation (scale 1.0 ↔ 1.05).
/// When `@Environment(\.accessibilityReduceMotion)` is true, the pulse is suppressed.
struct OrbView: View {

    var opacity:   CGFloat
    var isPulsing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulsed: Bool = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        BeoColor.accent.opacity(0.8),
                        BeoColor.accent.opacity(0.2)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 48
                )
            )
            .overlay(
                Circle()
                    .strokeBorder(BeoColor.cardBorder, lineWidth: 0.5)
            )
            .frame(width: 96, height: 96)
            .opacity(opacity)
            .scaleEffect(pulsed && isPulsing && !reduceMotion ? 1.05 : 1.0)
            .animation(BeoAnimation.spring, value: opacity)
            .onAppear { startPulse() }
            .onChange(of: isPulsing) { _, shouldPulse in
                if shouldPulse { startPulse() } else { pulsed = false }
            }
            .accessibilityHidden(true)
    }

    private func startPulse() {
        guard isPulsing && !reduceMotion else { return }
        withAnimation(
            .easeInOut(duration: 1.8)
            .repeatForever(autoreverses: true)
        ) {
            pulsed = true
        }
    }
}
