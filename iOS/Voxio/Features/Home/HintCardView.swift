import SwiftUI

/// Dismissible getting-started hint card rendered inside the `voiceFeedback`
/// VStack. Shows concrete example phrases using the first discovered speaker name
/// (or a placeholder when no speaker is available yet).
///
/// Entry/exit uses `.opacity` only, honouring Reduce Motion.
/// All text scales with Dynamic Type.
struct HintCardView: View {
    let speakerName: String?
    let language: Language
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let name = speakerName {
                Text(language == .danish ? "Prøv at sige:" : "Try saying:")
                    .font(BeoType.body)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    exampleRow(language == .danish ? "\(name), afspil" : "\(name), play")
                    exampleRow(language == .danish ? "\(name), pause" : "\(name), pause")
                    exampleRow(language == .danish ? "\(name), lydstyrke 50" : "\(name), volume 50")
                }
            } else {
                Text(
                    language == .danish
                        ? "Leder efter højttalere… Når en er fundet kan du f.eks. sige 'Beolab, afspil'"
                        : "Looking for speakers… Once one is found you can say e.g. 'Beolab, play'"
                )
                .font(BeoType.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            // Dismiss button
            Button(action: onDismiss) {
                Text(language == .danish ? "OK" : "Got it")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 8)
                    .glassEffect(in: RoundedRectangle(cornerRadius: Radius.sheet))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sheet)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language == .danish ? "Afvis tip" : "Dismiss hint")
        }
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: Radius.card))
        .transition(.opacity)
    }

    @ViewBuilder
    private func exampleRow(_ text: String) -> some View {
        Text(text)
            .font(BeoType.confirmation)
            .foregroundStyle(.primary)
    }
}
