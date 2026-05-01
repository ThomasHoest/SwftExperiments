import Foundation

/// Owns mDNS discovery, maintains the live speaker list, and resolves voice commands
/// to a target speaker using three-tier fallback:
///   1. Explicit name match in the leading transcript words (fuzzy, Levenshtein ≤ 2)
///   2. Single actively-playing speaker (implicit session)
///   3. Most recently explicitly-addressed speaker
@available(*, deprecated, message: "Use SpeakerDiscoveryService instead.")
@MainActor
class SpeakerRegistry: ObservableObject {
    @Published private(set) var speakers: [Speaker] = []
    private(set) var activeSpeaker: Speaker?

    let favorites = FavoritesService()

    private let discovery = MdnsDiscovery()
    private let matcher   = SpeakerNameMatcher()

    init() {
        discovery.onSpeakerDiscovered = { [weak self] ip, platform in
            guard let self else { return }
            let (client, eventSource) = makeSpeakerClientPair(host: ip, platform: platform)
            let speaker = Speaker(host: ip, client: client, eventSource: eventSource, platform: platform)
            do {
                try await speaker.initialize()
                self.speakers.append(speaker)
            } catch {
                Log.error("[SpeakerRegistry] rejected \(ip): \(error.localizedDescription)")
            }
        }
        discovery.onSpeakerRemoved = { [weak self] ip in
            guard let self else { return }
            if let idx = self.speakers.firstIndex(where: { $0.host == ip }) {
                self.speakers[idx].dispose()
                self.speakers.remove(at: idx)
            }
            if self.activeSpeaker?.host == ip { self.activeSpeaker = nil }
        }
    }

    func start() { discovery.start() }
    func stop()  { discovery.stop() }

    /// Resolves a target speaker from the leading words of a transcript.
    /// - Returns: The matched speaker and the remaining words (command portion), or `nil` if
    ///   no speaker can be inferred.
    func resolve(words: [String]) -> (Speaker, remainingWords: [String])? {
        Log.verbose("[SpeakerRegistry] resolve words=\(words) registry=\(speakers.map(\.name))")

        // Tier 1: explicit name in transcript
        if let (speaker, consumed) = matcher.match(words: words, in: speakers) {
            let remaining = Array(words.dropFirst(consumed))
            Log.info("[SpeakerRegistry] tier-1 (name match) → \(speaker.name), remaining=\(remaining)")
            activeSpeaker = speaker
            return (speaker, remaining)
        }
        // Tier 2: exactly one speaker is playing → implicit session
        let playing = speakers.filter { $0.isPlaying }
        if playing.count == 1 {
            Log.info("[SpeakerRegistry] tier-2 (single playing) → \(playing[0].name)")
            return (playing[0], words)
        }
        if playing.count > 1 {
            Log.verbose("[SpeakerRegistry] tier-2 skipped — \(playing.count) speakers playing: \(playing.map(\.name))")
        }
        // Tier 3: last explicitly addressed speaker
        if let active = activeSpeaker {
            Log.info("[SpeakerRegistry] tier-3 (last active) → \(active.name)")
            return (active, words)
        }
        Log.info("[SpeakerRegistry] no speaker resolved (words=\(words), playing=\(playing.count))")
        return nil
    }
}
