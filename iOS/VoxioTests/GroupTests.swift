import XCTest
@testable import Voxio

@MainActor
final class GroupTests: XCTestCase {

    private func makeTestSpeaker(host: String, jid: String? = nil) -> Speaker {
        let client = MockSpeakerClient()
        let events = MockSpeakerEventSource()
        let speaker = Speaker(host: host, client: client, eventSource: events, platform: .mozart)
        // Manually set identifier (bypass initialize() for unit tests)
        speaker.identifier = SpeakerIdentifier(host: host, jid: jid, platform: .mozart)
        return speaker
    }

    func testGroup_single_hasOneMember() {
        let speaker = makeTestSpeaker(host: "192.168.1.1")
        let group = SpeakerGroup.single(speaker)
        XCTAssertEqual(group.members.count, 1)
        XCTAssertEqual(group.hostSpeaker.host, speaker.host)
    }

    func testGroupId_stableForSameMembers() {
        let a = makeTestSpeaker(host: "192.168.1.1", jid: "jid-a")
        let b = makeTestSpeaker(host: "192.168.1.2", jid: "jid-b")
        let id1 = SpeakerGroup.makeId(for: [a, b])
        let id2 = SpeakerGroup.makeId(for: [b, a])
        XCTAssertEqual(id1, id2)
    }

    func testGroupId_differsForDifferentMembers() {
        let a = makeTestSpeaker(host: "192.168.1.1", jid: "jid-a")
        let b = makeTestSpeaker(host: "192.168.1.2", jid: "jid-b")
        let c = makeTestSpeaker(host: "192.168.1.3", jid: "jid-c")
        XCTAssertNotEqual(SpeakerGroup.makeId(for: [a, b]), SpeakerGroup.makeId(for: [a, c]))
    }
}
