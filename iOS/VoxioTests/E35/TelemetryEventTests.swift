import XCTest
@testable import Voxio

// E-35 — Unit tests for TelemetryEvent value types (T-3501).
//
// Tests cover:
//   • TelemetryOutcome raw string values
//   • TelemetryFlags OptionSet: individual flag distinctness and combination semantics
//   • TelemetryEvent conforms to Identifiable via its id: UUID property

final class TelemetryEventTests: XCTestCase {

    // MARK: - TelemetryOutcome raw values

    func testOutcome_confirmed_rawValue() {
        XCTAssertEqual(TelemetryOutcome.confirmed.rawValue, "confirmed")
    }

    func testOutcome_cancelled_rawValue() {
        XCTAssertEqual(TelemetryOutcome.cancelled.rawValue, "cancelled")
    }

    func testOutcome_timedOut_rawValue() {
        XCTAssertEqual(TelemetryOutcome.timedOut.rawValue, "timedOut")
    }

    func testOutcome_unknown_rawValue() {
        XCTAssertEqual(TelemetryOutcome.unknown.rawValue, "unknown")
    }

    func testOutcome_roundTripsFromRawValue() {
        XCTAssertEqual(TelemetryOutcome(rawValue: "confirmed"),  .confirmed)
        XCTAssertEqual(TelemetryOutcome(rawValue: "cancelled"),  .cancelled)
        XCTAssertEqual(TelemetryOutcome(rawValue: "timedOut"),   .timedOut)
        XCTAssertEqual(TelemetryOutcome(rawValue: "unknown"),    .unknown)
    }

    func testOutcome_invalidRawValue_returnsNil() {
        XCTAssertNil(TelemetryOutcome(rawValue: ""))
        XCTAssertNil(TelemetryOutcome(rawValue: "CONFIRMED"))
        XCTAssertNil(TelemetryOutcome(rawValue: "timed_out"))
    }

    // MARK: - TelemetryFlags OptionSet

    func testFlags_likelyMisparse_rawValue_isPowerOfTwo() {
        XCTAssertEqual(TelemetryFlags.likelyMisparse.rawValue, 1 << 0)
    }

    func testFlags_recoverableUnknown_rawValue_isPowerOfTwo() {
        XCTAssertEqual(TelemetryFlags.recoverableUnknown.rawValue, 1 << 1)
    }

    func testFlags_broadcast_rawValue_isPowerOfTwo() {
        XCTAssertEqual(TelemetryFlags.broadcast.rawValue, 1 << 2)
    }

    func testFlags_allFlagsAreDistinct() {
        let a = TelemetryFlags.likelyMisparse.rawValue
        let b = TelemetryFlags.recoverableUnknown.rawValue
        let c = TelemetryFlags.broadcast.rawValue
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(b, c)
        XCTAssertNotEqual(a, c)
    }

    func testFlags_combined_containsBothMembers() {
        let combined: TelemetryFlags = [.likelyMisparse, .broadcast]
        XCTAssertTrue(combined.contains(.likelyMisparse))
        XCTAssertTrue(combined.contains(.broadcast))
        XCTAssertFalse(combined.contains(.recoverableUnknown))
    }

    func testFlags_empty_containsNoMembers() {
        let empty = TelemetryFlags([])
        XCTAssertFalse(empty.contains(.likelyMisparse))
        XCTAssertFalse(empty.contains(.recoverableUnknown))
        XCTAssertFalse(empty.contains(.broadcast))
    }

    func testFlags_allThreeCombined_containsAll() {
        let all: TelemetryFlags = [.likelyMisparse, .recoverableUnknown, .broadcast]
        XCTAssertTrue(all.contains(.likelyMisparse))
        XCTAssertTrue(all.contains(.recoverableUnknown))
        XCTAssertTrue(all.contains(.broadcast))
    }

    func testFlags_rawValueSum_matchesExpectedBitPattern() {
        let all: TelemetryFlags = [.likelyMisparse, .recoverableUnknown, .broadcast]
        let expected = (1 << 0) | (1 << 1) | (1 << 2)
        XCTAssertEqual(all.rawValue, expected)
    }

    // MARK: - TelemetryEvent Identifiable

    func testEvent_isIdentifiableById() {
        let id = UUID()
        let event = TelemetryEvent(
            id: id,
            transcriptionAnonymised: "play music",
            intent: "playDefault",
            slotsAnonymised: "{}",
            parserPath: "regex",
            outcome: .confirmed,
            appVersion: "1.3.0",
            modelVersion: "n/a",
            locale: "en_GB",
            timestamp: Date(),
            flags: [],
            speakerId: "speaker-abc"
        )
        XCTAssertEqual(event.id, id)
    }

    func testEvent_twoEventsWithDifferentIds_areNotIdenticalById() {
        let eventA = TelemetryEvent(
            id: UUID(),
            transcriptionAnonymised: "stop",
            intent: "stop",
            slotsAnonymised: "{}",
            parserPath: "regex",
            outcome: .confirmed,
            appVersion: "1.3.0",
            modelVersion: "n/a",
            locale: "en_GB",
            timestamp: Date(),
            flags: [],
            speakerId: "spk-1"
        )
        let eventB = TelemetryEvent(
            id: UUID(),
            transcriptionAnonymised: "stop",
            intent: "stop",
            slotsAnonymised: "{}",
            parserPath: "regex",
            outcome: .confirmed,
            appVersion: "1.3.0",
            modelVersion: "n/a",
            locale: "en_GB",
            timestamp: Date(),
            flags: [],
            speakerId: "spk-1"
        )
        XCTAssertNotEqual(eventA.id, eventB.id)
    }

    func testEvent_idMatchesTheSameInstance() {
        let event = TelemetryEvent(
            id: UUID(),
            transcriptionAnonymised: "pause",
            intent: "pause",
            slotsAnonymised: "{}",
            parserPath: "regex",
            outcome: .confirmed,
            appVersion: "1.3.0",
            modelVersion: "n/a",
            locale: "da_DK",
            timestamp: Date(),
            flags: [],
            speakerId: "spk-2"
        )
        // Identifiable contract: event.id is stable across reads
        XCTAssertEqual(event.id, event.id)
    }
}
