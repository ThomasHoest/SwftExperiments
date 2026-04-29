import SwiftUI

struct HomeView: View {
    @StateObject private var registry      = SpeakerRegistry()
    @StateObject private var coordinator   = ConfirmationCoordinator()
    @StateObject private var motionManager = MotionManager()
    @ObservedObject private var langService = LanguageService.shared
    @State private var voiceToText    = VoiceToText()
    @State private var commandRouter  = CommandParserRouter()
    @State private var transcript     = ""
    @State private var micStatus      = "Initialising microphone…"
    @State private var audioLevel:    Float   = 0
    @State private var isListening    = false
    @State private var isCommandActive  = false
    @State private var selectedSpeaker: Speaker?
    @State private var hasAppeared    = false
    @State private var successMessage = ""

    private let errorService = ErrorResponseService()

    private var cs: CommandStrings { CommandStrings.forLanguage(langService.activeLanguage) }
    private var ui: UIStrings      { UIStrings.forLanguage(langService.activeLanguage) }

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

            // Success toast (E-09 T-0904)
            if !successMessage.isEmpty {
                VStack {
                    Spacer()
                    Text(successMessage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .glassEffect(in: Capsule())
                        .padding(.bottom, 48)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: successMessage)
        .onAppear(perform: onAppear)
        .onChange(of: registry.speakers.map(\.id)) { _, ids in
            if let sel = selectedSpeaker, !ids.contains(sel.id) {
                selectedSpeaker = registry.speakers.first
            } else if selectedSpeaker == nil {
                selectedSpeaker = registry.speakers.first
            }
        }
        .onChange(of: langService.activeLanguage) { _, language in
            voiceToText.setLanguage(language)
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
            Text(ui.lookingForSpeakers)
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
        Task { await commandRouter.warmUp() }

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
                    let cmd = CommandParser(language: langService.activeLanguage).parse(text)
                    if cmd == .confirm { coordinator.confirm() }
                    else if cmd == .cancel { coordinator.cancel() }
                    return
                }

                let words = text.lowercased()
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                guard let (speaker, remaining) = registry.resolve(words: words) else {
                    Log.info("[HomeView] no speaker resolved for: \(text)")
                    let available = registry.speakers.map(\.name)
                    coordinator.announce(errorService.spoken(.noSpeakerSpoken(available: available)))
                    return
                }
                selectedSpeaker = speaker

                let commandText   = remaining.isEmpty ? text : remaining.joined(separator: " ")
                let favoriteNames = await registry.favorites.listFavorites(for: speaker)
                let command = await commandRouter.parse(
                    commandText,
                    addressedSpeaker: speaker,
                    allSpeakers:      registry.speakers.map(\.name),
                    favoriteNames:    favoriteNames
                )
                Log.info("[HomeView] → \(speaker.name): \(command)")

                // Commands that need no confirmation (list, confirm, cancel, unknown)
                guard let confirmMsg = confirmationMessage(forParsed: command, speaker: speaker) else {
                    await dispatchParsed(command: command, to: speaker)
                    return
                }

                let confirmed = await coordinator.request(message: confirmMsg)
                if confirmed {
                    let succeeded = await dispatchParsed(command: command, to: speaker)
                    if succeeded {
                        showSuccess("Done")
                        if let completion = completionMessage(forParsed: command, speaker: speaker) {
                            coordinator.announce(completion)
                        }
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
        case .playFavorite(let i):  return cs.playFavorite(i, speaker.name)
        case .playDefault:          return cs.playDefault(speaker.name)
        case .stop:                 return cs.stop(speaker.name)
        case .pause:                return cs.pause(speaker.name)
        case .resume:               return cs.resume(speaker.name)
        case .setVolume(let level): return cs.setVolume(speaker.name, level)
        case .adjustVolume(let d):  return d > 0
            ? cs.adjustVolumeUp(speaker.name, abs(d))
            : cs.adjustVolumeDown(speaker.name, abs(d))
        case .mute:                 return cs.mute(speaker.name, speaker.volume)
        case .unmute:               return cs.unmute(speaker.name)
        case .listFavorites, .confirm, .cancel, .unknown:
            return nil
        }
    }

    private func completionMessage(for command: VoiceCommand, speaker: Speaker) -> String? {
        switch command {
        case .stop:                 return cs.stopped(speaker.name)
        case .pause:                return cs.paused(speaker.name)
        case .resume:               return cs.resumed(speaker.name)
        case .setVolume(let level): return cs.volumeSet(speaker.name, level)
        case .adjustVolume:         return cs.volumeAdjusted(speaker.name)
        case .mute:                 return cs.muted(speaker.name)
        case .unmute:               return cs.unmuted(speaker.name)
        default:                    return nil
        }
    }

    // ── Command dispatch ──────────────────────────────────────────────────────

    @MainActor
    @discardableResult
    private func dispatch(command: VoiceCommand, to speaker: Speaker) async -> Bool {
        switch command {
        case .playFavorite(let index):
            await registry.favorites.play(index: index, on: speaker)
            return true
        case .playDefault:
            await registry.favorites.playDefault(on: speaker)
            return true
        case .listFavorites:
            let names = await registry.favorites.listFavorites(for: speaker)
            let list  = names.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: ", ")
            coordinator.announce(cs.listFavoritesResult(speaker.name, list))
            return true
        case .stop:
            guard speaker.isPlaying else {
                coordinator.announce(errorService.spoken(.nothingPlaying(speaker: speaker.name)))
                return false
            }
            return await perform(speaker: speaker) { try await speaker.stop() }
        case .pause:
            guard speaker.isPlaying else {
                coordinator.announce(errorService.spoken(.nothingPlaying(speaker: speaker.name)))
                return false
            }
            return await perform(speaker: speaker) { try await speaker.pause() }
        case .resume:
            return await perform(speaker: speaker) { try await speaker.play() }
        case .setVolume(let level):
            return await perform(speaker: speaker) { try await speaker.setVolume(level) }
        case .adjustVolume(let delta):
            if delta > 0, let vol = speaker.volume, vol >= 100 {
                coordinator.announce(errorService.spoken(.volumeAtLimit(speaker: speaker.name, atMax: true)))
                return false
            }
            if delta < 0, let vol = speaker.volume, vol <= 0 {
                coordinator.announce(errorService.spoken(.volumeAtLimit(speaker: speaker.name, atMax: false)))
                return false
            }
            return await perform(speaker: speaker) { try await speaker.adjustVolume(delta) }
        case .mute:
            return await perform(speaker: speaker) { try await speaker.mute() }
        case .unmute:
            return await perform(speaker: speaker) { try await speaker.unmute() }
        case .confirm, .cancel, .unknown:
            Log.info("[HomeView] unhandled: \(command)")
            return false
        }
    }

    /// Executes a throwing speaker action; announces the appropriate error string on failure.
    @MainActor
    @discardableResult
    private func perform(speaker: Speaker, _ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            return true
        } catch let error as MozartError {
            let appError: AppError
            if case .timeout = error { appError = .apiTimeout }
            else { appError = .speakerUnreachable(speaker: speaker.name) }
            coordinator.announce(errorService.spoken(appError))
            return false
        } catch {
            coordinator.announce(errorService.spoken(.speakerUnreachable(speaker: speaker.name)))
            return false
        }
    }

    private func showSuccess(_ message: String) {
        successMessage = message
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            successMessage = ""
        }
    }

    // ── E-18: ParsedCommand confirmation / completion / dispatch ──────────────

    private func confirmationMessage(forParsed command: ParsedCommand, speaker: Speaker) -> String? {
        let step = command.volumeDelta ?? 10
        switch command.intent {
        case .playNamed:     return cs.playDefault(speaker.name)   // resolved name shown post-confirm
        case .playDefault:   return cs.playDefault(speaker.name)
        case .stop:          return cs.stop(speaker.name)
        case .pause:         return cs.pause(speaker.name)
        case .resume:        return cs.resume(speaker.name)
        case .setVolume:     return cs.setVolume(speaker.name, command.volumeValue ?? 50)
        case .volumeUp:      return cs.adjustVolumeUp(speaker.name, step)
        case .volumeDown:    return cs.adjustVolumeDown(speaker.name, step)
        case .mute:          return cs.mute(speaker.name, speaker.volume)
        case .unmute:        return cs.unmute(speaker.name)
        case .listFavorites, .confirm, .cancel, .unknown:
            return nil
        }
    }

    private func completionMessage(forParsed command: ParsedCommand, speaker: Speaker) -> String? {
        switch command.intent {
        case .stop:       return cs.stopped(speaker.name)
        case .pause:      return cs.paused(speaker.name)
        case .resume:     return cs.resumed(speaker.name)
        case .setVolume:  return cs.volumeSet(speaker.name, command.volumeValue ?? 0)
        case .volumeUp, .volumeDown: return cs.volumeAdjusted(speaker.name)
        case .mute:       return cs.muted(speaker.name)
        case .unmute:     return cs.unmuted(speaker.name)
        default:          return nil
        }
    }

    @MainActor
    @discardableResult
    private func dispatchParsed(command: ParsedCommand, to speaker: Speaker) async -> Bool {
        let step = command.volumeDelta ?? 10
        switch command.intent {

        case .playNamed:
            let name = command.favoriteName ?? ""
            guard !name.isEmpty else {
                coordinator.announce(errorService.spoken(.voiceNotRecognised))
                return false
            }
            let found = await registry.favorites.playNamed(name, on: speaker)
            if !found {
                let available = await registry.favorites.listFavorites(for: speaker)
                coordinator.announce(errorService.spoken(.favoriteNotFound(
                    name: name, speaker: speaker.name, available: available)))
            }
            return found

        case .playDefault:
            await registry.favorites.playDefault(on: speaker)
            return true

        case .listFavorites:
            let names = await registry.favorites.listFavorites(for: speaker)
            let list  = names.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: ", ")
            coordinator.announce(cs.listFavoritesResult(speaker.name, list))
            return true

        case .stop:
            guard speaker.isPlaying else {
                coordinator.announce(errorService.spoken(.nothingPlaying(speaker: speaker.name)))
                return false
            }
            return await perform(speaker: speaker) { try await speaker.stop() }

        case .pause:
            guard speaker.isPlaying else {
                coordinator.announce(errorService.spoken(.nothingPlaying(speaker: speaker.name)))
                return false
            }
            return await perform(speaker: speaker) { try await speaker.pause() }

        case .resume:
            return await perform(speaker: speaker) { try await speaker.play() }

        case .setVolume:
            let level = max(0, min(100, command.volumeValue ?? 50))
            return await perform(speaker: speaker) { try await speaker.setVolume(level) }

        case .volumeUp:
            if let vol = speaker.volume, vol >= 100 {
                coordinator.announce(errorService.spoken(.volumeAtLimit(speaker: speaker.name, atMax: true)))
                return false
            }
            return await perform(speaker: speaker) { try await speaker.adjustVolume(+step) }

        case .volumeDown:
            if let vol = speaker.volume, vol <= 0 {
                coordinator.announce(errorService.spoken(.volumeAtLimit(speaker: speaker.name, atMax: false)))
                return false
            }
            return await perform(speaker: speaker) { try await speaker.adjustVolume(-step) }

        case .mute:
            return await perform(speaker: speaker) { try await speaker.mute() }

        case .unmute:
            return await perform(speaker: speaker) { try await speaker.unmute() }

        case .confirm, .cancel, .unknown:
            Log.info("[HomeView] unhandled parsed command: \(command)")
            return false
        }
    }
}
