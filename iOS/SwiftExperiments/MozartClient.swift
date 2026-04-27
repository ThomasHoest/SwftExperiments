import Foundation

class MozartClient {
    private let baseUrl: String
    private let session: URLSession

    init(host: String) {
        baseUrl = "http://\(host)/api/v1"
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        session = URLSession(configuration: config)
    }

    func get(_ path: String) async -> [String: Any]? {
        guard let url = URL(string: baseUrl + path) else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch { return nil }
    }
}
