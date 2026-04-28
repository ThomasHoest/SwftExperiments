import Combine
import CoreMotion
import SwiftUI

@MainActor
class MotionManager: ObservableObject {
    @Published var roll: Double = 0
    @Published var pitch: Double = 0

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: OperationQueue()) { [weak self] motion, _ in
            guard let attitude = motion?.attitude else { return }
            let r = attitude.roll
            let p = attitude.pitch
            Task { @MainActor [weak self] in
                self?.roll = r
                self?.pitch = p
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
