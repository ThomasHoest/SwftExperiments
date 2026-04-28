import SwiftUI

struct HomeView: View {
    @StateObject private var registry      = SpeakerRegistry()
    @StateObject private var motionManager = MotionManager()
    @State private var voiceToText   = VoiceToText()
    @State private var transcript    = ""
    @State private var micStatus     = "Initialising microphone…"
    @State private var audioLevel:   Float   = 0
    @State private var isListening   = false
    @State private var isCommandActive = false
    @State private var selectedSpeaker: Speaker?
    @State private var hasAppeared   = false

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
                await dispatch(command: command, to: speaker)
            }
        }
        voiceToText.start { status in
            micStatus = status
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
            Log.info("[Favorites] \(speaker.name): \(names.joined(separator: ", "))")
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
