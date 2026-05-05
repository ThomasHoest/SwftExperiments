import Foundation

struct PersonalisationParser {
    private let store: PersonalisationStore
    private(set) var lastPath: String?

    init(store: PersonalisationStore) {
        self.store = store
    }

    mutating func parse(_ text: String, speakerId: String) -> ParsedCommand? {
        guard store.isEnabled else { return nil }
        let normalised = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let cmd = store.matchAlias(phrase: normalised, speakerId: speakerId) {
            Log.info("[PersonalisationParser] alias match for speakerId \(speakerId)")
            lastPath = "PersonalisationAlias"
            return cmd
        }
        if let cmd = store.matchConfirmedCommand(transcription: normalised, speakerId: speakerId) {
            Log.info("[PersonalisationParser] confirmed-command match for speakerId \(speakerId)")
            lastPath = "PersonalisationMemory"
            return cmd
        }
        return nil
    }
}
