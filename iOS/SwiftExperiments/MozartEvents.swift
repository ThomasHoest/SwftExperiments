import Foundation

class MozartEvents {
    private let url: URL
    private var task: URLSessionWebSocketTask?
    private var retryCount = 0
    private var cancelled = false

    var onEvent: ((String, [String: Any]) -> Void)?

    init(host: String) {
        url = URL(string: "ws://\(host):9339/")!
    }

    func connect() {
        cancelled = false
        openSocket()
    }

    private func openSocket() {
        guard !cancelled else { return }
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
            case .failure:
                let delay = min(pow(2.0, Double(self.retryCount)), 30.0)
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
        onEvent?(type, body)
    }

    func disconnect() {
        cancelled = true
        task?.cancel(with: .normalClosure, reason: nil)
    }
}
