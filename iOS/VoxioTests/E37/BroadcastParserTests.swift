import XCTest
@testable import Voxio

// E-37 — Unit tests for broadcast Stage 1 regex patterns in TwoStageFallbackParser (T-3703).
//
// Verifies that all specified broadcast trigger phrases resolve to the correct
// CommandIntent without touching the NLModel (Stage 2).

final class BroadcastParserTests: XCTestCase {

    private let parser = TwoStageFallbackParser()

    // MARK: — stopAll

    func testStopAll_english_stopEverything() {
        assertBroadcast("stop everything", intent: .stopAll)
    }

    func testStopAll_english_stopAll() {
        assertBroadcast("stop all", intent: .stopAll)
    }

    func testStopAll_danish_stopAlt() {
        assertBroadcast("stop alt", intent: .stopAll)
    }

    func testStopAll_danish_stopAlting() {
        assertBroadcast("stop alting", intent: .stopAll)
    }

    // MARK: — pauseAll

    func testPauseAll_english_pauseAll() {
        assertBroadcast("pause all", intent: .pauseAll)
    }

    func testPauseAll_english_pauseEverything() {
        assertBroadcast("pause everything", intent: .pauseAll)
    }

    func testPauseAll_danish_pauseAlt() {
        assertBroadcast("pause alt", intent: .pauseAll)
    }

    // MARK: — resumeAll

    func testResumeAll_english_resumeAll() {
        assertBroadcast("resume all", intent: .resumeAll)
    }

    func testResumeAll_english_playEverything() {
        assertBroadcast("play everything", intent: .resumeAll)
    }

    func testResumeAll_danish_genoptagAlt() {
        assertBroadcast("genoptag alt", intent: .resumeAll)
    }

    func testResumeAll_danish_afspilAlt() {
        assertBroadcast("afspil alt", intent: .resumeAll)
    }

    // MARK: — volumeUpAll (default step)

    func testVolumeUpAll_english_volumeUpAll() {
        assertBroadcast("volume up all", intent: .volumeUpAll)
    }

    func testVolumeUpAll_english_louderEverywhere() {
        assertBroadcast("louder everywhere", intent: .volumeUpAll)
    }

    func testVolumeUpAll_danish_skruOpForAlt() {
        assertBroadcast("skru op for alt", intent: .volumeUpAll)
    }

    func testVolumeUpAll_defaultDelta_isNil() {
        let result = parser.parseStage1("volume up all", raw: "volume up all")
        XCTAssertEqual(result?.intent, .volumeUpAll)
        XCTAssertNil(result?.volumeDelta, "Default volumeUpAll should have nil delta (router fills in default)")
    }

    // MARK: — volumeUpAll with explicit amount

    func testVolumeUpAll_withAmount_english() {
        let result = parser.parseStage1("volume up all 20", raw: "volume up all 20")
        XCTAssertEqual(result?.intent, .volumeUpAll)
        XCTAssertEqual(result?.volumeDelta, 20)
    }

    // MARK: — volumeDownAll (default step)

    func testVolumeDownAll_english_volumeDownAll() {
        assertBroadcast("volume down all", intent: .volumeDownAll)
    }

    func testVolumeDownAll_english_quieterEverywhere() {
        assertBroadcast("quieter everywhere", intent: .volumeDownAll)
    }

    func testVolumeDownAll_danish_skruNedForAlt() {
        assertBroadcast("skru ned for alt", intent: .volumeDownAll)
    }

    func testVolumeDownAll_defaultDelta_isNil() {
        let result = parser.parseStage1("volume down all", raw: "volume down all")
        XCTAssertEqual(result?.intent, .volumeDownAll)
        XCTAssertNil(result?.volumeDelta, "Default volumeDownAll should have nil delta")
    }

    // MARK: — volumeDownAll with explicit amount

    func testVolumeDownAll_withAmount_english() {
        let result = parser.parseStage1("volume down all 15", raw: "volume down all 15")
        XCTAssertEqual(result?.intent, .volumeDownAll)
        XCTAssertEqual(result?.volumeDelta, 15)
    }

    // MARK: — muteAll

    func testMuteAll_english_muteAll() {
        assertBroadcast("mute all", intent: .muteAll)
    }

    func testMuteAll_english_muteEverything() {
        assertBroadcast("mute everything", intent: .muteAll)
    }

    func testMuteAll_danish_slaAltFra() {
        assertBroadcast("slå alt fra", intent: .muteAll)
    }

    // MARK: — unmuteAll (must match before mute)

    func testUnmuteAll_english_unmuteAll() {
        assertBroadcast("unmute all", intent: .unmuteAll)
    }

    func testUnmuteAll_english_unmuteEverything() {
        assertBroadcast("unmute everything", intent: .unmuteAll)
    }

    func testUnmuteAll_danish_slaAltTil() {
        assertBroadcast("slå alt til", intent: .unmuteAll)
    }

    func testUnmuteAll_doesNotMatchMuteAll() {
        // "unmute" must not fall through to muteAll
        let result = parser.parseStage1("unmute all", raw: "unmute all")
        XCTAssertEqual(result?.intent, .unmuteAll, "unmute all must not match muteAll")
    }

    // MARK: — Single-speaker commands must NOT match broadcast patterns

    func testSingleStop_doesNotMatchStopAll() {
        let result = parser.parseStage1("stop", raw: "stop")
        XCTAssertEqual(result?.intent, .stop, "bare 'stop' must match single-speaker .stop, not .stopAll")
    }

    func testSinglePause_doesNotMatchPauseAll() {
        let result = parser.parseStage1("pause", raw: "pause")
        XCTAssertEqual(result?.intent, .pause)
    }

    func testSingleVolumeUp_doesNotMatchVolumeUpAll() {
        let result = parser.parseStage1("volume up", raw: "volume up")
        XCTAssertEqual(result?.intent, .volumeUp)
    }

    func testSingleMute_doesNotMatchMuteAll() {
        let result = parser.parseStage1("mute", raw: "mute")
        XCTAssertEqual(result?.intent, .mute)
    }

    // MARK: — Helpers

    private func assertBroadcast(_ text: String, intent: CommandIntent, file: StaticString = #file, line: UInt = #line) {
        let result = parser.parseStage1(text, raw: text)
        XCTAssertEqual(result?.intent, intent, "'\(text)' should produce .\(intent)", file: file, line: line)
    }
}
