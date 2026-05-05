import Foundation
import Network

// TODO: align with backend spec
private struct TelemetryUploadBatch: Codable {
    let deviceId: String
    let events: [[String: String]]
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
        guard let raw = Bundle.main.infoDictionary?["TELEMETRY_BASE_URL"] as? String else { return nil }
        return URL(string: raw)
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
        // In debug builds: skip network and interval guards so every call uploads immediately.
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

        guard let url = baseURL?.appendingPathComponent("telemetry/events") else { return }

        do {
            let batch = try buffer.pendingBatch(limit: 100)
            guard !batch.isEmpty else { return }

            let payload = TelemetryUploadBatch(
                deviceId: deviceId.uuidString,
                events: batch.map { event in
                    [
                        "id":                      event.id.uuidString,
                        "transcriptionAnonymised": event.transcriptionAnonymised,
                        "intent":                  event.intent,
                        "slotsAnonymised":         event.slotsAnonymised,
                        "parserPath":              event.parserPath,
                        "outcome":                 event.outcome.rawValue,
                        "appVersion":              event.appVersion,
                        "modelVersion":            event.modelVersion,
                        "locale":                  event.locale,
                        "timestamp":               ISO8601DateFormatter().string(from: event.timestamp),
                        "speakerId":               event.speakerId
                    ]
                }
            )

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        // TODO: verify endpoint with backend team
        guard let url = baseURL?
            .appendingPathComponent("telemetry")
            .appendingPathComponent(deviceId.uuidString) else {
            return .pending
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

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
}
