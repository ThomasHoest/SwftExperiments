import XCTest
@testable import Voxio

@MainActor
final class IntentsTests: XCTestCase {

    override func setUp() async throws {
        SpeakerStore.shared.activeSpeaker = nil
        SpeakerStore.shared.allSpeakers = []
    }

    // MARK: - PlaybackToggleIntent

    func testPlaybackToggle_pausesWhenPlaying() async throws {
        let (speaker, client) = makeSpeaker(playing: true)
        SpeakerStore.shared.activeSpeaker = speaker
        _ = try await PlaybackToggleIntent().perform()
        XCTAssertEqual(client.pauseCallCount, 1)
    }

    func testPlaybackToggle_playsWhenPaused() async throws {
        let (speaker, client) = makeSpeaker(playing: false)
        SpeakerStore.shared.activeSpeaker = speaker
        _ = try await PlaybackToggleIntent().perform()
        XCTAssertEqual(client.playCallCount, 1)
    }

    func testPlaybackToggle_noPlayOrPauseWhenPlaying() async throws {
        let (speaker, client) = makeSpeaker(playing: true)
        SpeakerStore.shared.activeSpeaker = speaker
        _ = try await PlaybackToggleIntent().perform()
        XCTAssertEqual(client.playCallCount, 0)
    }

    func testPlaybackToggle_noPauseWhenPaused() async throws {
        let (speaker, client) = makeSpeaker(playing: false)
        SpeakerStore.shared.activeSpeaker = speaker
        _ = try await PlaybackToggleIntent().perform()
        XCTAssertEqual(client.pauseCallCount, 0)
    }

    func testPlaybackToggle_returnsResultWhenNoActiveSpeaker() async throws {
        SpeakerStore.shared.activeSpeaker = nil
        let result = try await PlaybackToggleIntent().perform()
        // No speaker to call — result must not be nil and no crash occurs
        XCTAssertNotNil(result)
    }

    func testPlaybackToggle_returnsResultOnClientError() async throws {
        let (speaker, client) = makeSpeaker(playing: true)
        client.shouldThrow = .unreachable
        SpeakerStore.shared.activeSpeaker = speaker
        let result = try await PlaybackToggleIntent().perform()
        XCTAssertNotNil(result)
    }

    // MARK: - AdjustVolumeIntent

    func testAdjustVolume_normalDelta() async throws {
        let (speaker, client) = makeSpeaker(volume: 50)
        SpeakerStore.shared.activeSpeaker = speaker
        var intent = AdjustVolumeIntent()
        intent.delta = 10
        _ = try await intent.perform()
        XCTAssertEqual(client.setVolumeLastCall, 60)
    }

    func testAdjustVolume_negativeDelta() async throws {
        let (speaker, client) = makeSpeaker(volume: 50)
        SpeakerStore.shared.activeSpeaker = speaker
        var intent = AdjustVolumeIntent()
        intent.delta = -15
        _ = try await intent.perform()
        XCTAssertEqual(client.setVolumeLastCall, 35)
    }

    func testAdjustVolume_clampsAbove100() async throws {
        let (speaker, client) = makeSpeaker(volume: 95)
        SpeakerStore.shared.activeSpeaker = speaker
        var intent = AdjustVolumeIntent()
        intent.delta = 10
        _ = try await intent.perform()
        XCTAssertEqual(client.setVolumeLastCall, 100)
    }

    func testAdjustVolume_clampsBelow0() async throws {
        let (speaker, client) = makeSpeaker(volume: 3)
        SpeakerStore.shared.activeSpeaker = speaker
        var intent = AdjustVolumeIntent()
        intent.delta = -10
        _ = try await intent.perform()
        XCTAssertEqual(client.setVolumeLastCall, 0)
    }

    func testAdjustVolume_exactlyAt100() async throws {
        let (speaker, client) = makeSpeaker(volume: 100)
        SpeakerStore.shared.activeSpeaker = speaker
        var intent = AdjustVolumeIntent()
        intent.delta = 0
        _ = try await intent.perform()
        XCTAssertEqual(client.setVolumeLastCall, 100)
    }

    func testAdjustVolume_exactlyAt0() async throws {
        let (speaker, client) = makeSpeaker(volume: 0)
        SpeakerStore.shared.activeSpeaker = speaker
        var intent = AdjustVolumeIntent()
        intent.delta = 0
        _ = try await intent.perform()
        XCTAssertEqual(client.setVolumeLastCall, 0)
    }

    func testAdjustVolume_returnsResultWhenNoActiveSpeaker() async throws {
        SpeakerStore.shared.activeSpeaker = nil
        var intent = AdjustVolumeIntent()
        intent.delta = 10
        let result = try await intent.perform()
        XCTAssertNotNil(result)
    }

    func testAdjustVolume_returnsResultOnClientError() async throws {
        let (speaker, client) = makeSpeaker(volume: 50)
        client.shouldThrow = .unreachable
        SpeakerStore.shared.activeSpeaker = speaker
        var intent = AdjustVolumeIntent()
        intent.delta = 5
        let result = try await intent.perform()
        XCTAssertNotNil(result)
    }

    // MARK: - MuteIntent

    func testMute_togglesOnWhenUnmuted() async throws {
        let (speaker, client) = makeSpeaker(muted: false)
        SpeakerStore.shared.activeSpeaker = speaker
        _ = try await MuteIntent().perform()
        XCTAssertEqual(client.muteLastCall, true)
    }

    func testMute_togglesOffWhenMuted() async throws {
        let (speaker, client) = makeSpeaker(muted: true)
        SpeakerStore.shared.activeSpeaker = speaker
        _ = try await MuteIntent().perform()
        XCTAssertEqual(client.muteLastCall, false)
    }

    func testMute_returnsResultWhenNoActiveSpeaker() async throws {
        SpeakerStore.shared.activeSpeaker = nil
        let result = try await MuteIntent().perform()
        XCTAssertNotNil(result)
    }

    func testMute_returnsResultOnClientError() async throws {
        let (speaker, client) = makeSpeaker(muted: false)
        client.shouldThrow = .unreachable
        SpeakerStore.shared.activeSpeaker = speaker
        let result = try await MuteIntent().perform()
        XCTAssertNotNil(result)
    }

    // MARK: - JoinSpeakerIntent

    func testJoin_mozartTargetCallsJoinOnTarget() async throws {
        let (sourceSpeaker, _) = makeSpeaker(platform: .mozart, host: "192.168.1.1")
        let (targetSpeaker, targetClient) = makeSpeaker(platform: .mozart, host: "192.168.1.2")
        SpeakerStore.shared.allSpeakers = [sourceSpeaker, targetSpeaker]
        var intent = JoinSpeakerIntent()
        intent.source = SpeakerEntity(id: sourceSpeaker.host, name: sourceSpeaker.name)
        intent.target = SpeakerEntity(id: targetSpeaker.host, name: targetSpeaker.name)
        _ = try await intent.perform()
        XCTAssertEqual(targetClient.joinCallCount, 1)
    }

    func testJoin_mozartTargetDoesNotCallJoinOnSource() async throws {
        let (sourceSpeaker, sourceClient) = makeSpeaker(platform: .mozart, host: "192.168.1.1")
        let (targetSpeaker, _) = makeSpeaker(platform: .mozart, host: "192.168.1.2")
        SpeakerStore.shared.allSpeakers = [sourceSpeaker, targetSpeaker]
        var intent = JoinSpeakerIntent()
        intent.source = SpeakerEntity(id: sourceSpeaker.host, name: sourceSpeaker.name)
        intent.target = SpeakerEntity(id: targetSpeaker.host, name: targetSpeaker.name)
        _ = try await intent.perform()
        XCTAssertEqual(sourceClient.joinCallCount, 0)
    }

    func testJoin_bnrTargetCallsJoinOnSource() async throws {
        let (sourceSpeaker, sourceClient) = makeSpeaker(platform: .mozart, host: "192.168.1.1")
        let (targetSpeaker, _) = makeSpeaker(platform: .bnr, host: "192.168.1.2")
        SpeakerStore.shared.allSpeakers = [sourceSpeaker, targetSpeaker]
        var intent = JoinSpeakerIntent()
        intent.source = SpeakerEntity(id: sourceSpeaker.host, name: sourceSpeaker.name)
        intent.target = SpeakerEntity(id: targetSpeaker.host, name: targetSpeaker.name)
        _ = try await intent.perform()
        XCTAssertEqual(sourceClient.joinCallCount, 1)
    }

    func testJoin_bnrTargetDoesNotCallJoinOnTarget() async throws {
        let (sourceSpeaker, _) = makeSpeaker(platform: .mozart, host: "192.168.1.1")
        let (targetSpeaker, targetClient) = makeSpeaker(platform: .bnr, host: "192.168.1.2")
        SpeakerStore.shared.allSpeakers = [sourceSpeaker, targetSpeaker]
        var intent = JoinSpeakerIntent()
        intent.source = SpeakerEntity(id: sourceSpeaker.host, name: sourceSpeaker.name)
        intent.target = SpeakerEntity(id: targetSpeaker.host, name: targetSpeaker.name)
        _ = try await intent.perform()
        XCTAssertEqual(targetClient.joinCallCount, 0)
    }

    func testJoin_unknownSourceReturnsDialog() async throws {
        let (targetSpeaker, _) = makeSpeaker(platform: .mozart, host: "192.168.1.2")
        SpeakerStore.shared.allSpeakers = [targetSpeaker]
        var intent = JoinSpeakerIntent()
        intent.source = SpeakerEntity(id: "10.0.0.99", name: "Ghost")
        intent.target = SpeakerEntity(id: targetSpeaker.host, name: targetSpeaker.name)
        let result = try await intent.perform()
        XCTAssertNotNil(result)
    }

    func testJoin_unknownTargetReturnsDialog() async throws {
        let (sourceSpeaker, _) = makeSpeaker(platform: .mozart, host: "192.168.1.1")
        SpeakerStore.shared.allSpeakers = [sourceSpeaker]
        var intent = JoinSpeakerIntent()
        intent.source = SpeakerEntity(id: sourceSpeaker.host, name: sourceSpeaker.name)
        intent.target = SpeakerEntity(id: "10.0.0.99", name: "Ghost")
        let result = try await intent.perform()
        XCTAssertNotNil(result)
    }

    // MARK: - LeaveSpeakerIntent

    func testLeave_callsLeaveOnSpeaker() async throws {
        let (speaker, client) = makeSpeaker(platform: .mozart, host: "192.168.1.1")
        SpeakerStore.shared.allSpeakers = [speaker]
        var intent = LeaveSpeakerIntent()
        intent.speaker = SpeakerEntity(id: speaker.host, name: speaker.name)
        _ = try await intent.perform()
        XCTAssertEqual(client.leaveCallCount, 1)
    }

    func testLeave_unknownSpeakerReturnsDialog() async throws {
        SpeakerStore.shared.allSpeakers = []
        var intent = LeaveSpeakerIntent()
        intent.speaker = SpeakerEntity(id: "10.0.0.99", name: "Ghost")
        let result = try await intent.perform()
        XCTAssertNotNil(result)
    }

    func testLeave_returnsResultOnClientError() async throws {
        let (speaker, client) = makeSpeaker(platform: .mozart, host: "192.168.1.1")
        client.shouldThrow = .unreachable
        SpeakerStore.shared.allSpeakers = [speaker]
        var intent = LeaveSpeakerIntent()
        intent.speaker = SpeakerEntity(id: speaker.host, name: speaker.name)
        let result = try await intent.perform()
        XCTAssertNotNil(result)
    }

    // MARK: - IntentStrings — appNotRunning

    func testIntentStrings_appNotRunning_english_containsOpenVoxio() {
        let s = IntentStrings.appNotRunning(.english)
        XCTAssertTrue(s.contains("open Voxio first"), "Expected 'open Voxio first' in '\(s)'")
    }

    func testIntentStrings_appNotRunning_danish_containsAabnVoxio() {
        let s = IntentStrings.appNotRunning(.danish)
        XCTAssertTrue(s.contains("Åbn Voxio"), "Expected 'Åbn Voxio' in '\(s)'")
    }

    func testIntentStrings_appNotRunning_englishAndDanishDiffer() {
        XCTAssertNotEqual(
            IntentStrings.appNotRunning(.english),
            IntentStrings.appNotRunning(.danish)
        )
    }

    // MARK: - IntentStrings — speakerUnreachable

    func testIntentStrings_speakerUnreachable_interpolatesName_english() {
        let s = IntentStrings.speakerUnreachable("Living Room", .english)
        XCTAssertTrue(s.contains("Living Room"), "Expected speaker name in '\(s)'")
    }

    func testIntentStrings_speakerUnreachable_interpolatesName_danish() {
        let s = IntentStrings.speakerUnreachable("Stue", .danish)
        XCTAssertTrue(s.contains("Stue"), "Expected speaker name in '\(s)'")
    }

    func testIntentStrings_speakerUnreachable_englishAndDanishDiffer() {
        XCTAssertNotEqual(
            IntentStrings.speakerUnreachable("X", .english),
            IntentStrings.speakerUnreachable("X", .danish)
        )
    }

    // MARK: - IntentStrings — speakerNotFound

    func testIntentStrings_speakerNotFound_interpolatesName_english() {
        let s = IntentStrings.speakerNotFound("Balance", .english)
        XCTAssertTrue(s.contains("Balance"), "Expected speaker name in '\(s)'")
    }

    func testIntentStrings_speakerNotFound_interpolatesName_danish() {
        let s = IntentStrings.speakerNotFound("Balance", .danish)
        XCTAssertTrue(s.contains("Balance"), "Expected speaker name in '\(s)'")
    }

    // MARK: - IntentStrings — joined

    func testIntentStrings_joined_interpolatesBothNames_english() {
        let s = IntentStrings.joined("A5", "Balance", .english)
        XCTAssertTrue(s.contains("A5") && s.contains("Balance"),
                      "Expected both names in '\(s)'")
    }

    func testIntentStrings_joined_interpolatesBothNames_danish() {
        let s = IntentStrings.joined("A5", "Balance", .danish)
        XCTAssertTrue(s.contains("A5") && s.contains("Balance"),
                      "Expected both names in '\(s)'")
    }

    func testIntentStrings_joined_englishAndDanishDiffer() {
        XCTAssertNotEqual(
            IntentStrings.joined("A", "B", .english),
            IntentStrings.joined("A", "B", .danish)
        )
    }

    // MARK: - IntentStrings — left

    func testIntentStrings_left_interpolatesName_english() {
        let s = IntentStrings.left("Beosound", .english)
        XCTAssertTrue(s.contains("Beosound"), "Expected speaker name in '\(s)'")
    }

    func testIntentStrings_left_interpolatesName_danish() {
        let s = IntentStrings.left("Beosound", .danish)
        XCTAssertTrue(s.contains("Beosound"), "Expected speaker name in '\(s)'")
    }

    func testIntentStrings_left_englishAndDanishDiffer() {
        XCTAssertNotEqual(
            IntentStrings.left("X", .english),
            IntentStrings.left("X", .danish)
        )
    }

    // MARK: - Helpers

    private func makeSpeaker(
        playing: Bool = false,
        volume: Int = 50,
        muted: Bool = false,
        platform: SpeakerPlatform = .mozart,
        host: String = "192.168.1.99"
    ) -> (Speaker, MockSpeakerClient) {
        let client = MockSpeakerClient()
        client.volumeToReturn = volume
        let events = MockSpeakerEventSource()
        let speaker = Speaker(host: host, client: client, eventSource: events, platform: platform)
        speaker.volume = volume
        speaker.isMuted = muted
        if playing { speaker.state = .playing }
        return (speaker, client)
    }
}
