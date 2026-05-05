import Foundation
import Network

private struct TelemetryUploadEvent: Encodable {
    let transcriptionAnonymised: String
    let intent: String
    let slotsAnonymised: [String: String]
    let parserPath: String
    let outcome: String
    let locale: String
    let timestamp: String
    let flags: [String]
}

private struct TelemetryUploadBatch: Encodable {
    let deviceId: String
    let appVersion: String
    let modelVersion: String
    let events: [TelemetryUploadEvent]
}

@MainActor
final class TelemetryUploader {

    // MARK: - DeletionResult

    enum DeletionResult {
        case success
        case pending
        case failed(Error)
    }

    // MARK: - Properties

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "telemetryEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "telemetryEnabled") }
    }

    private(set) var currentPath: NWPath?

    private let buffer: TelemetryBuffer
    private let deviceId: UUID
    private let pathMonitor = NWPathMonitor()
    private let session: URLSession

    private var baseURL: URL? {
        guard let host = Bundle.main.infoDictionary?["TELEMETRY_HOSTNAME"] as? String,
              !host.isEmpty else { return nil }
        return URL(string: "https://\(host)")
    }

    private var apiKey: String? {
        Bundle.main.infoDictionary?["TELEMETRY_API_KEY"] as? String
    }

    // MARK: - Init

    init(buffer: TelemetryBuffer) {
        self.buffer = buffer
        self.deviceId = KeychainDeviceID.readOrCreate()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.currentPath = path
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "telemetry.pathmonitor"))
    }

    // MARK: - attemptUploadIfDue

    func attemptUploadIfDue() async {
        guard isEnabled else {
            Log.info("[TelemetryUploader] skipping — telemetry disabled")
            return
        }

#if DEBUG
        Log.info("[TelemetryUploader] DEBUG — bypassing Wi-Fi and interval guards")
#else
        guard currentPath?.status == .satisfied else {
            Log.info("[TelemetryUploader] skipping — no network path")
            return
        }
        guard currentPath?.isExpensive == false else {
            Log.info("[TelemetryUploader] skipping — cellular/expensive network")
            return
        }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            Log.info("[TelemetryUploader] skipping — low power mode")
            return
        }
        let lastUpload = UserDefaults.standard.object(forKey: "lastTelemetryUploadDate") as? Date
        if let last = lastUpload, Date().timeIntervalSince(last) < 86_400 {
            Log.info("[TelemetryUploader] skipping — uploaded less than 24h ago")
            return
        }
#endif

        guard let url = baseURL?.appendingPathComponent("api/telemetry/batch") else {
            Log.error("[TelemetryUploader] missing base URL")
            return
        }
        guard let key = apiKey, !key.isEmpty else {
            Log.error("[TelemetryUploader] missing API key — set TELEMETRY_API_KEY in xcconfig")
            return
        }

        do {
            let batch = try buffer.pendingBatch(limit: 100)
            guard !batch.isEmpty else { return }

            let appVersion   = batch[0].appVersion
            let modelVersion = batch[0].modelVersion

            let payload = TelemetryUploadBatch(
                deviceId: deviceId.uuidString,
                appVersion: appVersion,
                modelVersion: modelVersion,
                events: batch.map { event in
                    TelemetryUploadEvent(
                        transcriptionAnonymised: event.transcriptionAnonymised,
                        intent:                  event.intent,
                        slotsAnonymised:         decodeSlotsDict(event.slotsAnonymised),
                        parserPath:              normalisedParserPath(event.parserPath),
                        outcome:                 event.outcome.rawValue,
                        locale:                  normalisedLocale(event.locale),
                        timestamp:               ISO8601DateFormatter().string(from: event.timestamp),
                        flags:                   flagStrings(event.flags)
                    )
                }
            )

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.httpBody = try JSONEncoder().encode(payload)

            Log.info("[TelemetryUploader] uploading \(batch.count) event(s) to \(url)")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            Log.info("[TelemetryUploader] server responded \(http.statusCode)")
            if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                Log.info("[TelemetryUploader] response body: \(body)")
            }
            guard (200..<300).contains(http.statusCode) else { return }

            let uploadedIds = batch.map(\.id)
            try buffer.markUploaded(uploadedIds)
            UserDefaults.standard.set(Date(), forKey: "lastTelemetryUploadDate")
            Log.info("[TelemetryUploader] marked \(uploadedIds.count) event(s) uploaded")
        } catch {
            Log.error("[TelemetryUploader] upload failed: \(error)")
        }
    }

    // MARK: - requestDeletion

    func requestDeletion() async -> DeletionResult {
        guard let url = baseURL?
            .appendingPathComponent("api/telemetry")
            .appendingPathComponent(deviceId.uuidString),
              let key = apiKey, !key.isEmpty else {
            return .pending
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(key, forHTTPHeaderField: "x-api-key")

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failed(URLError(.badServerResponse))
            }
            return .success
        } catch {
            Log.error("[TelemetryUploader] deletion request failed: \(error)")
            return .failed(error)
        }
    }

    // MARK: - Private helpers

    private func normalisedParserPath(_ raw: String) -> String {
        switch raw {
        case "PersonalisationTier": return "PersonalisationAlias"
        case "Stage1-fast":         return "KeywordRegex"
        case "TwoStageFallback", "Fallback": return "NLModel"
        default:                    return raw
        }
    }

    private func normalisedLocale(_ identifier: String) -> String {
        let parts = identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-")
        guard parts.count >= 2 else { return identifier }
        return "\(parts[0].lowercased())-\(parts[1].uppercased())"
    }

    private func flagStrings(_ flags: TelemetryFlags) -> [String] {
        var result: [String] = []
        if flags.contains(.likelyMisparse)     { result.append("likelyMisparse") }
        if flags.contains(.recoverableUnknown) { result.append("recoverableUnknown") }
        if flags.contains(.broadcast)          { result.append("broadcast") }
        return result
    }

    private func decodeSlotsDict(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }
}
