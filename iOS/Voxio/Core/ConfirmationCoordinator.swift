import AVFoundation
import Combine

enum ConfirmationState: Equatable {
    case idle
    case pending(message: String)
}

/// Speaks a confirmation message, shows the confirmation sheet, and waits for
/// voice or tap confirmation. If neither arrives within 10 seconds, auto-cancels.
@MainActor
class ConfirmationCoordinator: NSObject, ObservableObject {
    @Published var state: ConfirmationState = .idle

    var isPending: Bool { state != .idle }

    // Wired by HomeView to pause/resume the mic around TTS playback.
    var onSpeechWillStart: (() -> Void)?
    var onSpeechDidEnd:    (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask:  Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Speaks `message`, waits for voice/tap/timeout, and returns `true` if confirmed.
    func request(message: String) async -> Bool {
        state = .pending(message: message)
        speak(message)
        return await withCheckedContinuation { cont in
            continuation = cont
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled else { return }
                Log.info("[Confirmation] timed out — auto-cancelling")
                resolve(result: false)
                speak("Action cancelled")
            }
        }
    }

    /// Speaks `text` for post-action completion feedback (no confirmation wait).
    func announce(_ text: String) {
        speak(text)
    }

    func confirm() {
        Log.info("[Confirmation] confirmed")
        resolve(result: true)
    }

    func cancel() {
        Log.info("[Confirmation] cancelled")
        resolve(result: false)
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private func resolve(result: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        state = .idle
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func speak(_ text: String) {
        onSpeechWillStart?()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        // T-0802 — Samantha voice; fall back to system English
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.en-US.Samantha")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}

// ── AVSpeechSynthesizerDelegate ───────────────────────────────────────────────

extension ConfirmationCoordinator: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.onSpeechDidEnd?()
        }
    }
}
