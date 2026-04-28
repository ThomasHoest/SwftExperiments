import AVFoundation
import Speech
import UIKit

class VoiceToText {
    private let recorder = AVService()
    private let parser   = CommandParser()

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

    func start(onStatus: @escaping (String) -> Void) {
        onStatus("Initialising microphone…")

        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard granted, speechStatus == .authorized else {
                        onStatus("Microphone access denied")
                        return
                    }

                    self.recorder.onTranscription = { [weak self] text, isFinal in
                        self?.onTranscript?(text)
                        if isFinal, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                            let command = self?.parser.parse(text) ?? .unknown(text)
                            Log.info("[Voice] \(command)")
                            self?.onFinalTranscript?(text)
                            self?.onCommand?(command)
                        }
                    }
                    self.recorder.onAudioLevel = { [weak self] level in
                        self?.onAudioLevel?(level)
                    }

                    do {
                        try self.recorder.startRecording()
                        onStatus("Listening…")
                    } catch {
                        onStatus("Microphone unavailable")
                    }

                    // T-0312 — stop when app moves to background
                    NotificationCenter.default.addObserver(
                        forName: UIApplication.didEnterBackgroundNotification,
                        object: nil,
                        queue: .main
                    ) { [weak self] _ in
                        self?.recorder.stopRecording()
                        onStatus("Paused")
                    }

                    // Resume when returning to foreground
                    NotificationCenter.default.addObserver(
                        forName: UIApplication.willEnterForegroundNotification,
                        object: nil,
                        queue: .main
                    ) { [weak self] _ in
                        try? self?.recorder.startRecording()
                        onStatus("Listening…")
                    }
                }
            }
        }
    }
}
