import Foundation

enum MozartError: Error, LocalizedError {
    case timeout
    case unreachable
    case invalidResponse
    case httpError(Int)
    case notFound

    var errorDescription: String? {
        switch self {
        case .timeout:         return "Could not reach the Bang & Olufsen service. Please try again"
        case .unreachable:     return "Could not reach the Bang & Olufsen service. Please try again"
        case .invalidResponse: return "Received an unexpected response from the speaker"
        case .httpError(let code): return "Speaker returned error \(code)"
        case .notFound:        return "The requested resource was not found on the speaker"
        }
    }
}
