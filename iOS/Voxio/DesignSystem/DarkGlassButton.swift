import SwiftUI

// T-2102 / T-2103 / T-2104 — Dark Liquid Glass pill button (v1.1)
// Haptics are the call site's responsibility — this component emits none.

struct DarkGlassButton: View {
    enum Role {
        case `default`
        case confirm    // accent gold icon; no v1.1 call sites — retained for forward compatibility
        case cancel     // label and icon in system red
        case disabled   // 0.4 opacity, non-interactive
    }

    let label: String
    var systemImage: String? = nil
    var role: Role = .default
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    private var labelColor: Color {
        switch role {
        case .cancel: return .red
        default:      return BeoColor.labelPrimary
        }
    }

    private var iconColor: Color {
        switch role {
        case .confirm: return BeoColor.accent
        case .cancel:  return .red
        default:       return .white
        }
    }

    // T-2205 — Increase Contrast border treatment
    private var borderColor: Color {
        contrast == .increased ? BeoColor.labelSecondary : DarkGlassButtonTokens.borderColor
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 1.0 : DarkGlassButtonTokens.borderWidth
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DarkGlassButtonTokens.iconGap) {
                if let img = systemImage {
                    Image(systemName: img)
                        .foregroundStyle(iconColor)
                        .symbolRenderingMode(.hierarchical)
                }
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(labelColor)
            }
            .padding(.vertical, DarkGlassButtonTokens.paddingV)
            .padding(.horizontal, DarkGlassButtonTokens.paddingH)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(DarkGlassPillStyle(borderColor: borderColor, borderWidth: borderWidth))
        .disabled(role == .disabled)
        .opacity(role == .disabled ? 0.4 : 1.0)
        .accessibilityLabel(label)
    }
}

// T-2104 — Icon-only circular variant; 36 × 36 pt visual, 44 × 44 pt hit area
struct DarkGlassIconButton: View {
    enum Role {
        case `default`
        case confirm
        case cancel
        case disabled
    }

    let systemImage: String
    var role: Role = .default
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    private var iconColor: Color {
        switch role {
        case .confirm: return BeoColor.accent
        case .cancel:  return .red
        default:       return .white
        }
    }

    private var borderColor: Color {
        contrast == .increased ? BeoColor.labelSecondary : DarkGlassButtonTokens.borderColor
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 1.0 : DarkGlassButtonTokens.borderWidth
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)
                .frame(width: DarkGlassButtonTokens.iconOnlySize,
                       height: DarkGlassButtonTokens.iconOnlySize)
        }
        .buttonStyle(DarkGlassPillStyle(borderColor: borderColor, borderWidth: borderWidth))
        .frame(minWidth: 44, minHeight: 44)
        .disabled(role == .disabled)
        .opacity(role == .disabled ? 0.4 : 1.0)
        .accessibilityLabel(accessibilityLabel)
    }
}

// Shared ButtonStyle — glass surface + press scale animation
private struct DarkGlassPillStyle: ButtonStyle {
    let borderColor: Color
    let borderWidth: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(
                .regular.tint(.black.opacity(0.45)).interactive(),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .scaleEffect(configuration.isPressed
                ? DarkGlassButtonTokens.pressedScale
                : 1.0
            )
            .animation(
                .spring(
                    response: DarkGlassButtonTokens.pressSpringResponse,
                    dampingFraction: DarkGlassButtonTokens.pressSpringDamping
                ),
                value: configuration.isPressed
            )
    }
}

// MARK: — Previews (T-2111)

#Preview("DarkGlassButton — all roles") {
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        VStack(spacing: 16) {
            DarkGlassButton(label: "Default", systemImage: "play.fill", role: .default, action: {})
            DarkGlassButton(label: "Confirm", systemImage: "checkmark", role: .confirm, action: {})
            DarkGlassButton(label: "Cancel", systemImage: "xmark", role: .cancel, action: {})
            DarkGlassButton(label: "Disabled", systemImage: "speaker.slash", role: .disabled, action: {})
        }
        .padding(24)
    }
    .preferredColorScheme(.dark)
}

#Preview("DarkGlassButton — Increase Contrast") {
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        VStack(spacing: 16) {
            DarkGlassButton(label: "Default", systemImage: "play.fill", role: .default, action: {})
            DarkGlassButton(label: "Cancel", systemImage: "xmark", role: .cancel, action: {})
            DarkGlassButton(label: "Disabled", role: .disabled, action: {})
        }
        .padding(24)
    }
    .preferredColorScheme(.dark)
    // Increase Contrast cannot be forced in previews; test via Accessibility settings
}

#Preview("DarkGlassIconButton — roles") {
    ZStack {
        Color(hex: "#0A0E1A").ignoresSafeArea()
        HStack(spacing: 16) {
            DarkGlassIconButton(systemImage: "questionmark.circle", role: .default,
                                accessibilityLabel: "Help", action: {})
            DarkGlassIconButton(systemImage: "checkmark", role: .confirm,
                                accessibilityLabel: "Confirm", action: {})
            DarkGlassIconButton(systemImage: "xmark", role: .cancel,
                                accessibilityLabel: "Cancel", action: {})
            DarkGlassIconButton(systemImage: "speaker.slash", role: .disabled,
                                accessibilityLabel: "Disabled", action: {})
        }
        .padding(24)
    }
    .preferredColorScheme(.dark)
}
