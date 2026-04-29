import UIKit

/// Centralised haptic feedback — all haptic calls go through here (E-14 T-1401).
@MainActor
final class HapticEngine {
    static let shared = HapticEngine()
    private init() {}

    func commandRecognised() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    func sheetAppeared()     { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    func actionConfirmed()   { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    func errorOccurred()     { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    func limitReached()      { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
