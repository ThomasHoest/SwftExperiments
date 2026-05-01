import Combine
import Foundation

/// Owns all transcript state and clearing logic.
///
/// Clearing triggers (all log to [Transcript]):
///   • Idle timeout   — no update received for 4 seconds
///   • Post-command   — clearAfterCommand() delays 5 s then clears
///   • Tap            — clearNow() clears immediately
@MainActor
final class TranscriptController: ObservableObject {

    @Published var text: String = ""

    /// Called after the transcript is wiped — wire to `voiceToText.resumeRecognition()`.
    var onClear: (() -> Void)?
    /// Called when the idle timer expires with non-empty text — wire to the same
    /// handler as `voiceToText.onFinalTranscript` so background noise doesn't
    /// swallow valid commands.
    var onForceFinal: ((String) -> Void)?

    private weak var coordinator: ConfirmationCoordinator?
    private var idleTask: Task<Void, Never>?

    private let idleTimeout  = Duration.seconds(4)
    private let postCmdDelay = Duration.seconds(5)

    func configure(coordinator: ConfirmationCoordinator) {
        self.coordinator = coordinator
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Called on every partial recognition result.
    func update(_ newText: String) {
        text = newText
        Log.verbose("[Transcript] update — '\(newText)'")
        scheduleIdle(after: idleTimeout, reason: "idle timeout")
    }

    /// Clears immediately — call from tap gesture or interruption.
    func clearNow() {
        Log.info("[Transcript] clearNow — was: '\(text)'")
        clear()
    }

    /// Clears after a 5-second delay — call after a command is dispatched.
    func clearAfterCommand() {
        Log.info("[Transcript] clearAfterCommand scheduled — text: '\(text)'")
        scheduleIdle(after: postCmdDelay, reason: "post-command delay")
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private func clear() {
        idleTask?.cancel()
        idleTask = nil
        guard !text.isEmpty else {
            Log.verbose("[Transcript] clear called but already empty")
            return
        }
        Log.info("[Transcript] CLEARED '\(text)'")
        text = ""
        onClear?()
    }

    private func scheduleIdle(after delay: Duration, reason: String) {
        idleTask?.cancel()
        idleTask = Task {
            Log.verbose("[Transcript] idle timer started (\(reason), \(delay))")
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                Log.verbose("[Transcript] idle timer cancelled (\(reason))")
                return
            }

            if let coordinator, coordinator.isPending {
                Log.info("[Transcript] idle fired — countdown pending, waiting")
                while let coordinator = self.coordinator, coordinator.isPending {
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: .seconds(1))
                }
                guard !Task.isCancelled else { return }
            }

            if reason == "idle timeout", !self.text.isEmpty, let onForceFinal = self.onForceFinal {
                Log.info("[Transcript] idle timeout — force-parsing '\(self.text)'")
                onForceFinal(self.text)
            } else {
                Log.info("[Transcript] idle fired (\(reason)) — CLEARING '\(self.text)'")
                clear()
            }
        }
    }

}
