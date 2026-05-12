import SwiftUI
import UIKit

// MARK: - SessionStripView
// T-5201–T-5208: Horizontal paging strip — one SpeakerCard per playing SpeakerGroup.
//
// Two-way binding (T-5202):
//   • onChange(of: scrollHostId) → updates selectedSpeaker to the matching host.
//   • onChange(of: selectedSpeaker?.id) → animates scrollHostId to the matching group's host.
//   • Re-entrancy guard: only animate scrollHostId if the new host differs from the current.
//   • Idle-speaker case (US-62): if the selected speaker is not in any playing group, do NOT
//     change scrollHostId — the strip stays where it was.
//
// Card insertion/removal (T-5203):
//   • onChange(of: groups.map(\.id)) → if the previously-visible host is gone, scroll to first.
//
// Screen-width workaround (T-5201):
//   • UIApplication.shared.connectedScenes is used to read the true screen width,
//     matching the SpeakerSelectorPill workaround for the iOS 26 ZStack inflation issue.
//
// Single-session fallback (T-5207):
//   • .scrollDisabled(true) when groups.count == 1. No trailing peek. No page dots (T-5204 guard).
//
// Front-most parallax (T-5208):
//   • roll and pitch are passed only to the card whose group.hostSpeaker.id == scrollHostId.
//   • All other cards receive roll: 0, pitch: 0.

struct SessionStripView: View {
    /// Playing groups only — caller (HomeView) is responsible for pre-filtering.
    let groups: [SpeakerGroup]

    /// Two-way binding shared with SpeakerSelectorPill via HomeView state.
    @Binding var selectedSpeaker: Speaker?

    /// Parallax inputs forwarded to the front-most card only (T-5208).
    let roll: Double
    let pitch: Double

    /// Passed to each SpeakerCard for the isExpanded card-expand animation.
    let isCommandActive: Bool

    /// E-56 T-5606 — transport error pass-through.
    /// The same binding is shared across all cards in the strip. Concurrent errors: last write wins.
    @Binding var errorMessage: String?

    /// Bound to .scrollPosition(id:anchor:center) on the inner ScrollView.
    /// Drives the page-dot active index and the selectedSpeaker update.
    @State private var scrollHostId: Speaker.ID?

    // MARK: - Screen width workaround (matching SpeakerSelectorPill)
    // SwiftUI's layout proposes an inflated width (~408pt on iPhone 14 Pro instead of 393pt)
    // due to an iOS 26 ZStack geometry issue. Read the true screen width from UIKit directly.
    private var screenWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 0
    }

    private var cardWidth: CGFloat {
        screenWidth - (Spacing.s16 * 2)
    }

    // MARK: - Active index for page dots (T-5205)
    private var activeIndex: Int {
        groups.firstIndex(where: { $0.hostSpeaker.id == scrollHostId }) ?? 0
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // T-5201: Horizontal scroll strip
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Spacing.s8) {
                    ForEach(groups) { group in
                        let isFrontmost = group.hostSpeaker.id == scrollHostId
                        SpeakerCard(
                            speaker: group.hostSpeaker,
                            isExpanded: isCommandActive,
                            // T-5208: pass roll/pitch only to the front-most card
                            roll: isFrontmost ? roll : 0,
                            pitch: isFrontmost ? pitch : 0,
                            // E-53 T-5306: non-host group members for the chip row
                            groupMembers: group.members.filter { $0.id != group.hostSpeaker.id },
                            // E-56 T-5606: error binding pass-through to HomeView toast
                            errorMessage: $errorMessage
                        )
                        .frame(width: cardWidth)
                        .id(group.hostSpeaker.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollHostId, anchor: .center)
            // T-5207: disable scroll when single session — no trailing peek
            .scrollDisabled(groups.count == 1)
            // T-5202: strip → selectedSpeaker
            .onChange(of: scrollHostId) { _, newHostId in
                guard let newHostId else { return }
                if let matchedGroup = groups.first(where: { $0.hostSpeaker.id == newHostId }) {
                    selectedSpeaker = matchedGroup.hostSpeaker
                }
            }
            // T-5202: selectedSpeaker → strip (with re-entrancy guard and idle-speaker handling)
            .onChange(of: selectedSpeaker?.id) { _, _ in
                guard let selected = selectedSpeaker else { return }
                // Find the group where the selected speaker is host OR member
                guard let matchedGroup = groups.first(where: {
                    $0.hostSpeaker.id == selected.id ||
                    $0.members.contains(where: { $0.id == selected.id })
                }) else {
                    // Idle speaker (not a member of any playing group) — do NOT change scrollHostId (US-62)
                    return
                }
                // Re-entrancy guard (T-5202 contract assertion 3):
                // Only animate if the strip isn't already showing this group's host
                if matchedGroup.hostSpeaker.id != scrollHostId {
                    withAnimation(BeoAnimation.spring) {
                        scrollHostId = matchedGroup.hostSpeaker.id
                    }
                }
            }
            // T-5203: card insertion/removal — move to first group if current host is gone
            .onChange(of: groups.map(\.id)) { _, newGroupIds in
                guard let currentHostId = scrollHostId else {
                    // No current position — set to first
                    scrollHostId = groups.first?.hostSpeaker.id
                    return
                }
                let currentHostStillPresent = groups.contains(where: {
                    $0.hostSpeaker.id == currentHostId
                })
                if !currentHostStillPresent {
                    scrollHostId = groups.first?.hostSpeaker.id
                }
            }

            // T-5205: page dots below the ScrollView, separated by Spacing.s8
            if groups.count > 1 {
                SessionPageDots(count: groups.count, selectedIndex: activeIndex)
                    .padding(.top, Spacing.s8)
            }
        }
        // T-5201: initialise scrollHostId on first render
        .onAppear {
            if scrollHostId == nil {
                scrollHostId = groups.first?.hostSpeaker.id
            }
        }
    }
}
