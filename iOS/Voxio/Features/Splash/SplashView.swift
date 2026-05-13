import SwiftUI

// MARK: - SplashView
//
// Brief launch splash matching the app icon — three gold capsule "audio bars"
// (tall-short-tall) inside a faint circle, with the "Voxio" wordmark below.
// Background matches the icon's dark navy so the system launch-screen flash
// (which is the system-managed appearance bridge from system → SwiftUI) is
// visually continuous.
//
// Shown by VoxioApp for ~1.2 s before HomeView takes over; cross-fades on
// dismiss. Honours `accessibilityReduceMotion` (no entrance animation when on).

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Matches the AppIcon background (dark navy).
    private let background = Color(red: 0.04, green: 0.055, blue: 0.10)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 32) {
                glyph
                Text("Voxio")
                    .font(.system(size: 48, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
            }
            .opacity(reduceMotion ? 1 : (appeared ? 1 : 0))
            .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.96))
        }
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
        }
    }

    // MARK: - Icon glyph

    /// The icon's three-capsule motif (tall-short-tall) inside a faint circle.
    private var glyph: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                .frame(width: 230, height: 230)

            HStack(alignment: .center, spacing: 16) {
                bar(height: 110)
                bar(height: 60)
                bar(height: 110)
            }
        }
        .frame(width: 230, height: 230)
        .accessibilityLabel("Voxio")
    }

    private func bar(height: CGFloat) -> some View {
        Capsule()
            .fill(Color(red: 0.784, green: 0.663, blue: 0.494))   // Accent (gold)
            .frame(width: 22, height: height)
    }
}

#if DEBUG
#Preview("SplashView") {
    SplashView()
        .preferredColorScheme(.dark)
}
#endif
