import XCTest
@testable import Voxio

// E-50 T-5001 — Unit tests for LogAnonymiser.
// Exercises all four rules, multi-match, no-match, and rule-ordering cases.

final class LogAnonymiserTests: XCTestCase {

    private let anon = LogAnonymiser()

    // MARK: - Rule 1: IPv4

    func testIPv4_singleAddress() {
        let result = anon.anonymise("Connecting to 192.168.1.42 on port 9339")
        XCTAssertEqual(result, "Connecting to [IP] on port 9339")
    }

    func testIPv4_twoAddresses() {
        let result = anon.anonymise("from 10.0.0.1 to 10.0.0.2")
        XCTAssertEqual(result, "from [IP] to [IP]")
    }

    func testIPv4_noAddress() {
        let line = "No addresses here at all"
        XCTAssertEqual(anon.anonymise(line), line)
    }

    func testIPv4_notReplaced_whenNoWordBoundary() {
        // A purely numeric token like a version number "1.2.3" has < 4 octets — not matched.
        let result = anon.anonymise("version 1.2.3 released")
        XCTAssertEqual(result, "version 1.2.3 released")
    }

    // MARK: - Rule 2: UUID

    func testUUID_uppercase() {
        let result = anon.anonymise("Device 550E8400-E29B-41D4-A716-446655440000 ready")
        XCTAssertEqual(result, "Device [UUID] ready")
    }

    func testUUID_lowercase() {
        let result = anon.anonymise("id=550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(result, "id=[UUID]")
    }

    func testUUID_mixed_case() {
        let result = anon.anonymise("Device 550e8400-E29B-41d4-A716-446655440000 ready")
        XCTAssertEqual(result, "Device [UUID] ready")
    }

    func testUUID_noUUID() {
        let line = "nothing uuid-shaped here"
        XCTAssertEqual(anon.anonymise(line), line)
    }

    // MARK: - Rule 3: JID

    func testJID_basic() {
        let result = anon.anonymise("Resolved abc123.jid.company.com")
        XCTAssertEqual(result, "Resolved [JID]")
    }

    func testJID_withSubdomains() {
        let result = anon.anonymise("endpoint: user42.jid.b-o.internal.net connected")
        XCTAssertEqual(result, "endpoint: [JID] connected")
    }

    func testJID_noJID() {
        let line = "just a regular hostname b-o.company.com"
        XCTAssertEqual(anon.anonymise(line), line)
    }

    // MARK: - Rule 4: Transcription

    func testTranscription_stripsPayload() {
        let input = "[CommandParserRouter] parsing: \"play kind of blue\""
        let result = anon.anonymise(input)
        XCTAssertTrue(result.hasSuffix("[CommandParserRouter] parsing: [TRANSCRIPTION]"))
        XCTAssertFalse(result.contains("play kind of blue"),
                       "Transcription content must be removed")
    }

    func testTranscription_preservesPrefix() {
        let prefix = "2024-01-01 12:00:00.000 [INFO] "
        let input = prefix + "[CommandParserRouter] parsing: some words"
        let result = anon.anonymise(input)
        XCTAssertTrue(result.contains(prefix))
        XCTAssertTrue(result.hasSuffix("[CommandParserRouter] parsing: [TRANSCRIPTION]"))
        XCTAssertFalse(result.contains("some words"))
    }

    func testTranscription_noMarker_unchanged() {
        let line = "[CommandParserRouter] dispatching"
        XCTAssertEqual(anon.anonymise(line), line)
    }

    // MARK: - Multi-match

    func testMultipleRules_IPAndUUID() {
        let input = "ip=192.168.0.1 id=550e8400-e29b-41d4-a716-446655440000"
        let result = anon.anonymise(input)
        XCTAssertFalse(result.contains("192.168.0.1"))
        XCTAssertFalse(result.contains("550e8400"))
        XCTAssertTrue(result.contains("[IP]"))
        XCTAssertTrue(result.contains("[UUID]"))
    }

    // MARK: - No-match

    func testNoMatch_lineReturnedUnchanged() {
        let line = "Everything is fine [INFO] speaker connected"
        XCTAssertEqual(anon.anonymise(line), line)
    }

    // MARK: - Rule ordering: UUID inside transcription payload is stripped by transcription rule

    func testRuleOrdering_UUIDInsideTranscription_removedByTranscriptionRule() {
        let input = "[CommandParserRouter] parsing: 550e8400-e29b-41d4-a716-446655440000"
        let result = anon.anonymise(input)
        // UUID rule runs first, so the UUID becomes [UUID]; transcription rule then strips the payload.
        XCTAssertTrue(result.hasSuffix("[CommandParserRouter] parsing: [TRANSCRIPTION]"),
                      "Transcription rule must remove payload even after UUID substitution; got: \(result)")
        XCTAssertFalse(result.contains("550e8400"))
    }

    // MARK: - Repeated calls (idempotency of compiled regexes)

    func testRepeatedCalls_doNotAllocateNewRegexes() {
        // Just verify 1000 calls don't crash or produce different results.
        let input = "connect to 10.0.0.1 device 550e8400-e29b-41d4-a716-446655440000"
        let expected = anon.anonymise(input)
        for _ in 0..<1000 {
            XCTAssertEqual(anon.anonymise(input), expected)
        }
    }
}
