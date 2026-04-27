import AVFoundation
import Speech

class AVService {
    let engine = AVAudioEngine()
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    var request: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?
    var onTranscription: ((_ text: String, _ error: Bool) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }
        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            if let data = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                let rms = sqrt((0..<frames).reduce(0.0) { $0 + Double(data[$1] * data[$1]) } / Double(frames))
                self?.onAudioLevel?(Float(rms))
            }
        }

        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                self?.onTranscription?(result.bestTranscription.formattedString, false)
            }
            if error != nil { self?.stopRecording() }
        }
    }

    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
    }
}
