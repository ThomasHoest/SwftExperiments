import XCTest
@testable import Voxio

// T-2415 / T-2416 — Tests for CommandParserRouter's new VoiceCommand API
// and toVoiceCommand(_:) mapping.
final class CommandParserRouterTests: XCTestCase {

    private var router: CommandParserRouter!

    override func setUp() {
        super.setUp()
        router = CommandParserRouter()
    }

    // MARK: - toVoiceCommand mapping

    func testToVoiceCommand_playFavoriteByNumber() {
        let parsed = ParsedCommand(intent: .playFavoriteByNumber, favoriteIndex: 2)
        let result = router.toVoiceCommand(parsed)
        XCTAssertEqual(result, .playFavorite(index: 2))
    }

    func testToVoiceCommand_playFavoriteByNumber_nilIndex_defaultsToOne() {
        let parsed = ParsedCommand(intent: .playFavoriteByNumber, favoriteIndex: nil)
        let result = router.toVoiceCommand(parsed)
        XCTAssertEqual(result, .playFavorite(index: 1))
    }

    func testToVoiceCommand_playNamed_resolvesToPlayDefault() {
        // playNamed has no VoiceCommand equivalent; must resolve to playDefault
        let parsed = ParsedCommand(intent: .playNamed, favoriteName: "Jazz Radio")
        let result = router.toVoiceCommand(parsed)
        XCTAssertEqual(result, .playDefault)
    }

    func testToVoiceCommand_playDefault() {
        let parsed = ParsedCommand(intent: .playDefault)
        XCTAssertEqual(router.toVoiceCommand(parsed), .playDefault)
    }

    func testToVoiceCommand_listFavorites() {
        let parsed = ParsedCommand(intent: .listFavorites)
        XCTAssertEqual(router.toVoiceCommand(parsed), .listFavorites)
    }

    func testToVoiceCommand_stop() {
        XCTAssertEqual(router.toVoiceCommand(ParsedCommand(intent: .stop)), .stop)
    }

    func testToVoiceCommand_pause() {
        XCTAssertEqual(router.toVoiceCommand(ParsedCommand(intent: .pause)), .pause)
    }

    func testToVoiceCommand_resume() {
        XCTAssertEqual(router.toVoiceCommand(ParsedCommand(intent: .resume)), .resume)
    }

    func testToVoiceCommand_setVolume_withValue() {
        let parsed = ParsedCommand(intent: .setVolume, volumeValue: 70)
        XCTAssertEqual(router.toVoiceCommand(parsed), .setVolume(70))
    }

    func testToVoiceCommand_setVolume_nilValue_defaultsFifty() {
        let parsed = ParsedCommand(intent: .setVolume, volumeValue: nil)
        XCTAssertEqual(router.toVoiceCommand(parsed), .setVolume(50))
    }

    func testToVoiceCommand_volumeUp_withDelta() {
        let parsed = ParsedCommand(intent: .volumeUp, volumeDelta: 20)
        XCTAssertEqual(router.toVoiceCommand(parsed), .adjustVolume(+20))
    }

    func testToVoiceCommand_volumeUp_nilDelta_defaultsTen() {
        let parsed = ParsedCommand(intent: .volumeUp, volumeDelta: nil)
        XCTAssertEqual(router.toVoiceCommand(parsed), .adjustVolume(+10))
    }

    func testToVoiceCommand_volumeDown_withDelta() {
        let parsed = ParsedCommand(intent: .volumeDown, volumeDelta: 15)
        XCTAssertEqual(router.toVoiceCommand(parsed), .adjustVolume(-15))
    }

    func testToVoiceCommand_volumeDown_nilDelta_defaultsMinusTen() {
        let parsed = ParsedCommand(intent: .volumeDown, volumeDelta: nil)
        XCTAssertEqual(router.toVoiceCommand(parsed), .adjustVolume(-10))
    }

    func testToVoiceCommand_mute() {
        XCTAssertEqual(router.toVoiceCommand(ParsedCommand(intent: .mute)), .mute)
    }

    func testToVoiceCommand_unmute() {
        XCTAssertEqual(router.toVoiceCommand(ParsedCommand(intent: .unmute)), .unmute)
    }

    func testToVoiceCommand_confirm() {
        XCTAssertEqual(router.toVoiceCommand(ParsedCommand(intent: .confirm)), .confirm)
    }

    func testToVoiceCommand_cancel() {
        XCTAssertEqual(router.toVoiceCommand(ParsedCommand(intent: .cancel)), .cancel)
    }

    func testToVoiceCommand_unknown_withRawText() {
        let parsed = ParsedCommand(intent: .unknown, rawText: "blah blah")
        XCTAssertEqual(router.toVoiceCommand(parsed), .unknown("blah blah"))
    }

    func testToVoiceCommand_unknown_nilRawText_defaultsEmpty() {
        let parsed = ParsedCommand(intent: .unknown, rawText: nil)
        XCTAssertEqual(router.toVoiceCommand(parsed), .unknown(""))
    }

    // MARK: - parse(_ transcript:) public API

    func testParse_stop_returnsStop() async {
        let result = await router.parse("stop")
        XCTAssertEqual(result, .stop)
    }

    func testParse_pause_returnsPause() async {
        let result = await router.parse("pause")
        XCTAssertEqual(result, .pause)
    }

    func testParse_resume_returnsResume() async {
        let result = await router.parse("resume")
        XCTAssertEqual(result, .resume)
    }

    func testParse_mute_returnsMute() async {
        let result = await router.parse("mute")
        XCTAssertEqual(result, .mute)
    }

    func testParse_unmute_returnsUnmute() async {
        let result = await router.parse("unmute")
        XCTAssertEqual(result, .unmute)
    }

    func testParse_volumeUp_returnsAdjustVolumePositive() async {
        let result = await router.parse("volume up")
        XCTAssertEqual(result, .adjustVolume(+10))
    }

    func testParse_volumeDown_returnsAdjustVolumeNegative() async {
        let result = await router.parse("volume down")
        XCTAssertEqual(result, .adjustVolume(-10))
    }

    func testParse_setVolumeAbsolute_returnsSetVolume() async {
        let result = await router.parse("set volume to 75")
        XCTAssertEqual(result, .setVolume(75))
    }

    func testParse_playFavoriteOne_returnsPlayFavoriteIndex1() async {
        let result = await router.parse("play favorite one")
        XCTAssertEqual(result, .playFavorite(index: 1))
    }

    func testParse_playFavoriteTwo_returnsPlayFavoriteIndex2() async {
        let result = await router.parse("play favorite two")
        XCTAssertEqual(result, .playFavorite(index: 2))
    }

    func testParse_playDefault_returnsPlayDefault() async {
        let result = await router.parse("play")
        XCTAssertEqual(result, .playDefault)
    }

    func testParse_confirm_returnsConfirm() async {
        let result = await router.parse("yes")
        XCTAssertEqual(result, .confirm)
    }

    func testParse_cancel_returnsCancel() async {
        let result = await router.parse("no")
        XCTAssertEqual(result, .cancel)
    }

    func testParse_garbage_returnsUnknown() async {
        let result = await router.parse("xyzzy frobble wibble")
        if case .unknown = result {
            // expected
        } else {
            XCTFail("Expected .unknown, got \(result)")
        }
    }

    func testParse_emptyString_returnsUnknown() async {
        let result = await router.parse("")
        if case .unknown = result {
            // expected
        } else {
            XCTFail("Expected .unknown for empty input, got \(result)")
        }
    }

    func testParse_danishStop_returnsStop() async {
        // "stop" is shared between EN and DA; the regex matches it
        let result = await router.parse("stop musik")
        XCTAssertEqual(result, .stop)
    }

    func testParse_listFavorites_returnsListFavorites() async {
        let result = await router.parse("list favorites")
        XCTAssertEqual(result, .listFavorites)
    }
}
