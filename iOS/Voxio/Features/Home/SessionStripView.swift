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

    // E-59 T-5905 — Per-card SessionViewModel dictionary (CF-3).
    // @State ensures a stable, long-lived instance for each group ID across re-renders.
    // Mirrors the existing @State scrollHostId stabilisation pattern.
    // Cleaned up via .onChange(of: groups.map(\.id)) when groups are removed.
    @State private var sessionVMs: [SpeakerGroup.ID: SessionViewModel] = [:]

    // E-59 — joinsInFlight aggregation for HomeView / SpeakerSelectorPill consumption.
    // Computed from all live session view models. Stays empty in E-59 (handleJoinDrop is stub).
    // E-60 T-6004 wires HomeView to read this and pass it to SpeakerSelectorPill.
    var joinsInFlightUnion: Set<String> {
        sessionVMs.values.reduce(into: Set<String>()) { $0.formUnion($1.joinsInFlight) }
    }

    /// The discovery service — injected from HomeView. Required to create SessionViewModels (CF-4).
    let discovery: SpeakerDiscoveryService

    /// E-59: binding written from .onChange observers in SessionStripView;
    /// read by HomeView and forwarded to SpeakerSelectorPill.
    @Binding var joinsInFlightUnionBinding: Set<String>

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
                        cardForGroup(group)
                            .frame(width: cardWidth)
                            .id(group.hostSpeaker.id)
                        // E-59 T-5905 — T-5907: Drop destination is per-card.
                        // Do NOT lift .dropDestination to the strip level (T-5907 comment).
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
                // Find the group where the selected speaker is host OR member.
                // The closure is hoisted into a local variable so the type-checker
                // doesn't have to infer the nested ||/contains-where chain in line.
                let selectedID = selected.id
                let predicate: (SpeakerGroup) -> Bool = { group in
                    if group.hostSpeaker.id == selectedID { return true }
                    return group.members.contains(where: { $0.id == selectedID })
                }
                guard let matchedGroup = groups.first(where: predicate) else {
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
                // E-59 T-5905 — Clean up sessionVMs for groups that no longer exist.
                let validIds = Set(newGroupIds)
                sessionVMs = sessionVMs.filter { validIds.contains($0.key) }
                // E-59 — Update joinsInFlightUnion binding so HomeView stays in sync.
                joinsInFlightUnionBinding = joinsInFlightUnion
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

    // MARK: - Per-card construction (extracted for type-checker performance)

    /// Builds a `SpeakerCard` for the given group with its stable `SessionViewModel`.
    /// Extracted from the `ForEach` body because the combination of an inline IIFE
    /// for `sessionVM` resolution plus the 8-arg `SpeakerCard` initialiser was
    /// exceeding the Swift type-checker's expression-complexity budget.
    @ViewBuilder
    private func cardForGroup(_ group: SpeakerGroup) -> some View {
        let isFrontmost = group.hostSpeaker.id == scrollHostId
        let sessionVM = resolvedSessionVM(for: group)
        SpeakerCard(
            speaker: group.hostSpeaker,
            isExpanded: isCommandActive,
            roll: isFrontmost ? roll : 0,
            pitch: isFrontmost ? pitch : 0,
            groupMembers: group.members.filter { $0.id != group.hostSpeaker.id },
            group: group,
            sessionVM: sessionVM,
            errorMessage: $errorMessage
        )
    }

    /// Get-or-create `SessionViewModel` for `group`. CF-3: the `@State` dictionary
    /// stabilises the instance across re-renders; deferred mutation avoids mutating
    /// `@State` during body evaluation.
    private func resolvedSessionVM(for group: SpeakerGroup) -> SessionViewModel {
        if let existing = sessionVMs[group.id] { return existing }
        let new = SessionViewModel(group: group, discovery: discovery)
        DispatchQueue.main.async { sessionVMs[group.id] = new }
        return new
    }
}
