import SwiftUI
import UIKit

/// T-2502 — Auto-execute countdown sheet surface.
/// Shows the command read-back text and a live "Cancelling in N…" counter.
/// The countdown digit updates instantly (no animation) for Reduce Motion friendliness.
struct CountdownConfirmationSurface: View {
    var readBackText: String
    var secondsRemaining: Int
    var onCancel: () -> Void

    @ObservedObject private var langService = LanguageService.shared

    private var ui: UIStrings { UIStrings.forLanguage(langService.activeLanguage) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Read-back label — SF Pro Display Regular 22pt
            Text(readBackText)
                .font(.system(size: 22, weight: .regular, design: .default))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 28)

            // Countdown label — SF Pro Text 14pt medium, secondary colour
            // Digit substitutes instantly — no animation (Reduce Motion friendly by construction)
            Text(ui.countdownLabel(n: secondsRemaining))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .animation(nil, value: secondsRemaining)

            Spacer(minLength: 20)

            // Cancel button
            DarkGlassButton(
                label: ui.cancelLabel,
                systemImage: "xmark",
                role: .cancel,
                action: onCancel
            )
            .padding(.horizontal, 24)

            // Safe area bottom padding
            Color.clear
                .frame(height: 0)
                .safeAreaPadding(.bottom)
        }
        .frame(maxWidth: .infinity)
        .preferredColorScheme(.dark)
        .presentationBackground(.ultraThinMaterial)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        .onAppear {
            // T-2503 — countdown-start haptic
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}
