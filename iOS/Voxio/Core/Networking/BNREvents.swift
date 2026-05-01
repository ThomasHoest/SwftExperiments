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
                let notifications = try await fetchNotifications()
                backoffSeconds = 1
                for notification in notifications {
                    if let event = normalise(notification) {
                        onEvent?(event)
                    }
                }
            } catch {
                guard !cancelled && !Task.isCancelled else { return }
                Log.info("[BNR-LP:\(host)] poll error (\(error.localizedDescription)) — retrying in \(Int(backoffSeconds))s")
                try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                backoffSeconds = min(backoffSeconds * 2, 30)
            }
        }
    }

    private func fetchNotifications() async throws -> [BNRNotification] {
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
            // The endpoint returns one or more newline-delimited JSON objects per response.
            let lines = (String(data: data, encoding: .utf8) ?? "")
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let results: [BNRNotification] = lines.compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                do {
                    return try decoder.decode(BNRNotification.self, from: lineData)
                } catch {
                    Log.error("[BNR-LP:\(host)] decode error: \(error) | raw: \(line)")
                    return nil
                }
            }
            guard !results.isEmpty else { throw SpeakerError.invalidResponse }
            return results
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
