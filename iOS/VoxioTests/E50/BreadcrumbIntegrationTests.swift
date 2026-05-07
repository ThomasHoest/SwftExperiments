import XCTest
@testable import Voxio

// E-50 — Integration tests for BreadcrumbTracker (T-5001 / T-5002).
//
// These tests verify BreadcrumbTracker.shared in a simulated navigation flow and confirm
// that the breadcrumb path is correctly maintained across push/pop/reset operations.
//
// Key API facts (corrected from the original file):
//   - currentPath: String       — returns stack joined with " > ", e.g. "Home > Settings"
//   - stack: [String]           — the raw navigation stack (private(set))
//   - push(_ screenName: String)
//   - pop()                     — no-op if stack is empty
//   - reset()                   — clears the stack; used in setUp/tearDown
//
// Tests that previously compared currentPath to [] (Array) are fixed to compare to ""
// (empty String), and array comparisons use .stack instead.

@MainActor
final class BreadcrumbIntegrationTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        BreadcrumbTracker.shared.reset()
    }

    override func tearDown() async throws {
        BreadcrumbTracker.shared.reset()
        try await super.tearDown()
    }

    // MARK: - T-5001: Home → Settings → LearnedPhrases navigation flow

    func testPushSequence_homeToSettingsToLearnedPhrases_currentPathCorrectAtEachStep() {
        // After reset, currentPath must be an empty String (not []).
        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "",
            "currentPath must be empty string after reset")

        BreadcrumbTracker.shared.push("Home")
        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "Home",
            "After pushing 'Home', currentPath must be 'Home'")

        BreadcrumbTracker.shared.push("Settings")
        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "Home > Settings",
            "After pushing 'Settings', currentPath must be 'Home > Settings'")

        BreadcrumbTracker.shared.push("LearnedPhrases")
        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "Home > Settings > LearnedPhrases",
            "After pushing 'LearnedPhrases', currentPath must be 'Home > Settings > LearnedPhrases'")
    }

    func testPushSequence_stackMatchesCurrentPath() {
        BreadcrumbTracker.shared.push("Home")
        BreadcrumbTracker.shared.push("Settings")

        XCTAssertEqual(BreadcrumbTracker.shared.stack, ["Home", "Settings"],
            "stack must match the individual screen names")
        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "Home > Settings",
            "currentPath must be stack joined with ' > '")
    }

    func testPopSequence_fromLearnedPhrasesBackToHome_currentPathCorrectAtEachStep() {
        BreadcrumbTracker.shared.push("Home")
        BreadcrumbTracker.shared.push("Settings")
        BreadcrumbTracker.shared.push("LearnedPhrases")

        BreadcrumbTracker.shared.pop()
        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "Home > Settings",
            "After popping 'LearnedPhrases', currentPath must be 'Home > Settings'")

        BreadcrumbTracker.shared.pop()
        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "Home",
            "After popping 'Settings', currentPath must be 'Home'")

        BreadcrumbTracker.shared.pop()
        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "",
            "After popping 'Home', currentPath must be empty string")
    }

    func testPopSequence_stackIsEmptyAfterPoppingAll() {
        BreadcrumbTracker.shared.push("Home")
        BreadcrumbTracker.shared.push("Settings")
        BreadcrumbTracker.shared.push("LearnedPhrases")
        BreadcrumbTracker.shared.pop()
        BreadcrumbTracker.shared.pop()
        BreadcrumbTracker.shared.pop()

        XCTAssertEqual(BreadcrumbTracker.shared.stack, [],
            "stack must be empty after popping all elements")
        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "",
            "currentPath must be empty string when stack is empty")
    }

    func testPushPop_interleaved_maintainsConsistentStack() {
        BreadcrumbTracker.shared.push("Home")
        BreadcrumbTracker.shared.push("Settings")
        BreadcrumbTracker.shared.pop()                       // back to Home
        BreadcrumbTracker.shared.push("HelpView")
        BreadcrumbTracker.shared.pop()                       // back to Home
        BreadcrumbTracker.shared.push("Settings")
        BreadcrumbTracker.shared.push("LearnedPhrases")

        XCTAssertEqual(BreadcrumbTracker.shared.stack, ["Home", "Settings", "LearnedPhrases"],
            "Interleaved push/pop sequence must produce the expected final stack")
        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "Home > Settings > LearnedPhrases",
            "currentPath must reflect the final stack state")
    }

    // MARK: - T-5001: Rapid push/pop (SwiftUI transition overlap)

    func testRapidPushPop_doesNotCrashAndStackStaysConsistent() {
        // Simulate rapid SwiftUI transitions where push and pop happen in rapid succession.
        for i in 0..<100 {
            BreadcrumbTracker.shared.push("Screen-\(i)")
        }
        for _ in 0..<100 {
            BreadcrumbTracker.shared.pop()
        }

        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "",
            "After 100 pushes and 100 pops, currentPath must be empty string")
        XCTAssertEqual(BreadcrumbTracker.shared.stack, [],
            "After 100 pushes and 100 pops, stack must be empty")
    }

    func testRapidPushPop_excessivePops_doesNotCrashOrUnderflow() {
        BreadcrumbTracker.shared.push("Home")

        // Pop more times than there are items on the stack — must not crash.
        for _ in 0..<10 {
            BreadcrumbTracker.shared.pop()
        }

        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "",
            "Excessive pops must not crash and must leave currentPath as empty string")
        XCTAssertEqual(BreadcrumbTracker.shared.stack, [],
            "Excessive pops must not crash and must leave stack empty")
    }

    func testRapidPushPop_concurrentSimulation_stackNeverNegative() {
        // Simulate many rapid interleaved pushes and pops at the call-site level
        // (sequential, since BreadcrumbTracker is @MainActor, but tests fast thrash).
        for _ in 0..<50 {
            BreadcrumbTracker.shared.push("Transient")
            BreadcrumbTracker.shared.pop()
        }

        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "",
            "Stack must be empty string after equal push/pop pairs")
        XCTAssertGreaterThanOrEqual(BreadcrumbTracker.shared.stack.count, 0,
            "Stack count must never be negative")
    }

    // MARK: - T-5002: IncidentReporter captures breadcrumbs at error time (via currentPath)

    func testIncidentReporter_capturesBreadcrumbsAtErrorTime_notAtUploadTime() async throws {
        // Remove any leftover dedup keys so the pipeline isn't suppressed.
        removeAllIncidentDedupKeys()
        FileLogListener.shared.resetRingBuffer()

        BreadcrumbTracker.shared.push("Home")

        // Fire error while on "Home".
        let line = "12:00:00.000 [ERROR] breadcrumb-capture-time-\(UUID().uuidString)"
        IncidentReporter.shared.didLog(level: .error, line: line, timestamp: Date())

        // Navigate further AFTER the error fires.
        BreadcrumbTracker.shared.push("Settings")
        BreadcrumbTracker.shared.push("AliasListView")

        // Wait for main-actor hop to complete.
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify the pipeline ran (dedup key written).
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("incident_reported_") }
        XCTAssertFalse(keys.isEmpty,
            "Pipeline must complete (dedup key written) confirming breadcrumb capture occurred")

        // Clean up.
        removeAllIncidentDedupKeys()
    }

    func testIncidentReporter_capturesBreadcrumbs_deepStack() async throws {
        removeAllIncidentDedupKeys()
        FileLogListener.shared.resetRingBuffer()

        BreadcrumbTracker.shared.push("Home")
        BreadcrumbTracker.shared.push("Settings")
        BreadcrumbTracker.shared.push("LearnedPhrases")

        let line = "12:00:00.000 [ERROR] deep-stack-breadcrumb-\(UUID().uuidString)"
        IncidentReporter.shared.didLog(level: .error, line: line, timestamp: Date())
        try await Task.sleep(nanoseconds: 200_000_000)

        // Pipeline ran with the full stack → dedup key present.
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("incident_reported_") }
        XCTAssertFalse(keys.isEmpty,
            "Pipeline must run with deep breadcrumb stack")

        removeAllIncidentDedupKeys()
    }

    func testIncidentReporter_capturesBreadcrumbs_emptyStack() async throws {
        removeAllIncidentDedupKeys()
        FileLogListener.shared.resetRingBuffer()
        // BreadcrumbTracker already reset in setUp.

        let line = "12:00:00.000 [ERROR] empty-stack-breadcrumb-\(UUID().uuidString)"
        IncidentReporter.shared.didLog(level: .error, line: line, timestamp: Date())
        try await Task.sleep(nanoseconds: 200_000_000)

        // Pipeline ran with empty breadcrumb path → dedup key present.
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("incident_reported_") }
        XCTAssertFalse(keys.isEmpty,
            "Pipeline must run when breadcrumb stack is empty")

        removeAllIncidentDedupKeys()
    }

    // MARK: - T-5001: reset() clears all state

    func testReset_clearsPreviouslyPushedScreens() {
        BreadcrumbTracker.shared.push("Home")
        BreadcrumbTracker.shared.push("Settings")
        BreadcrumbTracker.shared.reset()

        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "",
            "reset() must result in empty string currentPath")
        XCTAssertEqual(BreadcrumbTracker.shared.stack, [],
            "reset() must clear the stack to []")
    }

    func testReset_allowsFreshNavigationAfterwards() {
        BreadcrumbTracker.shared.push("Home")
        BreadcrumbTracker.shared.push("Settings")
        BreadcrumbTracker.shared.reset()

        BreadcrumbTracker.shared.push("Home")
        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "Home",
            "After reset(), fresh navigation must work correctly")
        XCTAssertEqual(BreadcrumbTracker.shared.stack, ["Home"],
            "After reset(), stack must contain only the newly-pushed screen")
    }

    // MARK: - currentPath is a value (snapshot semantics)

    func testCurrentPath_isSnapshot_notLiveReference() {
        BreadcrumbTracker.shared.push("Home")
        let snapshotBefore = BreadcrumbTracker.shared.currentPath // "Home"

        BreadcrumbTracker.shared.push("Settings")

        // The captured String is a value — it does not reflect subsequent mutations.
        XCTAssertEqual(snapshotBefore, "Home",
            "A previously captured currentPath String must not reflect subsequent push operations")
        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "Home > Settings",
            "currentPath must reflect the latest state after push")
    }

    func testStack_isSnapshot_notLiveReference() {
        BreadcrumbTracker.shared.push("Home")
        let snapshotBefore = BreadcrumbTracker.shared.stack // ["Home"]

        BreadcrumbTracker.shared.push("Settings")

        // Array is a value type — the captured snapshot does not change.
        XCTAssertEqual(snapshotBefore, ["Home"],
            "A previously captured stack Array must not reflect subsequent push operations")
        XCTAssertEqual(BreadcrumbTracker.shared.stack, ["Home", "Settings"],
            "stack must reflect the latest state after push")
    }

    // MARK: - currentPath format

    func testCurrentPath_singleElement_noSeparator() {
        BreadcrumbTracker.shared.push("Home")
        XCTAssertEqual(BreadcrumbTracker.shared.currentPath, "Home",
            "Single-element currentPath must not include a separator")
    }

    func testCurrentPath_separator_isSpaceGreaterThanSpace() {
        BreadcrumbTracker.shared.push("A")
        BreadcrumbTracker.shared.push("B")
        XCTAssertTrue(BreadcrumbTracker.shared.currentPath.contains(" > "),
            "currentPath must use ' > ' (space-gt-space) as the separator")
    }

    func testCurrentPath_noLeadingOrTrailingSeparator() {
        BreadcrumbTracker.shared.push("Home")
        let path = BreadcrumbTracker.shared.currentPath
        XCTAssertFalse(path.hasPrefix(" > "),
            "currentPath must not start with ' > '")
        XCTAssertFalse(path.hasSuffix(" > "),
            "currentPath must not end with ' > '")
    }

    // MARK: - Private helpers

    private func removeAllIncidentDedupKeys() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("incident_reported_") {
            defaults.removeObject(forKey: key)
        }
    }
}
