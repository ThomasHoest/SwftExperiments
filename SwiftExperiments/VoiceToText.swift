//
//  VoiceToText.swift
//  SwiftExperiments
//
//  Created by Thomas Høst Andersen on 23/12/2025.
//
import SwiftUI
internal import Combine

class VoiceToText : ObservableObject {
    let recorder = AVService()
    private var transcriptionCallback: (String, Bool) -> Void = {_,_ in }
    
    func initialize(transcriptionCallback: @escaping (String, Bool) -> Void){
        self.transcriptionCallback = transcriptionCallback
    }
    
    func processText(_ text: String, _ error: Bool) {
        //process command triggers
        transcriptionCallback(text,error)
    }
    
    func startTranscription() throws {
        try recorder.startRecording()
    }
}
