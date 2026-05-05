import XCTest
import CoreData
@testable import Voxio

// MARK: - E-34 PersonalisationStore Learned Phrases Tests
//
// Covers:
//   - confirmedCommands(for:) — new method added by E-34 implementer (T-3403 prerequisite)
//   - ConfirmedCommandRecord  — new value type added by E-34 implementer
//   - clearAllConfirmedCommands() with refreshAllObjects() fix (ADR E-34 consequence)
//   - saveAlias "voxio" reserved-word guard via PersonalisationStore.SaveAliasError
//     (ADR E-34 § "PersonalisationStore saveAlias does not validate for the 'Voxio' wake-word")
//
// TODO (E-34 implementer deliverables required before this suite fully compiles and passes):
//   1. Add `ConfirmedCommandRecord` struct to PersonalisationStore.swift
//   2. Add `confirmedCommands(for:) -> [ConfirmedCommandRecord]` method
//   3. Add `PersonalisationStore.SaveAliasError` error enum with `.reservedWord` and
//      `.duplicatePhrase` cases
//   4. Add `.reservedWord` guard to `saveAlias()` (containing check on "voxio")
//   5. Add `updateAlias(id:speakerId:phrase:intent:slots:)` method
//   6. Add `context.refreshAllObjects()` after NSBatchDeleteRequest in
//      `clearAllConfirmedCommands()` (ADR E-34 § "Swift 6 strict concurrency" consequence)
//
// NOTE: Each test class creates a fully isolated in-memory NSPersistentContainer to avoid
//       shared-singleton contamination between test runs.

// MARK: - In-memory store helper

/// Returns a fresh, isolated in-memory NSManagedObjectContext using the Voxio data model.
/// NSInMemoryStoreType avoids on-disk state entirely; each call produces a clean context.
private func makeInMemoryContext() -> NSManagedObjectContext {
    let container = NSPersistentContainer(name: "Voxio")
    let description = NSPersistentStoreDescription()
    description.type = NSInMemoryStoreType
    description.shouldAddStoreAsynchronously = false
    container.persistentStoreDescriptions = [description]
    container.loadPersistentStores { _, error in
        if let error {
            fatalError("E-34 test: failed to load in-memory store — \(error)")
        }
    }
    container.viewContext.automaticallyMergesChangesFromParent = true
    return container.viewContext
}

// MARK: - confirmedCommands(for:) tests
//
// TODO: PersonalisationStore.confirmedCommands(for:) and ConfirmedCommandRecord are
//       added by the E-34 implementer. Tests are written against the interface contract
//       in ADR E-34.

final class ConfirmedCommandsForTests: XCTestCase {

    @MainActor
    private func makeStore() -> PersonalisationStore {
        PersonalisationStore(context: makeInMemoryContext())
    }

    // MARK: T-3403-CC1 — empty result when no records exist

    /// confirmedCommands(for:) returns an empty array when no confirmed commands have
    /// been recorded for the given speakerId.
    @MainActor
    func testConfirmedCommandsFor_noRecords_returnsEmpty() {
        let store = makeStore()

        let records = store.confirmedCommands(for: "speaker-absent")

        XCTAssertTrue(records.isEmpty,
                      "confirmedCommands(for:) must return [] when no commands exist for the speaker")
    }

    // MARK: T-3403-CC2 — returns all records for the requested speakerId

    /// confirmedCommands(for:) returns every record belonging to the requested speakerId.
    @MainActor
    func testConfirmedCommandsFor_twoRecordsForSpeaker_returnsBoth() throws {
        let store = makeStore()
        let speakerId = "speaker-cc-two"

        try store.recordConfirmedCommand(speakerId: speakerId, transcription: "play jazz",
                                         intent: .playDefault, slots: [:])
        try store.recordConfirmedCommand(speakerId: speakerId, transcription: "stop music",
                                         intent: .stop, slots: [:])

        let records = store.confirmedCommands(for: speakerId)

        XCTAssertEqual(records.count, 2,
                       "confirmedCommands(for:) must return all 2 records for the speaker")
    }

    // MARK: T-3403-CC3 — does not return records for a different speakerId

    /// confirmedCommands(for:) must not return records belonging to a different speaker.
    @MainActor
    func testConfirmedCommandsFor_differentSpeakerRecords_notReturned() throws {
        let store = makeStore()
        let speakerA = "speaker-cc-iso-A"
        let speakerB = "speaker-cc-iso-B"

        try store.recordConfirmedCommand(speakerId: speakerA, transcription: "mute now",
                                         intent: .mute, slots: [:])

        let recordsForB = store.confirmedCommands(for: speakerB)

        XCTAssertTrue(recordsForB.isEmpty,
                      "confirmedCommands(for:) must not return records from a different speakerId")
    }

    // MARK: T-3403-CC4 — records sorted by lastUsedAt descending (most recent first)

    /// confirmedCommands(for:) returns results sorted by lastUsedAt descending so that
    /// the most recently used command appears at index 0.
    @MainActor
    func testConfirmedCommandsFor_sortedByLastUsedAtDescending() throws {
        let store = makeStore()
        let speakerId = "speaker-cc-sort"

        // Insert "older command" first so its lastUsedAt is earlier
        try store.recordConfirmedCommand(speakerId: speakerId, transcription: "older command",
                                         intent: .pause, slots: [:])
        // Brief sleep so the two Date() values are guaranteed to differ
        Thread.sleep(forTimeInterval: 0.02)
        // Insert "newer command" second — its lastUsedAt should be later
        try store.recordConfirmedCommand(speakerId: speakerId, transcription: "newer command",
                                         intent: .resume, slots: [:])

        let records = store.confirmedCommands(for: speakerId)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].transcription, "newer command",
                       "Most recently used command must be at index 0 (sorted descending by lastUsedAt)")
        XCTAssertEqual(records[1].transcription, "older command",
                       "Older command must be at index 1")
    }

    // MARK: T-3403-CC5 — ConfirmedCommandRecord.id matches the underlying Core Data entity id

    /// The id field on ConfirmedCommandRecord must be identical to the UUID stored on the
    /// underlying ConfirmedCommand Core Data entity.
    @MainActor
    func testConfirmedCommandRecord_id_matchesCoreDataEntityId() throws {
        let context = makeInMemoryContext()
        let store = PersonalisationStore(context: context)
        let speakerId = "speaker-cc-id"

        try store.recordConfirmedCommand(speakerId: speakerId, transcription: "verify id",
                                         intent: .stop, slots: [:])

        // Fetch the underlying Core Data entity directly to retrieve its stored UUID
        let fetchRequest: NSFetchRequest<ConfirmedCommand> = ConfirmedCommand.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "speakerId == %@", speakerId)
        let entities = try context.fetch(fetchRequest)
        let entityId = try XCTUnwrap(entities.first?.id,
                                     "ConfirmedCommand entity must have a non-nil id UUID")

        let records = store.confirmedCommands(for: speakerId)
        let record = try XCTUnwrap(records.first, "confirmedCommands(for:) must return one record")

        XCTAssertEqual(record.id, entityId,
                       "ConfirmedCommandRecord.id must equal the underlying Core Data entity's id UUID")
    }

    // MARK: T-3403-CC6 — ConfirmedCommandRecord.useCount reflects the stored value

    /// After two recordConfirmedCommand calls for the same transcription (upsert path),
    /// the returned record's useCount must be 2.
    @MainActor
    func testConfirmedCommandRecord_useCount_reflectsStoredValue() throws {
        let store = makeStore()
        let speakerId = "speaker-cc-usecount"
        let transcription = "volume up"

        // First call: inserts a new row with useCount = 1
        try store.recordConfirmedCommand(speakerId: speakerId, transcription: transcription,
                                         intent: .volumeUp, slots: [:])
        // Second call: upserts the existing row, incrementing useCount to 2
        try store.recordConfirmedCommand(speakerId: speakerId, transcription: transcription,
                                         intent: .volumeUp, slots: [:])

        let records = store.confirmedCommands(for: speakerId)
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.useCount, 2,
                       "ConfirmedCommandRecord.useCount must equal 2 after two recordConfirmedCommand calls for the same transcription")
    }

    // MARK: T-3403-CC7 — ConfirmedCommandRecord.intent matches the recorded intent

    /// The intent field on ConfirmedCommandRecord must match the intent supplied to
    /// recordConfirmedCommand.
    @MainActor
    func testConfirmedCommandRecord_intent_matchesRecordedIntent() throws {
        let store = makeStore()
        let speakerId = "speaker-cc-intent"

        try store.recordConfirmedCommand(speakerId: speakerId, transcription: "set volume to 40",
                                         intent: .setVolume, slots: ["volumeValue": "40"])

        let records = store.confirmedCommands(for: speakerId)
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.intent, .setVolume,
                       "ConfirmedCommandRecord.intent must be .setVolume as recorded")
    }

    // MARK: T-3403-CC8 — ConfirmedCommandRecord.speakerId matches the recorded speakerId

    /// The speakerId on ConfirmedCommandRecord must match the speakerId provided when the
    /// command was recorded.
    @MainActor
    func testConfirmedCommandRecord_speakerId_matchesRecorded() throws {
        let store = makeStore()
        let speakerId = "speaker-cc-spkid"

        try store.recordConfirmedCommand(speakerId: speakerId, transcription: "pause please",
                                         intent: .pause, slots: [:])

        let records = store.confirmedCommands(for: speakerId)
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.speakerId, speakerId,
                       "ConfirmedCommandRecord.speakerId must match the speakerId used when recording")
    }

    // MARK: T-3403-CC9 — transcription stored normalised to lowercase

    /// recordConfirmedCommand normalises the transcription to lowercase.
    /// confirmedCommands(for:) must return the lowercased transcription.
    @MainActor
    func testConfirmedCommandRecord_transcription_storedLowercased() throws {
        let store = makeStore()
        let speakerId = "speaker-cc-lower"

        try store.recordConfirmedCommand(speakerId: speakerId, transcription: "Play Jazz NOW",
                                         intent: .playDefault, slots: [:])

        let records = store.confirmedCommands(for: speakerId)
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.transcription, "play jazz now",
                       "ConfirmedCommandRecord.transcription must be stored and returned in lowercase")
    }
}

// MARK: - clearAllConfirmedCommands tests

final class ClearAllConfirmedCommandsTests: XCTestCase {

    @MainActor
    private func makeStore() -> PersonalisationStore {
        PersonalisationStore(context: makeInMemoryContext())
    }

    // MARK: T-3403-CL1 — after clear, confirmedCommands(for:) returns empty

    /// After clearAllConfirmedCommands(), confirmedCommands(for:) must return an empty
    /// array for any speakerId that previously had records.
    ///
    /// This test implicitly verifies that context.refreshAllObjects() was called after
    /// the NSBatchDeleteRequest (ADR E-34 consequence). Without the refresh, the
    /// in-memory context retains stale objects and confirmedCommands(for:) would still
    /// return non-empty results on a subsequent fetch.
    ///
    // TODO: clearAllConfirmedCommands() must call context.refreshAllObjects() after
    //       NSBatchDeleteRequest (ADR E-34 § "Swift 6 strict concurrency" consequence).
    @MainActor
    func testClearAll_confirmedCommandsForReturnsEmpty() throws {
        let store = makeStore()
        let speakerId = "speaker-clear-cc"

        try store.recordConfirmedCommand(speakerId: speakerId, transcription: "phrase one",
                                         intent: .stop, slots: [:])
        try store.recordConfirmedCommand(speakerId: speakerId, transcription: "phrase two",
                                         intent: .pause, slots: [:])

        // Pre-condition: verify records exist before the clear
        XCTAssertFalse(store.confirmedCommands(for: speakerId).isEmpty,
                       "Pre-condition: records must exist before clear")

        try store.clearAllConfirmedCommands()

        let afterClear = store.confirmedCommands(for: speakerId)
        XCTAssertTrue(afterClear.isEmpty,
                      "confirmedCommands(for:) must return [] after clearAllConfirmedCommands()")
    }

    // MARK: T-3403-CL2 — after clear, direct Core Data fetch on viewContext returns zero rows

    /// After clearAllConfirmedCommands(), a direct NSFetchRequest on the same viewContext
    /// must return zero rows. This is the observable proof that context.refreshAllObjects()
    /// was called: NSBatchDeleteRequest bypasses context change-tracking, so without the
    /// refresh the context count would remain non-zero despite the data being deleted in
    /// the persistent store.
    ///
    // TODO: clearAllConfirmedCommands() must call context.refreshAllObjects() (ADR E-34).
    @MainActor
    func testClearAll_viewContextFetchReturnsZeroRows() throws {
        let context = makeInMemoryContext()
        let store = PersonalisationStore(context: context)

        try store.recordConfirmedCommand(speakerId: "spk-ctx-clear", transcription: "ctx phrase",
                                         intent: .mute, slots: [:])

        try store.clearAllConfirmedCommands()

        let fetchRequest: NSFetchRequest<ConfirmedCommand> = ConfirmedCommand.fetchRequest()
        let count = try context.count(for: fetchRequest)
        XCTAssertEqual(count, 0,
                       "Direct viewContext fetch count must be 0 after clearAllConfirmedCommands(); " +
                       "a non-zero count indicates refreshAllObjects() was not called after NSBatchDeleteRequest")
    }

    // MARK: T-3403-CL3 — clear does not affect Alias entities

    /// clearAllConfirmedCommands() must remove only ConfirmedCommand entities.
    /// Any Alias entities saved before the clear must remain intact.
    @MainActor
    func testClearAll_doesNotAffectAliasEntities() throws {
        let context = makeInMemoryContext()
        let store = PersonalisationStore(context: context)
        let speakerId = "speaker-alias-safe"

        try store.saveAlias(speakerId: speakerId, phrase: "my alias",
                            intent: .playDefault, slots: [:])
        try store.recordConfirmedCommand(speakerId: speakerId, transcription: "my command",
                                         intent: .stop, slots: [:])

        try store.clearAllConfirmedCommands()

        // Alias must still be present
        let aliasRecords = store.aliases(for: speakerId)
        XCTAssertEqual(aliasRecords.count, 1,
                       "clearAllConfirmedCommands() must not delete Alias entities")
        XCTAssertEqual(aliasRecords.first?.phrase, "my alias")

        // All ConfirmedCommand entities must be gone
        let fetchRequest: NSFetchRequest<ConfirmedCommand> = ConfirmedCommand.fetchRequest()
        let confirmedCount = try context.count(for: fetchRequest)
        XCTAssertEqual(confirmedCount, 0,
                       "All ConfirmedCommand entities must be deleted by clearAllConfirmedCommands()")
    }

    // MARK: T-3403-CL4 — clear is a no-op when no records exist

    /// clearAllConfirmedCommands() must not throw when called on an empty store.
    @MainActor
    func testClearAll_emptyStore_doesNotThrow() {
        let store = makeStore()

        XCTAssertNoThrow(
            try store.clearAllConfirmedCommands(),
            "clearAllConfirmedCommands() must not throw when called on an empty store"
        )
    }

    // MARK: T-3403-CL5 — clear removes records across all speakerIds

    /// clearAllConfirmedCommands() must remove confirmed commands for every speakerId,
    /// not just the most recently recorded one.
    @MainActor
    func testClearAll_removesAcrossAllSpeakers() throws {
        let store = makeStore()

        try store.recordConfirmedCommand(speakerId: "spk-multi-1", transcription: "cmd a",
                                         intent: .stop, slots: [:])
        try store.recordConfirmedCommand(speakerId: "spk-multi-2", transcription: "cmd b",
                                         intent: .pause, slots: [:])
        try store.recordConfirmedCommand(speakerId: "spk-multi-3", transcription: "cmd c",
                                         intent: .resume, slots: [:])

        try store.clearAllConfirmedCommands()

        XCTAssertTrue(store.confirmedCommands(for: "spk-multi-1").isEmpty,
                      "spk-multi-1 commands must be cleared")
        XCTAssertTrue(store.confirmedCommands(for: "spk-multi-2").isEmpty,
                      "spk-multi-2 commands must be cleared")
        XCTAssertTrue(store.confirmedCommands(for: "spk-multi-3").isEmpty,
                      "spk-multi-3 commands must be cleared")
    }
}

// MARK: - saveAlias reserved-word validation tests
//
// The AliasEditSheet checks for "voxio" (contains, case-insensitive) in handleContinue()
// before ever calling store.saveAlias(). As a belt-and-braces defence, saveAlias() must
// also enforce the guard and throw SaveAliasError.reservedWord when the phrase contains
// "voxio" (any case). AliasEditSheet.handleSave() catches SaveAliasError.reservedWord.
//
// ADR E-34 § "PersonalisationStore saveAlias does not validate for the 'Voxio' wake-word":
//   "T-3402 implementers must either add the guard inside saveAlias() (preferred) or
//    enforce it exclusively in the UI layer."
// The implementer chose to add it to the store (referenced as SaveAliasError.reservedWord
// in AliasEditSheet.handleSave()) so these tests target the store-level guard.
//
// TODO: Add PersonalisationStore.SaveAliasError enum with .reservedWord and .duplicatePhrase
//       cases, and add the guard to saveAlias() before running this suite.

final class AliasReservedWordTests: XCTestCase {

    @MainActor
    private func makeStore() -> PersonalisationStore {
        PersonalisationStore(context: makeInMemoryContext())
    }

    // MARK: T-3402-RW1 — exact lowercase "voxio" is rejected

    /// saveAlias() must throw SaveAliasError.reservedWord when the phrase is exactly
    /// "voxio" (already lowercased as saveAlias normalises to lowercase internally).
    @MainActor
    func testSaveAlias_exactVoxioPhrase_throwsReservedWord() throws {
        let store = makeStore()
        let speakerId = "speaker-rw-exact"

        // TODO: cast error to PersonalisationStore.SaveAliasError.reservedWord once type exists
        XCTAssertThrowsError(
            try store.saveAlias(speakerId: speakerId, phrase: "voxio",
                                intent: .playDefault, slots: [:]),
            "saveAlias with phrase 'voxio' must throw a reserved-word error"
        )

        // The alias must not have been persisted
        let aliases = store.aliases(for: speakerId)
        XCTAssertTrue(aliases.isEmpty,
                      "No Alias entity must be persisted when phrase equals the reserved word 'voxio'")
    }

    // MARK: T-3402-RW2 — mixed-case "Voxio" is rejected (case-insensitive)

    /// The guard must be case-insensitive. "Voxio" normalises to "voxio" before the check.
    @MainActor
    func testSaveAlias_mixedCaseVoxio_throwsReservedWord() {
        let store = makeStore()
        let speakerId = "speaker-rw-mixed"

        XCTAssertThrowsError(
            try store.saveAlias(speakerId: speakerId, phrase: "Voxio",
                                intent: .playDefault, slots: [:]),
            "saveAlias with phrase 'Voxio' must throw a reserved-word error (case-insensitive guard)"
        )

        XCTAssertTrue(store.aliases(for: speakerId).isEmpty,
                      "No Alias entity must be persisted for 'Voxio'")
    }

    // MARK: T-3402-RW3 — all-caps "VOXIO" is rejected

    @MainActor
    func testSaveAlias_allCapsVoxio_throwsReservedWord() {
        let store = makeStore()
        let speakerId = "speaker-rw-caps"

        XCTAssertThrowsError(
            try store.saveAlias(speakerId: speakerId, phrase: "VOXIO",
                                intent: .stop, slots: [:]),
            "saveAlias with phrase 'VOXIO' must throw a reserved-word error"
        )
    }

    // MARK: T-3402-RW4 — phrase containing "voxio" as a substring
    //
    // AliasEditSheet.handleContinue() blocks any phrase that *contains* "voxio" (substring).
    // The store guard mirrors this behaviour: "voxio" anywhere in the lowercased phrase
    // triggers SaveAliasError.reservedWord.
    //
    // DOCUMENTED BEHAVIOUR: substring match (contains), not exact match.
    //   - "play voxio" must be rejected because it contains "voxio".
    //   - This matches AliasEditSheet.handleContinue() logic:
    //       `if trimmed.lowercased().contains("voxio") { ... }`
    @MainActor
    func testSaveAlias_phraseContainsVoxioSubstring_throwsReservedWord() {
        let store = makeStore()
        let speakerId = "speaker-rw-substring"

        // "play voxio" contains "voxio" — must be rejected
        XCTAssertThrowsError(
            try store.saveAlias(speakerId: speakerId, phrase: "play voxio",
                                intent: .playDefault, slots: [:]),
            "saveAlias with phrase 'play voxio' must throw a reserved-word error " +
            "because the phrase contains 'voxio' as a substring"
        )

        XCTAssertTrue(store.aliases(for: speakerId).isEmpty,
                      "No Alias entity must be persisted when phrase contains the reserved word")
    }

    // MARK: T-3402-RW5 — valid non-reserved phrase is saved successfully

    /// A phrase that does not contain "voxio" must be saved without error.
    @MainActor
    func testSaveAlias_normalPhrase_succeeds() throws {
        let store = makeStore()
        let speakerId = "speaker-rw-ok"

        XCTAssertNoThrow(
            try store.saveAlias(speakerId: speakerId, phrase: "morning music",
                                intent: .playDefault, slots: [:]),
            "A phrase not containing 'voxio' must be accepted without error"
        )

        let aliases = store.aliases(for: speakerId)
        XCTAssertEqual(aliases.count, 1)
        XCTAssertEqual(aliases.first?.phrase, "morning music")
    }

    // MARK: T-3402-RW6 — "voxio" prefix in a phrase is rejected

    /// A phrase that starts with "voxio" is rejected by the substring guard.
    @MainActor
    func testSaveAlias_phraseWithVoxioPrefix_throwsReservedWord() {
        let store = makeStore()
        let speakerId = "speaker-rw-prefix"

        XCTAssertThrowsError(
            try store.saveAlias(speakerId: speakerId, phrase: "voxio play jazz",
                                intent: .playDefault, slots: [:]),
            "saveAlias with phrase 'voxio play jazz' must throw reserved-word error"
        )
    }

    // MARK: T-3402-RW7 — phrase similar to but distinct from "voxio" is accepted

    /// Phrases that sound similar but do not contain the exact substring "voxio"
    /// (e.g. "voxo", "roxio") must be accepted.
    @MainActor
    func testSaveAlias_similarButNotVoxioPhrase_accepted() throws {
        let store = makeStore()
        let speakerId = "speaker-rw-similar"

        XCTAssertNoThrow(
            try store.saveAlias(speakerId: speakerId, phrase: "voxo",
                                intent: .stop, slots: [:]),
            "Phrase 'voxo' does not contain 'voxio' and must be accepted"
        )
    }
}

// MARK: - saveAlias duplicate-phrase validation tests
//
// AliasEditSheet.handleContinue() also checks for duplicate phrases.
// The store-level guard throws SaveAliasError.duplicatePhrase for the same phrase+speakerId
// combination. AliasEditSheet.handleSave() catches this error.
//
// TODO: Add .duplicatePhrase case to SaveAliasError and enforce in saveAlias() before
//       running this suite.

final class AliasDuplicatePhraseTests: XCTestCase {

    @MainActor
    private func makeStore() -> PersonalisationStore {
        PersonalisationStore(context: makeInMemoryContext())
    }

    // MARK: T-3402-DP1 — saving the same phrase for the same speaker throws duplicatePhrase

    /// When an alias with the same (normalised) phrase and speakerId already exists,
    /// saveAlias() must throw SaveAliasError.duplicatePhrase and not create a second row.
    @MainActor
    func testSaveAlias_duplicatePhraseSameSpeaker_throwsDuplicate() throws {
        let store = makeStore()
        let speakerId = "speaker-dup-1"

        // First save must succeed
        try store.saveAlias(speakerId: speakerId, phrase: "evening jazz",
                            intent: .playDefault, slots: [:])

        // Second save with the same phrase + speaker must fail
        XCTAssertThrowsError(
            try store.saveAlias(speakerId: speakerId, phrase: "evening jazz",
                                intent: .stop, slots: [:]),
            "saveAlias must throw duplicatePhrase when phrase already exists for the speaker"
        )

        // Only one alias must exist
        XCTAssertEqual(store.aliases(for: speakerId).count, 1,
                       "Only the first alias must be persisted; the duplicate must be rejected")
    }

    // MARK: T-3402-DP2 — same phrase on a different speaker is allowed

    /// Duplicate phrase detection must be scoped per speakerId. The same phrase saved for
    /// two different speakers must succeed for both.
    @MainActor
    func testSaveAlias_samePhraseOnDifferentSpeaker_allowed() throws {
        let store = makeStore()
        let speakerA = "speaker-dup-A"
        let speakerB = "speaker-dup-B"

        XCTAssertNoThrow(
            try store.saveAlias(speakerId: speakerA, phrase: "evening jazz",
                                intent: .playDefault, slots: [:])
        )
        XCTAssertNoThrow(
            try store.saveAlias(speakerId: speakerB, phrase: "evening jazz",
                                intent: .stop, slots: [:]),
            "Same phrase on a different speaker must be accepted (duplicates are per-speaker)"
        )

        XCTAssertEqual(store.aliases(for: speakerA).count, 1)
        XCTAssertEqual(store.aliases(for: speakerB).count, 1)
    }

    // MARK: T-3402-DP3 — duplicate check is case-insensitive (phrase normalised to lowercase)

    /// saveAlias normalises the phrase to lowercase before persisting. A subsequent save
    /// with the same phrase in different capitalisation must hit the duplicate guard.
    @MainActor
    func testSaveAlias_duplicatePhraseUppercase_throwsDuplicate() throws {
        let store = makeStore()
        let speakerId = "speaker-dup-case"

        try store.saveAlias(speakerId: speakerId, phrase: "morning mode",
                            intent: .playDefault, slots: [:])

        XCTAssertThrowsError(
            try store.saveAlias(speakerId: speakerId, phrase: "Morning Mode",
                                intent: .stop, slots: [:]),
            "saveAlias must throw duplicatePhrase for 'Morning Mode' when 'morning mode' already exists (case-insensitive)"
        )
    }
}
