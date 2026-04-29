import Combine

enum ConfirmationState: Equatable {
    case idle
    case pending(message: String)
}

/// Shows the confirmation sheet and waits for voice or tap confirmation.
/// If neither arrives within 10 seconds the request auto-cancels.
/// Feedback to the user is text-only (sheet + toasts); no TTS.
@MainActor
class ConfirmationCoordinator: ObservableObject {
    @Published var state: ConfirmationState = .idle

    var isPending: Bool { state != .idle }

    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask:  Task<Void, Never>?

    /// Shows the confirmation sheet with `message` and returns `true` if confirmed.
    func request(message: String) async -> Bool {
        state = .pending(message: message)
        return await withCheckedContinuation { cont in
            continuation = cont
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled else { return }
                Log.info("[Confirmation] timed out — auto-cancelling")
                resolve(result: false)
            }
        }
    }

    func confirm() {
        Log.info("[Confirmation] confirmed")
        resolve(result: true)
    }

    func cancel() {
        Log.info("[Confirmation] cancelled")
        resolve(result: false)
    }

    private func resolve(result: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        state = .idle
        continuation?.resume(returning: result)
        continuation = nil
    }
}
