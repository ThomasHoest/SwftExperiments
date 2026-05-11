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
    private var recognizer: SFSpeechRecognizer
    private var request:    SFSpeechAudioBufferRecognitionRequest?
    private var task:       SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var hasSpeech        = false
    private var stopped          = true
    private var isMuted          = false
    private var requestGeneration = 0

    // AVAudioSession.setActive() and AVAudioEngine.start() perform synchronous
    // IPC internally. Routing them through a dedicated serial queue keeps that
    // IPC off Swift's cooperative thread pool and suppresses unsafeForcedSync.
    private let audioQueue = DispatchQueue(label: "com.voxio.audio", qos: .userInitiated)

    init(locale: Locale = Locale(identifier: "en-US")) {
        recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    }

    // T-0303 — silence gate
    private let silenceThreshold: Float        = 0.01
    private let silenceDuration:  TimeInterval = 0.8

    var onTranscription: ((_ text: String, _ isFinal: Bool) -> Void)?
    var onAudioLevel:    ((Float) -> Void)?

    // ── Public ────────────────────────────────────────────────────────────────

    /// Swaps the speech recognizer locale, restarting recording if it was active.
    func setLocale(_ locale: Locale) {
        guard let newRecognizer = SFSpeechRecognizer(locale: locale) else {
            Log.info("[AVService] setLocale: no recognizer available for \(locale.identifier)")
            return
        }
        let wasRunning = !stopped
        if wasRunning { stopRecording() }
        recognizer = newRecognizer
        Log.info("[AVService] locale → \(locale.identifier)")
        if wasRunning {
            do { try startRecording() }
            catch { Log.error("[AVService] setLocale: restart recording failed: \(error)") }
        }
    }

    func startRecording() throws {
        var startError: Error?
        audioQueue.sync {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
                try session.setActive(true)
            } catch {
                startError = error
                return
            }
            stopped = false
            installTap()
            do { try engine.start() }
            catch { startError = error }
        }
        if let err = startError { throw err }
        startRequest()
    }

    func stopRecording() {
        stopped = true
        // Invalidate timer on the thread it was scheduled on (main).
        silenceTimer?.invalidate()
        silenceTimer = nil
        hasSpeech = false
        // Capture then nil out so the tap closure sees nil immediately.
        let req = request; let tsk = task
        request = nil;     task    = nil
        req?.endAudio()
        tsk?.cancel()
        audioQueue.async {
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
        }
    }

    /// Suspends recognition while the engine keeps running — used to prevent
    /// TTS output from being transcribed as voice commands.
    func mute() {
        guard !isMuted else { return }
        isMuted = true
        silenceTimer?.invalidate()
        silenceTimer = nil
        hasSpeech = false
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        Log.verbose("[AVService] muted")
    }

    /// Resumes recognition with a fresh request after a mute period.
    func unmute() {
        guard isMuted else { return }
        isMuted = false
        startRequest()
        Log.verbose("[AVService] unmuted")
    }

    // ── Private ───────────────────────────────────────────────────────────────

    /// Installs a single audio tap that feeds audio to the current request
    /// and drives the RMS/silence logic. Called once on `audioQueue`; the
    /// engine stays running between utterances while only the recognition
    /// request is recycled.
    private func installTap() {
        let inputNode = engine.inputNode
        let format    = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, !self.stopped else { return }
            // Guard zero-frame buffers that appear during engine startup —
            // appending them triggers an mDataByteSize assertion in AVAudioBuffer.
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            if !self.isMuted { self.request?.append(buffer) }
            guard let data = buffer.floatChannelData?[0] else { return }
            let rms = Float(sqrt(
                (0..<frames).reduce(0.0) { $0 + Double(data[$1] * data[$1]) } / Double(frames)
            ))
            self.onAudioLevel?(rms)
            if !self.isMuted { DispatchQueue.main.async { self.trackSilence(rms: rms) } }
        }
        engine.prepare()
    }

    /// Cancels the current recognition request and starts a fresh one with an
    /// empty buffer. Safe to call while the engine is running.
    func resetBuffer() {
        guard !isMuted, !stopped else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        hasSpeech = false
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        startRequest()
        Log.info("[AVService] buffer reset")
    }

    /// Starts a fresh `SFSpeechAudioBufferRecognitionRequest`. Safe to call
    /// while the engine is running — the existing tap feeds audio into the
    /// new request immediately.
    private func startRequest() {
        guard !isMuted, !stopped else { return }
        requestGeneration += 1
        let generation = requestGeneration

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self, !self.stopped, !self.isMuted else { return }
            guard self.requestGeneration == generation else { return }

            if let result {
                self.onTranscription?(result.bestTranscription.formattedString, result.isFinal)
                if result.isFinal {
                    self.hasSpeech = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        guard self.requestGeneration == generation else { return }
                        self.startRequest()
                    }
                }
            } else if let error {
                let nsErr = error as NSError
                if nsErr.domain == "kAFAssistantErrorDomain" && nsErr.code == 1110 {
                    Log.verbose("[AVService] no speech detected — restarting request")
                } else {
                    Log.error("[AVService] recognition error: \(error.localizedDescription)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard self.requestGeneration == generation else { return }
                    self.startRequest()
                }
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
