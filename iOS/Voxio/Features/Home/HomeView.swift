import SwiftUI

struct HomeView: View {
    @StateObject private var registry      = SpeakerRegistry()
    @StateObject private var coordinator   = ConfirmationCoordinator()
    @StateObject private var motionManager = MotionManager()
    @State private var voiceToText    = VoiceToText()
    @State private var transcript     = ""
    @State private var micStatus      = "Initialising microphone…"
    @State private var audioLevel:    Float   = 0
    @State private var isListening    = false
    @State private var isCommandActive  = false
    @State private var selectedSpeaker: Speaker?
    @State private var hasAppeared    = false

    private var displayedSpeaker: Speaker? {
        selectedSpeaker ?? registry.speakers.first
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                statusBar

                Spacer(minLength: 24)

                cardArea

                Spacer(minLength: 28)

                voiceFeedback

                Spacer(minLength: 20)

                if registry.speakers.count > 1 {
                    SpeakerSelectorPill(
                        speakers: registry.speakers,
                        selectedSpeaker: $selectedSpeaker
                    )
                    .padding(.bottom, 12)
                }
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
        }
        .onAppear(perform: onAppear)
        .onChange(of: registry.speakers.map(\.id)) { _, ids in
            if let sel = selectedSpeaker, !ids.contains(sel.id) {
                selectedSpeaker = registry.speakers.first
            } else if selectedSpeaker == nil {
                selectedSpeaker = registry.speakers.first
            }
        }
        .sheet(isPresented: Binding(
            get: { coordinator.isPending },
            set: { if !$0 { coordinator.cancel() } }
        )) {
            if case .pending(let message) = coordinator.state {
                ConfirmationSheet(
                    message: message,
                    onConfirm: { coordinator.confirm() },
                    onCancel:  { coordinator.cancel() }
                )
            }
        }
    }

    // ── Background ────────────────────────────────────────────────────────────

    private var background: some View {
        LinearGradient(
            colors: [Color(hex: "#0D0D14"), Color(hex: "#151520")],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // ── Status bar ────────────────────────────────────────────────────────────

    private var statusBar: some View {
        HStack {
            Spacer()
            ConnectionStatusChip(speakerCount: registry.speakers.count)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // ── Card area ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private var cardArea: some View {
        if let speaker = displayedSpeaker {
            SpeakerCard(
                speaker: speaker,
                isExpanded: isCommandActive,
                roll: motionManager.roll,
                pitch: motionManager.pitch
            )
            .padding(.horizontal, 20)
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.96)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Looking for speakers…")
                .font(BeoType.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .glassEffect(in: RoundedRectangle(cornerRadius: Radius.card))
        .padding(.horizontal, 20)
        .opacity(hasAppeared ? 1 : 0)
    }

    // ── Voice feedback area ───────────────────────────────────────────────────

    private var voiceFeedback: some View {
        VStack(spacing: 0) {
            WaveformView(audioLevel: audioLevel, isListening: isListening)
                .frame(height: 44)

            if !transcript.isEmpty {
                Text(transcript)
                    .font(BeoType.confirmation)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 40)
                    .padding(.top, 16)
                    .transition(.opacity)
                    .animation(.easeIn(duration: 0.15), value: transcript)
            }

            Text(micStatus)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
    }

    // ── Setup ─────────────────────────────────────────────────────────────────

    private func onAppear() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15)) {
            hasAppeared = true
        }

        registry.start()
        motionManager.start()

        // Wire TTS pause/resume — prevents synthesizer output feeding back into recognition
        coordinator.onSpeechWillStart = { [self] in voiceToText.pauseRecognition() }
        coordinator.onSpeechDidEnd    = { [self] in voiceToText.resumeRecognition() }

        voiceToText.onTranscript = { text in
            DispatchQueue.main.async {
                transcript = text
                isCommandActive = !text.isEmpty
            }
        }
        voiceToText.onAudioLevel = { rms in
            DispatchQueue.main.async {
                audioLevel = rms
                isListening = rms > 0.01
            }
        }
        voiceToText.onFinalTranscript = { text in
            Task { @MainActor in
                isCommandActive = false

                // While waiting for confirmation, only accept confirm/cancel
                if coordinator.isPending {
                    let cmd = CommandParser().parse(text)
                    if cmd == .confirm { coordinator.confirm() }
                    else if cmd == .cancel { coordinator.cancel() }
                    return
                }

                let words = text.lowercased()
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                guard let (speaker, remaining) = registry.resolve(words: words) else {
                    Log.info("[HomeView] no speaker resolved for: \(text)")
                    return
                }
                selectedSpeaker = speaker
                let commandText = remaining.isEmpty ? text : remaining.joined(separator: " ")
                let command = CommandParser().parse(commandText)
                Log.info("[HomeView] → \(speaker.name): \(command)")

                // Commands that need no confirmation (list, confirm, cancel, unknown)
                guard let confirmMsg = confirmationMessage(for: command, speaker: speaker) else {
                    await dispatch(command: command, to: speaker)
                    return
                }

                let confirmed = await coordinator.request(message: confirmMsg)
                if confirmed {
                    await dispatch(command: command, to: speaker)
                    if let completion = completionMessage(for: command, speaker: speaker) {
                        coordinator.announce(completion)
                    }
                }
            }
        }
        voiceToText.start { status in
            micStatus = status
        }
    }

    // ── Confirmation messages ─────────────────────────────────────────────────

    private func confirmationMessage(for command: VoiceCommand, speaker: Speaker) -> String? {
        switch command {
        case .playFavorite(let i):  return "Playing favorite \(i) on \(speaker.name)"
        case .playDefault:          return "Playing on \(speaker.name)"
        case .stop:                 return "Stopping \(speaker.name)"
        case .pause:                return "Pausing \(speaker.name)"
        case .resume:               return "Resuming \(speaker.name)"
        case .setVolume(let level): return "Setting \(speaker.name) volume to \(level)"
        case .adjustVolume(let d):  return "Turning \(speaker.name) volume \(d > 0 ? "up" : "down") by \(abs(d))"
        case .mute:                 return "Muting \(speaker.name)"
        case .unmute:               return "Unmuting \(speaker.name)"
        case .listFavorites, .confirm, .cancel, .unknown:
            return nil
        }
    }

    private func completionMessage(for command: VoiceCommand, speaker: Speaker) -> String? {
        switch command {
        case .stop:                 return "\(speaker.name) stopped"
        case .pause:                return "\(speaker.name) paused"
        case .resume:               return "\(speaker.name) resumed"
        case .setVolume(let level): return "\(speaker.name) volume is now \(level)"
        case .adjustVolume:         return "\(speaker.name) volume adjusted"
        case .mute:                 return "\(speaker.name) muted"
        case .unmute:               return "\(speaker.name) unmuted"
        default:                    return nil
        }
    }

    // ── Command dispatch ──────────────────────────────────────────────────────

    @MainActor
    private func dispatch(command: VoiceCommand, to speaker: Speaker) async {
        switch command {
        case .playFavorite(let index):
            await registry.favorites.play(index: index, on: speaker)
        case .playDefault:
            await registry.favorites.playDefault(on: speaker)
        case .listFavorites:
            let names = await registry.favorites.listFavorites(for: speaker)
            let list  = names.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: ", ")
            coordinator.announce("Favorites on \(speaker.name): \(list)")
        case .stop:
            try? await speaker.stop()
        case .pause:
            try? await speaker.pause()
        case .resume:
            try? await speaker.play()
        case .setVolume(let level):
            try? await speaker.setVolume(level)
        case .adjustVolume(let delta):
            try? await speaker.adjustVolume(delta)
        case .mute:
            try? await speaker.mute()
        case .unmute:
            try? await speaker.unmute()
        case .confirm, .cancel, .unknown:
            Log.info("[HomeView] unhandled: \(command)")
        }
    }
}
