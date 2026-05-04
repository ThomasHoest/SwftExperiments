import Foundation

enum SpeakerError: Error {
    case timeout
    case unreachable
    case httpError(Int)
    case invalidResponse
}

extension SpeakerError {
    static func from(_ mozartError: MozartError) -> SpeakerError {
        switch mozartError {
        case .timeout:              return .timeout
        case .unreachable:          return .unreachable
        case .httpError(let code):  return .httpError(code)
        case .invalidResponse:      return .invalidResponse
        case .notFound:             return .httpError(404)
        }
    }
}
