import SwiftUI

struct ConfirmationSheet: View {
    var message: String
    var onConfirm: () -> Void
    var onCancel:  () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // "or say Yes / No" mic indicator
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11))
                Text("or say Yes / No")
                    .font(.system(size: 13))
            }
            .foregroundStyle(.secondary)
            .padding(.top, 20)
            .padding(.bottom, 20)

            // About-to label
            Text("ABOUT TO:")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

            // Action read-back
            Text(message)
                .font(BeoType.nowPlaying)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

            Spacer()

            // Yes button
            Button(action: onConfirm) {
                Text("Yes")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color(hex: "#C8A97E"))
                    .foregroundStyle(Color(hex: "#0D0D14"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            // No button
            Button(action: onCancel) {
                Text("No")
                    .font(.system(size: 17, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.white.opacity(0.08))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "#1A1A28"))
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }
}
