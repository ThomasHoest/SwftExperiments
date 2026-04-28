import AVFoundation
import Speech

class VoiceToText {
    private let recorder = AVService()

    var onTranscript: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

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
                    self.recorder.onTranscription = { [weak self] text, _ in
                        self?.onTranscript?(text)
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
                }
            }
        }
    }
}
