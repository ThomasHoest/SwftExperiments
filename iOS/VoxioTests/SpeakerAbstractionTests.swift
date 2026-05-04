import XCTest
@testable import Voxio

@MainActor
final class SpeakerAbstractionTests: XCTestCase {

    func testSpeakerInit_populatesNameFromClient() async throws {
        let client = MockSpeakerClient()
        client.nameToReturn = "Living Room"
        let events = MockSpeakerEventSource()
        let speaker = Speaker(host: "192.168.1.1", client: client, eventSource: events, platform: .mozart)
        try await speaker.initialize()
        XCTAssertEqual(speaker.name, "Living Room")
    }

    func testSpeakerInit_populatesVolumeFromClient() async throws {
        let client = MockSpeakerClient()
        client.volumeToReturn = 42
        let events = MockSpeakerEventSource()
        let speaker = Speaker(host: "192.168.1.1", client: client, eventSource: events, platform: .mozart)
        try await speaker.initialize()
        XCTAssertEqual(speaker.volume, 42)
    }

    func testSpeakerPlay_delegatesToClient() async throws {
        let client = MockSpeakerClient()
        let events = MockSpeakerEventSource()
        let speaker = Speaker(host: "192.168.1.1", client: client, eventSource: events, platform: .mozart)
        try await speaker.initialize()
        try await speaker.play()
        XCTAssertEqual(client.playCallCount, 1)
    }

    func testSpeakerEvents_setsPlaybackStateFromStream() async throws {
        let client = MockSpeakerClient()
        let events = MockSpeakerEventSource()
        events.eventsToYield = [.playbackState(.playing)]
        let speaker = Speaker(host: "192.168.1.1", client: client, eventSource: events, platform: .mozart)
        try await speaker.initialize()
        // Give the event loop a moment to process
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(speaker.isPlaying)
    }

    func testSpeakerDispose_gracefulWithEmptyStream() async throws {
        let client = MockSpeakerClient()
        let events = MockSpeakerEventSource()
        let speaker = Speaker(host: "192.168.1.1", client: client, eventSource: events, platform: .mozart)
        try await speaker.initialize()
        speaker.dispose()  // should not crash
    }
}
