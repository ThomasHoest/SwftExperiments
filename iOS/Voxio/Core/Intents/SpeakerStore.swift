import Foundation

@MainActor
final class SpeakerStore {
    static let shared = SpeakerStore()
    var activeSpeaker: Speaker?
    var allSpeakers: [Speaker] = []
    private init() {}
}
