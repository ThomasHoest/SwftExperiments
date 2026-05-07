import XCTest
@testable import Voxio

// E-50 T-5003 — Unit tests for BreadcrumbTracker.
// All mutations are on the main actor.

@MainActor
final class BreadcrumbTrackerTests: XCTestCase {

    private var tracker: BreadcrumbTracker!

    override func setUp() async throws {
        try await super.setUp()
        // Create a fresh instance per test so tests don't share the .shared singleton.
        // BreadcrumbTracker has a private init so we must use .shared and reset it.
        tracker = BreadcrumbTracker.shared
        tracker.reset()
    }

    override func tearDown() async throws {
        tracker.reset()
        try await super.tearDown()
    }

    // MARK: - Initial state

    func testInitialState_stackEmpty() {
        XCTAssertEqual(tracker.stack, [])
    }

    func testInitialState_currentPathEmpty() {
        XCTAssertEqual(tracker.currentPath, "")
    }

    // MARK: - Push

    func testPush_appendsToStack() {
        tracker.push("Home")
        XCTAssertEqual(tracker.stack, ["Home"])
    }

    func testPush_currentPath_singleElement() {
        tracker.push("Home")
        XCTAssertEqual(tracker.currentPath, "Home")
    }

    func testPush_twoElements_currentPathJoined() {
        tracker.push("Home")
        tracker.push("Settings")
        XCTAssertEqual(tracker.currentPath, "Home > Settings")
    }

    func testPush_threeElements() {
        tracker.push("Home")
        tracker.push("Settings")
        tracker.push("Settings.Aliases")
        XCTAssertEqual(tracker.currentPath, "Home > Settings > Settings.Aliases")
    }

    func testPush_duplicateNames_bothAppended() {
        tracker.push("Home")
        tracker.push("Home")
        XCTAssertEqual(tracker.stack, ["Home", "Home"])
        XCTAssertEqual(tracker.currentPath, "Home > Home")
    }

    // MARK: - Pop

    func testPop_removesLastElement() {
        tracker.push("Home")
        tracker.push("Settings")
        tracker.pop()
        XCTAssertEqual(tracker.stack, ["Home"])
        XCTAssertEqual(tracker.currentPath, "Home")
    }

    func testPop_fromSingleElement_becomesEmpty() {
        tracker.push("Home")
        tracker.pop()
        XCTAssertEqual(tracker.stack, [])
        XCTAssertEqual(tracker.currentPath, "")
    }

    func testPop_onEmptyStack_doesNotCrash() {
        // Must not throw or crash
        tracker.pop()
        XCTAssertEqual(tracker.stack, [])
        XCTAssertEqual(tracker.currentPath, "")
    }

    func testPop_multipleTimes_stopsAtEmpty() {
        tracker.push("A")
        tracker.push("B")
        tracker.pop()
        tracker.pop()
        tracker.pop() // extra — must not crash
        XCTAssertEqual(tracker.stack, [])
    }

    // MARK: - Reset

    func testReset_emptyStack() {
        tracker.push("Home")
        tracker.push("Settings")
        tracker.reset()
        XCTAssertEqual(tracker.stack, [])
        XCTAssertEqual(tracker.currentPath, "")
    }

    func testReset_onEmptyStack_noOp() {
        tracker.reset()
        XCTAssertEqual(tracker.stack, [])
    }

    // MARK: - Separator format

    func testCurrentPath_separatorIsSpaceGreaterThanSpace() {
        tracker.push("A")
        tracker.push("B")
        XCTAssertTrue(tracker.currentPath.contains(" > "),
                      "Separator must be ' > ' (space-gt-space)")
    }

    func testCurrentPath_noTrailingSeparator() {
        tracker.push("Home")
        XCTAssertFalse(tracker.currentPath.hasPrefix(" > "))
        XCTAssertFalse(tracker.currentPath.hasSuffix(" > "))
    }
}
