import XCTest
@testable import Voxio

// MARK: - SpeakerIdentifierTransferableTests (E-59 T-5901)
//
// Verifies:
//   1. SpeakerIdentifier round-trips through JSONEncoder/JSONDecoder with all fields intact.
//   2. .id returns jid when present; host as fallback.
//   3. Two identifiers with same JID have same .id regardless of host.
//   4. .id is always non-empty.

final class SpeakerIdentifierTransferableTests: XCTestCase {

    // MARK: - Round-trip encoding

    func test_roundTrip_mozartWithJid_survivesEncoding() throws {
        let original = SpeakerIdentifier(host: "192.168.1.10", jid: "jid@mozart.local", platform: .mozart)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpeakerIdentifier.self, from: data)

        XCTAssertEqual(decoded.host, original.host)
        XCTAssertEqual(decoded.jid, original.jid)
        XCTAssertEqual(decoded.platform, original.platform)
    }

    func test_roundTrip_aseWithoutJid_survivesEncoding() throws {
        let original = SpeakerIdentifier(host: "10.0.0.5", jid: nil, platform: .bnr)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpeakerIdentifier.self, from: data)

        XCTAssertEqual(decoded.host, original.host)
        XCTAssertNil(decoded.jid)
        XCTAssertEqual(decoded.platform, original.platform)
    }

    func test_roundTrip_preservesEquality() throws {
        let original = SpeakerIdentifier(host: "192.168.1.10", jid: "jid@mozart.local", platform: .mozart)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpeakerIdentifier.self, from: data)

        // Hashable/Equatable — same values must be equal
        XCTAssertEqual(decoded, original)
    }

    // MARK: - .id computed property (CF-1)

    func test_id_returnsJidWhenPresent() {
        let identifier = SpeakerIdentifier(host: "192.168.1.10", jid: "speaker-jid@beo.dk", platform: .mozart)
        XCTAssertEqual(identifier.id, "speaker-jid@beo.dk")
    }

    func test_id_returnsHostWhenJidIsNil() {
        let identifier = SpeakerIdentifier(host: "192.168.1.10", jid: nil, platform: .bnr)
        XCTAssertEqual(identifier.id, "192.168.1.10")
    }

    func test_id_isNonEmpty_withJid() {
        let identifier = SpeakerIdentifier(host: "192.168.1.1", jid: "jid@beo", platform: .mozart)
        XCTAssertFalse(identifier.id.isEmpty)
    }

    func test_id_isNonEmpty_withoutJid() {
        let identifier = SpeakerIdentifier(host: "10.0.0.1", jid: nil, platform: .bnr)
        XCTAssertFalse(identifier.id.isEmpty)
    }

    func test_id_sameForSameJidDifferentHost() {
        let a = SpeakerIdentifier(host: "192.168.1.10", jid: "shared-jid@beo", platform: .mozart)
        let b = SpeakerIdentifier(host: "10.0.0.5",    jid: "shared-jid@beo", platform: .mozart)
        XCTAssertEqual(a.id, b.id)
    }

    func test_id_differsForDifferentJids() {
        let a = SpeakerIdentifier(host: "192.168.1.10", jid: "jid-a@beo", platform: .mozart)
        let b = SpeakerIdentifier(host: "192.168.1.10", jid: "jid-b@beo", platform: .mozart)
        XCTAssertNotEqual(a.id, b.id)
    }
}
