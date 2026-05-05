import XCTest
import CoreData
@testable import Voxio

// E-35 — Unit tests for TelemetryUploader (T-3505 / T-3506 / T-3508).
//
// Network calls are guarded by isEnabled and baseURL. Tests verify no side-effects
// occur when the uploader is disabled or when baseURL is nil (simulated by the
// absent TELEMETRY_BASE_URL xcconfig key in the test bundle).

@MainActor
final class TelemetryUploaderTests: XCTestCase {

    // MARK: - Helpers

    private func makeBuffer() -> TelemetryBuffer {
        TelemetryBuffer(context: PersistenceController.preview.viewContext)
    }

    private func makeUploader(buffer: TelemetryBuffer? = nil) -> TelemetryUploader {
        let buf = buffer ?? makeBuffer()
        return TelemetryUploader(buffer: buf)
    }

    // MARK: - isEnabled tests

    func testIsEnabled_defaultsToFalse() {
        UserDefaults.standard.removeObject(forKey: "telemetryEnabled")
        defer { UserDefaults.standard.removeObject(forKey: "telemetryEnabled") }

        let uploader = makeUploader()
        XCTAssertFalse(uploader.isEnabled,
            "isEnabled must default to false when 'telemetryEnabled' key is absent in UserDefaults")
    }

    func testIsEnabled_canBeSetToTrue() {
        defer { UserDefaults.standard.removeObject(forKey: "telemetryEnabled") }

        let uploader = makeUploader()
        uploader.isEnabled = true
        XCTAssertTrue(uploader.isEnabled)
    }

    func testIsEnabled_persistsAcrossInstances() {
        defer { UserDefaults.standard.removeObject(forKey: "telemetryEnabled") }

        let uploaderA = makeUploader()
        uploaderA.isEnabled = true

        let uploaderB = makeUploader()
        XCTAssertTrue(uploaderB.isEnabled,
            "isEnabled backed by UserDefaults must be visible to a new instance")
    }

    // MARK: - attemptUploadIfDue() when disabled

    func testAttemptUploadIfDue_noOp_whenDisabled() async throws {
        UserDefaults.standard.removeObject(forKey: "telemetryEnabled")
        defer { UserDefaults.standard.removeObject(forKey: "telemetryEnabled") }

        let buffer = makeBuffer()
        let speakerId = "spk-upload-noop-\(UUID().uuidString)"
        try buffer.record(
            transcription: "upload noOp test \(speakerId)",
            speakerName: "Speaker",
            speakerId: speakerId,
            intent: "stop",
            slots: [:],
            parserPath: "regex",
            outcome: .confirmed,
            locale: "en_GB",
            flags: []
        )

        let uploader = TelemetryUploader(buffer: buffer)
        XCTAssertFalse(uploader.isEnabled)

        await uploader.attemptUploadIfDue()

        let pending = try buffer.pendingBatch(limit: 100).filter { $0.speakerId == speakerId }
        XCTAssertFalse(pending.isEmpty,
            "attemptUploadIfDue must not mark events uploaded when isEnabled is false")
    }

    func testAttemptUploadIfDue_noOp_whenBaseURLNil() async throws {
        let rawURL = Bundle.main.infoDictionary?["TELEMETRY_BASE_URL"] as? String
        guard rawURL == nil || rawURL?.isEmpty == true else {
            // xcconfig is wired in this build — this test path requires nil URL
            return
        }

        let buffer = makeBuffer()
        let speakerId = "spk-base-url-nil-\(UUID().uuidString)"
        try buffer.record(
            transcription: "base url nil test \(speakerId)",
            speakerName: "Speaker",
            speakerId: speakerId,
            intent: "stop",
            slots: [:],
            parserPath: "regex",
            outcome: .confirmed,
            locale: "en_GB",
            flags: []
        )

        let uploader = TelemetryUploader(buffer: buffer)
        uploader.isEnabled = true
        defer { uploader.isEnabled = false; UserDefaults.standard.removeObject(forKey: "telemetryEnabled") }

        await uploader.attemptUploadIfDue()

        let pending = try buffer.pendingBatch(limit: 100).filter { $0.speakerId == speakerId }
        XCTAssertFalse(pending.isEmpty,
            "attemptUploadIfDue must not mark events uploaded when baseURL is nil")
    }

    // MARK: - requestDeletion() tests

    func testRequestDeletion_returnsPending_whenBaseURLNil() async {
        let rawURL = Bundle.main.infoDictionary?["TELEMETRY_BASE_URL"] as? String
        guard rawURL == nil || rawURL?.isEmpty == true else {
            return  // xcconfig is wired — skip nil-URL assertion
        }

        let uploader = makeUploader()
        uploader.isEnabled = true
        defer { uploader.isEnabled = false; UserDefaults.standard.removeObject(forKey: "telemetryEnabled") }

        let result = await uploader.requestDeletion()
        if case .pending = result {
            // Pass
        } else {
            XCTFail("requestDeletion() must return .pending when baseURL is nil; got \(result)")
        }
    }

    func testRequestDeletion_returnsPending_whenDisabled() async {
        UserDefaults.standard.removeObject(forKey: "telemetryEnabled")
        defer { UserDefaults.standard.removeObject(forKey: "telemetryEnabled") }

        let uploader = makeUploader()
        XCTAssertFalse(uploader.isEnabled)

        let result = await uploader.requestDeletion()
        if case .pending = result {
            // Pass: correct behaviour when disabled
        } else {
            XCTFail("requestDeletion() should return .pending when uploader is disabled; got \(result)")
        }
    }

    // MARK: - DeletionResult enum shape

    func testDeletionResult_successCase_exists() {
        let result = TelemetryUploader.DeletionResult.success
        if case .success = result { /* pass */ }
    }

    func testDeletionResult_pendingCase_exists() {
        let result = TelemetryUploader.DeletionResult.pending
        if case .pending = result { /* pass */ }
    }

    func testDeletionResult_failedCase_carriesError() {
        let error = NSError(domain: "TestDomain", code: 42)
        let result = TelemetryUploader.DeletionResult.failed(error)
        if case .failed(let e) = result {
            XCTAssertEqual((e as NSError).code, 42)
        } else {
            XCTFail("DeletionResult.failed must carry the provided error")
        }
    }
}
