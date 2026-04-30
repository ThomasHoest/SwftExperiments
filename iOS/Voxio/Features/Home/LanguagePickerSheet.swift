import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Non-dismissible sheet presented on first launch so the user can choose
/// their command language (English or Dansk) before the microphone starts.
struct LanguagePickerSheet: View {
    let onSelect: (Language) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Title — bilingual since we don't know the preferred language yet
            Text("Choose your language\nVælg dit sprog")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)

            // T-2107 — DarkGlassButton rows; shape changes from RoundedRectangle(12)→Capsule
            // per ADR-001 §Conflict 3, matching ButtonLookAndFeel.png
            DarkGlassButton(label: "English", systemImage: nil, role: .default) {
                onSelect(.english)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            DarkGlassButton(label: "Dansk", systemImage: nil, role: .default) {
                onSelect(.danish)
            }
            .padding(.horizontal, 24)
            .safeAreaPadding(.bottom)
        }
        .frame(maxWidth: .infinity)
        .preferredColorScheme(.dark) // T-2202 — enforce dark on sheet body root
        .presentationBackground(.ultraThinMaterial)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        .onAppear {
            #if canImport(UIKit)
            UIAccessibility.post(
                notification: .announcement,
                argument: "Choose your command language. Vælg dit kommandosprog."
            )
            #endif
        }
    }
}
