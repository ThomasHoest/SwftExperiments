import Foundation
import Combine

@MainActor
class SpeakerDiscoveryService: ObservableObject {
    @Published private(set) var groups: [SpeakerGroup] = []
    /// Becomes true once an initial-discovery settle window has elapsed without
    /// new speakers being added. Subscribers can safely run startup logic
    /// (e.g. picking the playing speaker as the default selection) once this fires.
    @Published private(set) var didSettle: Bool = false
    let favorites = FavoritesService()

    private let discovery = MdnsDiscovery()
    private var allSpeakers: [Speaker] = []
    private var settleTask: Task<Void, Never>?
    private var initialSettleTask: Task<Void, Never>?
    private let matcher = SpeakerNameMatcher()
    private(set) var activeSpeaker: Speaker?
    private var autoRetryTask: Task<Void, Never>?
    /// Coalesces multiple WS group-hint events into a single refreshGroups call.
    private var groupHintRefreshTask: Task<Void, Never>?

    init() {
        discovery.onSpeakerDiscovered = { [weak self] ip, platform in
            await self?.addSpeaker(ip: ip, platform: platform)
        }
        discovery.onSpeakerRemoved = { [weak self] ip in
            self?.removeSpeaker(ip: ip)
        }
    }

    func start() { discovery.start() }
    func stop()  { discovery.stop() }

    /// Re-starts the discovery pipeline from scratch.
    ///
    /// Cancels any pending auto-retry task, stops the current browse, clears all cached
    /// speaker and discovery state, then calls `start()`. `MdnsDiscovery.reset()` is called
    /// to clear `foundHosts` and related caches — without this, duplicate-host guards prevent
    /// re-discovery of previously known speakers (CF-2).
    ///
    /// This method is idempotent: calling it multiple times is safe.
    func restart() {
        autoRetryTask?.cancel()
        autoRetryTask = nil
        initialSettleTask?.cancel()
        stop()
        discovery.reset()
        allSpeakers = []
        groups = []
        didSettle = false
        Log.info("[SDS] restarted — all state cleared")
        start()
    }

    /// Schedules a silent 30-second auto-retry when discovery settled with zero speakers (T-5511).
    /// Cancelled when a speaker is added or when `restart()` is called manually.
    private func scheduleAutoRetry() {
        autoRetryTask?.cancel()
        autoRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            guard await self.didSettle && self.allSpeakers.isEmpty else { return }
            Log.info("[SDS] auto-retry: 30 s elapsed with no speakers, restarting")
            await self.restart()
        }
    }

    // Three-tier speaker resolution (same logic as old SpeakerRegistry)
    func resolve(words: [String]) -> (Speaker, remainingWords: [String])? {
        let speakers = allSpeakers
        if let (speaker, consumed) = matcher.match(words: words, in: speakers) {
            let remaining = Array(words.dropFirst(consumed))
            activeSpeaker = speaker
            return (speaker, remaining)
        }
        let playing = speakers.filter { $0.isPlaying }
        if playing.count == 1 { return (playing[0], words) }
        if let active = activeSpeaker { return (active, words) }
        return nil
    }

    private func addSpeaker(ip: String, platform: SpeakerPlatform) async {
        Log.info("[SDS] initializing \(platform.rawValue) speaker at \(ip)")
        let (client, eventSource) = makeSpeakerClientPair(host: ip, platform: platform)
        let speaker = Speaker(host: ip, client: client, eventSource: eventSource, platform: platform)
        // Beolink topology hint from WS — coalesced into one refresh per 500 ms.
        speaker.onGroupHint = { [weak self] in self?.scheduleGroupHintRefresh() }
        do {
            try await speaker.initialize()
            // Cancel any pending auto-retry now that we have at least one speaker.
            autoRetryTask?.cancel()
            autoRetryTask = nil
            allSpeakers.append(speaker)
            SpeakerStore.shared.allSpeakers = allSpeakers
            Log.info("[SDS] added \(speaker.name) (\(ip)) platform=\(platform.rawValue)")
            scheduleReconstruction()
            scheduleInitialSettle()
        } catch {
            Log.error("[SDS] rejected \(ip) (\(platform.rawValue)): \(error)")
        }
    }

    /// Coalesces multiple WS group-hint events (which can fire in bursts during a
    /// multiroom transition) into a single refreshGroups call. 500 ms is short
    /// enough to feel responsive but long enough to absorb a burst of related
    /// events firing across multiple speakers as a session forms or dissolves.
    private func scheduleGroupHintRefresh() {
        groupHintRefreshTask?.cancel()
        groupHintRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            Log.info("[SDS] WS group-hint debounce elapsed — refreshGroups()")
            await self.refreshGroups()
        }
    }

    // MARK: - Merge cooldown
    //
    // Mozart's `/beolink/listeners` lags 1–5 s behind a successful
    // `/beolink/expand` — the speaker returns 2xx for the expand but the
    // listeners endpoint reports the new follower only after internal state
    // settles. Within that window, reconstructGroupsAsync sees an empty (or
    // partial) listeners list and rebuilds the speaker's group from scratch,
    // wiping the optimistic merge that just made the dropped pill appear on
    // the card. The cooldown gates refreshGroups() so the local optimistic
    // state is the source of truth for a short period after a merge, then
    // refreshes resume normally to reconcile with whatever the server reports.
    private var mergeCooldownUntil: Date = .distantPast

    private static let mergeCooldownSeconds: TimeInterval = 5

    private func removeSpeaker(ip: String) {
        guard let idx = allSpeakers.firstIndex(where: { $0.host == ip }) else { return }
        let speaker = allSpeakers.remove(at: idx)
        SpeakerStore.shared.allSpeakers = allSpeakers
        speaker.dispose()
        WidgetStateWriter.removeSpeaker(host: ip)
        Log.info("[SDS] removed \(speaker.name) (\(ip))")
        // Remove from its group
        for (gi, group) in groups.enumerated() {
            guard let mi = group.members.firstIndex(where: { $0.host == ip }) else { continue }
            group.members.remove(at: mi)
            if group.members.isEmpty {
                groups.remove(at: gi)
            } else if group.hostSpeaker.host == ip {
                group.hostSpeaker = group.members[0]
            }
            break
        }
    }

    /// Resets a 2-second timer on each speaker addition. When the timer elapses
    /// without another addition, marks discovery as settled — subscribers can
    /// then run "all speakers discovered" startup logic (e.g. selecting the
    /// playing speaker). Fires at most once.
    /// After settling with zero speakers, schedules a 30-second auto-retry (T-5511).
    private func scheduleInitialSettle() {
        guard !didSettle else { return }
        initialSettleTask?.cancel()
        initialSettleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard !self.didSettle else { return }
                self.didSettle = true
                Log.info("[SDS] initial discovery settled (\(self.allSpeakers.count) speakers)")
                // If no speakers were found, schedule the 30 s silent auto-retry.
                if self.allSpeakers.isEmpty {
                    self.scheduleAutoRetry()
                }
            }
            // Boot-time follow-up refresh: by the time we reach this point each
            // speaker has been through scheduleReconstruction() once (500 ms
            // after add). Mozart's /beolink/listeners endpoint can lag a couple
            // of seconds after a speaker comes online, so the first sweep may
            // return empty even when the speakers are actually grouped. Run one
            // more refresh ~3 s later so that the listener state has time to
            // settle on each device.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            Log.info("[SDS] post-settle follow-up — refreshGroups()")
            await self.refreshGroups()
        }
    }

    private func scheduleReconstruction() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms settle window
            guard !Task.isCancelled else { return }
            self?.reconstructGroups()
        }
    }

    private func reconstructGroups() {
        // Simple reconstruction: each speaker starts as its own group-of-1.
        // Union-find merges speakers that report each other as peers.
        // (Async peer fetching happens in scheduleReconstruction; for now, group-of-1 is the default)
        // Full peer-based grouping requires async getPeers() calls — handled by reconstructGroupsAsync().
        Task { [weak self] in
            await self?.reconstructGroupsAsync()
        }
    }

    /// ADR-003: forces a fresh group reconstruction. F2 (drag-to-join,
    /// tap-to-remove) calls this after every expand/leave write to surface the
    /// change in UI within ~500 ms. Public surface; safe to call any time.
    ///
    /// Skips if a merge happened in the last `mergeCooldownSeconds` — the
    /// optimistic local state is authoritative until Mozart's listeners
    /// endpoint catches up.
    func refreshGroups() async {
        let now = Date()
        if now < mergeCooldownUntil {
            let remaining = mergeCooldownUntil.timeIntervalSince(now)
            Log.info("[SDS] refreshGroups skipped — merge cooldown (\(String(format: "%.1f", remaining))s remaining)")
            return
        }
        await reconstructGroupsAsync()
    }

    /// ADR-003: build SpeakerGroups from live Beolink state rather than the mesh
    /// discovery list. Two-phase reconstruction:
    ///
    ///   1. Leader-side scan (Mozart): each Mozart speaker reports its current
    ///      followers via GET /beolink/listeners. Non-empty ⇒ leader; group is
    ///      [self] + resolve(listeners by JID).
    ///   2. Follower-side scan (ASE + Mozart cross-check): for each speaker not
    ///      yet placed in a group, query getLeaderJid(). If a known speaker has
    ///      that JID, fold this speaker into its group (creating a 2-speaker
    ///      group if the leader's listeners didn't include us — handles the
    ///      brief race where one side updates ahead of the other).
    ///   3. Leftover: solo group-of-1.
    ///
    /// See ADR-003 §6/§7 for the full contract. Replaces the previous union-find
    /// over /beolink/peers, which incorrectly merged every Beolink-reachable
    /// Mozart speaker into a single group regardless of playback state.
    private func reconstructGroupsAsync() async {
        let speakers = allSpeakers
        var groupBuilder: [String: [Speaker]] = [:]   // key = leader JID
        var leaderOrder: [String] = []                // preserves discovery order
        var assigned: Set<Speaker.ID> = []

        // ── Phase 1: leader-side scan (Mozart speakers report their listeners) ──
        //
        // Failure mode: getListeners() can time out (5 s) on a slow/asleep
        // Mozart speaker, OR return empty while the speaker hasn't yet
        // propagated a just-completed /beolink/expand. With the naïve
        // `try? await ... ?? []` pattern both outcomes collapse to "speaker is
        // not a leader" — which then strips a real leader of its followers and
        // wipes any optimistic merge that drag-to-join just performed. We
        // distinguish the two: API failure (catch) preserves the speaker's
        // current group from `groups` if it has one with > 1 member; empty
        // result (success) still falls through to Phase 2/3 since the speaker
        // genuinely has no followers.
        for speaker in speakers where speaker.identifier.platform == .mozart {
            guard !assigned.contains(speaker.id) else { continue }
            guard let selfJid = speaker.identifier.jid else { continue }

            let listenersOrNil: [BeolinkPeer]?
            do {
                listenersOrNil = try await speaker.client.getListeners()
            } catch {
                Log.info("[SDS] getListeners failed for \(speaker.name): \(error). Preserving existing group if any.")
                listenersOrNil = nil
            }

            if let listeners = listenersOrNil, !listeners.isEmpty {
                var members: [Speaker] = [speaker]
                for listener in listeners {
                    if let s = speakers.first(where: { $0.identifier.jid == listener.jid }),
                       !members.contains(where: { $0.id == s.id }) {
                        members.append(s)
                    }
                }
                groupBuilder[selfJid] = members
                leaderOrder.append(selfJid)
                for m in members { assigned.insert(m.id) }
            } else if listenersOrNil == nil,
                      let existing = groups.first(where: {
                          $0.hostSpeaker.id == speaker.id && $0.members.count > 1
                      }) {
                // API failed AND the local model still considers this speaker a
                // leader → trust local state until the next refresh confirms.
                Log.info("[SDS] preserving \(speaker.name)'s existing group of \(existing.members.count) member(s) (API unavailable)")
                groupBuilder[selfJid] = existing.members
                leaderOrder.append(selfJid)
                for m in existing.members { assigned.insert(m.id) }
            }
            // else: success + empty listeners → genuinely solo or follower;
            //       fall through to Phase 2 / Phase 3.
        }

        // ── Phase 2: follower-side cross-check (ASE always; Mozart fallback) ──
        for speaker in speakers where !assigned.contains(speaker.id) {
            guard let leaderJid = try? await speaker.client.getLeaderJid(),
                  let leader = speakers.first(where: { $0.identifier.jid == leaderJid }) else { continue }
            if var existing = groupBuilder[leaderJid] {
                if !existing.contains(where: { $0.id == speaker.id }) { existing.append(speaker) }
                groupBuilder[leaderJid] = existing
            } else {
                groupBuilder[leaderJid] = [leader, speaker]
                leaderOrder.append(leaderJid)
                assigned.insert(leader.id)
            }
            assigned.insert(speaker.id)
        }

        // ── Phase 3: leftover speakers become solo groups in discovery order ──
        var soloKeys: [String] = []
        for speaker in speakers where !assigned.contains(speaker.id) {
            let key = "solo-\(speaker.id.uuidString)"
            groupBuilder[key] = [speaker]
            soloKeys.append(key)
        }

        // Build final groups: leaders first (discovery order), then solos.
        let orderedKeys = leaderOrder + soloKeys
        groups = orderedKeys.compactMap { key in
            guard let members = groupBuilder[key], !members.isEmpty else { return nil }
            // Leader is the first member for leader-keyed groups (we put `self` or
            // `leader` first); for solo groups it's the only member.
            return SpeakerGroup(members: members, hostSpeaker: members[0])
        }

        // Per-speaker role log so on-device debugging is straightforward.
        for speaker in speakers {
            let role: String
            if let group = groups.first(where: { $0.members.contains(where: { $0.id == speaker.id }) }) {
                if group.members.count == 1 {
                    role = "solo"
                } else if group.hostSpeaker.id == speaker.id {
                    role = "leader (\(group.members.count - 1) follower(s))"
                } else {
                    role = "follower of \(group.hostSpeaker.name)"
                }
            } else {
                role = "UNASSIGNED"
            }
            Log.info("[SDS] \(speaker.name): \(role)")
        }
        Log.info("[SDS] \(groups.count) group(s) from \(speakers.count) speaker(s)")
        WidgetStateWriter.writeDiscoveredSpeakers(speakers)
    }

    // Group state mutations (called from E-32 join/leave dispatch).
    //
    // SwiftUI propagation note: `groups` is `@Published` on an ObservableObject.
    // `@Published` fires `objectWillChange` on array mutations (replace, append,
    // remove) but NOT on inner mutations of the class instances the array holds
    // — `tg.members.append(...)` alone is invisible to views observing through
    // `discovery.objectWillChange`. The merge branch therefore replaces the
    // SpeakerGroup at its index with a freshly-constructed instance carrying
    // the updated member list, guaranteeing both array-level and instance-level
    // diffing fire.
    func mergeIntoSpeakerGroup(source: Speaker, target: Speaker) {
        Log.info("[SDS] mergeIntoSpeakerGroup ENTER source=\(source.name) target=\(target.name)")
        removeMember(source)
        if let idx = groups.firstIndex(where: { $0.members.contains { $0.id == target.id } }) {
            let old = groups[idx]
            let new = SpeakerGroup(members: old.members + [source], hostSpeaker: old.hostSpeaker)
            groups[idx] = new
            let names = new.members.map(\.name).joined(separator: ", ")
            Log.info("[SDS] mergeIntoSpeakerGroup → \(new.hostSpeaker.name) now has \(new.members.count) member(s): [\(names)]")
        } else {
            let new = SpeakerGroup(members: [target, source], hostSpeaker: target)
            groups.append(new)
            Log.info("[SDS] mergeIntoSpeakerGroup → created new group \(new.hostSpeaker.name) with \(new.members.count) member(s)")
        }
        // Guard the optimistic merge from being clobbered by a refresh that
        // reads listeners before Mozart has internally propagated the expand.
        mergeCooldownUntil = Date().addingTimeInterval(Self.mergeCooldownSeconds)
    }

    func removeMember(_ speaker: Speaker) {
        for (gi, group) in groups.enumerated() {
            guard let mi = group.members.firstIndex(where: { $0.id == speaker.id }) else { continue }
            group.members.remove(at: mi)
            if group.members.isEmpty {
                groups.remove(at: gi)
            } else if group.hostSpeaker.id == speaker.id {
                // Host left → promote first remaining member. The group ID
                // anchors to the host's stable identifier, so rebuild it.
                group.hostSpeaker = group.members[0]
                group.id = SpeakerGroup.makeId(forHost: group.hostSpeaker)
            }
            return
        }
    }
}
