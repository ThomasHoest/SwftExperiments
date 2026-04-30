import SwiftUI
import UIKit

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
    @AppStorage("hasSeenHint") private var hasSeenHint = false
    @State private var showHintManually = false
    @State private var showLanguagePicker = false
    @State private var currentToast:  Toast?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let errorService = ErrorResponseService()

    private var cs: CommandStrings { CommandStrings.forLanguage(langService.activeLanguage) }
    private var ui: UIStrings      { UIStrings.forLanguage(langService.activeLanguage) }

    private var displayedSpeaker: Speaker? {
        selectedSpeaker ?? registry.speakers.first
    }

    private var shouldShowHint: Bool {
        showHintManually || (!hasSeenHint && !registry.speakers.isEmpty)
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
            .frame(width: (UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.screen.bounds.width ?? 0) - 40)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }

            // Toast overlay (errors, volume limit, success)
            if let toast = currentToast {
                VStack {
                    ToastView(toast: toast)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal:   .move(edge: .top).combined(with: .opacity)
                        ))
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
        .animation(BeoAnimation.toast, value: currentToast)
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
        .onChange(of: transcript) { _, new in
            if !new.isEmpty { showHintManually = false }
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerSheet { language in
                Task { @MainActor in
                    langService.setLanguage(language)
                    showLanguagePicker = false
                    startListening()
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { coordinator.isPending },
            set: { if !$0 { coordinator.cancelCountdown(reason: .interruption) } }
        )) {
            if case .countdown(let readBack) = coordinator.state {
                CountdownConfirmationSurface(
                    readBackText: readBack,
                    secondsRemaining: coordinator.secondsRemaining,
                    onCancel: { coordinator.cancelCountdown(reason: .userTap) }
                )
            }
        }
    }

    // ── Background — T-2002 / T-2006 ─────────────────────────────────────────

    private var background: some View {
        Group {
            if UIImage(named: BeoAsset.appBackground) != nil {
                Image(BeoAsset.appBackground)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                // T-2006 — asset-missing fallback (no crash, no silent gradient)
                let _ = Log.error("AppBackground render failed")
                Color(hex: "#0A0E1A")
            }
        }
        .ignoresSafeArea()
    }

    // ── Status bar ── T-2108 ──────────────────────────────────────────────────

    private var hintButtonAccessibilityLabel: String {
        langService.activeLanguage == .danish
            ? "Vis kom-godt-i-gang-tip"
            : "Show getting-started hint"
    }

    private var statusBar: some View {
        HStack {
            DarkGlassIconButton(
                systemImage: "questionmark.circle",
                role: .default,
                accessibilityLabel: hintButtonAccessibilityLabel
            ) {
                showHintManually.toggle()
            }

            Spacer()
            ConnectionStatusChip(speakerCount: registry.speakers.count)
        }
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
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .transition(.opacity)
                    .animation(.easeIn(duration: 0.15), value: transcript)
            }

            Text(micStatus)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            if shouldShowHint && !coordinator.isPending {
                HintCardView(
                    speakerName: registry.speakers.first?.name,
                    language: langService.activeLanguage,
                    onDismiss: {
                        hasSeenHint = true
                        showHintManually = false
                    }
                )
                .transition(.opacity)
                .padding(.top, 12)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowHint)
    }

    // ── Setup ─────────────────────────────────────────────────────────────────

    private func onAppear() {
        withAnimation(reduceMotion
            ? .easeIn(duration: 0.2)
            : .spring(response: 0.5, dampingFraction: 0.8).delay(0.15)
        ) {
            hasAppeared = true
        }

        // T-1903 — show language picker on first launch; defer mic/discovery until chosen
        if !langService.hasExplicitlyChosen {
            showLanguagePicker = true
            return
        }
        startListening()
    }

    private func startListening() {
        voiceToText.setLanguage(langService.activeLanguage)
        registry.start()
        motionManager.start()
        Task { await commandRouter.warmUp() }

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

                // While countdown is active, only a cancel utterance stops it;
                // non-cancel utterances are silently ignored — countdown continues.
                if coordinator.isPending {
                    if CancelGrammar.matches(text) {
                        coordinator.cancelCountdown(reason: .userVoice)
                    }
                    return
                }

                let words = text.lowercased()
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                guard let (speaker, remaining) = registry.resolve(words: words) else {
                    Log.info("[HomeView] no speaker resolved for: \(text)")
                    let available = registry.speakers.map(\.name)
                    handleError(.noSpeakerSpoken(available: available))
                    clearTranscriptAfterDelay()
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
                if command.intent != .unknown { HapticEngine.shared.commandRecognised() }

                if command.intent == .playFavoriteByNumber {
                    await handlePlayFavoriteByNumber(command: command, speaker: speaker)
                    return
                }

                // Commands that need no confirmation (list, confirm, cancel, unknown)
                guard let confirmMsg = confirmationMessage(forParsed: command, speaker: speaker) else {
                    if command.intent == .unknown {
                        handleError(.voiceNotRecognised)
                    }
                    await dispatchParsed(command: command, to: speaker)
                    clearTranscriptAfterDelay()
                    return
                }

                if let preflight = preflightError(for: command, speaker: speaker) {
                    handleError(preflight)
                    return
                }

                coordinator.startCountdown(
                    action: { [weak self] in
                        guard let self else { return }
                        let succeeded = await self.dispatchParsed(command: command, to: speaker)
                        if succeeded { self.showSuccess("Done") }
                        self.clearTranscriptAfterDelay()
                    },
                    readBack: confirmMsg,
                    onResolved: { _ in }
                )
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
            let list  = names.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "  ·  ")
            transcript = cs.listFavoritesResult(speaker.name, list)
            clearTranscriptAfterDelay()
            return true
        case .stop:
            guard speaker.isPlaying else {
                handleError(.nothingPlaying(speaker: speaker.name))
                return false
            }
            return await perform(speaker: speaker) { try await speaker.stop() }
        case .pause:
            guard speaker.isPlaying else {
                handleError(.nothingPlaying(speaker: speaker.name))
                return false
            }
            return await perform(speaker: speaker) { try await speaker.pause() }
        case .resume:
            return await perform(speaker: speaker) { try await speaker.play() }
        case .setVolume(let level):
            return await perform(speaker: speaker) { try await speaker.setVolume(level) }
        case .adjustVolume(let delta):
            if delta > 0, let vol = speaker.volume, vol >= 100 {
                handleError(.volumeAtLimit(speaker: speaker.name, atMax: true))
                return false
            }
            if delta < 0, let vol = speaker.volume, vol <= 0 {
                handleError(.volumeAtLimit(speaker: speaker.name, atMax: false))
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
            handleError(appError)
            return false
        } catch {
            handleError(.speakerUnreachable(speaker: speaker.name))
            return false
        }
    }

    @MainActor
    private func handlePlayFavoriteByNumber(command: ParsedCommand, speaker: Speaker) async {
        guard let index = command.favoriteIndex else {
            handleError(.voiceNotRecognised)
            return
        }
        guard let favorite = await registry.favorites.favorite(at: index, for: speaker) else {
            let available = await registry.favorites.listFavorites(for: speaker)
            handleError(.favoriteIndexOutOfRange(index: index, speaker: speaker.name, available: available))
            return
        }
        let confirmMsg = cs.playFavoriteByName(favorite.displayName, speaker.name)
        coordinator.startCountdown(
            action: { [weak self] in
                guard let self else { return }
                let succeeded = await self.perform(speaker: speaker) {
                    try await speaker.playFavorite(presetIndex: favorite.presetIndex)
                }
                if succeeded { self.showSuccess("Done") }
            },
            readBack: confirmMsg,
            onResolved: { _ in }
        )
    }

    /// Returns an error that should skip the confirmation sheet entirely (volume limits, already muted).
    private func preflightError(for command: ParsedCommand, speaker: Speaker) -> AppError? {
        switch command.intent {
        case .volumeUp:
            if let vol = speaker.volume, vol >= 100 { return .volumeAtLimit(speaker: speaker.name, atMax: true) }
        case .volumeDown:
            if let vol = speaker.volume, vol <= 0 { return .volumeAtLimit(speaker: speaker.name, atMax: false) }
        case .mute:
            if speaker.isMuted { return .alreadyMuted(speaker: speaker.name) }
        default: break
        }
        return nil
    }

    private func clearTranscriptAfterDelay() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            while coordinator.isPending {
                try? await Task.sleep(for: .seconds(5))
            }
            transcript = ""
            voiceToText.resumeRecognition()
        }
    }

    private func handleError(_ error: AppError) {
        let message = errorService.spoken(error)
        let kind: ToastKind
        switch error {
        case .volumeAtLimit(_, let isMax):
            kind = .volumeLimit(message: message, isMax: isMax)
            HapticEngine.shared.limitReached()
        case .noSpeakerSpoken(let available):
            kind = .error(message: message, list: available)
            HapticEngine.shared.errorOccurred()
        case .speakerNotFound(_, let available):
            kind = .error(message: message, list: available)
            HapticEngine.shared.errorOccurred()
        case .favoriteNotFound(_, _, let available):
            kind = .error(message: message, list: available)
            HapticEngine.shared.errorOccurred()
        case .favoriteIndexOutOfRange(_, _, let available):
            kind = .error(message: message, list: available)
            HapticEngine.shared.errorOccurred()
        default:
            kind = .error(message: message, list: [])
            HapticEngine.shared.errorOccurred()
        }
        showToast(Toast(kind: kind))
    }

    private func showToast(_ toast: Toast) {
        currentToast = toast
        let toastID = toast.id
        Task {
            try? await Task.sleep(for: .seconds(toast.dismissDelay))
            if currentToast?.id == toastID { currentToast = nil }
        }
    }

    private func showSuccess(_ message: String) {
        showToast(Toast(kind: .success(message: message)))
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
        case .playFavoriteByNumber, .listFavorites, .confirm, .cancel, .unknown:
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
                handleError(.voiceNotRecognised)
                return false
            }
            let found = await registry.favorites.playNamed(name, on: speaker)
            if !found {
                let available = await registry.favorites.listFavorites(for: speaker)
                handleError(.favoriteNotFound(name: name, speaker: speaker.name, available: available))
            }
            return found

        case .playDefault:
            await registry.favorites.playDefault(on: speaker)
            return true

        case .listFavorites:
            let names = await registry.favorites.listFavorites(for: speaker)
            let list  = names.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "  ·  ")
            transcript = cs.listFavoritesResult(speaker.name, list)
            clearTranscriptAfterDelay()
            return true

        case .stop:
            guard speaker.isPlaying else {
                handleError(.nothingPlaying(speaker: speaker.name))
                return false
            }
            return await perform(speaker: speaker) { try await speaker.stop() }

        case .pause:
            guard speaker.isPlaying else {
                handleError(.nothingPlaying(speaker: speaker.name))
                return false
            }
            do {
                try await speaker.pause()
                return true
            } catch MozartError.httpError(let code) where code == 405 {
                handleError(.pauseNotSupported(speaker: speaker.name))
                return false
            } catch MozartError.timeout {
                handleError(.apiTimeout)
                return false
            } catch {
                handleError(.speakerUnreachable(speaker: speaker.name))
                return false
            }

        case .resume:
            return await perform(speaker: speaker) { try await speaker.play() }

        case .setVolume:
            let level = max(0, min(100, command.volumeValue ?? 50))
            return await perform(speaker: speaker) { try await speaker.setVolume(level) }

        case .volumeUp:
            if let vol = speaker.volume, vol >= 100 {
                handleError(.volumeAtLimit(speaker: speaker.name, atMax: true))
                return false
            }
            return await perform(speaker: speaker) { try await speaker.adjustVolume(+step) }

        case .volumeDown:
            if let vol = speaker.volume, vol <= 0 {
                handleError(.volumeAtLimit(speaker: speaker.name, atMax: false))
                return false
            }
            return await perform(speaker: speaker) { try await speaker.adjustVolume(-step) }

        case .mute:
            return await perform(speaker: speaker) { try await speaker.mute() }

        case .unmute:
            return await perform(speaker: speaker) { try await speaker.unmute() }

        case .playFavoriteByNumber:
            // handled before dispatch via handlePlayFavoriteByNumber
            Log.info("[HomeView] playFavoriteByNumber reached dispatch unexpectedly")
            return false

        case .confirm, .cancel, .unknown:
            Log.info("[HomeView] unhandled parsed command: \(command)")
            return false
        }
    }
}
