import SwiftUI
import UIKit

struct ConfirmationSheet: View {
    var message: String
    var onConfirm: () -> Void
    var onCancel:  () -> Void

    @ObservedObject private var langService = LanguageService.shared
    @State private var isVisible = false

    private var ui: UIStrings { UIStrings.forLanguage(langService.activeLanguage) }

    var body: some View {
        VStack(spacing: 0) {
            // mic indicator pill (T-1106)
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11))
                Text(ui.confirmationVoiceHint)
                    .font(.system(size: 13))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassEffect(in: Capsule())
            .padding(.top, 20)
            .padding(.bottom, 20)

            // "About to:" — SF Pro Text 12 pt, label-secondary (T-1103)
            Text(ui.confirmationAboutTo)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

            // Action read-back — SF Pro Display Regular 22 pt (T-1103)
            Text(message)
                .font(.system(size: 22, weight: .regular, design: .default))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

            Spacer()

            // Yes — filled Liquid Glass, accent gold tint (T-1104)
            Button {
                HapticEngine.shared.actionConfirmed()
                onConfirm()
            } label: {
                Text(ui.confirmYes)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: "#0D0D14"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color(hex: "#C8A97E"), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Yes, confirm")
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            // No — outlined Liquid Glass (T-1105)
            Button(action: onCancel) {
                Text(ui.confirmNo)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("No, cancel")
            .padding(.horizontal, 24)
            .safeAreaPadding(.bottom) // T-1110
        }
        .frame(maxWidth: .infinity)
        // T-1102 — Liquid Glass sheet surface
        .presentationBackground(.ultraThinMaterial)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        // T-1107 — slide-up spring entry
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 32)
        .onAppear {
            HapticEngine.shared.sheetAppeared()
            UIAccessibility.post(notification: .announcement, argument: message)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                isVisible = true
            }
        }
    }
}
