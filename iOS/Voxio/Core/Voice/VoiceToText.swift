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

    /// Switches recognition locale and command parsing language.
    func setLanguage(_ language: Language) {
        currentLanguage = language
        recorder.setLocale(language.locale)
        Log.info("[VoiceToText] language → \(language.localeIdentifier)")
    }

    func start(onStatus: @escaping (String) -> Void) {
        let ui = UIStrings.forLanguage(currentLanguage)
        onStatus(ui.initialisingMic)

        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let ui = UIStrings.forLanguage(self.currentLanguage)
                    guard granted, speechStatus == .authorized else {
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
    }
}
