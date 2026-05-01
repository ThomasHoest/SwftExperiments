import Foundation

@MainActor
final class MockSpeakerEventSource: SpeakerEventSource {
    var eventsToYield: [SpeakerEvent] = []

    func events() -> AsyncStream<SpeakerEvent> {
        AsyncStream { continuation in
            for event in eventsToYield { continuation.yield(event) }
            continuation.finish()
        }
    }
}
