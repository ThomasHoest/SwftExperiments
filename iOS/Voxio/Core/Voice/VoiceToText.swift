import AVFoundation
import Speech
import UIKit

class VoiceToText {
    private let recorder = AVService(locale: LanguageService.shared.activeLanguage.locale)
    private var currentLanguage: Language = LanguageService.shared.activeLanguage

    /// Called with every partial transcription string (for live display).
    var onTranscript: ((String) -> Void)?
    /// Called with the RMS audio level on every buffer tick.
    var onAudioLevel: ((Float) -> Void)?
    /// Called once per finalised utterance with the raw transcript text.
    var onFinalTranscript: ((String) -> Void)?
    /// Called once per finalised utterance with the parsed command.
    var onCommand: ((VoiceCommand) -> Void)?

    /// Suspends transcription callbacks while keeping the audio engine alive.
    /// Call before TTS playback to prevent feedback loops.
    func pauseRecognition()  { recorder.mute() }

    /// Resumes transcription after a pause.
    func resumeRecognition() { recorder.unmute() }

    /// Resets the accumulated recognition buffer and starts a fresh request.
    func resetRecognitionBuffer() { recorder.resetBuffer() }

    /// Switches recognition locale and command parsing language.
    func setLanguage(_ language: Language) {
        currentLanguage = language
        recorder.setLocale(language.locale)
        Log.info("[VoiceToText] language → \(language.localeIdentifier)")
    }

    /// Starts the recording pipeline.
    ///
    /// Permission requests (SFSpeechRecognizer.requestAuthorization and
    /// AVAudioApplication.requestRecordPermission) have moved to
    /// OnboardingView.handleCTA() per E-38 ADR. By the time this method is
    /// called, permissions are already determined.
    func start(onStatus: @escaping (String) -> Void) {
        let ui = UIStrings.forLanguage(currentLanguage)
        onStatus(ui.initialisingMic)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let ui = UIStrings.forLanguage(self.currentLanguage)

            // Check current authorization state without re-requesting
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            let micGranted = AVAudioApplication.shared.recordPermission == .granted

            guard micGranted, speechStatus == .authorized else {
                onStatus(ui.micAccessDenied)
                return
            }

            self.recorder.onTranscription = { [weak self] text, isFinal in
                self?.onTranscript?(text)
                if isFinal, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    self?.onFinalTranscript?(text)
                }
            }
            self.recorder.onAudioLevel = { [weak self] level in
                self?.onAudioLevel?(level)
            }

            do {
                try self.recorder.startRecording()
                onStatus(ui.listening)
            } catch {
                onStatus(ui.micUnavailable)
            }

            // T-0312 — stop when app moves to background
            NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.recorder.stopRecording()
                onStatus(UIStrings.forLanguage(self?.currentLanguage ?? .english).backgroundPaused)
            }

            // Resume when returning to foreground
            NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                try? self?.recorder.startRecording()
                onStatus(UIStrings.forLanguage(self?.currentLanguage ?? .english).listening)
            }
        }
    }
}
