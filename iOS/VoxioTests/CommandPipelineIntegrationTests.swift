import XCTest
import CoreData
@testable import Voxio

// E-41 — Integration tests for the command parsing pipeline (T-4109).
//
// These tests verify the original failing scenario: an alias phrase that
// contains no speaker name dispatches correctly to the alias's speaker.
// Tests use real PersonalisationStore + CommandParserRouter + UtteranceClassifier
// backed by an in-memory Core Data context (PersistenceController.preview).

@MainActor
final class CommandPipelineIntegrationTests: XCTestCase {

    // MARK: - Case 1: alias dispatch with no speaker name in transcript

    func test_alias_dispatches_to_correct_speaker_no_name_in_transcript() throws {
        let context = PersistenceController.preview.viewContext
        let store = PersonalisationStore(context: context)
        store.isEnabled = true

        let speakerA = makeTestSpeaker(name: "Kontor")
        let discovery = StubDiscoveryForIntegration()
        discovery.inject(speakers: [speakerA])

        try store.saveAlias(
            speakerId: speakerA.id.uuidString,
            phrase: "musik til arbejdet",
            intent: .playDefault,
            slots: [:]
        )

        let router = CommandParserRouter(personalisationStore: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )

        let outcome = classifier.classify("musik til arbejdet")

        guard case .personalised(let speaker, let parsed) = outcome else {
            return XCTFail("Expected .personalised for 'musik til arbejdet', got \(outcome)")
        }
        XCTAssertEqual(speaker.id, speakerA.id, "Must dispatch to speaker A")
        XCTAssertEqual(parsed.intent, .playDefault)
    }

    // MARK: - Case 2: confirmed-command dispatch with no speaker name

    func test_confirmed_command_dispatches_to_correct_speaker() throws {
        let context = PersistenceController.preview.viewContext
        let store = PersonalisationStore(context: context)
        store.isEnabled = true

        let speakerB = makeTestSpeaker(name: "Stue")
        let discovery = StubDiscoveryForIntegration()
        discovery.inject(speakers: [speakerB])

        try store.recordConfirmedCommand(
            speakerId: speakerB.id.uuidString,
            transcription: "tænd musikken",
            intent: .resume,
            slots: [:]
        )

        let router = CommandParserRouter(personalisationStore: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )

        let outcome = classifier.classify("tænd musikken")

        guard case .personalised(let speaker, let parsed) = outcome else {
            return XCTFail("Expected .personalised for 'tænd musikken', got \(outcome)")
        }
        XCTAssertEqual(speaker.id, speakerB.id, "Must dispatch to speaker B")
        XCTAssertEqual(parsed.intent, .resume)
    }

    // MARK: - Case 3: no alias, no focused speaker → unresolved

    func test_no_alias_no_focused_speaker_returns_unresolved() {
        let context = PersistenceController.preview.viewContext
        let store = PersonalisationStore(context: context)
        store.isEnabled = true

        let router = CommandParserRouter(personalisationStore: store)
        let discovery = StubDiscoveryForIntegration()

        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )

        let outcome = classifier.classify("musik til arbejdet")
        guard case .unresolved = outcome else {
            return XCTFail("Expected .unresolved when no alias and no focused speaker, got \(outcome)")
        }
    }

    // MARK: - Helpers

    private func makeTestSpeaker(name: String) -> Speaker {
        let client = MockSpeakerClient()
        client.nameToReturn = name
        let events = MockSpeakerEventSource()
        let speaker = Speaker(
            host: "192.168.99.\(Int.random(in: 2...254))",
            client: client,
            eventSource: events,
            platform: .mozart
        )
        speaker.name = name
        return speaker
    }
}

// MARK: - Integration-specific stub discovery

/// Overrides resolve() to use a locally held speaker list and injects groups
/// into the parent via the public mergeIntoSpeakerGroup / removeMember dance.
@MainActor
private final class StubDiscoveryForIntegration: SpeakerDiscoveryService {

    private let matcher = SpeakerNameMatcher()
    private(set) var stubSpeakers: [Speaker] = []

    func inject(speakers: [Speaker]) {
        stubSpeakers = speakers
        for speaker in speakers {
            let dummy = makeDummySpeaker()
            mergeIntoSpeakerGroup(source: dummy, target: speaker)
            removeMember(dummy)
        }
    }

    override func resolve(words: [String]) -> (Speaker, remainingWords: [String])? {
        guard let (speaker, consumed) = matcher.match(words: words, in: stubSpeakers) else {
            return nil
        }
        return (speaker, Array(words.dropFirst(consumed)))
    }

    private func makeDummySpeaker() -> Speaker {
        let client = MockSpeakerClient()
        let events = MockSpeakerEventSource()
        return Speaker(host: "dummy-\(UUID().uuidString)", client: client, eventSource: events, platform: .mozart)
    }
}
