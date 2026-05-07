import XCTest
import CryptoKit
@testable import Voxio

// E-50 — Integration tests for the anonymisation pipeline (T-5002 / T-5003).
//
// LogAnonymiser is a value type with no dependencies — tests exercise it directly and
// in combination with the FileLogListener ring buffer to confirm that context lines
// seeded via FileLogListener.shared.injectLine(_:) are anonymised before they would
// appear in an IncidentPayload.
//
// Covered patterns:
//   • IPv4 addresses (e.g. 192.168.1.1)  → [IP]
//   • UUIDs (RFC-4122)                   → [UUID]
//   • JID strings (.jid. pattern)        → [JID]
//   • Transcription fragments            → [TRANSCRIPTION] (via [CommandParserRouter] marker)
//
// The breadcrumbs field (BreadcrumbTracker.shared.currentPath) is a navigation path, NOT
// a log line — it is NOT anonymised. Tests confirm it is a plain " > "-joined String.
//
// Note on IncidentReporter integration:
//   IncidentReporter is a sealed singleton (private init). Anonymisation of contextLines
//   and errorLine happens inside IncidentReporter.handleError on the main actor. Rather
//   than re-invoking the singleton end-to-end for every pattern, these tests verify the
//   LogAnonymiser value type directly (the same instance used by the reporter). A single
//   smoke-test confirms the pipeline wires up correctly end-to-end via the dedup key.

@MainActor
final class AnonymisationPipelineTests: XCTestCase {

    // MARK: - setUp / tearDown

    private let anonymiser = LogAnonymiser()

    override func setUp() async throws {
        try await super.setUp()
        FileLogListener.shared.resetRingBuffer()
        BreadcrumbTracker.shared.reset()
        removeAllIncidentDedupKeys()
    }

    override func tearDown() async throws {
        removeAllIncidentDedupKeys()
        BreadcrumbTracker.shared.reset()
        FileLogListener.shared.resetRingBuffer()
        try await super.tearDown()
    }

    private func removeAllIncidentDedupKeys() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("incident_reported_") {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - IPv4 address anonymisation

    func testContextLines_IPv4Address_isRedacted() {
        let ipAddress = "192.168.1.50"
        let line = "2026-05-06 10:00:00 [INFO] Connecting to \(ipAddress) port 80"
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.contains(ipAddress),
            "IPv4 address '\(ipAddress)' must not appear in anonymised output; got: '\(result)'")
        XCTAssertTrue(result.contains("[IP]"),
            "Anonymised output must contain [IP] sentinel; got: '\(result)'")
    }

    func testContextLines_multipleIPv4Addresses_allRedacted() {
        let addresses = ["10.0.0.1", "172.16.5.99", "192.168.100.200"]
        for addr in addresses {
            let line = "2026-05-06 10:00:00 [INFO] Peer at \(addr)"
            let result = anonymiser.anonymise(line)
            XCTAssertFalse(result.contains(addr),
                "IPv4 '\(addr)' must not appear in anonymised output; got: '\(result)'")
        }
    }

    func testContextLines_multipleIPv4InOneLine_allRedacted() {
        let line = "2026-05-06 10:00:00 [INFO] src=10.0.0.1 dst=192.168.1.5"
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.contains("10.0.0.1"),
            "First IPv4 must be redacted; got: '\(result)'")
        XCTAssertFalse(result.contains("192.168.1.5"),
            "Second IPv4 must be redacted; got: '\(result)'")
    }

    // MARK: - UUID anonymisation

    func testContextLines_UUID_isRedacted() {
        let rawUUID = "A3B4C5D6-E7F8-9012-ABCD-EF1234567890"
        let line = "2026-05-06 10:00:01 [INFO] Device ID resolved: \(rawUUID)"
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.lowercased().contains(rawUUID.lowercased()),
            "UUID '\(rawUUID)' must not appear in anonymised output; got: '\(result)'")
        XCTAssertTrue(result.contains("[UUID]"),
            "Anonymised output must contain [UUID] sentinel; got: '\(result)'")
    }

    func testContextLines_lowercaseUUID_isRedacted() {
        let lowercaseUUID = UUID().uuidString.lowercased()
        let line = "2026-05-06 10:00:02 [INFO] session=\(lowercaseUUID)"
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.lowercased().contains(lowercaseUUID),
            "Lowercase UUID '\(lowercaseUUID)' must not appear in anonymised output; got: '\(result)'")
    }

    func testContextLines_uppercaseUUID_isRedacted() {
        let upperUUID = UUID().uuidString.uppercased()
        let line = "2026-05-06 10:00:03 [INFO] token=\(upperUUID)"
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.lowercased().contains(upperUUID.lowercased()),
            "Uppercase UUID must not appear in anonymised output; got: '\(result)'")
    }

    // MARK: - JID string anonymisation

    func testContextLines_JIDString_isRedacted() {
        // JID pattern: \b[A-Za-z0-9]+\.jid\.[A-Za-z0-9.-]+\b
        let jid = "user123.jid.beo-device.local"
        let line = "2026-05-06 10:00:04 [INFO] WebSocket connected as \(jid)"
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.contains(jid),
            "JID '\(jid)' must not appear in anonymised output; got: '\(result)'")
        XCTAssertTrue(result.contains("[JID]"),
            "Anonymised output must contain [JID] sentinel; got: '\(result)'")
    }

    func testContextLines_multipleJIDTokens_allRedacted() {
        let jid1 = "device.jid.speaker.local"
        let jid2 = "ctrl.jid.remote.lan"
        let line = "2026-05-06 10:00:05 [INFO] from=\(jid1) to=\(jid2)"
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.contains(jid1),
            "First JID must be redacted; got: '\(result)'")
        XCTAssertFalse(result.contains(jid2),
            "Second JID must be redacted; got: '\(result)'")
    }

    // MARK: - Transcription line anonymisation

    func testContextLines_transcriptionLine_isRedacted() {
        // Transcription lines contain voice command text following the [CommandParserRouter] marker.
        let transcription = "Beolab play my morning playlist"
        let line = "2026-05-06 10:00:06 [INFO] [CommandParserRouter] parsing: \"\(transcription)\""
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.contains(transcription),
            "Transcription text must not appear in anonymised output; got: '\(result)'")
        XCTAssertTrue(result.contains("[TRANSCRIPTION]"),
            "Anonymised output must contain [TRANSCRIPTION] sentinel; got: '\(result)'")
    }

    func testContextLines_transcriptionMarkerPresent_suffixStripped() {
        let line = "12:00:00.000 [INFO] [CommandParserRouter] parsing: \"skip to the next track\""
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.contains("skip to the next track"),
            "Text after [CommandParserRouter] parsing: must be stripped; got: '\(result)'")
    }

    // MARK: - errorLine anonymisation (direct LogAnonymiser test)

    func testErrorLine_IPv4InErrorMessage_isRedacted() {
        let ipAddress = "10.20.30.40"
        let line = "12:00:00.000 [ERROR] Failed to connect to speaker at \(ipAddress): timeout"
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.contains(ipAddress),
            "IPv4 '\(ipAddress)' must not appear in anonymised errorLine; got: '\(result)'")
    }

    func testErrorLine_UUIDInErrorMessage_isRedacted() {
        let uuid = UUID().uuidString
        let line = "12:00:00.000 [ERROR] Speaker \(uuid) returned unexpected status 500"
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.lowercased().contains(uuid.lowercased()),
            "UUID '\(uuid)' must not appear in anonymised errorLine; got: '\(result)'")
    }

    func testErrorLine_JIDInErrorMessage_isRedacted() {
        let jid = "admin.jid.speaker-host.local"
        let line = "12:00:00.000 [ERROR] Authentication failed for \(jid)"
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.contains(jid),
            "JID '\(jid)' must not appear in anonymised errorLine; got: '\(result)'")
    }

    func testErrorLine_isNotEmpty_afterAnonymisation() {
        let line = "12:00:00.000 [ERROR] plain error with no PII"
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.isEmpty,
            "Anonymised errorLine must not be empty (redacted text retains structure)")
    }

    func testErrorLine_noOpWhenNoPII_returnsOriginal() {
        let line = "12:00:00.000 [ERROR] plain error message"
        let result = anonymiser.anonymise(line)
        XCTAssertEqual(result, line,
            "A line with no PII must pass through anonymisation unchanged")
    }

    // MARK: - Mixed PII in a single line

    func testContextLines_mixedPII_allRedacted() {
        let uuid = UUID().uuidString
        let ip = "192.168.10.5"
        let jid = "deviceX.jid.local.network"
        let line = "2026-05-06 10:00:10 [INFO] Device:\(uuid) Host:\(ip) JID:\(jid)"
        let result = anonymiser.anonymise(line)
        XCTAssertFalse(result.lowercased().contains(uuid.lowercased()),
            "UUID must not appear in anonymised output; got: '\(result)'")
        XCTAssertFalse(result.contains(ip),
            "IPv4 must not appear in anonymised output; got: '\(result)'")
        XCTAssertFalse(result.contains(jid),
            "JID must not appear in anonymised output; got: '\(result)'")
    }

    // MARK: - breadcrumbs are a String, NOT anonymised

    func testBreadcrumbs_currentPath_isStringNotArray() {
        BreadcrumbTracker.shared.push("Home")
        BreadcrumbTracker.shared.push("Settings")
        BreadcrumbTracker.shared.push("LearnedPhrases")

        // currentPath is a String, not [String].
        let path: String = BreadcrumbTracker.shared.currentPath
        XCTAssertEqual(path, "Home > Settings > LearnedPhrases",
            "currentPath must be a ' > '-joined String, not an array")
    }

    func testBreadcrumbs_screenNamesAreNotAnonymised() {
        // Screen names are navigation labels, not PII.
        // They pass through currentPath without any anonymisation.
        BreadcrumbTracker.shared.push("Home")
        BreadcrumbTracker.shared.push("Settings")

        let path = BreadcrumbTracker.shared.currentPath
        XCTAssertTrue(path.contains("Home"),
            "Screen name 'Home' must appear verbatim in currentPath — breadcrumbs are not anonymised")
        XCTAssertTrue(path.contains("Settings"),
            "Screen name 'Settings' must appear verbatim in currentPath — breadcrumbs are not anonymised")
    }

    func testBreadcrumbs_emptyStack_isEmptyString() {
        // BreadcrumbTracker.reset() called in setUp.
        let path = BreadcrumbTracker.shared.currentPath
        XCTAssertEqual(path, "",
            "currentPath must be empty string when stack is empty (not an empty array)")
    }

    // MARK: - Ring buffer snapshot produces context lines for the pipeline

    func testContextLines_ringBufferNonEmpty_snapshotIsNonEmpty() {
        let benignLine = "2026-05-06 10:01:00 [INFO] Speaker discovered: Beosound Balance"
        FileLogListener.shared.injectLine(benignLine)

        let snapshot = FileLogListener.shared.ringBufferSnapshot()
        XCTAssertFalse(snapshot.isEmpty,
            "ring buffer snapshot must be non-empty after injectLine is called")
    }

    func testContextLines_ringBufferEmpty_snapshotIsEmpty() {
        // FileLogListener.shared.resetRingBuffer() called in setUp.
        let snapshot = FileLogListener.shared.ringBufferSnapshot()
        XCTAssertTrue(snapshot.isEmpty,
            "ring buffer snapshot must be empty after resetRingBuffer()")
    }

    func testContextLines_injectedLines_areRetainedInOrder() {
        let lines = [
            "2026-05-06 10:00:00 [INFO] Line one",
            "2026-05-06 10:00:01 [INFO] Line two",
            "2026-05-06 10:00:02 [INFO] Line three"
        ]
        for line in lines {
            FileLogListener.shared.injectLine(line)
        }

        let snapshot = FileLogListener.shared.ringBufferSnapshot()
        XCTAssertEqual(snapshot.count, 3,
            "Three injected lines must appear in the snapshot")
        XCTAssertTrue(snapshot[0].contains("Line one"),   "First line must be first in snapshot")
        XCTAssertTrue(snapshot[1].contains("Line two"),   "Second line must be second in snapshot")
        XCTAssertTrue(snapshot[2].contains("Line three"), "Third line must be third in snapshot")
    }

    // MARK: - End-to-end smoke test: pipeline runs without crashing with PII-rich ring buffer

    func testPipeline_smokeTest_runsWithPIIInRingBuffer() async throws {
        // Seed ring buffer with lines containing all PII patterns.
        FileLogListener.shared.injectLine("2026-05-06 10:00:00 [INFO] IP=192.168.1.99")
        FileLogListener.shared.injectLine("2026-05-06 10:00:01 [INFO] ID=\(UUID().uuidString)")
        FileLogListener.shared.injectLine("2026-05-06 10:00:02 [INFO] JID=ctrl.jid.beo.local")
        FileLogListener.shared.injectLine("2026-05-06 10:00:03 [INFO] [CommandParserRouter] parsing: \"play jazz\"")

        let line = "12:00:00.000 [ERROR] smoke-test-\(UUID().uuidString)"
        IncidentReporter.shared.didLog(level: .error, line: line, timestamp: Date())

        try await Task.sleep(nanoseconds: 200_000_000)

        let keys = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("incident_reported_") }
        XCTAssertFalse(keys.isEmpty,
            "Pipeline must complete (dedup key written) even when ring buffer contains all PII patterns")
    }
}
