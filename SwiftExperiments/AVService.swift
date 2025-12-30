//
//  AVService.swift
//  SwiftExperiments
//
//  Created by Thomas Høst Andersen on 23/12/2025.
//

import AVFoundation
import Speech

class AVService {
    let engine = AVAudioEngine()
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    var request: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?
    var onTranscription: ((_ data: String,_ error: Bool) -> Void)?
    
    func requestPermission() throws {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                print("Speech recognition authorized")
            default:
                print("Speech recognition not authorized: \(status)")
            }
        }
    }
    
    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)
        
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else { return }

        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) {
                buffer, _ in
                request.append(buffer)
            }

        engine.prepare()
        try engine.start()
        
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                self.onResult(result.bestTranscription.formattedString,
                         result.isFinal)
            }
            if error != nil {
                self.stopRecording()
            }
        }
    }
    
    func onResult(_ text: String, _ isFinal: Bool) {
        print("Text: \(text), Final: \(isFinal)")
        onTranscription?(text, false)
    }
    
    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
