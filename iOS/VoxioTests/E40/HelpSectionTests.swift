import XCTest
@testable import Voxio

// E-40 — Unit tests covering HelpSection data (T-4001–T-4004).
//
// Tests verify:
//   • Section count, order, and titles match US-65
//   • Row counts per section match US-65 (12 / 2 / 7)
//   • Speaker-name substitution works for all three sections
//   • Placeholder fallback is used when speakerA/B are nil
//   • EN and DA phrases are non-empty on every row
//   • The grouping section uses both speaker names correctly

final class HelpSectionTests: XCTestCase {

    // MARK: — Section structure

    func testAll_returnThreeSections() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: "Beosound")
        XCTAssertEqual(sections.count, 3, "HelpSection.all must return exactly 3 sections")
    }

    func testSectionOrder_singleSpeakerFirst() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: "Beosound")
        XCTAssertEqual(sections[0].titleEN, "Single speaker")
        XCTAssertEqual(sections[1].titleEN, "Grouping")
        XCTAssertEqual(sections[2].titleEN, "All speakers")
    }

    func testSectionTitles_danish() {
        let sections = HelpSection.all(speakerA: nil, speakerB: nil)
        XCTAssertEqual(sections[0].titleDA, "Enkelt højttaler")
        XCTAssertEqual(sections[1].titleDA, "Gruppering")
        XCTAssertEqual(sections[2].titleDA, "Alle højttalere")
    }

    // MARK: — T-4002 Single speaker: 12 rows

    func testSingleSpeakerSection_has12Rows() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: nil)
        XCTAssertEqual(sections[0].rows.count, 12, "Single speaker section must have exactly 12 rows per US-65")
    }

    func testSingleSpeakerSection_rowsHaveNonEmptyPhrases() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: nil)
        for row in sections[0].rows {
            XCTAssertFalse(row.phraseEN.isEmpty, "phraseEN must be non-empty for row: \(row.actionEN)")
            XCTAssertFalse(row.phraseDA.isEmpty, "phraseDA must be non-empty for row: \(row.actionEN)")
            XCTAssertFalse(row.actionEN.isEmpty, "actionEN must be non-empty")
            XCTAssertFalse(row.actionDA.isEmpty, "actionDA must be non-empty")
        }
    }

    func testSingleSpeakerSection_speakerNameSubstituted() {
        let speaker = "TestSpeaker"
        let sections = HelpSection.all(speakerA: speaker, speakerB: nil)
        let singleSpeaker = sections[0]
        for row in singleSpeaker.rows {
            XCTAssertTrue(row.phraseEN.hasPrefix(speaker), "phraseEN should start with speaker name '\(speaker)'; got '\(row.phraseEN)'")
            XCTAssertTrue(row.phraseDA.hasPrefix(speaker), "phraseDA should start with speaker name '\(speaker)'; got '\(row.phraseDA)'")
        }
    }

    func testSingleSpeakerSection_fallbackPlaceholder_whenNil() {
        let sections = HelpSection.all(speakerA: nil, speakerB: nil)
        let singleSpeaker = sections[0]
        for row in singleSpeaker.rows {
            XCTAssertTrue(row.phraseEN.hasPrefix("[Speaker]"), "phraseEN fallback should use '[Speaker]'; got '\(row.phraseEN)'")
            XCTAssertTrue(row.phraseDA.hasPrefix("[Speaker]"), "phraseDA fallback should use '[Speaker]'; got '\(row.phraseDA)'")
        }
    }

    // MARK: — T-4002 Specific row phrases (spot check against US-65)

    func testSingleSpeakerSection_playRow() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: nil)
        let rows = sections[0].rows
        guard let playRow = rows.first(where: { $0.actionEN == "Play" }) else {
            return XCTFail("Missing Play row")
        }
        XCTAssertEqual(playRow.phraseEN, "Beolab, play")
        XCTAssertEqual(playRow.phraseDA, "Beolab, afspil")
    }

    func testSingleSpeakerSection_muteRow() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: nil)
        let rows = sections[0].rows
        guard let muteRow = rows.first(where: { $0.actionEN == "Mute" }) else {
            return XCTFail("Missing Mute row")
        }
        XCTAssertEqual(muteRow.phraseEN, "Beolab, mute")
        XCTAssertEqual(muteRow.phraseDA, "Beolab, tavs")
    }

    func testSingleSpeakerSection_unmuteRow() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: nil)
        let rows = sections[0].rows
        guard let unmuteRow = rows.first(where: { $0.actionEN == "Unmute" }) else {
            return XCTFail("Missing Unmute row")
        }
        XCTAssertEqual(unmuteRow.phraseEN, "Beolab, unmute")
        XCTAssertEqual(unmuteRow.phraseDA, "Beolab, slå lyden til")
    }

    func testSingleSpeakerSection_volumeAbsoluteRow() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: nil)
        let rows = sections[0].rows
        guard let volRow = rows.first(where: { $0.actionEN == "Volume" }) else {
            return XCTFail("Missing Volume row")
        }
        XCTAssertEqual(volRow.phraseEN, "Beolab, volume 50")
        XCTAssertEqual(volRow.phraseDA, "Beolab, lydstyrke 50")
    }

    func testSingleSpeakerSection_listFavouritesRow() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: nil)
        let rows = sections[0].rows
        guard let listRow = rows.first(where: { $0.actionEN == "List favourites" }) else {
            return XCTFail("Missing 'List favourites' row")
        }
        XCTAssertEqual(listRow.phraseEN, "Beolab, what are my favorites?")
        XCTAssertEqual(listRow.phraseDA, "Beolab, hvad er mine favoritter?")
    }

    // MARK: — T-4003 Grouping: 2 rows

    func testGroupingSection_has2Rows() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: "Beosound")
        XCTAssertEqual(sections[1].rows.count, 2, "Grouping section must have exactly 2 rows per US-65")
    }

    func testGroupingSection_usesBothSpeakerNames() {
        let a = "SpeakerA"
        let b = "SpeakerB"
        let sections = HelpSection.all(speakerA: a, speakerB: b)
        let grouping = sections[1]

        // Join row: [Speaker A], join [Speaker B]
        let joinRow = grouping.rows[0]
        XCTAssertTrue(joinRow.phraseEN.contains(a), "Join phraseEN should contain speakerA")
        XCTAssertTrue(joinRow.phraseEN.contains(b), "Join phraseEN should contain speakerB")
        XCTAssertTrue(joinRow.phraseDA.contains(a), "Join phraseDA should contain speakerA")
        XCTAssertTrue(joinRow.phraseDA.contains(b), "Join phraseDA should contain speakerB")

        // Leave row: [Speaker A], leave the group
        let leaveRow = grouping.rows[1]
        XCTAssertTrue(leaveRow.phraseEN.contains(a), "Leave phraseEN should contain speakerA")
        XCTAssertTrue(leaveRow.phraseDA.contains(a), "Leave phraseDA should contain speakerA")
    }

    func testGroupingSection_joinPhrases() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: "Beosound")
        let joinRow = sections[1].rows[0]
        XCTAssertEqual(joinRow.phraseEN, "Beolab, join Beosound")
        XCTAssertEqual(joinRow.phraseDA, "Beolab, tilslut Beosound")
    }

    func testGroupingSection_leavePhrases() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: "Beosound")
        let leaveRow = sections[1].rows[1]
        XCTAssertEqual(leaveRow.phraseEN, "Beolab, leave the group")
        XCTAssertEqual(leaveRow.phraseDA, "Beolab, forlad gruppen")
    }

    func testGroupingSection_fallbackPlaceholders_whenNil() {
        let sections = HelpSection.all(speakerA: nil, speakerB: nil)
        let joinRow = sections[1].rows[0]
        XCTAssertTrue(joinRow.phraseEN.contains("[Speaker]"), "Join phraseEN fallback should contain '[Speaker]'")
        XCTAssertTrue(joinRow.phraseEN.contains("[Speaker B]"), "Join phraseEN fallback should contain '[Speaker B]'")
    }

    // MARK: — T-4004 System actions: 7 rows

    func testSystemActionsSection_has7Rows() {
        let sections = HelpSection.all(speakerA: nil, speakerB: nil)
        XCTAssertEqual(sections[2].rows.count, 7, "System actions section must have exactly 7 rows per US-65")
    }

    func testSystemActionsSection_rowsHaveNonEmptyPhrases() {
        let sections = HelpSection.all(speakerA: nil, speakerB: nil)
        for row in sections[2].rows {
            XCTAssertFalse(row.phraseEN.isEmpty, "phraseEN must be non-empty for system action row: \(row.actionEN)")
            XCTAssertFalse(row.phraseDA.isEmpty, "phraseDA must be non-empty for system action row: \(row.actionEN)")
        }
    }

    func testSystemActionsSection_doesNotContainSpeakerPlaceholder() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: "Beosound")
        for row in sections[2].rows {
            XCTAssertFalse(row.phraseEN.contains("Beolab"), "System action phraseEN should not contain a speaker name")
            XCTAssertFalse(row.phraseDA.contains("Beolab"), "System action phraseDA should not contain a speaker name")
        }
    }

    func testSystemActionsSection_stopAllRow() {
        let sections = HelpSection.all(speakerA: nil, speakerB: nil)
        guard let row = sections[2].rows.first(where: { $0.actionEN == "Stop all" }) else {
            return XCTFail("Missing 'Stop all' row")
        }
        XCTAssertEqual(row.phraseEN, "stop everything")
        XCTAssertEqual(row.phraseDA, "stop alt")
    }

    func testSystemActionsSection_pauseAllRow() {
        let sections = HelpSection.all(speakerA: nil, speakerB: nil)
        guard let row = sections[2].rows.first(where: { $0.actionEN == "Pause all" }) else {
            return XCTFail("Missing 'Pause all' row")
        }
        XCTAssertEqual(row.phraseEN, "pause all")
        XCTAssertEqual(row.phraseDA, "pause alle")
    }

    func testSystemActionsSection_resumeAllRow() {
        let sections = HelpSection.all(speakerA: nil, speakerB: nil)
        guard let row = sections[2].rows.first(where: { $0.actionEN == "Resume all" }) else {
            return XCTFail("Missing 'Resume all' row")
        }
        XCTAssertEqual(row.phraseEN, "resume all")
        XCTAssertEqual(row.phraseDA, "genoptag alt")
    }

    func testSystemActionsSection_volumeDownAllRow() {
        let sections = HelpSection.all(speakerA: nil, speakerB: nil)
        guard let row = sections[2].rows.first(where: { $0.actionEN == "Volume down all" }) else {
            return XCTFail("Missing 'Volume down all' row")
        }
        XCTAssertEqual(row.phraseEN, "volume down everywhere")
        XCTAssertEqual(row.phraseDA, "skru ned overalt")
    }

    func testSystemActionsSection_volumeUpAllRow() {
        let sections = HelpSection.all(speakerA: nil, speakerB: nil)
        guard let row = sections[2].rows.first(where: { $0.actionEN == "Volume up all" }) else {
            return XCTFail("Missing 'Volume up all' row")
        }
        XCTAssertEqual(row.phraseEN, "volume up everywhere")
        XCTAssertEqual(row.phraseDA, "skru op overalt")
    }

    func testSystemActionsSection_muteAllRow() {
        let sections = HelpSection.all(speakerA: nil, speakerB: nil)
        guard let row = sections[2].rows.first(where: { $0.actionEN == "Mute all" }) else {
            return XCTFail("Missing 'Mute all' row")
        }
        XCTAssertEqual(row.phraseEN, "mute everything")
        XCTAssertEqual(row.phraseDA, "mute alt")
    }

    func testSystemActionsSection_unmuteAllRow() {
        let sections = HelpSection.all(speakerA: nil, speakerB: nil)
        guard let row = sections[2].rows.first(where: { $0.actionEN == "Unmute all" }) else {
            return XCTFail("Missing 'Unmute all' row")
        }
        XCTAssertEqual(row.phraseEN, "unmute everything")
        XCTAssertEqual(row.phraseDA, "unmute alle")
    }

    // MARK: — T-4005 Total row count

    func testAllSections_totalRowCount_is21() {
        let sections = HelpSection.all(speakerA: "Beolab", speakerB: "Beosound")
        let total = sections.reduce(0) { $0 + $1.rows.count }
        XCTAssertEqual(total, 21, "Total row count across all sections must be 21 per US-65 (12 + 2 + 7)")
    }

    // MARK: — HelpView interface contract

    func testHelpView_init_defaultsDisplayLanguageToActiveLanguage() {
        let view = HelpView(
            speakerA: "Beolab",
            speakerB: nil,
            activeLanguage: .danish,
            isPresented: .constant(true)
        )
        // The view init stores activeLanguage; accessible via the public property
        XCTAssertEqual(view.activeLanguage, .danish)
    }

    func testHelpView_init_englishActiveLanguage() {
        let view = HelpView(
            speakerA: nil,
            speakerB: nil,
            activeLanguage: .english,
            isPresented: .constant(true)
        )
        XCTAssertEqual(view.activeLanguage, .english)
    }

    func testHelpView_speakerAandBPassedThrough() {
        let view = HelpView(
            speakerA: "Alpha",
            speakerB: "Beta",
            activeLanguage: .english,
            isPresented: .constant(true)
        )
        XCTAssertEqual(view.speakerA, "Alpha")
        XCTAssertEqual(view.speakerB, "Beta")
    }

    func testHelpView_nilSpeakersArePreserved() {
        let view = HelpView(
            speakerA: nil,
            speakerB: nil,
            activeLanguage: .english,
            isPresented: .constant(true)
        )
        XCTAssertNil(view.speakerA)
        XCTAssertNil(view.speakerB)
    }
}
