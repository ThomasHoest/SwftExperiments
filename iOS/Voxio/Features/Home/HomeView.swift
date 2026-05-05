import SwiftUI
import UIKit
import Speech
import AVFoundation

struct HomeView: View {
    @StateObject private var discovery     = SpeakerDiscoveryService()
    @StateObject private var coordinator   = ConfirmationCoordinator()
    @StateObject private var motionManager = MotionManager()
    @ObservedObject private var langService = LanguageService.shared
    @State private var voiceToText    = VoiceToText()
    @State private var personalisationStore: PersonalisationStore
    @State private var commandRouter: CommandParserRouter
    @State private var telemetryBuffer: TelemetryBuffer
    @State private var telemetryUploader: TelemetryUploader

    init() {
        let store = PersonalisationStore(context: PersistenceController.shared.viewContext)
        let buffer = TelemetryBuffer(context: PersistenceController.shared.viewContext)
        _personalisationStore = State(initialValue: store)
        _commandRouter = State(initialValue: CommandParserRouter(personalisationStore: store))
        _telemetryBuffer = State(initialValue: buffer)
        _telemetryUploader = State(initialValue: TelemetryUploader(buffer: buffer))
    }
    @StateObject private var transcriptController = TranscriptController()
    @State private var micStatus      = "Initialising microphone…"
    @State private var audioLevel:    Float   = 0
    @State private var isListening    = false
    @State private var isCommandActive  = false
    @State private var selectedSpeaker: Speaker?
    @State private var hasAppeared    = false
    @State private var successMessage = ""
    // T-3804: retained read-only for migration from v1.2 hasSeenHint → hasCompletedOnboarding
    @AppStorage("hasSeenHint") private var hasSeenHint = false
    // T-3802: onboarding persistence key
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasSeenTelemetryPrompt") private var hasSeenTelemetryPrompt = false
    @State private var showTelemetryPrompt = false
    // T-3805: re-showable sheet binding (wired to SettingsView in E-39 T-3906)
    @State private var showOnboardingSheet = false
    // E-40 T-4006 — HelpView sheet trigger
    @State private var showHelp = false
    @State private var showLanguagePicker = false
    @State private var currentToast:  Toast?

    // Exposed for Settings sheet (E-39 T-3906)
    var onboardingSheetBinding: Binding<Bool> { $showOnboardingSheet }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let errorService = ErrorResponseService()

    private var cs: CommandStrings { CommandStrings.forLanguage(langService.activeLanguage) }
    private var ui: UIStrings      { UIStrings.forLanguage(langService.activeLanguage) }

    private var broadcastHandler: BroadcastCommandHandler { BroadcastCommandHandler(discovery: discovery) }

    private func isBroadcast(_ command: VoiceCommand) -> Bool {
        switch command {
        case .stopAll, .pauseAll, .resumeAll, .adjustVolumeAll, .muteAll, .unmuteAll: return true
        default: return false
        }
    }

    private var displayedSpeaker: Speaker? {
        selectedSpeaker ?? discovery.groups.first?.hostSpeaker
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

                if discovery.groups.flatMap(\.members).count > 1 {
                    SpeakerSelectorPill(
                        speakers: discovery.groups.flatMap(\.members),
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
        // T-3802 — full-screen onboarding cover on first launch
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { _ in }
        )) {
            OnboardingView(onDismiss: {
                // T-3803 — permissions were requested inside OnboardingView.handleCTA()
                // before this closure is called. Set flag only — onChange(hasCompletedOnboarding)
                // is the single trigger for startListeningIfReady() to prevent double-start.
                hasCompletedOnboarding = true
            })
        }
        // T-3805 — re-showable sheet from Settings (isReshow path; does not change hasCompletedOnboarding)
        .sheet(isPresented: $showOnboardingSheet) {
            OnboardingView(onDismiss: { showOnboardingSheet = false }, isReshow: true)
        }
        // E-40 T-4006 — Help sheet (replaces HintCardView; disabled during active countdown)
        .sheet(isPresented: $showHelp) {
            let members = discovery.groups.flatMap(\.members)
            HelpView(
                speakerA: members.first?.name,
                speakerB: members.dropFirst().first?.name,
                activeLanguage: langService.activeLanguage,
                isPresented: $showHelp
            )
        }
        .animation(BeoAnimation.toast, value: currentToast)
        .alert("Help improve Voxio?", isPresented: $showTelemetryPrompt) {
            Button("Enable") {
                telemetryUploader.isEnabled = true
                hasSeenTelemetryPrompt = true
            }
            Button("Not now", role: .cancel) {
                hasSeenTelemetryPrompt = true
            }
        }
        .onAppear(perform: onAppear)
        // ADR §Consequences point 2 — re-fire startListening when hasCompletedOnboarding flips
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if completed { startListeningIfReady() }
        }
        .onChange(of: discovery.groups.flatMap(\.members).map(\.id)) { _, ids in
            // Removal: if the user's selected speaker just disappeared, fall back to first available.
            if let sel = selectedSpeaker, !ids.contains(sel.id) {
                selectedSpeaker = discovery.groups.flatMap(\.members).first
                SpeakerStore.shared.activeSpeaker = selectedSpeaker
            } else if selectedSpeaker == nil && discovery.didSettle {
                // Post-settle additions (rare): pick any new arrival.
                selectedSpeaker = discovery.groups.flatMap(\.members).first
                SpeakerStore.shared.activeSpeaker = selectedSpeaker
            }
        }
        .onChange(of: discovery.didSettle) { _, settled in
            // Initial-startup auto-select: prefer the playing speaker, else first.
            guard settled, selectedSpeaker == nil else { return }
            let members = discovery.groups.flatMap(\.members)
            let pick = members.first(where: { $0.isPlaying }) ?? members.first
            selectedSpeaker = pick
            SpeakerStore.shared.activeSpeaker = pick
            if let pick {
                Log.info("[HomeView] initial selection: \(pick.name) (playing=\(pick.isPlaying))")
            }
        }
        .onChange(of: langService.activeLanguage) { _, language in
            voiceToText.setLanguage(language)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await telemetryUploader.attemptUploadIfDue() }
            }
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

    // ── Status bar ── T-2108 / E-40 T-4006 ──────────────────────────────────────

    private var helpButtonAccessibilityLabel: String {
        langService.activeLanguage == .danish ? "Hjælp" : "Help"
    }

    private var statusBar: some View {
        HStack {
            // E-40 T-4006 — opens HelpView sheet (replaces old HintCardView toggle)
            DarkGlassIconButton(
                systemImage: "questionmark.circle",
                role: coordinator.isPending ? .disabled : .default,
                accessibilityLabel: helpButtonAccessibilityLabel
            ) {
                showHelp = true
            }

            Spacer()
            ConnectionStatusChip(speakerCount: discovery.groups.flatMap(\.members).count)
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

            if !transcriptController.text.isEmpty {
                Text(transcriptController.text)
                    .font(BeoType.confirmation)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .transition(.opacity)
                    .animation(.easeIn(duration: 0.15), value: transcriptController.text)
                    .onTapGesture { transcriptController.clearNow() }
            }

            Text(micStatus)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            // HintCardView removed per E-38; replaced by OnboardingView fullScreenCover
        }
    }

    // ── Setup ─────────────────────────────────────────────────────────────────

    private func onAppear() {
        withAnimation(reduceMotion
            ? .easeIn(duration: 0.2)
            : .spring(response: 0.5, dampingFraction: 0.8).delay(0.15)
        ) {
            hasAppeared = true
        }

        // T-3804 — migrate users upgrading from v1.2 (hasSeenHint → hasCompletedOnboarding).
        // Return immediately — onChange(hasCompletedOnboarding) is the single trigger for
        // startListeningIfReady() to avoid a double-start with the onChange handler below.
        if hasSeenHint && !hasCompletedOnboarding {
            hasCompletedOnboarding = true
            return
        }

        // T-3802 — gate: if onboarding not complete, fullScreenCover handles it
        if !hasCompletedOnboarding {
            return
        }

        // T-1903 — show language picker on first launch; defer mic/discovery until chosen
        if !langService.hasExplicitlyChosen {
            showLanguagePicker = true
            return
        }
        startListening()
    }

    /// Starts the listening pipeline when all preconditions are met.
    /// Called from onAppear (gate passed), from the onboarding dismiss closure,
    /// and from the onChange(hasCompletedOnboarding) handler.
    private func startListeningIfReady() {
        guard hasCompletedOnboarding else { return }
        guard langService.hasExplicitlyChosen else {
            showLanguagePicker = true
            return
        }
        startListening()
    }

    private func startListening() {
        voiceToText.setLanguage(langService.activeLanguage)
        discovery.start()
        motionManager.start()
        Task { await commandRouter.warmUp() }

        transcriptController.configure(coordinator: coordinator)
        transcriptController.onClear = { voiceToText.resetRecognitionBuffer() }

        voiceToText.onTranscript = { text in
            DispatchQueue.main.async {
                transcriptController.update(text)
                isCommandActive = !text.isEmpty
            }
        }
        voiceToText.onAudioLevel = { rms in
            DispatchQueue.main.async {
                audioLevel = rms
                isListening = rms > 0.01
            }
        }
        let handleFinalTranscript: (String) -> Void = { text in
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

                // Broadcast pre-check: parse the full transcript before speaker resolution
                // so SpeakerMatcher cannot consume words from broadcast phrases
                // (e.g. "stop alle" — "Stue" fuzzy-matches "stop", leaving only "alle").
                if let broadcastCmd = commandRouter.parseBroadcast(text) {
                    HapticEngine.shared.commandRecognised()
                    Log.info("[HomeView] → broadcast (pre-resolve): \(broadcastCmd)")
                    let result = await broadcastHandler.handle(broadcastCmd)
                    let message = result.totalCount == 0
                        ? cs.broadcastNothingInScope
                        : cs.broadcastExecuted(result.successCount, result.totalCount)
                    showToast(Toast(kind: .success(message: message)))
                    transcriptController.clearAfterCommand()
                    return
                }

                let words = text.lowercased()
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                guard let (speaker, remaining) = discovery.resolve(words: words) else {
                    Log.info("[HomeView] no speaker resolved for: \(text)")
                    let available = discovery.groups.flatMap(\.members).map(\.name)
                    handleError(.noSpeakerSpoken(available: available))
                    transcriptController.clearAfterCommand()
                    return
                }
                selectedSpeaker = speaker

                let commandText = remaining.isEmpty ? text : remaining.joined(separator: " ")
                let command = await commandRouter.parse(commandText, speakerId: speaker.id.uuidString)
                Log.info("[HomeView] → \(speaker.name): \(command)")
                if case .unknown = command { } else { HapticEngine.shared.commandRecognised() }

                // Broadcast intercept — runs before single-speaker dispatch (ADR E-37).
                if isBroadcast(command) {
                    Log.info("[HomeView][clear] path=broadcast command=\(command)")
                    let result = await broadcastHandler.handle(command)
                    let message: String
                    if result.totalCount == 0 {
                        message = cs.broadcastNothingInScope
                    } else {
                        message = cs.broadcastExecuted(result.successCount, result.totalCount)
                    }
                    showToast(Toast(kind: .success(message: message)))
                    transcriptController.clearAfterCommand()
                    return
                }

                if case .playFavorite(let index) = command {
                    Log.info("[HomeView][clear] path=playFavorite index=\(index)")
                    await handlePlayFavorite(index: index, speaker: speaker)
                    return
                }

                // Commands that need no confirmation (listFavorites, confirm, cancel, unknown)
                guard let confirmMsg = confirmationMessage(for: command, speaker: speaker) else {
                    Log.info("[HomeView][clear] path=noConfirmation command=\(command) → clearAfterCommand")
                    if case .unknown = command { handleError(.voiceNotRecognised) }
                    await dispatch(command: command, to: speaker)
                    transcriptController.clearAfterCommand()
                    return
                }

                if let preflight = preflightError(for: command, speaker: speaker) {
                    Log.info("[HomeView][clear] path=preflightError command=\(command) error=\(preflight) → clearAfterCommand")
                    handleError(preflight)
                    transcriptController.clearAfterCommand()
                    return
                }

                Log.info("[HomeView][clear] path=countdown command=\(command) → clearAfterCommand deferred to action")

                let capturedParserPath = commandRouter.lastParserPath ?? "unknown"

                coordinator.startCountdown(
                    action: {
                        let succeeded = await dispatch(command: command, to: speaker)
                        if succeeded { showSuccess("Done") }
                        transcriptController.clearAfterCommand()
                    },
                    readBack: confirmMsg,
                    onResolved: { resolution in
                        // T-3305: record confirmed command on execution
                        // T-3306: delete confirmed command on cancellation
                        Task { @MainActor in
                            switch resolution {
                            case .fired:
                                try? personalisationStore.recordConfirmedCommand(
                                    speakerId: speaker.id.uuidString,
                                    transcription: commandText.lowercased(),
                                    intent: command.toCommandIntent(),
                                    slots: [:]
                                )
                                try? telemetryBuffer.record(
                                    transcription: commandText,
                                    speakerName: speaker.name,
                                    speakerId: speaker.id.uuidString,
                                    intent: command.toCommandIntent().rawValue,
                                    slots: [:],
                                    parserPath: capturedParserPath,
                                    outcome: .confirmed,
                                    locale: Locale.current.identifier
                                )
                                let count = UserDefaults.standard.integer(forKey: "confirmedCommandCount") + 1
                                UserDefaults.standard.set(count, forKey: "confirmedCommandCount")
                                if count == 50 && !hasSeenTelemetryPrompt {
                                    showTelemetryPrompt = true
                                }
                            case .cancelled:
                                try? personalisationStore.deleteConfirmedCommand(
                                    transcription: commandText.lowercased(),
                                    speakerId: speaker.id.uuidString
                                )
                                try? telemetryBuffer.record(
                                    transcription: commandText,
                                    speakerName: speaker.name,
                                    speakerId: speaker.id.uuidString,
                                    intent: command.toCommandIntent().rawValue,
                                    slots: [:],
                                    parserPath: capturedParserPath,
                                    outcome: .cancelled,
                                    locale: Locale.current.identifier
                                )
                            }
                        }
                    }
                )
            }
        }
        voiceToText.onFinalTranscript = handleFinalTranscript
        transcriptController.onForceFinal  = handleFinalTranscript
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
        case .joinSpeaker(let targetName):
            return cs.joinSpeakers(speaker.name, targetName)
        case .leaveSpeaker:         return cs.leaveSpeaker(speaker.name)
        case .listFavorites, .confirm, .cancel, .unknown:
            return nil
        // Broadcast commands execute immediately — no countdown confirmation (ADR E-37).
        case .stopAll, .pauseAll, .resumeAll, .adjustVolumeAll, .muteAll, .unmuteAll:
            return nil
        }
    }

    private func completionMessage(for command: VoiceCommand, speaker: Speaker, resolvedTarget: Speaker? = nil) -> String? {
        switch command {
        case .stop:                 return cs.stopped(speaker.name)
        case .pause:                return cs.paused(speaker.name)
        case .resume:               return cs.resumed(speaker.name)
        case .setVolume(let level): return cs.volumeSet(speaker.name, level)
        case .adjustVolume:         return cs.volumeAdjusted(speaker.name)
        case .mute:                 return cs.muted(speaker.name)
        case .unmute:               return cs.unmuted(speaker.name)
        case .joinSpeaker:
            if let target = resolvedTarget { return cs.joined(speaker.name, target.name) }
            return nil
        case .leaveSpeaker:         return cs.leftGroup(speaker.name)
        default:                    return nil
        }
    }

    // ── Command dispatch ──────────────────────────────────────────────────────

    @MainActor
    @discardableResult
    private func dispatch(command: VoiceCommand, to speaker: Speaker) async -> Bool {
        switch command {
        case .playFavorite(let index):
            await discovery.favorites.play(index: index, on: speaker)
            return true
        case .playDefault:
            await discovery.favorites.playDefault(on: speaker)
            return true
        case .listFavorites:
            let names = await discovery.favorites.listFavorites(for: speaker)
            let list  = names.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "  ·  ")
            transcriptController.update(cs.listFavoritesResult(speaker.name, list))
            transcriptController.clearAfterCommand()
            return true
        case .stop:
            return await perform(speaker: speaker) { try await speaker.stop() }
        case .pause:
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
        case .joinSpeaker(let targetName):
            let allSpeakers = discovery.groups.flatMap(\.members)
            guard !targetName.isEmpty else {
                handleError(.noSpeakerSpoken(available: allSpeakers.map(\.name)))
                return false
            }
            let lower = targetName.lowercased()
            guard let target = allSpeakers.first(where: {
                $0.name.lowercased().contains(lower) || lower.contains($0.name.lowercased())
            }) else {
                handleError(.speakerNotFound(spoken: targetName, available: allSpeakers.map(\.name)))
                return false
            }
            // Master-side expand: tell the target (currently broadcasting) to add the
            // command-issuing speaker as a listener.
            return await perform(speaker: target) {
                try await target.client.join(peer: speaker.identifier)
                discovery.mergeIntoSpeakerGroup(source: speaker, target: target)
            }
        case .leaveSpeaker:
            return await perform(speaker: speaker) {
                try await speaker.client.leave()
                discovery.removeMember(speaker)
            }
        case .confirm, .cancel, .unknown:
            Log.info("[HomeView] unhandled: \(command)")
            return false
        // Broadcast commands are handled before dispatch() is called (see isBroadcast intercept).
        case .stopAll, .pauseAll, .resumeAll, .adjustVolumeAll, .muteAll, .unmuteAll:
            Log.info("[HomeView] broadcast command reached dispatch unexpectedly: \(command)")
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
        } catch let error as SpeakerError {
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
    private func handlePlayFavorite(index: Int, speaker: Speaker) async {
        guard let favorite = await discovery.favorites.favorite(at: index, for: speaker) else {
            let available = await discovery.favorites.listFavorites(for: speaker)
            Log.info("[HomeView][clear] path=handlePlayFavorite guardFail index=\(index) → clearAfterCommand")
            handleError(.favoriteIndexOutOfRange(index: index, speaker: speaker.name, available: available))
            transcriptController.clearAfterCommand()
            return
        }
        Log.info("[HomeView][clear] path=handlePlayFavorite countdown favorite=\(favorite.displayName)")
        let confirmMsg = cs.playFavoriteByName(favorite.displayName, speaker.name)
        coordinator.startCountdown(
            action: {
                let succeeded = await perform(speaker: speaker) {
                    try await speaker.playFavorite(presetIndex: favorite.presetIndex)
                }
                if succeeded { showSuccess("Done") }
                transcriptController.clearAfterCommand()
            },
            readBack: confirmMsg,
            onResolved: { _ in }
        )
    }

    private func preflightError(for command: VoiceCommand, speaker: Speaker) -> AppError? {
        switch command {
        case .adjustVolume(let d) where d > 0:
            if let vol = speaker.volume, vol >= 100 { return .volumeAtLimit(speaker: speaker.name, atMax: true) }
        case .adjustVolume(let d) where d < 0:
            if let vol = speaker.volume, vol <= 0 { return .volumeAtLimit(speaker: speaker.name, atMax: false) }
        case .mute:
            if speaker.isMuted { return .alreadyMuted(speaker: speaker.name) }
        // Broadcast commands execute immediately — no preflight (ADR E-37).
        case .stopAll, .pauseAll, .resumeAll, .adjustVolumeAll, .muteAll, .unmuteAll:
            return nil
        default: break
        }
        return nil
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

}
