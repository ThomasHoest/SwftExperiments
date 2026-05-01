import Foundation

class BNREvents {
    private let host: String
    private let port: Int
    private let decoder = JSONDecoder()
    private let pollSession: URLSession
    private var loopTask: Task<Void, Never>?
    private var cancelled = false

    var onEvent: ((BNREvent) -> Void)?

    init(host: String, port: Int = 8080) {
        self.host = host
        self.port = port
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.pollSession = URLSession(configuration: config)
    }

    // Used in unit tests to inject a URLProtocol-backed session.
    init(host: String, port: Int = 8080, session: URLSession) {
        self.host = host
        self.port = port
        self.pollSession = session
    }

    func connect() {
        cancelled = false
        loopTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func disconnect() {
        Log.info("[BNR-LP:\(host)] disconnecting")
        cancelled = true
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: - Long-poll loop

    private func pollLoop() async {
        var backoffSeconds: Double = 1

        while !cancelled && !Task.isCancelled {
            do {
                let notification = try await fetchNextNotification()
                backoffSeconds = 1   // reset on success
                if let event = normalise(notification) {
                    onEvent?(event)
                }
            } catch {
                guard !cancelled && !Task.isCancelled else { return }
                Log.info("[BNR-LP:\(host)] poll error (\(error.localizedDescription)) — retrying in \(Int(backoffSeconds))s")
                try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                backoffSeconds = min(backoffSeconds * 2, 30)
            }
        }
    }

    private func fetchNextNotification() async throws -> BNRNotification {
        guard let url = URL(string: "http://\(host):\(port)/BeoNotify/Notifications") else {
            throw SpeakerError.invalidResponse
        }
        Log.verbose("[BNR-LP:\(host)] GET /BeoNotify/Notifications")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        do {
            let (data, response) = try await pollSession.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw SpeakerError.httpError(status)
            }
            do {
                return try decoder.decode(BNRNotification.self, from: data)
            } catch {
                let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                Log.error("[BNR-LP:\(host)] decode error: \(error) | raw: \(raw)")
                throw SpeakerError.invalidResponse
            }
        } catch let error as SpeakerError {
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut:
                throw SpeakerError.timeout
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet,
                 .cannotFindHost, .dnsLookupFailed:
                throw SpeakerError.unreachable
            default:
                throw SpeakerError.unreachable
            }
        }
    }
}
