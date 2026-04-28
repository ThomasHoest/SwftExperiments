import Foundation

class MozartEvents {
    private let host: String
    private let url: URL
    private var task: URLSessionWebSocketTask?
    private var retryCount = 0
    private var cancelled = false
    private let decoder = JSONDecoder()

    var onEvent: ((BeoEvent) -> Void)?

    init(host: String) {
        self.host = host
        url = URL(string: "ws://\(host):9339/")!
    }

    func connect() {
        cancelled = false
        openSocket()
    }

    private func openSocket() {
        guard !cancelled else { return }
        Log.info("[WS:\(host)] connecting")
        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
        receive()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self, !self.cancelled else { return }
            switch result {
            case .success(let message):
                self.retryCount = 0
                if case .string(let text) = message { self.processMessage(text) }
                self.receive()
            case .failure(let error):
                let delay = min(pow(2.0, Double(self.retryCount)), 30.0)
                Log.info("[WS:\(self.host)] disconnected (\(error.localizedDescription)) — reconnecting in \(Int(delay))s")
                self.retryCount = min(self.retryCount + 1, 5)
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { self.openSocket() }
            }
        }
    }

    private func processMessage(_ json: String) {
        guard let msgData  = json.data(using: .utf8),
              let obj      = try? JSONSerialization.jsonObject(with: msgData) as? [String: Any],
              let type     = obj["eventType"] as? String,
              let body     = obj["eventData"] as? [String: Any],
              let bodyData = try? JSONSerialization.data(withJSONObject: body)
        else { return }

        let event = parse(type: type, data: bodyData)
        Log.verbose("[WS:\(host)] \(type)")
        onEvent?(event)
    }

    private func parse(type: String, data: Data) -> BeoEvent {
        switch type {
        case "WebSocketEventPlaybackState":
            return decode(PlaybackStateEvent.self, from: data).map(BeoEvent.playbackState) ?? .unknown(type)
        case "WebSocketEventPlaybackMetadata":
            return decode(PlaybackMetadataEvent.self, from: data).map(BeoEvent.playbackMetadata) ?? .unknown(type)
        case "WebSocketEventVolume":
            return decode(VolumeResponse.self, from: data).map(BeoEvent.volume) ?? .unknown(type)
        case "WebSocketEventBattery":
            return decode(Battery.self, from: data).map(BeoEvent.battery) ?? .unknown(type)
        case "WebSocketEventPlaybackSource":
            return decode(Source.self, from: data).map(BeoEvent.playbackSource) ?? .unknown(type)
        case "WebSocketEventPowerState":
            return decode(PowerState.self, from: data).map(BeoEvent.power) ?? .unknown(type)
        case "WebSocketEventPlaybackProgress":
            return decode(PlaybackProgressEvent.self, from: data).map(BeoEvent.progress) ?? .unknown(type)
        default:
            return .unknown(type)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder.decode(type, from: data)
    }

    func disconnect() {
        Log.info("[WS:\(host)] disconnecting")
        cancelled = true
        task?.cancel(with: .normalClosure, reason: nil)
    }
}
