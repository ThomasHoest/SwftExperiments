import Foundation
import Combine

/// Owns mDNS discovery, maintains the live speaker list, and resolves voice commands
/// to a target speaker using three-tier fallback:
///   1. Explicit name match in the leading transcript words (fuzzy, Levenshtein ≤ 2)
///   2. Single actively-playing speaker (implicit session)
///   3. Most recently explicitly-addressed speaker
@MainActor
class SpeakerRegistry: ObservableObject {
    @Published private(set) var speakers: [Speaker] = []
    private(set) var activeSpeaker: Speaker?

    let favorites = FavoritesService()

    private let discovery = MdnsDiscovery()
    private let matcher   = SpeakerNameMatcher()
    private var cancellable: AnyCancellable?

    init() {
        cancellable = discovery.$speakers.sink { [weak self] list in
            guard let self else { return }
            self.speakers = list
            if let active = self.activeSpeaker, !list.contains(where: { $0.id == active.id }) {
                self.activeSpeaker = nil
            }
        }
    }

    func start() { discovery.start() }
    func stop()  { discovery.stop() }

    /// Resolves a target speaker from the leading words of a transcript.
    /// - Returns: The matched speaker and the remaining words (command portion), or `nil` if
    ///   no speaker can be inferred.
    func resolve(words: [String]) -> (Speaker, remainingWords: [String])? {
        // Tier 1: explicit name in transcript
        if let (speaker, consumed) = matcher.match(words: words, in: speakers) {
            activeSpeaker = speaker
            return (speaker, Array(words.dropFirst(consumed)))
        }
        // Tier 2: exactly one speaker is playing → implicit session
        let playing = speakers.filter { $0.isPlaying }
        if playing.count == 1 {
            return (playing[0], words)
        }
        // Tier 3: last explicitly addressed speaker
        if let active = activeSpeaker {
            return (active, words)
        }
        return nil
    }
}
