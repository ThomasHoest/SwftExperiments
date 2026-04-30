import SwiftUI

struct SpeakerSelectorPill: View {
    var speakers: [Speaker]
    @Binding var selectedSpeaker: Speaker?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(speakers) { speaker in
                        let isActive = selectedSpeaker?.id == speaker.id
                        Button {
                            withAnimation(BeoAnimation.spring) { selectedSpeaker = speaker }
                            withAnimation(BeoAnimation.spring) { proxy.scrollTo(speaker.id, anchor: .center) }
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
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
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
