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
        Log.info("[BNR-LP:\(host)] pollLoop started")

        while !cancelled && !Task.isCancelled {
            do {
                let count = try await streamNotifications()
                backoffSeconds = 1
                Log.info("[BNR-LP:\(host)] stream ended after \(count) notification(s) — re-issuing")
                if count == 0 {
                    // Empty stream — small pause to avoid hot loop if speaker misbehaves.
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            } catch {
                guard !cancelled && !Task.isCancelled else { return }
                Log.info("[BNR-LP:\(host)] poll error (\(error.localizedDescription)) — retrying in \(Int(backoffSeconds))s")
                try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                backoffSeconds = min(backoffSeconds * 2, 30)
            }
        }
        Log.info("[BNR-LP:\(host)] pollLoop exited (cancelled=\(cancelled))")
    }

    /// Streams newline-delimited JSON notifications from `/BeoNotify/Notifications`.
    /// Each line is decoded and emitted to `onEvent` as soon as it arrives — no waiting
    /// for the response to close. Returns the count of decoded notifications when the
    /// server closes the stream (or `?timeout=` fires).
    private func streamNotifications() async throws -> Int {
        // ?timeout=55 keeps the speaker holding the connection for up to 55s of idle time.
        // Headers per BeoNetRemote reference (api-reference-bnr-client.md §Connection model).
        guard let url = URL(string: "http://\(host):\(port)/BeoNotify/Notifications?timeout=55") else {
            throw SpeakerError.invalidResponse
        }
        Log.info("[BNR-LP:\(host)] fetch start (streaming)")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("keep-alive", forHTTPHeaderField: "Connection")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (bytes, response) = try await pollSession.bytes(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                Log.info("[BNR-LP:\(host)] fetch returned status:\(status)")
                throw SpeakerError.httpError(status)
            }

            var count = 0
            for try await line in bytes.lines {
                if cancelled || Task.isCancelled { break }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
                do {
                    let n = try decoder.decode(BNRNotification.self, from: lineData)
                    let type = n.notification.type
                    let isNoisy = type == "SOFTWARE_UPDATE_STATE" || type == "PROGRESS_INFORMATION"
                    if isNoisy {
                        Log.verbose("[BNR-LP:\(host)] notification \(type) | raw: \(trimmed)")
                    } else {
                        Log.info("[BNR-LP:\(host)] notification \(type) | raw: \(trimmed)")
                    }
                    count += 1
                    if let event = normalise(n) {
                        onEvent?(event)
                    }
                } catch {
                    Log.error("[BNR-LP:\(host)] decode error: \(error) | raw: \(trimmed)")
                }
            }
            return count
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
