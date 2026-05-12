import SwiftUI
import UIKit

struct SpeakerSelectorPill: View {
    var speakers: [Speaker]
    @Binding var selectedSpeaker: Speaker?
    /// Used by the connector helper to determine which adjacent pills share a group. (T-5406)
    var groups: [SpeakerGroup]

    /// E-59 T-5903: union of joinsInFlight across all SessionViewModels. Supplied by HomeView.
    /// Default keeps pre-E-59 call sites valid (no breaking change).
    var joinsInFlightUnion: Set<String> = []

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
                    // E-59 T-5903/T-5904: draggable pills use .draggable + long-press haptic;
                    // non-draggable pills omit .draggable entirely (not nil — absent).
                    let draggable = isDraggable(speaker)
                    Group {
                        if draggable {
                            // Replaced Button with a styled view + .onTapGesture so the Button's
                            // built-in gesture recogniser doesn't compete with .draggable for
                            // long-press priority. .contentShape(Capsule()) makes the entire
                            // visible capsule grabbable (not just the text + bars subviews).
                            pillButton(speaker: speaker, isActive: isActive, isPlaying: isPlaying)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Capsule())
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel(accessibilityLabel(for: speaker, isActive: isActive, isPlaying: isPlaying))
                                .accessibilityHint(isActive ? "" : "Show this speaker")
                                .id(speaker.id)
                                // E-59 T-5904: drag source.
                                .draggable(speaker.identifier) {
                                    Log.info("[Drag] preview built for \(speaker.name) jid=\(speaker.identifier.jid ?? "nil")")
                                    return dragPreviewCapsule(speaker)
                                }
                                // Long-press fires lift haptic before the system drag begins.
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                                        Log.info("[Drag] lift haptic — \(speaker.name) eligible to drag")
                                        HapticEngine.shared.dragLifted()
                                    }
                                )
                                // Tap-to-select fires AFTER any drag has finished — TapGesture loses
                                // gesture competition to DragGesture, so tap only fires on a real tap.
                                .onTapGesture {
                                    withAnimation(BeoAnimation.spring) { selectedSpeaker = speaker }
                                }
                        } else {
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
                            // Non-draggable: .draggable modifier OMITTED (not nil — absent).
                            // .draggable(nil) behaves inconsistently across iOS versions.
                        }
                    }
                    // E-59 T-5903: dim non-draggable pills (spec TR-2 / design-spec §1.2 / §4.1 step 6).
                    .opacity(draggable ? 1.0 : 0.5)

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

    // MARK: - Drag eligibility (E-59 T-5903)
    //
    // Returns true when the pill may be dragged (spec TR-2):
    //   a) Returns false if speaker is the hostSpeaker of any group in `groups`
    //      with playbackState == .playing. Playing hosts anchor a session and
    //      cannot themselves join another session via drag.
    //   b) Returns false if speaker is a member of any group in `groups` with
    //      members.count > 1. The speaker is already in a multi-speaker group.
    //   c) Returns false if speaker.identifier.id is in joinsInFlightUnion.
    //      A join is already in flight for this speaker.
    //   Returns true otherwise (idle solo speaker is draggable).
    //
    // Note: joinsInFlightUnion is populated by HomeView from SessionViewModel.joinsInFlight
    // aggregation (T-6004). In E-59 scope, joinsInFlight stays empty (stub handleJoinDrop).
    private func isDraggable(_ speaker: Speaker) -> Bool {
        // (a) Playing host — cannot drag the host of a playing session
        let isPlayingHost = groups.contains { group in
            group.hostSpeaker.id == speaker.id && group.playbackState == .playing
        }
        if isPlayingHost { return false }

        // (b) Already in a multi-speaker group
        let isInMultiSpeakerGroup = groups.contains { group in
            group.members.count > 1 &&
            group.members.contains { $0.id == speaker.id }
        }
        if isInMultiSpeakerGroup { return false }

        // (c) Join in flight for this speaker
        if joinsInFlightUnion.contains(speaker.identifier.id) { return false }

        return true
    }

    // MARK: - Drag preview capsule (E-59 T-5904)
    //
    // A near-perfect copy of the source pill rendered at 0.85 opacity, 1.06× scale.
    // The scale and opacity are applied within the preview view itself per spec design-spec §2.1.
    // SwiftUI's .draggable handles the ghost rendering; this closure provides only the preview.
    @ViewBuilder
    private func dragPreviewCapsule(_ speaker: Speaker) -> some View {
        HStack(spacing: Spacing.s8) {
            Text(speaker.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(speaker.isPlaying ? BeoColor.accent : Color.primary)
        }
        .padding(.leading, Spacing.s16)
        .padding(.trailing, Spacing.s12)
        .padding(.vertical, Spacing.s12)
        .glassEffect(in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )
        .opacity(0.85)
        .scaleEffect(1.06)
    }
}
