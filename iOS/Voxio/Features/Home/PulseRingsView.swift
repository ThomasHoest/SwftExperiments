import SwiftUI

/// Three concentric `Circle().stroke` rings that expand and fade behind the orb during
/// the pre-settle discovery animation (E-55 T-5506).
///
/// Each ring expands from 96 pt to 200 pt over 2.0 s with `.easeOut`, repeating forever.
/// Opacity animates from 0.15 → 0 over the same duration.
/// Ring 2 starts 0.6 s after ring 1; ring 3 starts 0.6 s after ring 2.
///
/// **Reduce Motion:** replaced by a single static ring at 0.1 opacity.
/// **Accessibility:** `accessibilityHidden(true)` — decorative.
struct PulseRingsView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            staticRing
        } else {
            animatedRings
        }
    }

    // MARK: - Reduce Motion variant

    private var staticRing: some View {
        Circle()
            .stroke(BeoColor.accent.opacity(0.1), lineWidth: 1)
            .frame(width: 200, height: 200)
            .accessibilityHidden(true)
    }

    // MARK: - Animated variant

    private var animatedRings: some View {
        ZStack {
            PulseRing(delay: 0.0)
            PulseRing(delay: 0.6)
            PulseRing(delay: 1.2)
        }
        .accessibilityHidden(true)
    }
}

/// A single expanding/fading ring. Each `PulseRing` owns its own `@State phase` so
/// the three rings in `PulseRingsView` animate independently with correct stagger.
private struct PulseRing: View {

    let delay: Double

    @State private var active: Bool = false

    private let minDiameter: CGFloat = 96
    private let maxDiameter: CGFloat = 200
    private let duration:    Double  = 2.0

    var body: some View {
        Circle()
            .stroke(BeoColor.accent, lineWidth: 1)
            .frame(
                width:  active ? maxDiameter : minDiameter,
                height: active ? maxDiameter : minDiameter
            )
            .opacity(active ? 0 : 0.15)
            .onAppear {
                withAnimation(
                    .easeOut(duration: duration)
                    .repeatForever(autoreverses: false)
                    .delay(delay)
                ) {
                    active = true
                }
            }
    }
}
