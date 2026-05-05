import Testing
import CoreData
@testable import Voxio

// MARK: - CommandParserRouterPersonalisationTests
//
// Tests for the updated CommandParserRouter.parse(_:speakerId:) (T-3304).
// These tests verify that:
//   — Tier 0 (PersonalisationParser) is consulted before Stage 1 regex.
//   — A Tier 0 hit short-circuits Stage 1.
//   — A Tier 0 miss falls through to Stage 1 regex.
//   — speakerId is correctly passed through to the store.
//
// NOTE: The existing CommandParserRouterTests.swift uses the OLD
// func parse(_ transcript: String) async -> VoiceCommand signature and must be
// updated by the implementer to use the new
// func parse(_ transcript: String, speakerId: String) async -> VoiceCommand.
//
// All tests use PersistenceController.preview (in-memory Core Data).

// MARK: - Helpers

/// Builds a CommandParserRouter pre-seeded with an alias for the given speakerId.
@MainActor
private func makeRouter(
    withAliasPhrase phrase: String,
    intent: CommandIntent,
    slots: [String: String] = [:],
    speakerId: String
) throws -> CommandParserRouter {
    let store = PersonalisationStore(context: PersistenceController.preview.viewContext)
    store.isEnabled = true
    try store.saveAlias(speakerId: speakerId, phrase: phrase, intent: intent, slots: slots)
    return CommandParserRouter(personalisationStore: store)
}

/// Builds a CommandParserRouter pre-seeded with a confirmed-command for the given speakerId.
@MainActor
private func makeRouter(
    withConfirmedTranscription transcription: String,
    intent: CommandIntent,
    slots: [String: String] = [:],
    speakerId: String
) throws -> CommandParserRouter {
    let store = PersonalisationStore(context: PersistenceController.preview.viewContext)
    store.isEnabled = true
    try store.recordConfirmedCommand(speakerId: speakerId, transcription: transcription, intent: intent, slots: slots)
    return CommandParserRouter(personalisationStore: store)
}

/// Builds a CommandParserRouter with an empty store (simulates no personalisation data).
@MainActor
private func makeRouterWithEmptyStore() -> CommandParserRouter {
    let store = PersonalisationStore(context: PersistenceController.preview.viewContext)
    store.isEnabled = true
    return CommandParserRouter(personalisationStore: store)
}

// MARK: -

@Suite("CommandParserRouter — Tier 0 personalisation short-circuits Stage 1")
struct CommandParserRouterPersonalisationShortCircuitTests {

    // MARK: T-3304-A1 — personalisation tier match returns its result without calling Stage 1

    @Test("parse: alias match short-circuits Stage 1 — returns personalisaton result")
    @MainActor
    func parse_aliasMatch_shortCircuitsStage1() async throws {
        let speakerId = "spk-cpr-shortcircuit"

        // "stop" is a phrase Stage 1 would normally parse as .stop → .stop VoiceCommand.
        // We register an alias mapping "stop" to .mute for this speaker.
        // If Tier 0 runs first, the result should be .mute, not .stop.
        let router = try makeRouter(
            withAliasPhrase: "stop",
            intent: .mute,
            speakerId: speakerId
        )

        let result = await router.parse("stop", speakerId: speakerId)
        #expect(result == .mute, "Tier 0 alias should override Stage 1 regex result for 'stop'")
    }

    @Test("parse: alias match maps through toVoiceCommand correctly")
    @MainActor
    func parse_aliasMatch_correctVoiceCommandReturned() async throws {
        let speakerId = "spk-cpr-alias-map"

        // Alias "morning tunes" → .playFavoriteByNumber with favoriteIndex = 2
        let router = try makeRouter(
            withAliasPhrase: "morning tunes",
            intent: .playFavoriteByNumber,
            slots: ["favoriteIndex": "2"],
            speakerId: speakerId
        )

        let result = await router.parse("morning tunes", speakerId: speakerId)
        #expect(result == .playFavorite(index: 2))
    }

    @Test("parse: confirmed-command match short-circuits Stage 1 — returns personalisation result")
    @MainActor
    func parse_confirmedCommandMatch_shortCircuitsStage1() async throws {
        let speakerId = "spk-cpr-confirmed"

        // "volume up" is a phrase Stage 1 parses as .adjustVolume(+10).
        // We seed a confirmed-command entry mapping "volume up" to .setVolume with value 75.
        // If Tier 0 runs first, result should be .setVolume(75).
        let router = try makeRouter(
            withConfirmedTranscription: "volume up",
            intent: .setVolume,
            slots: ["volumeValue": "75"],
            speakerId: speakerId
        )

        let result = await router.parse("volume up", speakerId: speakerId)
        #expect(result == .setVolume(75), "Tier 0 confirmed-command should override Stage 1 for 'volume up'")
    }

    // MARK: T-3304-A2 — personalisation miss falls through to Stage 1 regex

    @Test("parse: no personalisation match falls through to Stage 1 regex — 'stop' returns .stop")
    @MainActor
    func parse_noPersonalisationMatch_fallsThroughToStage1() async {
        let router = makeRouterWithEmptyStore()

        // "stop" has no alias/confirmed-command — Stage 1 should handle it
        let result = await router.parse("stop", speakerId: "spk-cpr-fallthrough")
        #expect(result == .stop)
    }

    @Test("parse: no personalisation match falls through to Stage 1 regex — 'pause' returns .pause")
    @MainActor
    func parse_noPersonalisationMatch_pause_returnsPause() async {
        let router = makeRouterWithEmptyStore()
        let result = await router.parse("pause", speakerId: "spk-cpr-fallthrough-pause")
        #expect(result == .pause)
    }

    @Test("parse: no personalisation match falls through to Stage 1 regex — 'volume up' returns .adjustVolume(+10)")
    @MainActor
    func parse_noPersonalisationMatch_volumeUp_returnsAdjustVolume() async {
        let router = makeRouterWithEmptyStore()
        let result = await router.parse("volume up", speakerId: "spk-cpr-fallthrough-vol")
        #expect(result == .adjustVolume(+10))
    }

    @Test("parse: alias for speakerA does not intercept parse for speakerB")
    @MainActor
    func parse_aliasForSpeakerA_noEffectOnSpeakerB() async throws {
        let speakerA = "spk-cpr-speaker-A"
        let speakerB = "spk-cpr-speaker-B"

        // Alias "stop" → .mute, but only for speakerA
        let router = try makeRouter(
            withAliasPhrase: "stop",
            intent: .mute,
            speakerId: speakerA
        )

        // Parsing with speakerB should fall through to Stage 1
        let result = await router.parse("stop", speakerId: speakerB)
        #expect(result == .stop, "speakerB has no alias for 'stop'; Stage 1 should return .stop")
    }
}

// MARK: -

@Suite("CommandParserRouter — speakerId is passed to store")
struct CommandParserRouterSpeakerIdPassThroughTests {

    // MARK: T-3304-B1 — speakerId is correctly passed through

    @Test("parse: speakerId passed to store; alias scoped to correct speaker resolves correctly")
    @MainActor
    func parse_speakerIdPassthrough_correctSpeakerAliasResolved() async throws {
        let speakerA = "spk-id-passthrough-A"
        let speakerB = "spk-id-passthrough-B"

        let store = PersonalisationStore(context: PersistenceController.preview.viewContext)
        store.isEnabled = true

        // Give each speaker a different alias for the same phrase
        try store.saveAlias(speakerId: speakerA, phrase: "evening mode", intent: .mute, slots: [:])
        try store.saveAlias(speakerId: speakerB, phrase: "evening mode", intent: .resume, slots: [:])

        let router = CommandParserRouter(personalisationStore: store)

        let resultA = await router.parse("evening mode", speakerId: speakerA)
        let resultB = await router.parse("evening mode", speakerId: speakerB)

        #expect(resultA == .mute, "speakerA alias for 'evening mode' should resolve to .mute")
        #expect(resultB == .resume, "speakerB alias for 'evening mode' should resolve to .resume")
    }

    @Test("parse: empty speakerId still works when store has no matching alias")
    @MainActor
    func parse_emptySpeakerId_noAlias_fallsThrough() async {
        let store = PersonalisationStore(context: PersistenceController.preview.viewContext)
        store.isEnabled = true
        let router = CommandParserRouter(personalisationStore: store)

        let result = await router.parse("mute", speakerId: "")
        #expect(result == .mute, "Empty speakerId with no alias falls through to Stage 1")
    }
}

// MARK: -

@Suite("CommandParserRouter — personalisation disabled")
struct CommandParserRouterPersonalisationDisabledTests {

    @Test("parse: isEnabled=false causes personalisation to be skipped; Stage 1 handles the phrase")
    @MainActor
    func parse_personalisationDisabled_stage1Handles() async throws {
        let speakerId = "spk-cpr-disabled"
        let store = PersonalisationStore(context: PersistenceController.preview.viewContext)

        // Register alias mapping "pause" to .stop (would override Stage 1 if enabled)
        try store.saveAlias(speakerId: speakerId, phrase: "pause", intent: .stop, slots: [:])

        // Disable personalisation
        store.isEnabled = false

        let router = CommandParserRouter(personalisationStore: store)
        let result = await router.parse("pause", speakerId: speakerId)

        // With personalisation disabled, Stage 1 should parse "pause" as .pause — not the aliased .stop
        #expect(result == .pause, "With personalisation disabled, Stage 1 must handle 'pause'")
    }
}

// MARK: -

@Suite("CommandParserRouter — toVoiceCommand mapping with personalisation intents")
struct CommandParserRouterToVoiceCommandTests {

    // These tests verify that toVoiceCommand correctly maps personalised ParsedCommand
    // results to VoiceCommand — important because the personalisation layer uses the
    // same toVoiceCommand path as Stage 1 and Foundation Models.

    @Test("toVoiceCommand: .stop ParsedCommand from personalisation maps to .stop VoiceCommand")
    @MainActor
    func toVoiceCommand_stop() throws {
        let store = PersonalisationStore(context: PersistenceController.preview.viewContext)
        let router = CommandParserRouter(personalisationStore: store)
        let mapped = router.toVoiceCommand(ParsedCommand(intent: .stop))
        #expect(mapped == .stop)
    }

    @Test("toVoiceCommand: .mute ParsedCommand from personalisation maps to .mute VoiceCommand")
    @MainActor
    func toVoiceCommand_mute() throws {
        let store = PersonalisationStore(context: PersistenceController.preview.viewContext)
        let router = CommandParserRouter(personalisationStore: store)
        let mapped = router.toVoiceCommand(ParsedCommand(intent: .mute))
        #expect(mapped == .mute)
    }

    @Test("toVoiceCommand: .setVolume with value maps to .setVolume(_:) VoiceCommand")
    @MainActor
    func toVoiceCommand_setVolume() throws {
        let store = PersonalisationStore(context: PersistenceController.preview.viewContext)
        let router = CommandParserRouter(personalisationStore: store)
        let mapped = router.toVoiceCommand(ParsedCommand(intent: .setVolume, volumeValue: 65))
        #expect(mapped == .setVolume(65))
    }
}
