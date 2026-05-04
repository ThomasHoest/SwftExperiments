import Foundation

protocol SpeakerEventSource: AnyObject {
    func events() -> AsyncStream<SpeakerEvent>
}
