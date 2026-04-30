import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Non-dismissible sheet presented on first launch so the user can choose
/// their command language (English or Dansk) before the microphone starts.
///
/// Matches `ConfirmationSheet` styling — Liquid Glass material, design tokens.
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

            // English row
            Button {
                onSelect(.english)
            } label: {
                Text("English")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: "#0D0D14"))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 11)
                    .background(Color(hex: "#C8A97E"), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
            .accessibilityLabel("English")

            // Danish row
            Button {
                onSelect(.danish)
            } label: {
                Text("Dansk")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 11)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .safeAreaPadding(.bottom)
            .accessibilityLabel("Dansk")
        }
        .frame(maxWidth: .infinity)
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
