import Foundation
import Observation

// MARK: - SessionViewModel (E-59 T-5902)
//
// Per-card drag-drop state for a single SpeakerGroup session card.
// Created and owned by SessionStripView in a [SpeakerGroup.ID: SessionViewModel]
// @State dictionary — this ensures a stable, long-lived instance across re-renders
// for the same group ID (CF-3).
//
// Behavioural contracts:
//   1. resolveSpeaker(_:) checks discovery.groups.flatMap(\.members), matches by
//      identifier.jid first (when non-nil), then by identifier.host. Returns nil
//      when no match found. discovery.allSpeakers is private (CF-4).
//   2. dropZoneActive and joinsInFlight mutations are on @MainActor.
//   3. Stub log lines:
//      handleJoinDrop: Log.info("[SessionVM] handleJoinDrop stub: \(source.name) → \(target.name)")
//      handleRemoveTap: Log.info("[SessionVM] handleRemoveTap stub: \(speaker.name)")

@Observable @MainActor
final class SessionViewModel {

    // MARK: - Drag-drop state

    /// True while a drag ghost is inside this card's bounds.
    /// Drives the gold-border overlay in SpeakerCard.
    var dropZoneActive: Bool = false

    /// Identifiers of sources currently in-flight for this card.
    /// Set<String> keyed by SpeakerIdentifier.id.
    var joinsInFlight: Set<String> = []

    /// Join tasks keyed by SpeakerIdentifier.id.
    /// Private(set) so E-60 can read keys but only SessionViewModel mutates.
    private(set) var joinTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Group and discovery context

    let group: SpeakerGroup
    let discovery: SpeakerDiscoveryService

    // MARK: - Init

    init(group: SpeakerGroup, discovery: SpeakerDiscoveryService) {
        self.group = group
        self.discovery = discovery
    }

    // MARK: - Speaker resolution (CF-4)
    //
    // Uses discovery.groups.flatMap(\.members) — every speaker assigned to at least
    // a solo group by ADR-003's reconstructGroupsAsync. discovery.allSpeakers is
    // private and cannot be accessed here.
    //
    // Race-window caveat: a speaker discovered by mDNS but not yet through
    // reconstructGroupsAsync() would be absent. Returning nil (rejecting the drop)
    // is safe — that speaker's pill wouldn't be draggable yet either.

    /// Resolves a transferred SpeakerIdentifier to a live Speaker.
    /// Matches by jid first (when non-nil), then by host. Returns nil if no match.
    func resolveSpeaker(_ identifier: SpeakerIdentifier) -> Speaker? {
        let allMembers = discovery.groups.flatMap(\.members)
        // JID-first match (Mozart; most stable)
        if let jid = identifier.jid {
            if let match = allMembers.first(where: { $0.identifier.jid == jid }) {
                return match
            }
        }
        // Host fallback (ASE or Mozart without JID resolved yet)
        return allMembers.first(where: { $0.identifier.host == identifier.host })
    }

    // MARK: - Join drop handler (stub — E-60 T-6001 implements)
    //
    // E-59: stub — logs the call and returns.
    // E-60 T-6001: full implementation (join API call, joinsInFlight management,
    //              discovery.refreshGroups() after ≥ 300 ms debounce per ADR-003 §5).
    // Do NOT call discovery.refreshGroups() here — that is E-60's responsibility.

    func handleJoinDrop(source: Speaker, target: Speaker) {
        Log.info("[SessionVM] handleJoinDrop stub: \(source.name) → \(target.name)")
    }

    // MARK: - Remove tap handler (stub — E-61 T-6101 implements)
    //
    // E-59: stub — logs the call and returns.
    // E-61 T-6101: full implementation (optimistic remove, leave() API call, rollback on failure).

    func handleRemoveTap(_ speaker: Speaker) {
        Log.info("[SessionVM] handleRemoveTap stub: \(speaker.name)")
    }
}
