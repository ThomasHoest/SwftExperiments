import Foundation

protocol LogListener: AnyObject {
    func didLog(level: Log.Level, line: String, timestamp: Date)
}

enum Log {

    // MARK: - Level

    enum Level: Int, Comparable {
        case verbose = 0
        case info    = 1
        case error   = 2
        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // MARK: - Global minimum (fast gate before dispatching to listeners)

    /// Change to .verbose to emit all messages to every listener.
    static var minimumLevel: Level = .info

    // MARK: - Listeners

    private static var _listeners: [any LogListener] = []
    private static let lock = NSLock()

    static func addListener(_ listener: any LogListener) {
        lock.withLock { _listeners.append(listener) }
    }

    // MARK: - Public API

    static func verbose(_ message: String) { emit(.verbose, message) }
    static func info   (_ message: String) { emit(.info,    message) }
    static func error  (_ message: String) { emit(.error,   message) }

    // MARK: - Private

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static func emit(_ level: Level, _ message: String) {
        guard level >= minimumLevel else { return }
        let now = Date()
        let tag: String
        switch level {
        case .verbose: tag = "VERBOSE"
        case .info:    tag = "INFO"
        case .error:   tag = "ERROR"
        }
        let line = "\(formatter.string(from: now)) [\(tag)] \(message)"
        let listeners = lock.withLock { _listeners }
        for listener in listeners {
            listener.didLog(level: level, line: line, timestamp: now)
        }
    }
}
