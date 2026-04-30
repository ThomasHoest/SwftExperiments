import Combine
import Foundation
import UIKit

enum Resolution { case fired, cancelled }
enum CancelReason { case userTap, userVoice, interruption }

/// State for the auto-execute countdown confirmation flow.
enum ConfirmationState: Equatable {
    case idle
    case countdown(readBack: String)
}

/// Presents a 3-second countdown before auto-executing a voice command.
/// The user can cancel via tap or voice; the countdown can also be interrupted
/// programmatically (e.g. sheet dismissed by system gesture).
@MainActor
class ConfirmationCoordinator: ObservableObject {
    @Published var state: ConfirmationState = .idle
    @Published var secondsRemaining: Int = 3

    var isPending: Bool { state != .idle }

    private var countdownTask: Task<Void, Never>?
    private var pendingOnResolved: ((Resolution) -> Void)?

    /// Starts a 3-second countdown, then fires `action` unless cancelled first.
    /// Returns immediately; `onResolved` is called with `.fired` or `.cancelled`.
    func startCountdown(
        action: @escaping () async -> Void,
        readBack: String,
        onResolved: @escaping (Resolution) -> Void
    ) {
        // Cancel any in-flight countdown silently (new command supersedes old)
        countdownTask?.cancel()
        countdownTask = nil
        pendingOnResolved = nil

        secondsRemaining = 3
        state = .countdown(readBack: readBack)
        pendingOnResolved = onResolved

        countdownTask = Task { [weak self] in
            guard let self else { return }

            // Tick from 3 down to 1 (display each value for 1 second)
            for tick in stride(from: 3, through: 1, by: -1) {
                await MainActor.run { self.secondsRemaining = tick }
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }

            if Task.isCancelled { return }

            // Fire — success haptic, clear state, then execute action
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.state = .idle
                self.countdownTask = nil
            }

            let resolvedCallback = await MainActor.run { () -> ((Resolution) -> Void)? in
                let cb = self.pendingOnResolved
                self.pendingOnResolved = nil
                return cb
            }

            await action()
            resolvedCallback?(.fired)
        }
    }

    /// Cancels the countdown.
    /// `.userTap` / `.userVoice` → error haptic. `.interruption` → no haptic.
    func cancelCountdown(reason: CancelReason) {
        guard isPending else { return }

        countdownTask?.cancel()
        countdownTask = nil

        let callback = pendingOnResolved
        pendingOnResolved = nil

        if reason == .userTap || reason == .userVoice {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }

        state = .idle
        callback?(.cancelled)
    }
}
