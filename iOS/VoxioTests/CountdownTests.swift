import XCTest
@testable import Voxio

// T-2509 — Countdown state machine and CancelGrammar unit tests.
// ConfirmationCoordinator is @MainActor so every test runs on the main actor.
@MainActor
final class CountdownTests: XCTestCase {

    // MARK: - ConfirmationCoordinator

    func testCountdownFires_actionCalledOnce() async throws {
        let coordinator = ConfirmationCoordinator()
        var actionCallCount = 0
        var resolution: Resolution?

        coordinator.startCountdown(
            action: { actionCallCount += 1 },
            readBack: "Test action",
            onResolved: { resolution = $0 }
        )

        // Wait long enough for the 2-second countdown to complete
        try await Task.sleep(for: .seconds(3))

        XCTAssertEqual(actionCallCount, 1)
        XCTAssertEqual(resolution, .fired)
        XCTAssertFalse(coordinator.isPending)
    }

    func testTapCancel_actionNotCalled() async throws {
        let coordinator = ConfirmationCoordinator()
        var actionCallCount = 0
        var resolution: Resolution?

        coordinator.startCountdown(
            action: { actionCallCount += 1 },
            readBack: "Test action",
            onResolved: { resolution = $0 }
        )

        try await Task.sleep(for: .milliseconds(500))
        coordinator.cancelCountdown(reason: .userTap)

        try await Task.sleep(for: .seconds(1))

        XCTAssertEqual(actionCallCount, 0)
        XCTAssertEqual(resolution, .cancelled)
        XCTAssertFalse(coordinator.isPending)
    }

    func testVoiceCancel_actionNotCalled() async throws {
        let coordinator = ConfirmationCoordinator()
        var actionCallCount = 0
        var resolution: Resolution?

        coordinator.startCountdown(
            action: { actionCallCount += 1 },
            readBack: "Test action",
            onResolved: { resolution = $0 }
        )

        try await Task.sleep(for: .milliseconds(500))
        coordinator.cancelCountdown(reason: .userVoice)

        try await Task.sleep(for: .seconds(1))

        XCTAssertEqual(actionCallCount, 0)
        XCTAssertEqual(resolution, .cancelled)
    }

    func testCancelIsIdempotent_resolvedOnce() async throws {
        let coordinator = ConfirmationCoordinator()
        var resolvedCount = 0

        coordinator.startCountdown(
            action: { },
            readBack: "Test",
            onResolved: { _ in resolvedCount += 1 }
        )

        try await Task.sleep(for: .milliseconds(200))
        coordinator.cancelCountdown(reason: .userTap)
        coordinator.cancelCountdown(reason: .userTap) // second call must be a no-op

        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(resolvedCount, 1)
    }

    func testInterruptionCancel_resolvedCancelled() async throws {
        let coordinator = ConfirmationCoordinator()
        var actionCallCount = 0
        var resolution: Resolution?

        coordinator.startCountdown(
            action: { actionCallCount += 1 },
            readBack: "Test",
            onResolved: { resolution = $0 }
        )

        try await Task.sleep(for: .milliseconds(300))
        coordinator.cancelCountdown(reason: .interruption)

        try await Task.sleep(for: .seconds(1))

        XCTAssertEqual(actionCallCount, 0)
        XCTAssertEqual(resolution, .cancelled)
        // Note: .interruption must NOT fire an error haptic — this is a side-effect
        // that cannot be asserted here; verified manually per T-2510.
    }

    func testSecondsRemainingDecrements() async throws {
        let coordinator = ConfirmationCoordinator()

        coordinator.startCountdown(action: { }, readBack: "Test", onResolved: { _ in })
        XCTAssertEqual(coordinator.secondsRemaining, 2)

        try await Task.sleep(for: .seconds(1.1))
        XCTAssertEqual(coordinator.secondsRemaining, 1)

        coordinator.cancelCountdown(reason: .interruption)
    }

    // MARK: - CancelGrammar

    func testCancelGrammar_englishTokens() {
        XCTAssertTrue(CancelGrammar.matches("cancel"))
        XCTAssertTrue(CancelGrammar.matches("no"))
        XCTAssertTrue(CancelGrammar.matches("CANCEL"))
        XCTAssertTrue(CancelGrammar.matches("No thanks"))
    }

    func testCancelGrammar_danishTokens() {
        XCTAssertTrue(CancelGrammar.matches("nej"))
        XCTAssertTrue(CancelGrammar.matches("annuller"))
        XCTAssertTrue(CancelGrammar.matches("Annuller det"))
    }

    func testCancelGrammar_substringsDoNotMatch() {
        XCTAssertFalse(CancelGrammar.matches("I cannot"))
        XCTAssertFalse(CancelGrammar.matches("playing now"))
        XCTAssertFalse(CancelGrammar.matches(""))
    }
}
