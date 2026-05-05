import Testing
import CoreData
@testable import Voxio

// MARK: - PersonalisationParserTests
//
// Tests for PersonalisationParser (T-3303 / T-3304).
// PersonalisationParser is a pure struct that wraps PersonalisationStore.
// All tests use PersistenceController.preview (in-memory Core Data store).

@Suite("PersonalisationParser — Alias matching")
struct PersonalisationParserAliasTests {

    private func makeParser(isEnabled: Bool = true) -> (PersonalisationParser, PersonalisationStore) {
        let store = PersonalisationStore(context: PersistenceController.preview.viewContext)
        store.isEnabled = isEnabled
        let parser = PersonalisationParser(store: store)
        return (parser, store)
    }

    // MARK: T-3303-A1 — alias match returns ParsedCommand with correct intent

    @Test("parse: alias match returns ParsedCommand with correct intent")
    @MainActor
    func parse_aliasMatch_returnsCorrectIntent() throws {
        let (parser, store) = makeParser()
        let speakerId = "spk-parser-alias-1"

        try store.saveAlias(
            speakerId: speakerId,
            phrase: "morning routine",
            intent: .playFavoriteByNumber,
            slots: ["favoriteIndex": "3"]
        )

        let result = parser.parse("morning routine", speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .playFavoriteByNumber)
        #expect(result?.favoriteIndex == 3)
    }

    // MARK: T-3303-A2 — alias takes priority over confirmed-command

    @Test("parse: alias takes priority over confirmed-command for the same phrase")
    @MainActor
    func parse_aliasPriority_overConfirmedCommand() throws {
        let (parser, store) = makeParser()
        let speakerId = "spk-alias-priority"
        let phrase = "my special phrase"

        // Add a confirmed-command entry with .stop intent
        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: phrase,
            intent: .stop,
            slots: [:]
        )

        // Add an alias with .mute intent for the same phrase
        try store.saveAlias(
            speakerId: speakerId,
            phrase: phrase,
            intent: .mute,
            slots: [:]
        )

        // Alias (mute) must win over confirmed-command (stop)
        let result = parser.parse(phrase, speakerId: speakerId)
        #expect(result?.intent == .mute, "Alias should take priority over confirmed-command")
    }

    // MARK: T-3303-A3 — no match returns nil

    @Test("parse: returns nil when neither alias nor confirmed-command matches")
    @MainActor
    func parse_noMatch_returnsNil() throws {
        let (parser, store) = makeParser()
        let speakerId = "spk-no-match"

        try store.saveAlias(speakerId: speakerId, phrase: "existing phrase", intent: .stop, slots: [:])

        let result = parser.parse("completely different phrase", speakerId: speakerId)
        #expect(result == nil)
    }

    @Test("parse: returns nil when store is empty for speakerId")
    @MainActor
    func parse_emptyStore_returnsNil() {
        let (parser, _) = makeParser()
        let result = parser.parse("anything", speakerId: "spk-empty")
        #expect(result == nil)
    }

    // MARK: T-3303-A4 — isEnabled = false always returns nil

    @Test("parse: isEnabled=false returns nil even when alias exists")
    @MainActor
    func parse_isEnabledFalse_aliasExists_returnsNil() throws {
        let (parser, store) = makeParser(isEnabled: false)
        let speakerId = "spk-disabled-alias"

        try store.saveAlias(
            speakerId: speakerId,
            phrase: "go silent",
            intent: .mute,
            slots: [:]
        )

        let result = parser.parse("go silent", speakerId: speakerId)
        #expect(result == nil, "isEnabled=false must prevent any match")
    }

    @Test("parse: isEnabled=false returns nil even when confirmed-command exists")
    @MainActor
    func parse_isEnabledFalse_confirmedCommandExists_returnsNil() throws {
        let (parser, store) = makeParser(isEnabled: false)
        let speakerId = "spk-disabled-cmd"

        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: "louder now",
            intent: .volumeUp,
            slots: [:]
        )

        let result = parser.parse("louder now", speakerId: speakerId)
        #expect(result == nil, "isEnabled=false must prevent any match")
    }
}

// MARK: -

@Suite("PersonalisationParser — ConfirmedCommand matching")
struct PersonalisationParserConfirmedCommandTests {

    private func makeParser() -> (PersonalisationParser, PersonalisationStore) {
        let store = PersonalisationStore(context: PersistenceController.preview.viewContext)
        store.isEnabled = true
        let parser = PersonalisationParser(store: store)
        return (parser, store)
    }

    // MARK: T-3303-B1 — confirmed-command match returns ParsedCommand

    @Test("parse: confirmed-command match returns ParsedCommand with correct intent")
    @MainActor
    func parse_confirmedCommandMatch_returnsCorrectIntent() throws {
        let (parser, store) = makeParser()
        let speakerId = "spk-confirmed-match"

        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: "turn it up",
            intent: .volumeUp,
            slots: ["volumeDelta": "20"]
        )

        let result = parser.parse("turn it up", speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .volumeUp)
        #expect(result?.volumeDelta == 20)
    }
}

// MARK: -

@Suite("PersonalisationParser — Input normalisation")
struct PersonalisationParserNormalisationTests {

    private func makeParser() -> (PersonalisationParser, PersonalisationStore) {
        let store = PersonalisationStore(context: PersistenceController.preview.viewContext)
        store.isEnabled = true
        let parser = PersonalisationParser(store: store)
        return (parser, store)
    }

    // MARK: T-3303-C1 — leading/trailing whitespace is normalised

    @Test("parse: leading whitespace in input is normalised before matching")
    @MainActor
    func parse_leadingWhitespace_normalised() throws {
        let (parser, store) = makeParser()
        let speakerId = "spk-whitespace-lead"

        try store.saveAlias(speakerId: speakerId, phrase: "stop the bass", intent: .stop, slots: [:])

        let result = parser.parse("   stop the bass", speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .stop)
    }

    @Test("parse: trailing whitespace in input is normalised before matching")
    @MainActor
    func parse_trailingWhitespace_normalised() throws {
        let (parser, store) = makeParser()
        let speakerId = "spk-whitespace-trail"

        try store.saveAlias(speakerId: speakerId, phrase: "stop the bass", intent: .stop, slots: [:])

        let result = parser.parse("stop the bass   ", speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .stop)
    }

    @Test("parse: leading and trailing whitespace in input both normalised")
    @MainActor
    func parse_bothWhitespace_normalised() throws {
        let (parser, store) = makeParser()
        let speakerId = "spk-whitespace-both"

        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: "pause music",
            intent: .pause,
            slots: [:]
        )

        let result = parser.parse("  pause music  ", speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .pause)
    }

    @Test("parse: mixed-case input with whitespace is normalised")
    @MainActor
    func parse_mixedCaseAndWhitespace_normalised() throws {
        let (parser, store) = makeParser()
        let speakerId = "spk-case-and-space"

        try store.saveAlias(speakerId: speakerId, phrase: "evening calm", intent: .resume, slots: [:])

        let result = parser.parse("  Evening Calm  ", speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .resume)
    }

    @Test("parse: empty string after whitespace trimming returns nil")
    @MainActor
    func parse_whitespaceOnly_returnsNil() throws {
        let (parser, _) = makeParser()
        // A phrase composed only of spaces normalises to empty string — should not match anything
        let result = parser.parse("   ", speakerId: "spk-space-only")
        #expect(result == nil)
    }
}

// MARK: -

@Suite("PersonalisationParser — isEnabled toggle re-enables correctly")
struct PersonalisationParserToggleTests {

    @Test("parse: re-enabling isEnabled after it was false resumes matching")
    @MainActor
    func parse_reEnableAfterDisable_matchesAgain() throws {
        let store = PersonalisationStore(context: PersistenceController.preview.viewContext)
        let speakerId = "spk-re-enable"
        let parser = PersonalisationParser(store: store)

        try store.saveAlias(speakerId: speakerId, phrase: "go quiet", intent: .mute, slots: [:])

        store.isEnabled = false
        #expect(parser.parse("go quiet", speakerId: speakerId) == nil)

        store.isEnabled = true
        let result = parser.parse("go quiet", speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .mute)
    }
}
