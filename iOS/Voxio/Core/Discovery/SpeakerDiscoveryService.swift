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
        do {
            try await speaker.initialize()
            allSpeakers.append(speaker)
            SpeakerStore.shared.allSpeakers = allSpeakers
            Log.info("[SDS] added \(speaker.name) (\(ip)) platform=\(platform.rawValue)")
            scheduleReconstruction()
            scheduleInitialSettle()
        } catch {
            Log.error("[SDS] rejected \(ip) (\(platform.rawValue)): \(error)")
        }
    }

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
            }
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

    private func reconstructGroupsAsync() async {
        let speakers = allSpeakers
        var sets = Array(0..<speakers.count)

        func find(_ x: Int) -> Int {
            var x = x
            while sets[x] != x { sets[x] = sets[sets[x]]; x = sets[x] }
            return x
        }
        func union(_ x: Int, _ y: Int) { sets[find(x)] = find(y) }

        for (i, speaker) in speakers.enumerated() {
            guard speaker.identifier.platform == .mozart else { continue }
            let peers = (try? await speaker.client.getPeers()) ?? []
            for peer in peers {
                if let j = speakers.firstIndex(where: { $0.identifier.jid == peer.jid }) {
                    union(i, j)
                }
            }
        }

        var components: [Int: [Speaker]] = [:]
        for (i, speaker) in speakers.enumerated() {
            components[find(i), default: []].append(speaker)
        }

        groups = components.values.map { members in
            let host = members.first(where: { $0.identifier.platform == .mozart }) ?? members[0]
            return SpeakerGroup(members: members, hostSpeaker: host)
        }
        Log.info("[SDS] \(groups.count) group(s) from \(speakers.count) speaker(s)")
        WidgetStateWriter.writeDiscoveredSpeakers(speakers)
    }

    // Group state mutations (called from E-32 join/leave dispatch)
    func mergeIntoSpeakerGroup(source: Speaker, target: Speaker) {
        removeMember(source)
        if let tg = groups.first(where: { $0.members.contains { $0.id == target.id } }) {
            tg.members.append(source)
            tg.id = SpeakerGroup.makeId(for: tg.members)
        } else {
            groups.append(SpeakerGroup(members: [target, source], hostSpeaker: target))
        }
    }

    func removeMember(_ speaker: Speaker) {
        for (gi, group) in groups.enumerated() {
            guard let mi = group.members.firstIndex(where: { $0.id == speaker.id }) else { continue }
            group.members.remove(at: mi)
            if group.members.isEmpty {
                groups.remove(at: gi)
            } else if group.hostSpeaker.id == speaker.id {
                group.hostSpeaker = group.members[0]
                group.id = SpeakerGroup.makeId(for: group.members)
            }
            return
        }
    }
}
