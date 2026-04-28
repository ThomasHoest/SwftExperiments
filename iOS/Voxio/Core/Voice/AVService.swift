import AVFoundation
import Speech

/// Wraps `AVAudioEngine` + `SFSpeechRecognizer` into a continuous listen loop.
///
/// Each utterance is bounded by silence detection: when the RMS level stays
/// below `silenceThreshold` for `silenceDuration` seconds after speech has
/// been heard, the current recognition request is finalised (`isFinal: true`)
/// and a fresh request is started automatically.
class AVService {
    private let engine      = AVAudioEngine()
    private let recognizer  = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var request:    SFSpeechAudioBufferRecognitionRequest?
    private var task:       SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var hasSpeech   = false
    private var stopped     = true

    // T-0303 — silence gate
    private let silenceThreshold: Float        = 0.01
    private let silenceDuration:  TimeInterval = 1.5

    var onTranscription: ((_ text: String, _ isFinal: Bool) -> Void)?
    var onAudioLevel:    ((Float) -> Void)?

    // ── Public ────────────────────────────────────────────────────────────────

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)
        stopped = false
        installTap()
        try engine.start()
        startRequest()
    }

    func stopRecording() {
        stopped = true
        silenceTimer?.invalidate()
        silenceTimer = nil
        hasSpeech = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
    }

    // ── Private ───────────────────────────────────────────────────────────────

    /// Installs a single audio tap that feeds audio to the current request
    /// and drives the RMS/silence logic. Called once; the engine stays running
    /// between utterances while only the recognition request is recycled.
    private func installTap() {
        let inputNode = engine.inputNode
        let format    = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            guard let self, let data = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            let rms    = Float(sqrt(
                (0..<frames).reduce(0.0) { $0 + Double(data[$1] * data[$1]) } / Double(frames)
            ))
            self.onAudioLevel?(rms)
            DispatchQueue.main.async { self.trackSilence(rms: rms) }
        }
        engine.prepare()
    }

    /// Starts a fresh `SFSpeechAudioBufferRecognitionRequest`. Safe to call
    /// while the engine is running — the existing tap feeds audio into the
    /// new request immediately.
    private func startRequest() {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self, !self.stopped else { return }

            if let result {
                self.onTranscription?(result.bestTranscription.formattedString, result.isFinal)
                if result.isFinal {
                    self.hasSpeech = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.startRequest() }
                }
            } else if error != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.startRequest() }
            }
        }
    }

    /// Called on the main thread from the audio tap. Resets the silence timer
    /// when speech is detected; starts it when silence follows speech.
    private func trackSilence(rms: Float) {
        if rms > silenceThreshold {
            hasSpeech = true
            silenceTimer?.invalidate()
            silenceTimer = nil
        } else if hasSpeech, silenceTimer == nil {
            silenceTimer = Timer.scheduledTimer(
                withTimeInterval: silenceDuration,
                repeats: false
            ) { [weak self] _ in
                self?.silenceTimer = nil
                self?.request?.endAudio()
            }
        }
    }
}
