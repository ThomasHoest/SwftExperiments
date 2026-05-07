import Foundation
import Network

/// A shared singleton wrapping `NWPathMonitor` that exposes a simple `isWiFi` flag.
/// `IncidentReporter` consults this before every upload; only on-device WiFi
/// paths are considered eligible (matching the ADR-006 WiFi-only upload policy).
///
/// - Note: `stop()` is provided for test teardown only. Production code must not call it.
public final class WiFiPathMonitor {

    // MARK: - Singleton

    public static let shared = WiFiPathMonitor()

    // MARK: - Private state

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "voxio.wifipath", qos: .utility)
    private let lock = NSLock()
    private var _isWiFi: Bool = false
    private var started: Bool = false

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Current WiFi status. Protected by `lock` so safe to call from any thread/actor.
    public var isWiFi: Bool {
        lock.withLock { _isWiFi }
    }

    /// Starts monitoring. Idempotent — calling more than once has no effect.
    public func start() {
        let alreadyStarted = lock.withLock { () -> Bool in
            guard !started else { return true }
            started = true
            return false
        }
        guard !alreadyStarted else { return }

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let wifi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            self.lock.withLock { self._isWiFi = wifi }
        }
        monitor.start(queue: queue)
    }

    /// Cancels the underlying monitor. Intended for test teardown only.
    public func stop() {
        monitor.cancel()
        lock.withLock {
            _isWiFi = false
            started = false
        }
    }
}
