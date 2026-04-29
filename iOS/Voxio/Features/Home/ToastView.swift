import SwiftUI

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(alignment: listItems.isEmpty ? .center : .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(BeoType.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !listItems.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(listItems, id: \.self) { item in
                                Text("• \(item)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 80)
                }
            }
        }
        .padding(.horizontal, Spacing.s16)
        .padding(.vertical, Spacing.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: Radius.sheet))
        .padding(.horizontal, Spacing.s16)
    }

    private var iconName: String {
        switch toast.kind {
        case .error:                     return "exclamationmark.bubble"
        case .volumeLimit(_, let isMax): return isMax ? "speaker.wave.3" : "speaker.slash"
        case .success:                   return "checkmark.circle"
        }
    }

    private var iconColor: Color {
        switch toast.kind {
        case .error:       return BeoColor.muted
        case .volumeLimit: return BeoColor.accent
        case .success:     return Color.green
        }
    }

    private var message: String {
        switch toast.kind {
        case .error(let m, _):       return m
        case .volumeLimit(let m, _): return m
        case .success(let m):        return m
        }
    }

    private var listItems: [String] {
        if case .error(_, let list) = toast.kind { return list }
        return []
    }
}
