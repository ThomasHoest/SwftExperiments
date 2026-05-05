import Foundation

typealias UtteranceClass = UtteranceClassifier.Outcome

/// Classifies a spoken utterance into one of five intent-first categories before
/// any speaker-specific parsing is attempted.
///
/// Classification order is locked:
///   1. broadcast  — router.parseBroadcast wins first so aliases cannot shadow broadcast phrases
///   2. personalised — alias / confirmed-command across all speakers
///   3. addressed  — SpeakerNameMatcher finds a speaker name in the tokens
///   4. focused    — fall back to the currently focused speaker (UI selection)
///   5. unresolved — no classification possible
@MainActor
struct UtteranceClassifier {

    enum Outcome {
        case broadcast(VoiceCommand)
        case personalised(speaker: Speaker, command: ParsedCommand)
        case addressed(speaker: Speaker, remainder: String)
        case focused(speaker: Speaker, text: String)
        case unresolved
    }

    private let discovery: SpeakerDiscoveryService
    private let personalisationStore: PersonalisationStore
    private let router: CommandParserRouter
    private let focusedSpeaker: () -> Speaker?

    init(
        discovery: SpeakerDiscoveryService,
        personalisationStore: PersonalisationStore,
        router: CommandParserRouter,
        focusedSpeaker: @escaping () -> Speaker?
    ) {
        self.discovery = discovery
        self.personalisationStore = personalisationStore
        self.router = router
        self.focusedSpeaker = focusedSpeaker
    }

    func classify(_ text: String) -> Outcome {
        // Branch 1: broadcast — runs before alias lookup so saved aliases cannot shadow broadcast intent
        if let broadcastCmd = router.parseBroadcast(text) {
            return .broadcast(broadcastCmd)
        }

        // Branch 2: personalised — cross-speaker alias or confirmed-command match
        if personalisationStore.isEnabled,
           let aliasMatch = personalisationStore.matchPersonalisedCommandAcrossAllSpeakers(phrase: text) {
            let allMembers = discovery.groups.flatMap(\.members)
            if let speaker = allMembers.first(where: { $0.stableId == aliasMatch.speakerId }) {
                Log.info("[UtteranceClassifier] personalised match → \(speaker.name) for: \(text)")
                return .personalised(speaker: speaker, command: aliasMatch.command)
            } else {
                Log.info("[UtteranceClassifier] personalised alias found but speaker offline, falling through for: \(text)")
            }
        }

        // Branch 3: addressed — SpeakerNameMatcher finds a name in the tokens
        let words = text.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        if let (speaker, remainingWords) = discovery.resolve(words: words) {
            let remainder = remainingWords.isEmpty ? text : remainingWords.joined(separator: " ")
            return .addressed(speaker: speaker, remainder: remainder)
        }

        // Branch 4: focused — use the currently selected speaker in the UI
        if let speaker = focusedSpeaker() {
            return .focused(speaker: speaker, text: text)
        }

        // Branch 5: unresolved
        return .unresolved
    }
}
