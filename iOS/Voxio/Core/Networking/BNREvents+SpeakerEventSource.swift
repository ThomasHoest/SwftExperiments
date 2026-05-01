import Foundation

extension BNREvents: SpeakerEventSource {
    func events() -> AsyncStream<SpeakerEvent> {
        AsyncStream { continuation in
            self.onEvent = { bnrEvent in
                if let speakerEvent = Self.translate(bnrEvent) {
                    continuation.yield(speakerEvent)
                }
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onEvent = nil
                    self?.disconnect()
                }
            }
            self.connect()
        }
    }

    private static func translate(_ event: BNREvent) -> SpeakerEvent? {
        switch event {
        case .volume(let level, let muted):
            return .volume(level: level, muted: muted)
        case .source(let name, let id):
            return .source(name: name, id: id)
        case .playbackState(let s):
            switch s {
            case .playing:   return .playbackState(.playing)
            case .paused:    return .playbackState(.paused)
            case .stopped:   return .playbackState(.stopped)
            case .buffering: return .playbackState(.buffering)
            }
        case .metadata(let title, let artist, let album):
            return .metadata(title: title, artist: artist, album: album)
        case .unknown:
            return nil
        }
    }
}
