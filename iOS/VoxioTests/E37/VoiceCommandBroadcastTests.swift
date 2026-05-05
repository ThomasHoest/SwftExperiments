import XCTest
@testable import Voxio

// E-37 — Unit tests for new broadcast VoiceCommand cases and helpers (T-3701).
//
// Verifies:
//   • All six broadcast VoiceCommand cases exist and are Equatable
//   • CustomStringConvertible produces the expected strings
//   • toCommandIntent() maps correctly for broadcast cases

final class VoiceCommandBroadcastTests: XCTestCase {

    // MARK: — Equatable

    func testStopAll_isEquatable() {
        XCTAssertEqual(VoiceCommand.stopAll, VoiceCommand.stopAll)
    }

    func testPauseAll_isEquatable() {
        XCTAssertEqual(VoiceCommand.pauseAll, VoiceCommand.pauseAll)
    }

    func testResumeAll_isEquatable() {
        XCTAssertEqual(VoiceCommand.resumeAll, VoiceCommand.resumeAll)
    }

    func testAdjustVolumeAll_isEquatable() {
        XCTAssertEqual(VoiceCommand.adjustVolumeAll(10), VoiceCommand.adjustVolumeAll(10))
        XCTAssertNotEqual(VoiceCommand.adjustVolumeAll(10), VoiceCommand.adjustVolumeAll(-10))
    }

    func testMuteAll_isEquatable() {
        XCTAssertEqual(VoiceCommand.muteAll, VoiceCommand.muteAll)
    }

    func testUnmuteAll_isEquatable() {
        XCTAssertEqual(VoiceCommand.unmuteAll, VoiceCommand.unmuteAll)
    }

    // MARK: — CustomStringConvertible

    func testStopAll_description() {
        XCTAssertEqual(VoiceCommand.stopAll.description, "stopAll")
    }

    func testPauseAll_description() {
        XCTAssertEqual(VoiceCommand.pauseAll.description, "pauseAll")
    }

    func testResumeAll_description() {
        XCTAssertEqual(VoiceCommand.resumeAll.description, "resumeAll")
    }

    func testAdjustVolumeAll_positive_description() {
        XCTAssertEqual(VoiceCommand.adjustVolumeAll(10).description, "adjustVolumeAll(+10)")
    }

    func testAdjustVolumeAll_negative_description() {
        XCTAssertEqual(VoiceCommand.adjustVolumeAll(-10).description, "adjustVolumeAll(-10)")
    }

    func testMuteAll_description() {
        XCTAssertEqual(VoiceCommand.muteAll.description, "muteAll")
    }

    func testUnmuteAll_description() {
        XCTAssertEqual(VoiceCommand.unmuteAll.description, "unmuteAll")
    }

    // MARK: — toCommandIntent() broadcast mapping

    func testStopAll_toCommandIntent() {
        XCTAssertEqual(VoiceCommand.stopAll.toCommandIntent(), .stopAll)
    }

    func testPauseAll_toCommandIntent() {
        XCTAssertEqual(VoiceCommand.pauseAll.toCommandIntent(), .pauseAll)
    }

    func testResumeAll_toCommandIntent() {
        XCTAssertEqual(VoiceCommand.resumeAll.toCommandIntent(), .resumeAll)
    }

    func testAdjustVolumeAll_positive_toCommandIntent() {
        XCTAssertEqual(VoiceCommand.adjustVolumeAll(10).toCommandIntent(), .volumeUpAll)
    }

    func testAdjustVolumeAll_negative_toCommandIntent() {
        XCTAssertEqual(VoiceCommand.adjustVolumeAll(-10).toCommandIntent(), .volumeDownAll)
    }

    func testMuteAll_toCommandIntent() {
        XCTAssertEqual(VoiceCommand.muteAll.toCommandIntent(), .muteAll)
    }

    func testUnmuteAll_toCommandIntent() {
        XCTAssertEqual(VoiceCommand.unmuteAll.toCommandIntent(), .unmuteAll)
    }

    // MARK: — CommandParserRouter.toVoiceCommand() broadcast mapping

    func testToVoiceCommand_stopAll() {
        let router = CommandParserRouter(personalisationStore: PersonalisationStore(context: PersistenceController.preview.viewContext))
        let cmd = router.toVoiceCommand(ParsedCommand(intent: .stopAll))
        XCTAssertEqual(cmd, .stopAll)
    }

    func testToVoiceCommand_pauseAll() {
        let router = CommandParserRouter(personalisationStore: PersonalisationStore(context: PersistenceController.preview.viewContext))
        let cmd = router.toVoiceCommand(ParsedCommand(intent: .pauseAll))
        XCTAssertEqual(cmd, .pauseAll)
    }

    func testToVoiceCommand_resumeAll() {
        let router = CommandParserRouter(personalisationStore: PersonalisationStore(context: PersistenceController.preview.viewContext))
        let cmd = router.toVoiceCommand(ParsedCommand(intent: .resumeAll))
        XCTAssertEqual(cmd, .resumeAll)
    }

    func testToVoiceCommand_volumeUpAll_defaultDelta() {
        let router = CommandParserRouter(personalisationStore: PersonalisationStore(context: PersistenceController.preview.viewContext))
        let cmd = router.toVoiceCommand(ParsedCommand(intent: .volumeUpAll))
        XCTAssertEqual(cmd, .adjustVolumeAll(+10))
    }

    func testToVoiceCommand_volumeDownAll_defaultDelta() {
        let router = CommandParserRouter(personalisationStore: PersonalisationStore(context: PersistenceController.preview.viewContext))
        let cmd = router.toVoiceCommand(ParsedCommand(intent: .volumeDownAll))
        XCTAssertEqual(cmd, .adjustVolumeAll(-10))
    }

    func testToVoiceCommand_volumeUpAll_customDelta() {
        let router = CommandParserRouter(personalisationStore: PersonalisationStore(context: PersistenceController.preview.viewContext))
        let cmd = router.toVoiceCommand(ParsedCommand(intent: .volumeUpAll, volumeDelta: 20))
        XCTAssertEqual(cmd, .adjustVolumeAll(+20))
    }

    func testToVoiceCommand_muteAll() {
        let router = CommandParserRouter(personalisationStore: PersonalisationStore(context: PersistenceController.preview.viewContext))
        let cmd = router.toVoiceCommand(ParsedCommand(intent: .muteAll))
        XCTAssertEqual(cmd, .muteAll)
    }

    func testToVoiceCommand_unmuteAll() {
        let router = CommandParserRouter(personalisationStore: PersonalisationStore(context: PersistenceController.preview.viewContext))
        let cmd = router.toVoiceCommand(ParsedCommand(intent: .unmuteAll))
        XCTAssertEqual(cmd, .unmuteAll)
    }
}
