import SwiftUI

// MARK: - SessionPageDots
// T-5204: Page dot indicator for the session strip.
// Returns EmptyView() when count <= 1.
// Active dot: 8 pt Circle in BeoColor.accent.
// Inactive dots: 6 pt Circle in BeoColor.muted at 0.4 opacity.
// Spacing: Spacing.s8 between dots.
// Active-index animation: BeoAnimation.toast.
// Reduce Motion: opacity-only, no scale change.
// accessibilityHidden(true): page dots are decorative — cards carry the navigation information.

struct SessionPageDots: View {
    /// Total number of sessions. Returns EmptyView() when count <= 1.
    let count: Int

    /// Zero-based index of the currently visible session.
    let selectedIndex: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if count <= 1 {
            EmptyView()
        } else {
            HStack(spacing: Spacing.s8) {
                ForEach(0..<count, id: \.self) { index in
                    let isActive = index == selectedIndex
                    if isActive {
                        Circle()
                            .fill(BeoColor.accent)
                            .frame(width: 8, height: 8)
                            .transition(reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale))
                    } else {
                        Circle()
                            .fill(BeoColor.muted.opacity(0.4))
                            .frame(width: 6, height: 6)
                            .transition(reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale))
                    }
                }
            }
            .animation(BeoAnimation.toast, value: selectedIndex)
            .accessibilityHidden(true)
        }
    }
}
