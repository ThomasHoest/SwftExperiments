import XCTest
@testable import Voxio

// E-37 — Unit tests for BroadcastResult value type and CommandStrings broadcast toast strings (T-3706, T-3707).

final class BroadcastResultTests: XCTestCase {

    // MARK: — BroadcastResult struct

    func testBroadcastResult_storedProperties() {
        let result = BroadcastResult(successCount: 3, totalCount: 4, intent: .stopAll)
        XCTAssertEqual(result.successCount, 3)
        XCTAssertEqual(result.totalCount, 4)
        XCTAssertEqual(result.intent, .stopAll)
    }

    func testBroadcastResult_allSuccess() {
        let result = BroadcastResult(successCount: 2, totalCount: 2, intent: .pauseAll)
        XCTAssertEqual(result.successCount, result.totalCount)
    }

    func testBroadcastResult_partialFailure() {
        let result = BroadcastResult(successCount: 1, totalCount: 3, intent: .muteAll)
        XCTAssertLessThan(result.successCount, result.totalCount)
    }

    func testBroadcastResult_nothingInScope() {
        let result = BroadcastResult(successCount: 0, totalCount: 0, intent: .resumeAll)
        XCTAssertEqual(result.totalCount, 0)
    }

    // MARK: — CommandStrings broadcast toast strings (EN)

    func testCommandStrings_broadcastExecuted_english_singular() {
        let cs = CommandStrings.forLanguage(.english)
        let msg = cs.broadcastExecuted(1, 1)
        XCTAssertTrue(msg.contains("1"), "Should mention the speaker count")
        XCTAssertFalse(msg.contains("speakers"), "Singular: should not say 'speakers'")
    }

    func testCommandStrings_broadcastExecuted_english_plural() {
        let cs = CommandStrings.forLanguage(.english)
        let msg = cs.broadcastExecuted(3, 4)
        XCTAssertTrue(msg.contains("3"), "Should mention success count")
        XCTAssertTrue(msg.contains("4"), "Should mention total count")
    }

    func testCommandStrings_broadcastNothingInScope_english() {
        let cs = CommandStrings.forLanguage(.english)
        XCTAssertFalse(cs.broadcastNothingInScope.isEmpty)
    }

    // MARK: — CommandStrings broadcast toast strings (DA)

    func testCommandStrings_broadcastExecuted_danish() {
        let cs = CommandStrings.forLanguage(.danish)
        let msg = cs.broadcastExecuted(2, 3)
        XCTAssertFalse(msg.isEmpty)
        XCTAssertTrue(msg.contains("2"), "Should mention success count")
    }

    func testCommandStrings_broadcastNothingInScope_danish() {
        let cs = CommandStrings.forLanguage(.danish)
        XCTAssertFalse(cs.broadcastNothingInScope.isEmpty)
    }
}
