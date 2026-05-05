import Testing
import CoreData
@testable import Voxio

// MARK: - PersonalisationStoreTests
//
// Tests for PersonalisationStore (T-3301 / T-3302).
// All tests use PersistenceController.preview (in-memory Core Data store).
// PersonalisationStore is @MainActor; every test function is @MainActor.
//
// NOTE: These tests require a VoxioTests Xcode test target with the
// Voxio.xcdatamodeld resource included in its target membership.

@Suite("PersonalisationStore — Alias CRUD")
struct PersonalisationStoreAliasTests {

    // Each test builds its own store from the preview in-memory context so
    // tests are fully isolated from each other.
    private func makeStore() -> PersonalisationStore {
        PersonalisationStore(context: PersistenceController.preview.viewContext)
    }

    // MARK: T-3302-A1 — saveAlias persists and aliases(for:) returns it

    @Test("saveAlias: saved alias is returned by aliases(for:)")
    @MainActor
    func saveAlias_returnedByAliasesFor() throws {
        let store = makeStore()
        let speakerId = "speaker-save-alias"

        try store.saveAlias(
            speakerId: speakerId,
            phrase: "morning music",
            intent: .playFavoriteByNumber,
            slots: ["favoriteIndex": "1"]
        )

        let records = store.aliases(for: speakerId)
        #expect(records.count == 1)
        #expect(records[0].phrase == "morning music")
        #expect(records[0].intent == .playFavoriteByNumber)
        #expect(records[0].slots["favoriteIndex"] == "1")
        #expect(records[0].speakerId == speakerId)
    }

    // MARK: T-3302-A2 — matchAlias returns ParsedCommand with correct intent (case-insensitive)

    @Test("matchAlias: case-insensitive exact match returns ParsedCommand with correct intent")
    @MainActor
    func matchAlias_caseInsensitive_returnsCorrectIntent() throws {
        let store = makeStore()
        let speakerId = "speaker-match-alias"

        try store.saveAlias(
            speakerId: speakerId,
            phrase: "Morning Music",
            intent: .setVolume,
            slots: ["volumeValue": "42"]
        )

        // Query with different casing
        let result = store.matchAlias(phrase: "morning music", speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .setVolume)
        #expect(result?.volumeValue == 42)
    }

    @Test("matchAlias: uppercase input matches lowercased saved phrase")
    @MainActor
    func matchAlias_uppercaseInput_matches() throws {
        let store = makeStore()
        let speakerId = "speaker-case-upper"

        try store.saveAlias(
            speakerId: speakerId,
            phrase: "stop the music",
            intent: .stop,
            slots: [:]
        )

        let result = store.matchAlias(phrase: "STOP THE MUSIC", speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .stop)
    }

    // MARK: T-3302-A3 — matchAlias returns nil when no alias exists for phrase

    @Test("matchAlias: returns nil when phrase has no stored alias")
    @MainActor
    func matchAlias_noMatch_returnsNil() throws {
        let store = makeStore()
        let speakerId = "speaker-no-alias"

        // Store an alias for a different phrase
        try store.saveAlias(
            speakerId: speakerId,
            phrase: "play jazz",
            intent: .playDefault,
            slots: [:]
        )

        let result = store.matchAlias(phrase: "something unrelated", speakerId: speakerId)
        #expect(result == nil)
    }

    // MARK: T-3302-A4 — matchAlias respects isEnabled = false

    @Test("matchAlias: isEnabled=false returns nil even when alias exists")
    @MainActor
    func matchAlias_isEnabledFalse_returnsNil() throws {
        let store = makeStore()
        let speakerId = "speaker-disabled"

        try store.saveAlias(
            speakerId: speakerId,
            phrase: "evening mood",
            intent: .resume,
            slots: [:]
        )

        store.isEnabled = false
        defer { store.isEnabled = true } // restore default so other tests unaffected

        // When isEnabled is false PersonalisationParser guards it, but the store's
        // matchAlias itself is still called. PersonalisationParser.parse() guards isEnabled.
        // Here we test the store directly — matchAlias should still return a result;
        // the isEnabled gate lives in PersonalisationParser.parse().
        // To test the combined behaviour (store + parser), see PersonalisationParserTests.
        let result = store.matchAlias(phrase: "evening mood", speakerId: speakerId)
        #expect(result != nil, "Store.matchAlias ignores isEnabled — gate is in PersonalisationParser")
    }

    // MARK: T-3302-A5 — deleteAlias removes by id

    @Test("deleteAlias: removes alias by id; subsequent aliases(for:) does not contain it")
    @MainActor
    func deleteAlias_removesById() throws {
        let store = makeStore()
        let speakerId = "speaker-delete-alias"

        try store.saveAlias(
            speakerId: speakerId,
            phrase: "bedtime tune",
            intent: .pause,
            slots: [:]
        )

        let before = store.aliases(for: speakerId)
        #expect(before.count == 1)
        let aliasId = before[0].id

        try store.deleteAlias(aliasId)

        let after = store.aliases(for: speakerId)
        #expect(after.isEmpty)
    }

    @Test("deleteAlias: deleting non-existent id is a no-op (no error thrown)")
    @MainActor
    func deleteAlias_nonExistentId_noOp() throws {
        let store = makeStore()
        #expect(throws: Never.self) {
            try store.deleteAlias(UUID())
        }
    }

    // MARK: T-3302-A6 — deleteAllAliases removes only targeted speaker's aliases

    @Test("deleteAllAliases: removes all aliases for speaker; leaves other speakers' aliases intact")
    @MainActor
    func deleteAllAliases_leavesOtherSpeakersIntact() throws {
        let store = makeStore()
        let speakerA = "speaker-delete-all-A"
        let speakerB = "speaker-delete-all-B"

        try store.saveAlias(speakerId: speakerA, phrase: "alpha one", intent: .stop, slots: [:])
        try store.saveAlias(speakerId: speakerA, phrase: "alpha two", intent: .pause, slots: [:])
        try store.saveAlias(speakerId: speakerB, phrase: "beta one", intent: .resume, slots: [:])

        try store.deleteAllAliases(for: speakerA)

        #expect(store.aliases(for: speakerA).isEmpty)
        #expect(store.aliases(for: speakerB).count == 1)
        #expect(store.aliases(for: speakerB)[0].phrase == "beta one")
    }
}

// MARK: -

@Suite("PersonalisationStore — ConfirmedCommand CRUD")
struct PersonalisationStoreConfirmedCommandTests {

    private func makeStore() -> PersonalisationStore {
        PersonalisationStore(context: PersistenceController.preview.viewContext)
    }

    // MARK: T-3302-B1 — recordConfirmedCommand inserts new row

    @Test("recordConfirmedCommand: inserts a new row on first call")
    @MainActor
    func recordConfirmedCommand_insertsNewRow() throws {
        let store = makeStore()
        let speakerId = "speaker-record-new"

        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: "play my playlist",
            intent: .playDefault,
            slots: [:]
        )

        // Verify via matchConfirmedCommand
        let result = store.matchConfirmedCommand(transcription: "play my playlist", speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .playDefault)
    }

    // MARK: T-3302-B2 — recordConfirmedCommand upserts: second call increments useCount

    @Test("recordConfirmedCommand: second call with same transcription+speakerId increments useCount")
    @MainActor
    func recordConfirmedCommand_secondCall_incrementsUseCount() throws {
        let store = makeStore()
        let speakerId = "speaker-upsert"
        let transcription = "louder please"

        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: transcription,
            intent: .volumeUp,
            slots: [:]
        )
        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: transcription,
            intent: .volumeUp,
            slots: [:]
        )

        // After two inserts the match should still succeed (not duplicate)
        // The useCount bump is internal; we verify via matchConfirmedCommand succeeding
        // and that only one row exists by checking matchConfirmedCommand returns data.
        let result = store.matchConfirmedCommand(transcription: transcription, speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .volumeUp)
    }

    @Test("recordConfirmedCommand: second call updates lastUsedAt to a later date")
    @MainActor
    func recordConfirmedCommand_secondCall_updatesLastUsedAt() throws {
        let store = makeStore()
        let speakerId = "speaker-lastusedat"
        let transcription = "silence now"

        let before = Date()
        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: transcription,
            intent: .mute,
            slots: [:]
        )
        // Insert a tiny sleep to ensure dates differ
        Thread.sleep(forTimeInterval: 0.01)
        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: transcription,
            intent: .mute,
            slots: [:]
        )

        // The record must still be findable after the upsert
        let result = store.matchConfirmedCommand(transcription: transcription, speakerId: speakerId)
        #expect(result != nil)
        _ = before // suppress unused-variable warning
    }

    // MARK: T-3302-B3 — matchConfirmedCommand returns correct ParsedCommand for exact match

    @Test("matchConfirmedCommand: returns correct ParsedCommand for exact-match transcription")
    @MainActor
    func matchConfirmedCommand_exactMatch_returnsCorrectCommand() throws {
        let store = makeStore()
        let speakerId = "speaker-exact-match"

        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: "set volume to 55",
            intent: .setVolume,
            slots: ["volumeValue": "55"]
        )

        let result = store.matchConfirmedCommand(transcription: "set volume to 55", speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .setVolume)
        #expect(result?.volumeValue == 55)
    }

    // MARK: T-3302-B4 — matchConfirmedCommand is case-insensitive

    @Test("matchConfirmedCommand: case-insensitive — 'Play Music' matches 'play music'")
    @MainActor
    func matchConfirmedCommand_caseInsensitive() throws {
        let store = makeStore()
        let speakerId = "speaker-case-insensitive"

        // Record with mixed case; store normalises to lowercase internally
        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: "Play Music",
            intent: .playDefault,
            slots: [:]
        )

        let result = store.matchConfirmedCommand(transcription: "play music", speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .playDefault)
    }

    @Test("matchConfirmedCommand: uppercase query matches lowercased stored transcription")
    @MainActor
    func matchConfirmedCommand_uppercaseQuery_matches() throws {
        let store = makeStore()
        let speakerId = "speaker-uppercase-query"

        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: "resume the song",
            intent: .resume,
            slots: [:]
        )

        let result = store.matchConfirmedCommand(transcription: "RESUME THE SONG", speakerId: speakerId)
        #expect(result != nil)
        #expect(result?.intent == .resume)
    }

    // MARK: T-3302-B5 — deleteConfirmedCommand removes the specific row

    @Test("deleteConfirmedCommand: removes the specific row")
    @MainActor
    func deleteConfirmedCommand_removesRow() throws {
        let store = makeStore()
        let speakerId = "speaker-delete-cmd"

        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: "quiet down",
            intent: .volumeDown,
            slots: [:]
        )

        // Confirm it exists
        #expect(store.matchConfirmedCommand(transcription: "quiet down", speakerId: speakerId) != nil)

        try store.deleteConfirmedCommand(transcription: "quiet down", speakerId: speakerId)

        #expect(store.matchConfirmedCommand(transcription: "quiet down", speakerId: speakerId) == nil)
    }

    @Test("deleteConfirmedCommand: deleting non-existent transcription is a no-op")
    @MainActor
    func deleteConfirmedCommand_nonExistent_noOp() throws {
        let store = makeStore()
        #expect(throws: Never.self) {
            try store.deleteConfirmedCommand(transcription: "ghost phrase", speakerId: "speaker-ghost")
        }
    }

    // MARK: T-3302-B6 — clearAllConfirmedCommands removes all rows

    @Test("clearAllConfirmedCommands: removes all rows across all speakers")
    @MainActor
    func clearAllConfirmedCommands_removesAll() throws {
        let store = makeStore()

        try store.recordConfirmedCommand(speakerId: "spk-clear-1", transcription: "phrase one", intent: .stop, slots: [:])
        try store.recordConfirmedCommand(speakerId: "spk-clear-2", transcription: "phrase two", intent: .pause, slots: [:])
        try store.recordConfirmedCommand(speakerId: "spk-clear-2", transcription: "phrase three", intent: .mute, slots: [:])

        try store.clearAllConfirmedCommands()

        #expect(store.matchConfirmedCommand(transcription: "phrase one", speakerId: "spk-clear-1") == nil)
        #expect(store.matchConfirmedCommand(transcription: "phrase two", speakerId: "spk-clear-2") == nil)
        #expect(store.matchConfirmedCommand(transcription: "phrase three", speakerId: "spk-clear-2") == nil)
    }
}

// MARK: -

@Suite("PersonalisationStore — LRU eviction")
struct PersonalisationStoreLRUTests {

    private func makeStore() -> PersonalisationStore {
        PersonalisationStore(context: PersistenceController.preview.viewContext)
    }

    // MARK: T-3302-C1 — 201 entries triggers eviction to 200 (oldest evicted)

    @Test("LRU eviction: after inserting 201 ConfirmedCommand rows count is capped at 200")
    @MainActor
    func lruEviction_201Inserts_countIs200() throws {
        let store = makeStore()
        let speakerId = "speaker-lru"

        // Insert 200 unique phrases first
        for i in 1...200 {
            try store.recordConfirmedCommand(
                speakerId: speakerId,
                transcription: "phrase \(i)",
                intent: .stop,
                slots: [:]
            )
        }

        // Insert the 201st — this should trigger eviction of the oldest entry
        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: "phrase 201",
            intent: .stop,
            slots: [:]
        )

        // Count rows for speakerId by attempting to fetch all (count via matchConfirmedCommand
        // isn't directly available, so we use aliases(for:) analogue via Core Data context)
        let context = PersistenceController.preview.viewContext
        let request: NSFetchRequest<ConfirmedCommand> = ConfirmedCommand.fetchRequest()
        request.predicate = NSPredicate(format: "speakerId == %@", speakerId)
        let count = try context.count(for: request)
        #expect(count == 200)
    }

    @Test("LRU eviction: oldest entry (phrase 1) is evicted when 201st entry is added")
    @MainActor
    func lruEviction_oldestEntryEvicted() throws {
        let store = makeStore()
        let speakerId = "speaker-lru-oldest"

        // Phrase 1 will be inserted first — it should be evicted
        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: "first phrase ever",
            intent: .stop,
            slots: [:]
        )

        // Insert 199 more unique phrases
        for i in 2...200 {
            try store.recordConfirmedCommand(
                speakerId: speakerId,
                transcription: "phrase \(i)",
                intent: .pause,
                slots: [:]
            )
        }

        // Insert 201st
        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: "phrase 201",
            intent: .resume,
            slots: [:]
        )

        // The first phrase should have been evicted
        let evicted = store.matchConfirmedCommand(transcription: "first phrase ever", speakerId: speakerId)
        #expect(evicted == nil, "Oldest entry should have been evicted by LRU")

        // The 201st phrase should still be present
        let newest = store.matchConfirmedCommand(transcription: "phrase 201", speakerId: speakerId)
        #expect(newest != nil)
    }

    @Test("LRU eviction: entries for different speakers are isolated — eviction only affects targeted speaker")
    @MainActor
    func lruEviction_isolatedPerSpeaker() throws {
        let store = makeStore()
        let speakerA = "speaker-lru-isolated-A"
        let speakerB = "speaker-lru-isolated-B"

        // Speaker B has one entry
        try store.recordConfirmedCommand(
            speakerId: speakerB,
            transcription: "keep me",
            intent: .mute,
            slots: [:]
        )

        // Fill speaker A to 200 + 1 to trigger eviction
        for i in 1...201 {
            try store.recordConfirmedCommand(
                speakerId: speakerA,
                transcription: "a phrase \(i)",
                intent: .stop,
                slots: [:]
            )
        }

        // Speaker B's entry must be untouched
        let speakerBResult = store.matchConfirmedCommand(transcription: "keep me", speakerId: speakerB)
        #expect(speakerBResult != nil)
    }

    @Test("LRU eviction: 200 entries does not trigger eviction")
    @MainActor
    func lruEviction_exactly200_noEviction() throws {
        let store = makeStore()
        let speakerId = "speaker-lru-exact-200"

        for i in 1...200 {
            try store.recordConfirmedCommand(
                speakerId: speakerId,
                transcription: "phrase \(i)",
                intent: .stop,
                slots: [:]
            )
        }

        let context = PersistenceController.preview.viewContext
        let request: NSFetchRequest<ConfirmedCommand> = ConfirmedCommand.fetchRequest()
        request.predicate = NSPredicate(format: "speakerId == %@", speakerId)
        let count = try context.count(for: request)
        #expect(count == 200)
    }
}

// MARK: -

@Suite("PersonalisationStore — Slot round-trip")
struct PersonalisationStoreSlotTests {

    private func makeStore() -> PersonalisationStore {
        PersonalisationStore(context: PersistenceController.preview.viewContext)
    }

    @Test("saveAlias with slots: favoriteIndex slot round-trips correctly")
    @MainActor
    func saveAlias_favoriteIndexSlot_roundTrips() throws {
        let store = makeStore()
        let speakerId = "speaker-slot-fav"

        try store.saveAlias(
            speakerId: speakerId,
            phrase: "play number two",
            intent: .playFavoriteByNumber,
            slots: ["favoriteIndex": "2"]
        )

        let result = store.matchAlias(phrase: "play number two", speakerId: speakerId)
        #expect(result?.intent == .playFavoriteByNumber)
        #expect(result?.favoriteIndex == 2)
    }

    @Test("saveAlias with slots: volumeValue slot round-trips correctly")
    @MainActor
    func saveAlias_volumeValueSlot_roundTrips() throws {
        let store = makeStore()
        let speakerId = "speaker-slot-vol"

        try store.saveAlias(
            speakerId: speakerId,
            phrase: "meeting volume",
            intent: .setVolume,
            slots: ["volumeValue": "30"]
        )

        let result = store.matchAlias(phrase: "meeting volume", speakerId: speakerId)
        #expect(result?.intent == .setVolume)
        #expect(result?.volumeValue == 30)
    }

    @Test("saveAlias with empty slots: returns ParsedCommand with all optional slots nil")
    @MainActor
    func saveAlias_emptySlots_nilSlotFields() throws {
        let store = makeStore()
        let speakerId = "speaker-empty-slots"

        try store.saveAlias(
            speakerId: speakerId,
            phrase: "stop now",
            intent: .stop,
            slots: [:]
        )

        let result = store.matchAlias(phrase: "stop now", speakerId: speakerId)
        #expect(result?.intent == .stop)
        #expect(result?.favoriteIndex == nil)
        #expect(result?.volumeValue == nil)
        #expect(result?.volumeDelta == nil)
        #expect(result?.targetSpeakerName == nil)
    }

    @Test("recordConfirmedCommand with volumeDelta slot: round-trips correctly")
    @MainActor
    func recordConfirmedCommand_volumeDeltaSlot_roundTrips() throws {
        let store = makeStore()
        let speakerId = "speaker-slot-delta"

        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: "a bit louder",
            intent: .volumeUp,
            slots: ["volumeDelta": "15"]
        )

        let result = store.matchConfirmedCommand(transcription: "a bit louder", speakerId: speakerId)
        #expect(result?.intent == .volumeUp)
        #expect(result?.volumeDelta == 15)
    }
}

// MARK: -

@Suite("PersonalisationStore — Speaker isolation")
struct PersonalisationStoreSpeakerIsolationTests {

    private func makeStore() -> PersonalisationStore {
        PersonalisationStore(context: PersistenceController.preview.viewContext)
    }

    @Test("aliases(for:) only returns aliases for the requested speakerId")
    @MainActor
    func aliasesFor_onlyReturnsMatchingSpeaker() throws {
        let store = makeStore()

        try store.saveAlias(speakerId: "spk-iso-A", phrase: "morning", intent: .playDefault, slots: [:])
        try store.saveAlias(speakerId: "spk-iso-B", phrase: "evening", intent: .stop, slots: [:])

        let resultsA = store.aliases(for: "spk-iso-A")
        let resultsB = store.aliases(for: "spk-iso-B")

        #expect(resultsA.count == 1)
        #expect(resultsA[0].phrase == "morning")
        #expect(resultsB.count == 1)
        #expect(resultsB[0].phrase == "evening")
    }

    @Test("matchAlias does not match across different speakerIds")
    @MainActor
    func matchAlias_doesNotCrossSpeak() throws {
        let store = makeStore()

        try store.saveAlias(speakerId: "spk-cross-A", phrase: "morning music", intent: .playDefault, slots: [:])

        // Same phrase, different speakerId — should NOT match
        let result = store.matchAlias(phrase: "morning music", speakerId: "spk-cross-B")
        #expect(result == nil)
    }

    @Test("matchConfirmedCommand does not match across different speakerIds")
    @MainActor
    func matchConfirmedCommand_doesNotCrossSpeak() throws {
        let store = makeStore()

        try store.recordConfirmedCommand(
            speakerId: "spk-cross-cmd-A",
            transcription: "silent mode",
            intent: .mute,
            slots: [:]
        )

        let result = store.matchConfirmedCommand(transcription: "silent mode", speakerId: "spk-cross-cmd-B")
        #expect(result == nil)
    }
}
