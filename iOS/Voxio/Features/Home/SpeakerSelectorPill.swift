import SwiftUI
import UIKit

struct SpeakerSelectorPill: View {
    var speakers: [Speaker]
    @Binding var selectedSpeaker: Speaker?

    @State private var scrollPosition: Speaker.ID?

    // SwiftUI's layout proposes an inflated width (~408pt on iPhone 14 Pro instead of 393pt)
    // due to an iOS 26 ZStack geometry issue. Read the true screen width from UIKit directly.
    private var scrollWidth: CGFloat {
        let w = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 0
        return w - 40
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(speakers) { speaker in
                    let isActive = selectedSpeaker?.id == speaker.id
                    // T-2110 exception (a): speaker selector pills retain existing pill style (T-1004)
                    Button {
                        withAnimation(BeoAnimation.spring) { selectedSpeaker = speaker }
                    } label: {
                        pillButton(name: speaker.name, isActive: isActive)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isActive ? "\(speaker.name), selected" : speaker.name)
                    .accessibilityHint(isActive ? "" : "Select this speaker")
                    .id(speaker.id)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .onChange(of: selectedSpeaker?.id) { _, id in
            withAnimation(BeoAnimation.spring) { scrollPosition = id }
        }
        .frame(width: scrollWidth)
        .clipShape(Rectangle())
    }

    @ViewBuilder
    private func pillButton(name: String, isActive: Bool) -> some View {
        Text(name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isActive ? Color(hex: "#C8A97E") : .primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .glassEffect(in: Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isActive ? Color(hex: "#C8A97E").opacity(0.55) : Color.clear,
                        lineWidth: 1
                    )
            )
    }
}
