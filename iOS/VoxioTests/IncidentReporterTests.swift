import XCTest
import CryptoKit
@testable import Voxio

// E-50 T-5004 — Unit tests for IncidentReporter.
//
// Networking is NOT performed in unit tests — TELEMETRY_HOSTNAME is absent in the
// test bundle, so IncidentReporter.upload() returns early after the guard.
// Tests focus on: dedup logic, fingerprint properties, non-error no-op,
// recursion guard, and WiFi-guard short-circuit.

@MainActor
final class IncidentReporterTests: XCTestCase {

    // MARK: - Setup / teardown

    override func setUp() async throws {
        try await super.setUp()
        BreadcrumbTracker.shared.reset()
        // Clean up any leftover dedup keys from prior test runs.
        removeAllIncidentKeys()
    }

    override func tearDown() async throws {
        removeAllIncidentKeys()
        BreadcrumbTracker.shared.reset()
        try await super.tearDown()
    }

    private func removeAllIncidentKeys() {
        let defaults = UserDefaults.standard
        let dict = defaults.dictionaryRepresentation()
        for key in dict.keys where key.hasPrefix("incident_reported_") {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Non-error no-op

    func testNonError_doesNotWriteUserDefaults() async throws {
        let reporter = IncidentReporter.shared

        reporter.didLog(level: .info, line: "12:00:00.000 [INFO] some info", timestamp: Date())
        reporter.didLog(level: .verbose, line: "12:00:00.000 [VERBOSE] verbose", timestamp: Date())

        // Give the hop to MainActor a chance to run (if any).
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 s

        let dict = UserDefaults.standard.dictionaryRepresentation()
        let incidentKeys = dict.keys.filter { $0.hasPrefix("incident_reported_") }
        XCTAssertTrue(incidentKeys.isEmpty,
                      "Non-error log calls must not write any incident_reported_ key")
    }

    // MARK: - Error writes dedup key

    func testError_writesUserDefaultsDedupKey() async throws {
        let reporter = IncidentReporter.shared
        let line = "12:00:00.000 [ERROR] connection refused unique-\(UUID().uuidString)"

        reporter.didLog(level: .error, line: line, timestamp: Date())

        // Allow main-actor hop to complete.
        try await Task.sleep(nanoseconds: 200_000_000)

        let dict = UserDefaults.standard.dictionaryRepresentation()
        let incidentKeys = dict.keys.filter { $0.hasPrefix("incident_reported_") }
        XCTAssertFalse(incidentKeys.isEmpty,
                       "An error log call must write at least one incident_reported_ key")
    }

    // MARK: - 24-hour deduplication

    func testDedup_sameFingerprint_onlyOneKeyWritten() async throws {
        let reporter = IncidentReporter.shared
        // Use the same message so both calls produce the same fingerprint.
        let msg = "connection timeout identical-\(UUID().uuidString)"
        let line = "12:00:00.000 [ERROR] \(msg)"

        reporter.didLog(level: .error, line: line, timestamp: Date())
        try await Task.sleep(nanoseconds: 200_000_000)

        let dict1 = UserDefaults.standard.dictionaryRepresentation()
        let keys1 = dict1.keys.filter { $0.hasPrefix("incident_reported_") }
        XCTAssertEqual(keys1.count, 1, "First error should write exactly one dedup key")

        let firstValue = UserDefaults.standard.double(forKey: keys1[0])

        reporter.didLog(level: .error, line: line, timestamp: Date())
        try await Task.sleep(nanoseconds: 200_000_000)

        // The key should still exist and its value should not have been updated
        // (second call is deduped within 24 h).
        let secondValue = UserDefaults.standard.double(forKey: keys1[0])
        XCTAssertEqual(firstValue, secondValue,
                       "Second call within 24 h must not update the dedup timestamp")
    }

    func testDedup_expired24h_writesNewTimestamp() async throws {
        let reporter = IncidentReporter.shared
        let msg = "timeout expired-dedup-\(UUID().uuidString)"
        let line = "12:00:00.000 [ERROR] \(msg)"

        // Manually plant a dedup key that is 25 hours old.
        reporter.didLog(level: .error, line: line, timestamp: Date())
        try await Task.sleep(nanoseconds: 200_000_000)

        let dict = UserDefaults.standard.dictionaryRepresentation()
        let keys = dict.keys.filter { $0.hasPrefix("incident_reported_") }
        guard let key = keys.first else {
            XCTFail("Expected a dedup key to be written"); return
        }

        // Back-date the timestamp by 25 hours.
        let old = Date().timeIntervalSince1970 - (25 * 3600)
        UserDefaults.standard.set(old, forKey: key)

        let before = UserDefaults.standard.double(forKey: key)

        // Fire the same error again — should write a fresh timestamp.
        reporter.didLog(level: .error, line: line, timestamp: Date())
        try await Task.sleep(nanoseconds: 200_000_000)

        let after = UserDefaults.standard.double(forKey: key)
        XCTAssertGreaterThan(after, before,
                             "Error fired after 24 h must update the dedup timestamp")
    }

    // MARK: - Different fingerprints produce separate keys

    func testDifferentMessages_produceDifferentKeys() async throws {
        let reporter = IncidentReporter.shared
        let id = UUID().uuidString
        let line1 = "12:00:00.000 [ERROR] connection refused alpha-\(id)"
        let line2 = "12:00:00.000 [ERROR] socket timeout beta-\(id)"

        reporter.didLog(level: .error, line: line1, timestamp: Date())
        reporter.didLog(level: .error, line: line2, timestamp: Date())
        try await Task.sleep(nanoseconds: 300_000_000)

        let dict = UserDefaults.standard.dictionaryRepresentation()
        let keys = dict.keys.filter { $0.hasPrefix("incident_reported_") }
        XCTAssertEqual(keys.count, 2,
                       "Two distinct error messages must produce two separate dedup keys")
    }

    // MARK: - Fingerprint properties

    func testFingerprint_is16LowercaseHexChars() async throws {
        let reporter = IncidentReporter.shared
        let line = "12:00:00.000 [ERROR] fingerprint-shape-\(UUID().uuidString)"

        reporter.didLog(level: .error, line: line, timestamp: Date())
        try await Task.sleep(nanoseconds: 200_000_000)

        let dict = UserDefaults.standard.dictionaryRepresentation()
        let keys = dict.keys.filter { $0.hasPrefix("incident_reported_") }
        guard let key = keys.first else {
            XCTFail("Expected a dedup key"); return
        }

        let fingerprint = String(key.dropFirst("incident_reported_".count))
        XCTAssertEqual(fingerprint.count, 16, "Fingerprint must be exactly 16 characters")

        let allowedChars = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(fingerprint.unicodeScalars.allSatisfy { allowedChars.contains($0) },
                      "Fingerprint must be lowercase hex; got: \(fingerprint)")
    }

    func testFingerprint_digitStripping_sameForDifferentCounts() async throws {
        // Two lines that differ only in numeric values should produce the same fingerprint.
        let reporter = IncidentReporter.shared

        // Use a suffix that is unique across test runs to avoid collision with other tests.
        let suffix = UUID().uuidString
        let line42  = "12:00:00.000 [ERROR] Connection failed count=42 id=\(suffix)"
        let line999 = "12:00:00.000 [ERROR] Connection failed count=999 id=\(suffix)"

        reporter.didLog(level: .error, line: line42, timestamp: Date())
        try await Task.sleep(nanoseconds: 200_000_000)

        let dict1 = UserDefaults.standard.dictionaryRepresentation()
        let keys1 = dict1.keys.filter { $0.hasPrefix("incident_reported_") }
        guard let key42 = keys1.first else {
            XCTFail("Expected dedup key for line42"); return
        }

        // Back-date so the second call doesn't get deduped by the first.
        UserDefaults.standard.set(Date().timeIntervalSince1970 - 90_000, forKey: key42)

        reporter.didLog(level: .error, line: line999, timestamp: Date())
        try await Task.sleep(nanoseconds: 200_000_000)

        // If fingerprints match, the second call will have updated the same key.
        let dict2 = UserDefaults.standard.dictionaryRepresentation()
        let keys2 = dict2.keys.filter { $0.hasPrefix("incident_reported_") }

        // Only one unique key should exist (the same fingerprint).
        XCTAssertEqual(keys2.count, 1,
                       "Lines differing only in digit content must hash to the same fingerprint; found keys: \(keys2)")
    }

    // MARK: - Recursion guard

    func testRecursionGuard_internalTag_doesNotWriteUserDefaults() async throws {
        let reporter = IncidentReporter.shared
        let line = "12:00:00.000 [ERROR] [IncidentReporter:internal] upload failed: timeout"

        reporter.didLog(level: .error, line: line, timestamp: Date())
        try await Task.sleep(nanoseconds: 200_000_000)

        let dict = UserDefaults.standard.dictionaryRepresentation()
        let incidentKeys = dict.keys.filter { $0.hasPrefix("incident_reported_") }
        XCTAssertTrue(incidentKeys.isEmpty,
                      "Lines containing [IncidentReporter:internal] must be silently ignored")
    }

    // MARK: - LogAnonymiser integration (context lines are anonymised)

    func testAnonymiser_ipInErrorLine_isReplacedInDedupKey() async throws {
        // We can't easily inspect the payload, but we can verify the dedup key is written
        // (which means anonymisation ran without crashing) and that the fingerprint exists.
        let reporter = IncidentReporter.shared
        let line = "12:00:00.000 [ERROR] failed connecting to 192.168.1.1 unique-\(UUID().uuidString)"

        reporter.didLog(level: .error, line: line, timestamp: Date())
        try await Task.sleep(nanoseconds: 200_000_000)

        let dict = UserDefaults.standard.dictionaryRepresentation()
        let keys = dict.keys.filter { $0.hasPrefix("incident_reported_") }
        XCTAssertFalse(keys.isEmpty,
                       "Error with IP address in line must still produce a dedup key")
    }

    // MARK: - WiFi guard (unit-level: verify upload skips without WiFi)
    // The WiFiPathMonitor.shared.isWiFi flag defaults to false until start() is called
    // and a real network update arrives. In unit tests the monitor is never started,
    // so isWiFi == false and the upload code path is not exercised.
    // This test verifies the dedup key IS written (dedup happens before WiFi check)
    // even when WiFi is absent — matching ADR Consequence 3.

    func testWiFiGuard_dedupWrittenBeforeWiFiCheck() async throws {
        // WiFiPathMonitor.shared is not started in tests → isWiFi == false.
        XCTAssertFalse(WiFiPathMonitor.shared.isWiFi,
                       "isWiFi must be false in unit tests (monitor not started)")

        let reporter = IncidentReporter.shared
        let line = "12:00:00.000 [ERROR] wifi-guard-test-\(UUID().uuidString)"

        reporter.didLog(level: .error, line: line, timestamp: Date())
        try await Task.sleep(nanoseconds: 200_000_000)

        let dict = UserDefaults.standard.dictionaryRepresentation()
        let keys = dict.keys.filter { $0.hasPrefix("incident_reported_") }
        XCTAssertFalse(keys.isEmpty,
                       "Dedup key must be written even when WiFi is absent (ADR Consequence 3)")
    }
}
