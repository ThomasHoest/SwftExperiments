import Foundation

class MozartEvents {
    private let host: String
    private let url: URL
    private var task: URLSessionWebSocketTask?
    private var retryCount = 0
    private var cancelled = false

    var onEvent: ((String, [String: Any]) -> Void)?

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
        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["eventType"] as? String,
              let body = obj["eventData"] as? [String: Any]
        else { return }
        Log.verbose("[WS:\(host)] event: \(type) \(body)")
        onEvent?(type, body)
    }

    func disconnect() {
        Log.info("[WS:\(host)] disconnecting")
        cancelled = true
        task?.cancel(with: .normalClosure, reason: nil)
    }
}
