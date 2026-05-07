import Foundation
import CryptoKit

// MARK: - IncidentPayload

/// JSON payload sent to the telemetry backend for each new incident.
struct IncidentPayload: Encodable {
    let fingerprint: String      // 16 lowercase hex chars
    let appVersion: String
    let osVersion: String
    let deviceModel: String
    let contextLines: [String]
    let breadcrumbs: String
    let errorLine: String
}

// MARK: - IncidentReporter

/// Observes every `.error` log line, fingerprints it, deduplicates over 24 h,
/// and fire-and-forgets an upload to the telemetry backend over WiFi only.
///
/// Registered as a `LogListener` via `Log.addListener(IncidentReporter.shared)`
/// in `VoxioApp.init()`, **after** `FileLogListener.shared`.
@MainActor
final class IncidentReporter: LogListener {

    // MARK: - Singleton

    static let shared = IncidentReporter()

    // MARK: - Private constants

    /// Recursion guard token — lines containing this are never re-processed.
    /// Declared `nonisolated` so it can be read from the `nonisolated` `didLog` entry point.
    nonisolated static let internalTag = "[IncidentReporter:internal]"

    // MARK: - Config (loaded once — stored properties, not computed, so actor isolation is fine)

    private let telemetryHostname: String? = {
        Bundle.main.infoDictionary?["TELEMETRY_HOSTNAME"] as? String
    }()

    private let telemetryAPIKey: String? = {
        Bundle.main.infoDictionary?["TELEMETRY_API_KEY"] as? String
    }()

    // MARK: - Cached helpers

    private let anonymiser = LogAnonymiser()

    // MARK: - Init

    private init() {}

    // MARK: - LogListener

    /// `nonisolated` entry point required by the `LogListener` protocol.
    /// Hops to the main actor for dedup/assembly; then fires a detached task for upload.
    nonisolated func didLog(level: Log.Level, line: String, timestamp: Date) {
        // Step 1 — fast-exit for non-error lines and recursion guard.
        guard level == .error else { return }
        guard !line.contains(Self.internalTag) else { return }

        // Step 2 — hop to main actor.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.handleError(line: line, timestamp: timestamp)
        }
    }

    // MARK: - Main-actor work

    @MainActor
    private func handleError(line: String, timestamp: Date) {
        // Step 3 — anonymise the error line.
        let errorLine = anonymiser.anonymise(line)

        // Step 4 — compute fingerprint.
        let fingerprint = computeFingerprint(from: errorLine)

        // Step 5 — 24-hour dedup.
        let dedupKey = "incident_reported_" + fingerprint
        let now = Date().timeIntervalSince1970
        if let stored = UserDefaults.standard.object(forKey: dedupKey) as? Double,
           now - stored < 86_400 {
            return
        }
        // Write dedup timestamp before the WiFi check (per ADR Consequence 3).
        UserDefaults.standard.set(now, forKey: dedupKey)

        // Step 6 — capture context.
        let rawContextLines = FileLogListener.shared.ringBufferSnapshot()
        let contextLines = rawContextLines.map { anonymiser.anonymise($0) }
        let breadcrumbs = BreadcrumbTracker.shared.currentPath

        // Step 7 — assemble payload.
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let deviceModel = Self.deviceModel()

        let payload = IncidentPayload(
            fingerprint: fingerprint,
            appVersion: appVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            contextLines: contextLines,
            breadcrumbs: breadcrumbs,
            errorLine: errorLine
        )

        // Step 8 — fire-and-forget upload.
        // Capture config values on main actor before entering detached task.
        let hostname = telemetryHostname
        let apiKey = telemetryAPIKey
        Task.detached {
            await IncidentReporter.upload(payload, hostname: hostname, apiKey: apiKey)
        }
    }

    // MARK: - Fingerprinting

    @MainActor
    private func computeFingerprint(from errorLine: String) -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        // Strip timestamp prefix (first 23 chars: "yyyy-MM-dd HH:mm:ss.SSS") if present.
        let messagePortion: String
        if errorLine.count > 23, errorLine.prefix(4).allSatisfy(\.isNumber) {
            messagePortion = String(errorLine.dropFirst(23))
        } else {
            messagePortion = errorLine
        }

        // Strip all decimal digit runs to normalise numeric values.
        let digitPattern = try! NSRegularExpression(pattern: #"\d+"#)
        let normalised = digitPattern.stringByReplacingMatches(
            in: messagePortion,
            range: NSRange(messagePortion.startIndex..., in: messagePortion),
            withTemplate: ""
        )

        let input = normalised + appVersion
        let digest = SHA256.hash(data: Data(input.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    // MARK: - Upload (retry with backoff) — static so it can be called from a detached task

    private static func upload(
        _ payload: IncidentPayload,
        hostname: String?,
        apiKey: String?
    ) async {
        guard WiFiPathMonitor.shared.isWiFi else { return }

        guard let hostname, !hostname.isEmpty,
              let apiKey, !apiKey.isEmpty else { return }

        guard let url = URL(string: "https://\(hostname)/api/incidents/report") else { return }
        guard let body = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-telemetry-key")
        request.httpBody = body
        request.timeoutInterval = 30

        let delays: [TimeInterval] = [0, 2, 5, 10]
        var lastError: Error?

        for (attemptIndex, retryDelay) in delays.enumerated() {
            if attemptIndex > 0 {
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { return }

                if (200..<300).contains(http.statusCode) {
                    return
                }

                // HTTP 4xx — non-retryable.
                if (400..<500).contains(http.statusCode) {
                    logInternal("non-retryable HTTP \(http.statusCode) — giving up")
                    return
                }

                // HTTP 5xx — transient, fall through to retry.
                lastError = URLError(.badServerResponse)

            } catch let urlError as URLError {
                switch urlError.code {
                case .timedOut, .networkConnectionLost:
                    // Transient — retry.
                    lastError = urlError
                default:
                    // Non-transient — give up.
                    logInternal("non-retryable error: \(urlError.localizedDescription)")
                    return
                }
            } catch {
                logInternal("non-retryable error: \(error.localizedDescription)")
                return
            }
        }

        // All attempts exhausted.
        let errMsg = lastError?.localizedDescription ?? "unknown"
        logInternal("upload failed after retries: \(errMsg)")
    }

    // MARK: - Internal logging (recursion guard applied via the [IncidentReporter:internal] token)

    /// Logs an internal error message. Prefixed with `internalTag` to prevent recursive incident capture.
    private static func logInternal(_ message: String) {
        Log.error("\(internalTag) \(message)")
    }

    // MARK: - Device model

    private static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { rawPtr in
            let ptr = rawPtr.bindMemory(to: CChar.self)
            return String(cString: ptr.baseAddress!)
        }
    }
}
