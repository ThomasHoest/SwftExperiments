import Foundation

class MozartClient {
    private let host: String
    private let baseUrl: String
    private let session: URLSession

    init(host: String) {
        self.host   = host
        baseUrl     = "http://\(host)/api/v1"
        let config  = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        session     = URLSession(configuration: config)
    }

    func get(_ path: String) async -> [String: Any]? {
        guard let url = URL(string: baseUrl + path) else { return nil }
        Log.info("[\(host)] GET \(path)")
        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.error("[\(host)] GET \(path) → unexpected response format")
                return nil
            }
            Log.info("[\(host)] GET \(path) → \(json.keys.sorted().joined(separator: ", "))")
            return json
        } catch {
            Log.error("[\(host)] GET \(path) failed: \(error.localizedDescription)")
            return nil
        }
    }
}
