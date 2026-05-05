import Foundation

final class FileLogListener: LogListener {

    // MARK: - Shared instance

    static let shared = FileLogListener(flushInterval: 30, bufferCapacity: 500)

    // MARK: - Configuration

    let flushInterval: TimeInterval
    let bufferCapacity: Int

    // MARK: - Private state

    private let queue = DispatchQueue(label: "voxio.filelog", qos: .utility)
    private var buffer: [String] = []
    private var flushTimer: DispatchSourceTimer?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    // MARK: - Init

    init(flushInterval: TimeInterval = 30, bufferCapacity: Int = 500) {
        self.flushInterval = flushInterval
        self.bufferCapacity = bufferCapacity
        setupTimer()
    }

    // MARK: - LogListener

    func didLog(level: Log.Level, line: String, timestamp: Date) {
        guard level >= .info else { return }
        let fileTimestamp = Self.timestampFormatter.string(from: timestamp)
        // Replace the short HH:mm:ss.SSS prefix with a full yyyy-MM-dd HH:mm:ss.SSS prefix
        let fileLine: String
        if line.count > 12, line.first?.isNumber == true {
            fileLine = fileTimestamp + line.dropFirst(12)
        } else {
            fileLine = line
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.buffer.append(fileLine)
            if self.buffer.count >= self.bufferCapacity {
                self.flush()
            }
        }
    }

    // MARK: - Flush

    /// Flushes the in-memory buffer to disk. Must be called on `queue`.
    private func flush() {
        guard !buffer.isEmpty else { return }
        let lines = buffer
        buffer.removeAll(keepingCapacity: true)
        writeToFile(lines)
    }

    /// Synchronously flushes the buffer. Safe to call from any thread (including MainActor).
    func flushSync() {
        queue.sync { flush() }
    }

    // MARK: - File access

    func logFileURLs() -> [URL] {
        let dir = logsDirectory()
        let all = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        return all
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func pruneOldLogs(keepingDays: Int = 7) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let cutoff = Calendar.current.date(byAdding: .day, value: -keepingDays, to: Date()) else { return }
            let cutoffStr = Self.dateFormatter.string(from: cutoff)
            for url in self.logFileURLs() {
                let stem = url.deletingPathExtension().lastPathComponent
                let dateStr = stem.hasPrefix("voxio-") ? String(stem.dropFirst(6)) : stem
                if dateStr < cutoffStr {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    // MARK: - Private helpers

    private func setupTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        timer.setEventHandler { [weak self] in self?.flush() }
        timer.resume()
        flushTimer = timer
    }

    private func logsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func logFileURL(for date: Date = Date()) -> URL {
        logsDirectory().appendingPathComponent("voxio-\(Self.dateFormatter.string(from: date)).log")
    }

    private func writeToFile(_ lines: [String]) {
        let url = logFileURL()
        guard let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
