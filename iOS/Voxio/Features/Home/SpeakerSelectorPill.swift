import SwiftUI
import UIKit

struct SpeakerSelectorPill: View {
    var speakers: [Speaker]
    @Binding var selectedSpeaker: Speaker?
    /// Used by the connector helper to determine which adjacent pills share a group. (T-5406)
    var groups: [SpeakerGroup]

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
            HStack(spacing: 0) {
                ForEach(speakers.indices, id: \.self) { i in
                    let speaker = speakers[i]
                    let isActive = selectedSpeaker?.id == speaker.id
                    let isPlaying = speaker.isPlaying

                    // T-2110 exception (a): speaker selector pills retain existing pill style (T-1004)
                    Button {
                        withAnimation(BeoAnimation.spring) { selectedSpeaker = speaker }
                    } label: {
                        pillButton(speaker: speaker, isActive: isActive, isPlaying: isPlaying)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: speaker, isActive: isActive, isPlaying: isPlaying))
                    .accessibilityHint(isActive ? "" : "Show this speaker")
                    .id(speaker.id)

                    // Connector segment between adjacent pills (T-5406)
                    if i < speakers.count - 1 {
                        connectorLine(currentSpeaker: speaker, nextSpeaker: speakers[i + 1])
                    }
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

    // MARK: - Pill button (T-5403 / T-5404)

    @ViewBuilder
    private func pillButton(speaker: Speaker, isActive: Bool, isPlaying: Bool) -> some View {
        HStack(spacing: Spacing.s8) {
            Text(speaker.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isPlaying ? BeoColor.accent : (isActive ? BeoColor.text : Color.primary))

            if isPlaying {
                PlaybackBars(height: 10)
                    .transition(.opacity.animation(BeoAnimation.toast))
            }
        }
        .padding(.leading, Spacing.s16)
        .padding(.trailing, Spacing.s12)
        .padding(.vertical, Spacing.s12)
        .glassEffect(in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    isPlaying
                        ? BeoColor.accent.opacity(0.55)
                        : (isActive ? Color.white.opacity(0.4) : Color.clear),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Accessibility label (T-5405)

    private func accessibilityLabel(for speaker: Speaker, isActive: Bool, isPlaying: Bool) -> String {
        var parts = [speaker.name]
        if isPlaying  { parts.append("playing") }
        if isActive   { parts.append("selected") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Group connector (T-5406)

    /// Returns true when speakers `a` and `b` share any `SpeakerGroup` in `groups`.
    /// Must be called on @MainActor. Pure sync query — no async.
    private func sameGroup(_ a: Speaker, _ b: Speaker) -> Bool {
        groups.contains { group in
            let ids = group.members.map(\.id)
            return ids.contains(a.id) && ids.contains(b.id)
        }
    }

    /// Draws a 1 pt muted connector (BeoColor.muted.opacity(0.3), width 8 pt, height 1 pt)
    /// when sameGroup returns true, otherwise a transparent placeholder of the same size.
    @ViewBuilder
    private func connectorLine(currentSpeaker: Speaker, nextSpeaker: Speaker) -> some View {
        Rectangle()
            .fill(sameGroup(currentSpeaker, nextSpeaker)
                  ? BeoColor.muted.opacity(0.3)
                  : Color.clear)
            .frame(width: 8, height: 1)
    }
}
