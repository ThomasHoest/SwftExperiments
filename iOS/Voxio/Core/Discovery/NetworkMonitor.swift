import Foundation
import Network
import Observation

/// Wraps `NWPathMonitor` and exposes connectivity state as `@Observable` properties.
///
/// Defaults `isOnWifi` and `isAvailable` to `true` per ADR-002 D2 revision: this avoids an
/// offline-state flash during the brief window between view mount and the first
/// `pathUpdateHandler` callback (typically < 50 ms on device).
///
/// **Actor isolation:** the `pathUpdateHandler` runs on a private background queue.
/// State is forwarded to the main actor via `Task { @MainActor in self?.update(from: path) }`.
@Observable @MainActor final class NetworkMonitor {

    // MARK: - Public state

    /// `true` when the device has an active Wi-Fi path (status == .satisfied && interfaceType == .wifi).
    /// Defaults to `true` to prevent an offline-state flash on first mount.
    var isOnWifi: Bool = true

    /// `true` when any network path is satisfied (Wi-Fi or cellular).
    /// Informational only — not consumed by the F3 state machine.
    var isAvailable: Bool = true

    // MARK: - Private

    private let monitor = NWPathMonitor()
    private let queue   = DispatchQueue(label: "com.voxio.networkmonitor", qos: .utility)

    // MARK: - Lifecycle

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.update(from: path)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    // MARK: - Private helpers

    private func update(from path: NWPath) {
        let wifi      = path.status == .satisfied && path.usesInterfaceType(.wifi)
        let available = path.status == .satisfied
        isOnWifi    = wifi
        isAvailable = available
        Log.info("[NetworkMonitor] isOnWifi=\(isOnWifi) isAvailable=\(isAvailable)")
    }
}
