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

    // MARK: - Drag-to-join haptics (E-59 prerequisite)

    /// Fired on long-press hold (drag initiated). Medium impact.
    func dragLifted()           { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }

    /// Fired when the drag ghost enters a session card's drop-zone bounds. Light impact.
    func dragEnteredDropZone()  { UIImpactFeedbackGenerator(style: .light).impactOccurred() }

    /// Fired when a drag is released outside any valid drop destination. Warning notification.
    /// Note: SwiftUI's .draggable does not expose a cancel callback in iOS 16/17;
    /// iOS 26 availability unverified. This is fired from a best-effort observer (T-5908).
    func dragCancelled()        { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
