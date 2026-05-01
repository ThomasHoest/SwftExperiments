import Foundation

private enum LogLevel: Int {
    case verbose = 0
    case info    = 1
    case error   = 2
}

// ── Change this to adjust what gets printed ───────────────────────────────────
private let currentLevel: LogLevel = .info

enum Log {
    static func verbose(_ message: String) { emit(.verbose, message) }
    static func info   (_ message: String) { emit(.info,    message) }
    static func error  (_ message: String) { emit(.error,   message) }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static func emit(_ level: LogLevel, _ message: String) {
        guard level.rawValue >= currentLevel.rawValue else { return }
        let tag: String
        switch level {
        case .verbose: tag = "VERBOSE"
        case .info:    tag = "INFO"
        case .error:   tag = "ERROR"
        }
        let ts = formatter.string(from: Date())
        print("\(ts) [\(tag)] \(message)")
    }
}
