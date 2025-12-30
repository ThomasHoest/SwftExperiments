//
//  TextView.swift
//  SwiftExperiments
//
//  Created by Thomas Høst Andersen on 01/12/2025.
//

import SwiftUI
import Observation

@Observable
class TranscriptionModel {
    var Transcription: String = ""
}

struct TranscriptionView: View {
    let voiceToText = VoiceToText()
    @State var transcription = TranscriptionModel()
    
    init() {
        voiceToText.initialize(transcriptionCallback: textUpdated)
    }
    
    var body: some View {
        VStack {
            Text("Transcription")
                .font(.title)
            Spacer()
            Text(transcription.Transcription)
            Spacer()

            Button("Transcribe!") {
                do{
                    try voiceToText.startTranscription()
                } catch {
                    print("Failed to start transcription")
                }
            }
            .padding()
        }
        .padding()
    }
    
    func textUpdated(_ text: String, _ error: Bool) {
        transcription.Transcription = text
    }
}

