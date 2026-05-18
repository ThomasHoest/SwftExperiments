import SwiftUI

// MARK: - GroupingCoachMark (E-59 T-5909)
//
// A ViewModifier that renders a one-time coach mark overlay above the bottom bar
// instructing the user how to drag a speaker pill to join a session.
//
// Behavioural contracts:
//   1. Shows when hasEligiblePill && !hasSeen.
//   2. Auto-dismisses after 3 seconds via Task { try? await Task.sleep(for: .seconds(3)) }.
//   3. On dismiss: hasSeen = true (persisted via @AppStorage).
//   4. Position: overlay above the modified view, Spacing.s8 above the content.
//   5. Text: BeoType.caption, BeoColor.muted. .transition(.opacity).
//   6. .allowsHitTesting(false) on the label so taps pass through to the bar beneath.

struct GroupingCoachMark: ViewModifier {
    @AppStorage("hasSeenGroupingCoachMark") private var hasSeen: Bool = false

    let hasEligiblePill: Bool
    let onDismiss: () -> Void

    @State private var isVisible: Bool = false
    @State private var dismissTask: Task<Void, Never>? = nil

    private var shouldShow: Bool { hasEligiblePill && !hasSeen }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isVisible {
                    coachMarkLabel
                        .transition(.opacity.animation(BeoAnimation.toast))
                        // Position above the modified content
                        .offset(y: -(Spacing.s8 + 24))  // 24 pt approx label height
                }
            }
            .onChange(of: shouldShow) { _, newValue in
                if newValue {
                    show()
                } else {
                    hide()
                }
            }
            .onAppear {
                if shouldShow { show() }
            }
    }

    private var coachMarkLabel: some View {
        let strings = GroupingStrings.forLanguage(LanguageService.shared.activeLanguage)
        return Text(strings.coachMark)
            .font(BeoType.caption)
            .foregroundStyle(BeoColor.muted)
            .padding(.horizontal, Spacing.s12)
            .padding(.vertical, Spacing.s8)
            .background(.ultraThinMaterial, in: Capsule())
            .allowsHitTesting(false)
    }

    private func show() {
        guard !hasSeen else { return }
        withAnimation(BeoAnimation.toast) { isVisible = true }
        // Auto-dismiss after 3 seconds
        dismissTask?.cancel()
        dismissTask = Task { [onDismiss] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismiss(via: onDismiss)
            }
        }
    }

    private func hide() {
        withAnimation(BeoAnimation.toast) { isVisible = false }
        dismissTask?.cancel()
        dismissTask = nil
    }

    private func dismiss(via onDismiss: () -> Void) {
        hasSeen = true
        withAnimation(BeoAnimation.toast) { isVisible = false }
        onDismiss()
    }
}
