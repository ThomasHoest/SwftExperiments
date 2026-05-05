import XCTest
import CoreData
@testable import Voxio

// E-41 — Unit tests for UtteranceClassifier (T-4108).
//
// All tests use an in-memory Core Data context derived from
// PersistenceController.preview. Each test constructs its own store,
// classifier, and speaker list. No Foundation Models dependency is triggered —
// the classifier only runs Stage 1 broadcast patterns and exact-string
// alias lookups.

// MARK: - Stub helpers

/// Subclass that overrides resolve(words:) to operate on an injected speaker list.
/// Groups are injected through the public mergeIntoSpeakerGroup / removeMember dance.
@MainActor
private final class StubDiscovery: SpeakerDiscoveryService {

    private let matcher = SpeakerNameMatcher()
    private(set) var stubSpeakers: [Speaker] = []

    func inject(speakers: [Speaker]) {
        stubSpeakers = speakers
        for speaker in speakers {
            let dummy = makeDummySpeaker(label: "dummy-\(speaker.id.uuidString)")
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

    private func makeDummySpeaker(label: String) -> Speaker {
        let client = MockSpeakerClient()
        let events = MockSpeakerEventSource()
        return Speaker(host: label, client: client, eventSource: events, platform: .mozart)
    }
}

private func makeSpeaker(name: String) -> Speaker {
    let client = MockSpeakerClient()
    client.nameToReturn = name
    let events = MockSpeakerEventSource()
    let speaker = Speaker(host: "192.168.1.\(Int.random(in: 2...254))", client: client, eventSource: events, platform: .mozart)
    speaker.name = name
    return speaker
}

private func makeStore() -> PersonalisationStore {
    PersonalisationStore(context: PersistenceController.preview.viewContext)
}

private func makeRouter(store: PersonalisationStore) -> CommandParserRouter {
    CommandParserRouter(personalisationStore: store)
}

// MARK: - Tests

@MainActor
final class UtteranceClassifierTests: XCTestCase {

    // MARK: - Broadcast branch

    func test_broadcast_stop_all() {
        let store = makeStore()
        let discovery = StubDiscovery()
        let router = makeRouter(store: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )
        let outcome = classifier.classify("stop alle")
        guard case .broadcast(let cmd) = outcome else {
            return XCTFail("Expected .broadcast, got \(outcome)")
        }
        XCTAssertEqual(cmd, .stopAll)
    }

    func test_broadcast_volume_up_all_with_amount() {
        let store = makeStore()
        let discovery = StubDiscovery()
        let router = makeRouter(store: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )
        let outcome = classifier.classify("skru op for alt 20")
        guard case .broadcast(let cmd) = outcome else {
            return XCTFail("Expected .broadcast, got \(outcome)")
        }
        XCTAssertEqual(cmd, .adjustVolumeAll(+20))
    }

    // MARK: - Personalised branch

    func test_personalised_alias_no_speaker_name() throws {
        let store = makeStore()
        store.isEnabled = true
        let speakerA = makeSpeaker(name: "Kontor")
        try store.saveAlias(
            speakerId: speakerA.id.uuidString,
            phrase: "musik til arbejdet",
            intent: .playDefault,
            slots: [:]
        )
        let discovery = StubDiscovery()
        discovery.inject(speakers: [speakerA])
        let router = makeRouter(store: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )
        let outcome = classifier.classify("musik til arbejdet")
        guard case .personalised(let speaker, let parsed) = outcome else {
            return XCTFail("Expected .personalised, got \(outcome)")
        }
        XCTAssertEqual(speaker.id, speakerA.id)
        XCTAssertEqual(parsed.intent, .playDefault)
    }

    func test_personalised_speaker_offline_falls_through() throws {
        let store = makeStore()
        store.isEnabled = true
        let speakerB = makeSpeaker(name: "Soveværelse")
        try store.saveAlias(
            speakerId: speakerB.id.uuidString,
            phrase: "godnatmusik",
            intent: .playDefault,
            slots: [:]
        )
        let discovery = StubDiscovery()
        // speakerB is NOT injected into discovery (offline)
        let router = makeRouter(store: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )
        let outcome = classifier.classify("godnatmusik")
        guard case .unresolved = outcome else {
            return XCTFail("Expected .unresolved when speaker offline, got \(outcome)")
        }
    }

    func test_personalisation_disabled_skips_branch() throws {
        let store = makeStore()
        store.isEnabled = false
        let speakerA = makeSpeaker(name: "Stue")
        try store.saveAlias(
            speakerId: speakerA.id.uuidString,
            phrase: "morgenmusik",
            intent: .playDefault,
            slots: [:]
        )
        let discovery = StubDiscovery()
        discovery.inject(speakers: [speakerA])
        let router = makeRouter(store: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )
        let outcome = classifier.classify("morgenmusik")
        // With personalisation disabled, the alias is skipped.
        // "morgenmusik" does not match any speaker name or broadcast → unresolved (no focused speaker).
        if case .personalised = outcome {
            XCTFail("personalised branch must be skipped when isEnabled=false")
        }
    }

    // MARK: - Addressed branch

    func test_addressed_simple() {
        let store = makeStore()
        let stue = makeSpeaker(name: "Stue")
        let discovery = StubDiscovery()
        discovery.inject(speakers: [stue])
        let router = makeRouter(store: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )
        let outcome = classifier.classify("stue play")
        guard case .addressed(let speaker, let remainder) = outcome else {
            return XCTFail("Expected .addressed, got \(outcome)")
        }
        XCTAssertEqual(speaker.id, stue.id)
        XCTAssertEqual(remainder, "play")
    }

    func test_addressed_fuzzy() {
        let store = makeStore()
        let stue = makeSpeaker(name: "Stue")
        let discovery = StubDiscovery()
        discovery.inject(speakers: [stue])
        let router = makeRouter(store: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )
        // "stu" is Levenshtein distance 1 from "stue"
        let outcome = classifier.classify("stu play")
        guard case .addressed(let speaker, let remainder) = outcome else {
            return XCTFail("Expected .addressed for fuzzy match, got \(outcome)")
        }
        XCTAssertEqual(speaker.id, stue.id)
        XCTAssertEqual(remainder, "play")
    }

    func test_addressed_bare_speaker_name() {
        let store = makeStore()
        let stue = makeSpeaker(name: "Stue")
        let discovery = StubDiscovery()
        discovery.inject(speakers: [stue])
        let router = makeRouter(store: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )
        let outcome = classifier.classify("stue")
        guard case .addressed(let speaker, let remainder) = outcome else {
            return XCTFail("Expected .addressed for bare speaker name, got \(outcome)")
        }
        XCTAssertEqual(speaker.id, stue.id)
        // When remainingWords is empty, classifier returns original text as remainder
        XCTAssertEqual(remainder, "stue")
    }

    // MARK: - Focused branch

    func test_focused_fallback_used() {
        let store = makeStore()
        let stue = makeSpeaker(name: "Stue")
        let discovery = StubDiscovery()
        // No speakers injected — "pause" won't match any name
        let router = makeRouter(store: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { stue }
        )
        let outcome = classifier.classify("pause")
        guard case .focused(let speaker, let text) = outcome else {
            return XCTFail("Expected .focused, got \(outcome)")
        }
        XCTAssertEqual(speaker.id, stue.id)
        XCTAssertEqual(text, "pause")
    }

    // MARK: - Unresolved

    func test_unresolved_no_focused_speaker() {
        let store = makeStore()
        let discovery = StubDiscovery()
        let router = makeRouter(store: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )
        let outcome = classifier.classify("pause")
        guard case .unresolved = outcome else {
            return XCTFail("Expected .unresolved when no focused speaker, got \(outcome)")
        }
    }

    // MARK: - Precedence tests

    func test_broadcast_wins_over_alias() throws {
        let store = makeStore()
        store.isEnabled = true
        let speakerA = makeSpeaker(name: "Stue")
        // Save alias with broadcast phrase — broadcast branch must still win
        try store.saveAlias(
            speakerId: speakerA.id.uuidString,
            phrase: "stop alle",
            intent: .pause,
            slots: [:]
        )
        let discovery = StubDiscovery()
        discovery.inject(speakers: [speakerA])
        let router = makeRouter(store: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )
        let outcome = classifier.classify("stop alle")
        guard case .broadcast(let cmd) = outcome else {
            return XCTFail("Expected .broadcast to win over alias, got \(outcome)")
        }
        XCTAssertEqual(cmd, .stopAll)
    }

    func test_personalised_wins_over_addressed() throws {
        let store = makeStore()
        store.isEnabled = true
        // Speaker named "Stue". Alias phrase "stu musik" fuzzy-matches "Stue" (Levenshtein 1).
        // The personalised branch runs before addressed, so it must win.
        let stue = makeSpeaker(name: "Stue")
        try store.saveAlias(
            speakerId: stue.id.uuidString,
            phrase: "stu musik",
            intent: .playDefault,
            slots: [:]
        )
        let discovery = StubDiscovery()
        discovery.inject(speakers: [stue])
        let router = makeRouter(store: store)
        let classifier = UtteranceClassifier(
            discovery: discovery,
            personalisationStore: store,
            router: router,
            focusedSpeaker: { nil }
        )
        let outcome = classifier.classify("stu musik")
        guard case .personalised(let speaker, let parsed) = outcome else {
            return XCTFail("Expected .personalised to win over .addressed for 'stu musik', got \(outcome)")
        }
        XCTAssertEqual(speaker.id, stue.id)
        XCTAssertEqual(parsed.intent, .playDefault)
    }
}
