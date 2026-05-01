import Foundation

extension MozartEvents: SpeakerEventSource {
    func events() -> AsyncStream<SpeakerEvent> {
        AsyncStream { continuation in
            self.onEvent = { beoEvent in
                if let speakerEvent = Self.translate(beoEvent) {
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

    private static func translate(_ event: BeoEvent) -> SpeakerEvent? {
        switch event {
        case .playbackState(let e):
            let state: SpeakerPlaybackState
            switch e.value {
            case .playing, .started: state = .playing
            case .paused:            state = .paused
            case .stopped, .unknown: state = .stopped
            case .buffering:         state = .buffering
            }
            return .playbackState(state)
        case .playbackMetadata(let e):
            return .metadata(title: e.title, artist: e.artistName, album: e.albumName)
        case .volume(let v):
            return .volume(level: v.volume.level, muted: v.volume.muted ?? false)
        case .battery(let b):
            return .battery(b)
        case .playbackSource(let s):
            return .source(name: s.displayName, id: s.id)
        case .power, .progress, .unknown:
            return nil
        }
    }
}
