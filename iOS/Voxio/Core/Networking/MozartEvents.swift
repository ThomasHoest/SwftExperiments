import Foundation
import Network

class MozartEvents {
    private let host: String
    private let url: URL
    private var task: URLSessionWebSocketTask?
    private var retryCount = 0
    private var cancelled = false
    private let decoder = JSONDecoder()

    // Path monitoring — pause retries on cellular, resume on WiFi
    private let pathMonitor: NWPathMonitor
    private let pathQueue = DispatchQueue(label: "mozart.path", qos: .utility)
    private var pathSatisfied = false
    private var pendingReconnect = false

    var onEvent: ((BeoEvent) -> Void)?

    init(host: String) {
        self.host = host
        url = URL(string: "ws://\(host):9339/")!
        pathMonitor = NWPathMonitor()
        setupPathMonitor()
    }

    func connect() {
        cancelled = false
        openSocket()
    }

    private func setupPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let nowSatisfied = path.status == .satisfied && !path.isExpensive
            let wasSatisfied = self.pathSatisfied
            self.pathSatisfied = nowSatisfied

            if nowSatisfied && !wasSatisfied && self.pendingReconnect && !self.cancelled {
                Log.info("[WS:\(self.host)] WiFi restored — reconnecting")
                self.pendingReconnect = false
                self.retryCount = 0
                self.openSocket()
            }
        }
        pathMonitor.start(queue: pathQueue)
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
                if self.pathSatisfied {
                    let delay = min(pow(2.0, Double(self.retryCount)), 30.0)
                    Log.info("[WS:\(self.host)] disconnected (\(error.localizedDescription)) — retrying in \(Int(delay))s")
                    self.retryCount = min(self.retryCount + 1, 5)
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { self.openSocket() }
                } else {
                    Log.info("[WS:\(self.host)] disconnected — no WiFi, parked until path restores")
                    self.pendingReconnect = true
                }
            }
        }
    }

    private func processMessage(_ json: String) {
        guard let msgData = json.data(using: .utf8),
              let obj     = try? JSONSerialization.jsonObject(with: msgData) as? [String: Any],
              let type    = obj["eventType"] as? String,
              let body    = obj["eventData"] as? [String: Any],
              let bodyData = try? JSONSerialization.data(withJSONObject: body)
        else {
            Log.error("[WS:\(host)] malformed message — eventType/eventData missing or unparseable")
            return
        }

        let event = parse(type: type, data: bodyData)
        // Log unknown event types at INFO so on-device verification can identify
        // any group-relevant events that firmware emits under names we don't yet
        // recognise. Known types stay at verbose to avoid log spam.
        if case .unknown(let t) = event {
            Log.info("[WS:\(host)] unhandled event type: \(t)")
        } else {
            Log.verbose("[WS:\(host)] \(type)")
        }
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
        // Beolink (multiroom) topology changes. The Mozart Open API spec names
        // these `WebSocketEventBeolinkExperiencesResult` / `…PeersResult`, but
        // on-device traces show current firmware emits the generic
        // `WebSocketEventNotification` instead. Treat all three as topology
        // hints — the discovery service debounces (500 ms) and re-queries
        // /beolink/listeners, so over-triggering on unrelated notifications is
        // harmless: at worst we pay one extra listeners sweep per burst.
        case "WebSocketEventBeolinkExperiencesResult",
             "WebSocketEventBeolinkPeersResult",
             "WebSocketEventNotification":
            return .beolinkChanged
        default:
            return .unknown(type)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        do { return try decoder.decode(type, from: data) }
        catch { Log.error("[WS:\(host)] decode \(type) failed: \(error)"); return nil }
    }

    func disconnect() {
        Log.info("[WS:\(host)] disconnecting")
        cancelled = true
        pendingReconnect = false
        pathMonitor.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
    }
}
