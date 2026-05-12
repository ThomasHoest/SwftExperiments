import Foundation
import UIKit
import Observation

// MARK: - SessionViewModel (E-59 T-5902 / E-60 T-6001 / T-6003)
//
// Per-card drag-drop state for a single SpeakerGroup session card.
// Created and owned by SessionStripView in a [SpeakerGroup.ID: SessionViewModel]
// @State dictionary — this ensures a stable, long-lived instance across re-renders
// for the same group ID (CF-3).
//
// E-60 additions (T-6001 / T-6003):
//   • onError: (String) -> Void — injected callback to surface error toasts (CF-1).
//     SessionStripView injects a closure that writes to HomeView's errorMessage binding.
//     Do NOT use a ToastCenter singleton — it does not exist (ADR-E60 CF-1).
//   • pulsingChips: Set<String> — chip ids in the 0.4 s success-pulse window (T-6003).
//   • lastDropCompletedAt: Date? — plain stored property; @Observable observes it
//     automatically (CF-2 — NOT @Published). Observed by coach-mark to trigger dismiss.
//   • handleJoinDrop: full implementation replacing E-59 stub.
//   • joinWithTimeout(source:target:seconds:) — static helper races join against 10 s
//     Task.sleep via withThrowingTaskGroup per ADR-002 D5.
//   • errorToastText(for:speakerName:) — maps SpeakerError to localised reason string.
//   • pulseChip(for:) — inserts id into pulsingChips, removes after 400 ms.
//
// Behavioural contracts:
//   1. resolveSpeaker(_:) checks discovery.groups.flatMap(\.members), matches by
//      identifier.jid first (when non-nil), then by identifier.host. Returns nil
//      when no match found. discovery.allSpeakers is private (CF-4).
//   2. dropZoneActive and joinsInFlight mutations are on @MainActor.
//   3. handleJoinDrop is idempotent — re-entry while joinsInFlight.contains(key) returns.
//   4. The detached Task is NOT cancelled on view teardown — spec TR-4 step 5.
//   5. On success: mergeIntoSpeakerGroup fires BEFORE joinsInFlight.remove so the
//      loading chip resolves to .member in the same render pass.
//   6. refreshGroups() runs after 350 ms sleep (≥ 300 ms ADR-003 §5 contract 6).
//   7. onError is always called on the main actor; injected closure writes to binding.
//   8. SpeakerError.timeout      → "Couldn't add NAME — connection timed out"
//      SpeakerError.unreachable  → "Couldn't add NAME — speaker unreachable"
//      Other                     → "Couldn't add NAME"

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
    /// Private(set) so callers can read keys; only SessionViewModel mutates.
    private(set) var joinTasks: [String: Task<Void, Never>] = [:]

    // MARK: - E-60 additions (T-6001 / T-6003)

    /// Chip ids currently in the 0.4 s success-pulse animation window.
    /// GroupChipRow (or the chip subview) reads this to apply the pulse effect.
    private(set) var pulsingChips: Set<String> = []

    /// Set on every successful join completion.
    /// Observed by GroupingCoachMark (T-5909) to trigger dismiss.
    /// Plain stored property — @Observable handles observation (ADR-E60 CF-2).
    var lastDropCompletedAt: Date? = nil

    // MARK: - Group and discovery context

    let group: SpeakerGroup
    let discovery: SpeakerDiscoveryService

    // MARK: - Error callback (E-60 CF-1)

    /// Delivers a user-facing error string to the enclosing view hierarchy.
    /// SessionStripView injects a closure that writes to HomeView's errorMessage binding.
    /// Must NOT be a ToastCenter call — no such singleton exists (ADR-E60 CF-1).
    let onError: (String) -> Void

    // MARK: - Init

    /// CF-6: signature changed from E-59 — onError parameter added.
    /// SessionStripView.resolvedSessionVM(for:) MUST be updated to supply the closure.
    init(
        group: SpeakerGroup,
        discovery: SpeakerDiscoveryService,
        onError: @escaping (String) -> Void
    ) {
        self.group = group
        self.discovery = discovery
        self.onError = onError
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

    // MARK: - Join drop handler (E-60 T-6001)
    //
    // Replaces E-59 stub. Full implementation per spec TR-4 and ADR-002 D5.
    //
    // Flow:
    //   1. Guard idempotency — return if key already in joinsInFlight.
    //   2. Insert key into joinsInFlight → loading chip appears.
    //   3. Fire commandRecognised() haptic synchronously on main actor.
    //   4. Launch a non-cancelled Task (survives view teardown per TR-4 step 5).
    //   5a. Success: mergeIntoSpeakerGroup → remove key → pulseChip → set lastDropCompletedAt
    //       → accessibility announcement → 350 ms sleep → refreshGroups().
    //   5b. Failure: remove key → errorOccurred haptic → onError(toastText).

    func handleJoinDrop(source: Speaker, target: Speaker) {
        let key = source.identifier.id
        Log.info("[Join] handleJoinDrop ENTER source=\(source.name)(\(source.host)) target=\(target.name)(\(target.host)) key=\(key)")
        guard !joinsInFlight.contains(key) else {
            Log.info("[Join] idempotent return — joinsInFlight already contains \(key)")
            return
        }
        joinsInFlight.insert(key)
        Log.info("[Join] inserted \(key) into joinsInFlight (now \(joinsInFlight.count) in flight)")
        HapticEngine.shared.commandRecognised()

        let task = Task { [weak self] in
            let started = Date()
            do {
                // The PLAYING device (target) is the broadcasting leader and is the one
                // that must call /beolink/expand (Mozart) or expandExperience (BNR) with
                // the new follower's JID. SpeakerClient.join(peer:) means "I'm the leader,
                // add this peer as my listener." Earlier code had source/target swapped,
                // which produced a syntactically valid no-op against the wrong device.
                Log.info("[Join] calling target.client.join(peer:) — target=\(target.name) expands to source=\(source.name) (peer.jid=\(source.identifier.jid ?? "nil") peer.host=\(source.identifier.host))")
                try await Self.joinWithTimeout(source: source, target: target, seconds: 10)
                let elapsed = Date().timeIntervalSince(started) * 1000
                Log.info("[Join] SUCCESS — \(source.name) → \(target.name) in \(Int(elapsed)) ms")
                await MainActor.run {
                    guard let self else { return }
                    // Merge BEFORE removing joinsInFlight so the chip resolves
                    // to .member in the same render pass (contract 5).
                    self.discovery.mergeIntoSpeakerGroup(source: source, target: target)
                    Log.info("[Join] mergeIntoSpeakerGroup applied — local model updated")
                    self.joinsInFlight.remove(key)
                    self.joinTasks.removeValue(forKey: key)
                    self.pulseChip(for: source)
                    self.lastDropCompletedAt = Date()
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "\(source.name) joined \(target.name)"
                    )
                }
                // ≥ 300 ms debounce per ADR-003 §5 contract 6 (350 ms chosen).
                try? await Task.sleep(for: .milliseconds(350))
                Log.info("[Join] post-debounce — calling discovery.refreshGroups()")
                await self?.discovery.refreshGroups()
            } catch {
                let elapsed = Date().timeIntervalSince(started) * 1000
                Log.error("[Join] FAILED \(source.name) → \(target.name) in \(Int(elapsed)) ms: \(error)")
                await MainActor.run {
                    guard let self else { return }
                    self.joinsInFlight.remove(key)
                    self.joinTasks.removeValue(forKey: key)
                    HapticEngine.shared.errorOccurred()
                    self.onError(Self.errorToastText(for: error, speakerName: source.name))
                }
            }
        }
        joinTasks[key] = task
    }

    // MARK: - Remove tap handler (stub — E-61 T-6101 implements)
    //
    // E-59: stub — logs the call and returns.
    // E-61 T-6101: full implementation (optimistic remove, leave() API call, rollback on failure).

    func handleRemoveTap(_ speaker: Speaker) {
        Log.info("[SessionVM] handleRemoveTap stub: \(speaker.name)")
    }

    // MARK: - Private helpers (E-60)

    /// Races `target.client.join(peer: source.identifier)` against a `seconds`-long
    /// `Task.sleep` timeout via `withThrowingTaskGroup`. First child to complete wins;
    /// the other is cancelled. Throws `SpeakerError.timeout` if the sleep wins first.
    ///
    /// Note the call direction: TARGET (the playing leader) calls `join(peer:)` with
    /// SOURCE's identifier, because `SpeakerClient.join(peer:)` means "I'm the leader,
    /// add this peer as my listener" — it invokes `/beolink/expand/{peer.jid}` on the
    /// caller (Mozart) or `expandExperience(listenerJid:)` on the caller (BNR).
    private static func joinWithTimeout(
        source: Speaker,
        target: Speaker,
        seconds: Int
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await target.client.join(peer: source.identifier) }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw SpeakerError.timeout
            }
            // First child result (success or thrown) determines outcome.
            try await group.next()
            group.cancelAll()
        }
    }

    /// Inserts `speaker.identifier.id` into `pulsingChips` and removes it after 400 ms.
    /// GroupChipRow (or individual chip subview) reads `pulsingChips` to trigger the
    /// 1.0 → 0.7 → 1.0 opacity pulse per design-spec §4.1 step 7.
    /// T-6003 simplification note: explicit keyframe animation requires passing
    /// pulsingChips into GroupChipRow — a non-trivial wiring change. The .member chip
    /// transition already animates naturally via ForEach identity diffing (loading chip
    /// removed, member chip appears). Explicit pulse plumbing is deferred; the
    /// ForEach insertion transition provides the visible success feedback.
    private func pulseChip(for speaker: Speaker) {
        let id = speaker.identifier.id
        pulsingChips.insert(id)
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            pulsingChips.remove(id)
        }
    }

    /// Maps a thrown error to a localised user-facing error toast string.
    /// Uses GroupingStrings for EN/DA support.
    ///
    ///   SpeakerError.timeout      → "Couldn't add NAME — connection timed out"
    ///   SpeakerError.unreachable  → "Couldn't add NAME — speaker unreachable"
    ///   Other                     → "Couldn't add NAME"
    private static func errorToastText(for error: Error, speakerName: String) -> String {
        let strings = GroupingStrings.forLanguage(LanguageService.shared.activeLanguage)
        switch error as? SpeakerError {
        case .timeout:
            return String(format: strings.joinFailed, speakerName, strings.joinFailedTimeout)
        case .unreachable:
            return String(format: strings.joinFailed, speakerName, strings.joinFailedUnreachable)
        default:
            return String(format: strings.joinFailedGeneric, speakerName)
        }
    }
}
