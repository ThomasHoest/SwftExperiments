import Foundation

final class ConsoleLogListener: LogListener {
    private let minimumLevel: Log.Level

    init(minimumLevel: Log.Level = .info) {
        self.minimumLevel = minimumLevel
    }

    func didLog(level: Log.Level, line: String, timestamp: Date) {
        guard level >= minimumLevel else { return }
        print(line)
    }
}
