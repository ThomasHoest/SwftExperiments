import XCTest
import CoreData
@testable import Voxio

// E-35 — Unit tests for TelemetryBuffer (T-3502 / T-3503 / T-3504).
//
// All tests use an in-memory Core Data context derived from
// PersistenceController.preview so they are fully isolated from the
// on-disk production store. Each test uses a unique speakerId / transcription
// to avoid cross-test contamination within the shared in-memory context.

@MainActor
final class TelemetryBufferTests: XCTestCase {

    // MARK: - Helpers

    private func makeBuffer() -> TelemetryBuffer {
        TelemetryBuffer(context: PersistenceController.preview.viewContext)
    }

    private func record(
        in buffer: TelemetryBuffer,
        transcription: String = "play music",
        speakerName: String = "TestSpeaker",
        speakerId: String = "spk-default",
        intent: String = "playDefault",
        slots: [String: String] = [:],
        parserPath: String = "regex",
        outcome: TelemetryOutcome = .confirmed,
        locale: String = "en_GB",
        flags: TelemetryFlags = []
    ) throws {
        try buffer.record(
            transcription: transcription,
            speakerName: speakerName,
            speakerId: speakerId,
            intent: intent,
            slots: slots,
            parserPath: parserPath,
            outcome: outcome,
            locale: locale,
            flags: flags
        )
    }

    // MARK: - record() tests

    func testRecord_persistsEventToCoreData() throws {
        let buffer = makeBuffer()
        let speakerId = "spk-record-persists-\(UUID().uuidString)"

        try record(in: buffer, transcription: "play music on living room", speakerName: "Stue", speakerId: speakerId)

        let batch = try buffer.pendingBatch(limit: 10)
        XCTAssertFalse(batch.isEmpty, "record() should persist at least one event")
    }

    func testRecord_stripsSpeakerNameFromTranscription() throws {
        let buffer = makeBuffer()
        let speakerId = "spk-strip-\(UUID().uuidString)"
        let speakerName = "Stue"
        let rawTranscription = "spil musik på stue"

        try buffer.record(
            transcription: rawTranscription,
            speakerName: speakerName,
            speakerId: speakerId,
            intent: "playDefault",
            slots: [:],
            parserPath: "regex",
            outcome: .confirmed,
            locale: "da_DK",
            flags: []
        )

        let batch = try buffer.pendingBatch(limit: 10)
        let events = batch.filter { $0.speakerId == speakerId }
        XCTAssertFalse(events.isEmpty)
        let stored = events[0].transcriptionAnonymised.lowercased()
        XCTAssertFalse(stored.contains("stue"),
            "Speaker name 'stue' must be stripped from transcriptionAnonymised")
    }

    func testRecord_hashesFavoriteNameInSlots() throws {
        let buffer = makeBuffer()
        let speakerId = "spk-hash-\(UUID().uuidString)"
        let favoriteName = "Jazz Radio"

        try buffer.record(
            transcription: "play jazz radio",
            speakerName: "Stue",
            speakerId: speakerId,
            intent: "playNamed",
            slots: ["favoriteName": favoriteName],
            parserPath: "regex",
            outcome: .confirmed,
            locale: "en_GB",
            flags: []
        )

        let batch = try buffer.pendingBatch(limit: 10)
        let events = batch.filter { $0.speakerId == speakerId }
        XCTAssertFalse(events.isEmpty)

        guard let data = events[0].slotsAnonymised.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data),
              let hashPrefix = decoded["favoriteName"] else {
            return XCTFail("slotsAnonymised must be valid JSON with a 'favoriteName' key")
        }
        XCTAssertEqual(hashPrefix.count, 8, "Slot value hash must be exactly 8 hex characters")
        let hexCharSet = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(hashPrefix.unicodeScalars.allSatisfy { hexCharSet.contains($0) },
            "Slot value hash must be lowercase hex")
        XCTAssertNotEqual(hashPrefix, favoriteName,
            "Raw favorite name must not appear in slotsAnonymised")
    }

    func testRecord_doesNotRecordWhenDailyCapReached() throws {
        // NOTE: This test modifies the shared in-memory context's today-count.
        // It relies on unique speakerIds to avoid contaminating other tests.
        let buffer = makeBuffer()
        let speakerId = "spk-cap-\(UUID().uuidString)"

        for i in 1...200 {
            try buffer.record(
                transcription: "cap test \(speakerId) \(i)",
                speakerName: "CapSpeaker",
                speakerId: speakerId,
                intent: "stop",
                slots: [:],
                parserPath: "regex",
                outcome: .confirmed,
                locale: "en_GB",
                flags: []
            )
        }

        let countAtCap = try buffer.pendingBatch(limit: 250).filter { $0.speakerId == speakerId }.count
        XCTAssertEqual(countAtCap, 200, "Should have exactly 200 events at cap")

        // 201st record — must be silently dropped (per-day cap is enforced globally, not per-speaker,
        // so after 200 events today the buffer silently no-ops regardless of speakerId).
        // This test documents the expected silent-drop behaviour.
        let pendingBeforeDrop = try buffer.pendingBatch(limit: 300).count
        XCTAssertNoThrow(try buffer.record(
            transcription: "cap test 201 \(speakerId)",
            speakerName: "CapSpeaker",
            speakerId: speakerId,
            intent: "stop",
            slots: [:],
            parserPath: "regex",
            outcome: .confirmed,
            locale: "en_GB",
            flags: []
        ))
        let pendingAfterDrop = try buffer.pendingBatch(limit: 300).count
        XCTAssertEqual(pendingAfterDrop, pendingBeforeDrop,
            "record() must silently drop events once the daily cap is reached")
    }

    func testRecord_evictsOldestWhenGlobalCountExceeds1000() throws {
        let buffer = makeBuffer()
        let context = PersistenceController.preview.viewContext

        // Pre-populate with 1,000 entities directly to avoid hitting the per-day cap.
        let entityName = "TelemetryEventEntity"
        for i in 1...1000 {
            let entity = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
            entity.setValue(UUID(), forKey: "id")
            entity.setValue("evict-setup-\(i)", forKey: "transcriptionAnonymised")
            entity.setValue("stop", forKey: "intent")
            entity.setValue("{}", forKey: "slotsAnonymised")
            entity.setValue("regex", forKey: "parserPath")
            entity.setValue("confirmed", forKey: "outcome")
            entity.setValue("1.3.0", forKey: "appVersion")
            entity.setValue("n/a", forKey: "modelVersion")
            entity.setValue("en_GB", forKey: "locale")
            entity.setValue(Date(timeIntervalSinceNow: -Double(1001 - i)), forKey: "timestamp")
            entity.setValue("{}", forKey: "slotsAnonymised")
            entity.setValue("0", forKey: "flagsJSON")
            entity.setValue("spk-evict-setup", forKey: "speakerId")
            entity.setValue(false, forKey: "uploaded")
        }
        try context.save()

        // Now record one more — should trigger eviction of the oldest
        try buffer.record(
            transcription: "eviction trigger \(UUID().uuidString)",
            speakerName: "EvictSpeaker",
            speakerId: "spk-evict-trigger",
            intent: "stop",
            slots: [:],
            parserPath: "regex",
            outcome: .confirmed,
            locale: "en_GB",
            flags: []
        )

        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let count = try context.count(for: request)
        XCTAssertLessThanOrEqual(count, TelemetryBuffer.maxEventCount,
            "Global event count must not exceed maxEventCount after eviction")
    }

    // MARK: - pendingBatch() tests

    func testPendingBatch_returnsOnlyUnuploadedEvents() throws {
        let buffer = makeBuffer()
        let speakerId = "spk-pending-\(UUID().uuidString)"

        try record(in: buffer, transcription: "pending test A \(speakerId)", speakerId: speakerId)
        try record(in: buffer, transcription: "pending test B \(speakerId)", speakerId: speakerId)

        let batch = try buffer.pendingBatch(limit: 100)
        let myEvents = batch.filter { $0.speakerId == speakerId }
        XCTAssertFalse(myEvents.isEmpty, "pendingBatch must return unuploaded events")

        guard let firstId = myEvents.first?.id else { return XCTFail("batch was empty") }
        try buffer.markUploaded([firstId])

        let afterMark = try buffer.pendingBatch(limit: 100)
        XCTAssertFalse(afterMark.map(\.id).contains(firstId),
            "Uploaded event must not appear in pendingBatch")
    }

    func testPendingBatch_returnsEventsOldestFirst() throws {
        let buffer = makeBuffer()
        let speakerId = "spk-order-\(UUID().uuidString)"

        try record(in: buffer, transcription: "oldest event \(speakerId)", speakerId: speakerId)
        Thread.sleep(forTimeInterval: 0.05)
        try record(in: buffer, transcription: "newest event \(speakerId)", speakerId: speakerId)

        let batch = try buffer.pendingBatch(limit: 100).filter { $0.speakerId == speakerId }
        XCTAssertGreaterThanOrEqual(batch.count, 2)
        let timestamps = batch.map(\.timestamp)
        for i in 1..<timestamps.count {
            XCTAssertLessThanOrEqual(timestamps[i - 1], timestamps[i],
                "pendingBatch must be sorted ascending by timestamp")
        }
    }

    func testPendingBatch_respectsLimitParameter() throws {
        let buffer = makeBuffer()
        let speakerId = "spk-limit-\(UUID().uuidString)"

        for i in 1...10 {
            try record(in: buffer, transcription: "limit test \(speakerId) \(i)", speakerId: speakerId)
        }
        let batch = try buffer.pendingBatch(limit: 3)
        XCTAssertLessThanOrEqual(batch.count, 3, "pendingBatch must respect the limit parameter")
    }

    func testPendingBatch_limitZero_returnsEmpty() throws {
        let buffer = makeBuffer()
        let speakerId = "spk-limit0-\(UUID().uuidString)"

        try record(in: buffer, transcription: "limit zero test \(speakerId)", speakerId: speakerId)
        let batch = try buffer.pendingBatch(limit: 0)
        XCTAssertTrue(batch.isEmpty, "pendingBatch(limit: 0) must return empty array")
    }

    // MARK: - markUploaded() tests

    func testMarkUploaded_setsUploadedTrue() throws {
        let buffer = makeBuffer()
        let speakerId = "spk-mark-\(UUID().uuidString)"

        try record(in: buffer, transcription: "mark uploaded test A \(speakerId)", speakerId: speakerId)
        try record(in: buffer, transcription: "mark uploaded test B \(speakerId)", speakerId: speakerId)

        let before = try buffer.pendingBatch(limit: 100).filter { $0.speakerId == speakerId }
        XCTAssertFalse(before.isEmpty)

        let idsToMark = before.prefix(1).map(\.id)
        try buffer.markUploaded(Array(idsToMark))

        let after = try buffer.pendingBatch(limit: 100)
        for id in idsToMark {
            XCTAssertFalse(after.map(\.id).contains(id),
                "Event with id \(id) should have uploaded=true and be absent from pendingBatch")
        }
    }

    func testMarkUploaded_doesNotModifyOtherEvents() throws {
        let buffer = makeBuffer()
        let speakerId = "spk-mark-iso-\(UUID().uuidString)"

        try record(in: buffer, transcription: "mark uploaded isolate A \(speakerId)", speakerId: speakerId)
        try record(in: buffer, transcription: "mark uploaded isolate B \(speakerId)", speakerId: speakerId)

        let all = try buffer.pendingBatch(limit: 100).filter { $0.speakerId == speakerId }
        XCTAssertGreaterThanOrEqual(all.count, 2)

        let firstId = all[0].id
        let secondId = all[1].id
        try buffer.markUploaded([firstId])

        let remaining = try buffer.pendingBatch(limit: 100)
        XCTAssertTrue(remaining.map(\.id).contains(secondId),
            "Non-targeted event must remain pending after markUploaded")
        XCTAssertFalse(remaining.map(\.id).contains(firstId),
            "Targeted event must be absent from pendingBatch after markUploaded")
    }

    func testMarkUploaded_emptyIdList_isNoOp() throws {
        let buffer = makeBuffer()
        let speakerId = "spk-empty-mark-\(UUID().uuidString)"

        try record(in: buffer, transcription: "mark empty list test \(speakerId)", speakerId: speakerId)
        let before = try buffer.pendingBatch(limit: 100).filter { $0.speakerId == speakerId }.count

        XCTAssertNoThrow(try buffer.markUploaded([]))

        let after = try buffer.pendingBatch(limit: 100).filter { $0.speakerId == speakerId }.count
        XCTAssertEqual(after, before, "markUploaded([]) must not alter the pending batch")
    }

    // MARK: - flagAsMisparse() tests

    func testFlagAsMisparse_setsLikelyMisparseFlag() throws {
        let buffer = makeBuffer()
        let speakerId = "spk-flag-\(UUID().uuidString)"

        try record(in: buffer, transcription: "misparse flag test \(speakerId)", speakerId: speakerId, outcome: .cancelled)

        let batch = try buffer.pendingBatch(limit: 10).filter { $0.speakerId == speakerId }
        XCTAssertFalse(batch.isEmpty)

        let eventId = batch[0].id
        try buffer.flagAsMisparse(eventId: eventId)

        let updated = try buffer.pendingBatch(limit: 10)
        guard let updatedEvent = updated.first(where: { $0.id == eventId }) else {
            return XCTFail("Event \(eventId) should still be in pendingBatch")
        }
        XCTAssertTrue(updatedEvent.flags.contains(.likelyMisparse),
            "flagAsMisparse must set the .likelyMisparse flag on the event")
    }

    func testFlagAsMisparse_unknownId_doesNotThrow() throws {
        let buffer = makeBuffer()
        XCTAssertNoThrow(try buffer.flagAsMisparse(eventId: UUID()))
    }

    // MARK: - deleteAll() tests

    func testDeleteAll_removesAllTelemetryEventEntities() throws {
        let buffer = makeBuffer()
        let speakerId = "spk-delall-\(UUID().uuidString)"

        try record(in: buffer, transcription: "delete all test 1 \(speakerId)", speakerId: speakerId)
        try record(in: buffer, transcription: "delete all test 2 \(speakerId)", speakerId: speakerId)

        let before = try buffer.pendingBatch(limit: 100).filter { $0.speakerId == speakerId }
        XCTAssertGreaterThan(before.count, 0)

        try buffer.deleteAll()

        let after = try buffer.pendingBatch(limit: 100)
        XCTAssertTrue(after.isEmpty, "deleteAll must remove all TelemetryEvent entities")
    }

    func testDeleteAll_doesNotAffectAliasEntities() throws {
        let buffer = makeBuffer()
        let context = PersistenceController.preview.viewContext
        let speakerId = "spk-delall-alias-\(UUID().uuidString)"

        let alias = Alias(context: context)
        alias.id = UUID()
        alias.speakerId = speakerId
        alias.phrase = "do not delete me \(speakerId)"
        alias.intentRaw = CommandIntent.stop.rawValue
        alias.slotsJSON = "{}"
        alias.createdAt = Date()
        try context.save()

        try record(in: buffer, transcription: "will be deleted \(speakerId)", speakerId: speakerId)
        try buffer.deleteAll()

        let aliasRequest: NSFetchRequest<Alias> = Alias.fetchRequest()
        aliasRequest.predicate = NSPredicate(format: "speakerId == %@", speakerId)
        let aliases = try context.fetch(aliasRequest)
        XCTAssertFalse(aliases.isEmpty,
            "Alias entities must not be removed by TelemetryBuffer.deleteAll()")
    }

    func testDeleteAll_doesNotAffectConfirmedCommandEntities() throws {
        let buffer = makeBuffer()
        let context = PersistenceController.preview.viewContext
        let speakerId = "spk-delall-cmd-\(UUID().uuidString)"

        let store = PersonalisationStore(context: context)
        try store.recordConfirmedCommand(
            speakerId: speakerId,
            transcription: "keep this command \(speakerId)",
            intent: .stop,
            slots: [:]
        )

        try record(in: buffer, transcription: "will be deleted too \(speakerId)", speakerId: speakerId)
        try buffer.deleteAll()

        let result = store.matchConfirmedCommand(
            transcription: "keep this command \(speakerId)",
            speakerId: speakerId
        )
        XCTAssertNotNil(result,
            "ConfirmedCommand entities must not be removed by TelemetryBuffer.deleteAll()")
    }

    // MARK: - Misparse detection window tests

    func testMisparseWindow_confirmedEventWithin30s_flagsCancelledEvent() throws {
        let buffer = makeBuffer()
        let speakerId = "spk-misparse-hit-\(UUID().uuidString)"

        try buffer.record(
            transcription: "stop",
            speakerName: "TestSpeaker",
            speakerId: speakerId,
            intent: "stop",
            slots: [:],
            parserPath: "regex",
            outcome: .cancelled,
            locale: "en_GB",
            flags: []
        )

        try buffer.record(
            transcription: "play music",
            speakerName: "TestSpeaker",
            speakerId: speakerId,
            intent: "playDefault",
            slots: [:],
            parserPath: "regex",
            outcome: .confirmed,
            locale: "en_GB",
            flags: []
        )

        let batch = try buffer.pendingBatch(limit: 100)
        let cancelledEvents = batch.filter { $0.outcome == .cancelled && $0.speakerId == speakerId }
        XCTAssertFalse(cancelledEvents.isEmpty, "Cancelled event should still be in store")
        XCTAssertTrue(cancelledEvents[0].flags.contains(.likelyMisparse),
            "Cancelled event should be retroactively flagged as .likelyMisparse")
    }

    func testMisparseWindow_confirmedEventAfter30s_doesNotFlagCancelledEvent() throws {
        // Testing the exact 30s boundary requires clock injection which TelemetryBuffer
        // doesn't expose. This test is skipped and documents the known gap.
        throw XCTSkip("Misparse 30s window boundary test requires clock injection in TelemetryBuffer")
    }

    func testMisparseWindow_differentSpeakerId_doesNotFlagCancelledEvent() throws {
        let buffer = makeBuffer()
        let speakerIdA = "spk-misparse-iso-A-\(UUID().uuidString)"
        let speakerIdB = "spk-misparse-iso-B-\(UUID().uuidString)"

        try buffer.record(
            transcription: "stop",
            speakerName: "SpeakerA",
            speakerId: speakerIdA,
            intent: "stop",
            slots: [:],
            parserPath: "regex",
            outcome: .cancelled,
            locale: "en_GB",
            flags: []
        )

        try buffer.record(
            transcription: "play music",
            speakerName: "SpeakerB",
            speakerId: speakerIdB,
            intent: "playDefault",
            slots: [:],
            parserPath: "regex",
            outcome: .confirmed,
            locale: "en_GB",
            flags: []
        )

        let batch = try buffer.pendingBatch(limit: 100)
        let cancelledForA = batch.filter { $0.outcome == .cancelled && $0.speakerId == speakerIdA }
        XCTAssertFalse(cancelledForA.isEmpty, "Cancelled event for speaker A must be in store")
        XCTAssertFalse(cancelledForA[0].flags.contains(.likelyMisparse),
            "Cancelled event for speaker A must NOT be flagged when confirmed event is for speaker B")
    }
}
