import SwiftUI

struct ContentView: View {
    @StateObject private var registry = SpeakerRegistry()
    @State private var voiceToText = VoiceToText()
    @State private var transcript = ""
    @State private var micStatus = "Initialising microphone…"
    @State private var orbScale: CGFloat = 1.0
    @State private var orbGlow: Double = 0.15
    @State private var orbBlur: Double = 24
    @State private var micActive = false
    @State private var breathingTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            BeoColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                orbSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                BeoColor.separator.frame(height: 1)

                speakerSection
                    .frame(height: UIScreen.main.bounds.height * 0.42)
            }
        }
        .onAppear(perform: onAppear)
    }

    // ── Orb + transcript ──────────────────────────────────────────────────────

    private var orbSection: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(orbGradient)
                    .frame(width: 160, height: 160)
                    .shadow(color: BeoColor.accent.opacity(orbGlow),
                            radius: orbBlur, x: 0, y: 0)
                    .scaleEffect(orbScale)
            }

            if !transcript.isEmpty {
                Text(transcript)
                    .font(.custom("Georgia", size: 22).italic())
                    .multilineTextAlignment(.center)
                    .foregroundColor(BeoColor.text)
                    .padding(.horizontal, Spacing.s24 * 2)
                    .padding(.top, Spacing.s24 + Spacing.s8)
            }

            Text(micStatus)
                .font(.system(size: 11))
                .foregroundColor(BeoColor.muted)
                .padding(.top, Spacing.s16)

            Spacer()
        }
    }

    private var orbGradient: RadialGradient {
        RadialGradient(
            stops: [
                .init(color: Color(hex: "#F4EDE0"), location: 0.00),
                .init(color: Color(hex: "#C8A07E"), location: 0.42),
                .init(color: Color(hex: "#7A5534"), location: 1.00),
            ],
            center: UnitPoint(x: 0.38, y: 0.33),
            startRadius: 0,
            endRadius: 80
        )
    }

    // ── Speaker panel ─────────────────────────────────────────────────────────

    private var speakerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("S P E A K E R S")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(BeoColor.accent)
                .padding(.horizontal, Spacing.s20)
                .padding(.top, Spacing.s20)
                .padding(.bottom, Spacing.s12)

            ScrollView {
                LazyVStack(spacing: Spacing.s8) {
                    ForEach(registry.speakers) { speaker in
                        SpeakerCardView(speaker: speaker)
                            .padding(.horizontal, Spacing.s20)
                    }
                }
                .padding(.bottom, Spacing.s20)
            }
        }
    }

    // ── Setup ─────────────────────────────────────────────────────────────────

    private func onAppear() {
        startBreathing()
        registry.start()

        voiceToText.onTranscript = { text in
            DispatchQueue.main.async { transcript = text }
        }
        voiceToText.onAudioLevel = { rms in
            DispatchQueue.main.async { driveOrb(rms: Double(rms)) }
        }
        voiceToText.onFinalTranscript = { text in
            Task { @MainActor in
                let words = text.lowercased()
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                guard let (speaker, remaining) = registry.resolve(words: words) else {
                    Log.info("[ContentView] no speaker resolved for: \(text)")
                    return
                }
                let commandText = remaining.isEmpty ? text : remaining.joined(separator: " ")
                let command = CommandParser().parse(commandText)
                Log.info("[ContentView] → \(speaker.name): \(command)")
                await dispatch(command: command, to: speaker)
            }
        }
        voiceToText.start { status in
            micStatus = status
            if status == "Listening…" {
                breathingTask?.cancel()
                breathingTask = nil
                micActive = true
            }
        }
    }

    // ── Dispatch ──────────────────────────────────────────────────────────────

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
            Log.info("[ContentView] unhandled command: \(command)")
        }
    }

    // ── Orb animation ─────────────────────────────────────────────────────────

    private func driveOrb(rms: Double) {
        let boost = min(rms * 4.0, 0.55)
        withAnimation(.linear(duration: 0.05)) {
            orbScale = 1.0 + boost
            orbGlow  = 0.15 + boost * 1.5
            orbBlur  = 24   + boost * 80
        }
    }

    private func startBreathing() {
        breathingTask = Task { @MainActor in
            var expand = true
            while !Task.isCancelled {
                withAnimation(BeoAnimation.spring) {
                    orbScale = expand ? 1.045 : 1.0
                }
                expand.toggle()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
