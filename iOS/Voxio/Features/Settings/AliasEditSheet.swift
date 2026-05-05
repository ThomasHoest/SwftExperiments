import Speech
import SwiftUI

// MARK: - AliasEditSheet

struct AliasEditSheet: View {
    enum Mode {
        case add
        case edit(AliasRecord)
    }

    let mode: Mode
    let store: PersonalisationStore
    let discoveredSpeakers: [Speaker]
    @Binding var isPresented: Bool

    // MARK: Step tracking

    @State private var currentStep: Int = 1

    // MARK: Step 1 state

    @State private var phrase: String = ""
    @FocusState private var phraseFieldFocused: Bool
    @State private var validationMessage: String? = nil
    @State private var isListening: Bool = false
    @State private var micDenied: Bool = false

    // MARK: Step 2 state

    @State private var selectedSpeakerId: String = ""
    @State private var selectedIntent: CommandIntent? = nil
    @State private var favoriteName: String = ""
    @State private var favoriteIndex: Int = 1
    @State private var volumeValue: Int = 40
    @State private var targetSpeakerName: String = ""
    @State private var speakerFavorites: [Favorite] = []
    @State private var isFetchingFavorites: Bool = false

    // MARK: Dirty / confirm-discard state

    @State private var showDiscardAlert: Bool = false
    @State private var showDeleteAlert: Bool = false

    // MARK: Mic

    @State private var speechRecognizer: SFSpeechRecognizer? = nil
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest? = nil
    @State private var recognitionTask: SFSpeechRecognitionTask? = nil
    @State private var audioEngine: AVAudioEngine? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Helpers

    private var isEditMode: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingAlias: AliasRecord? {
        if case .edit(let record) = mode { return record }
        return nil
    }

    private var initialPhrase: String {
        editingAlias?.phrase ?? ""
    }

    private var initialSpeakerId: String {
        editingAlias?.speakerId ?? (discoveredSpeakers.first?.stableId ?? "")
    }

    private var isDirty: Bool {
        if isEditMode {
            guard let original = editingAlias else { return false }
            let intentChanged   = selectedIntent != original.intent
            let phraseChanged   = phrase != original.phrase
            let speakerChanged  = selectedSpeakerId != original.speakerId
            let slotsChanged    = currentSlots != original.slots
            return intentChanged || phraseChanged || speakerChanged || slotsChanged
        } else {
            return !phrase.isEmpty || selectedIntent != nil
        }
    }

    private var currentSlots: [String: String] {
        guard let intent = selectedIntent else { return [:] }
        switch intent {
        case .playNamed:           return ["favoriteName": favoriteName]
        case .playFavoriteByNumber: return ["favoriteIndex": "\(favoriteIndex)"]
        case .setVolume:           return ["volumeValue": "\(volumeValue)"]
        case .joinSpeaker:         return ["targetSpeakerName": targetSpeakerName]
        default:                   return [:]
        }
    }

    private var isSaveEnabled: Bool {
        guard !phrase.isEmpty, let _ = selectedIntent else { return false }
        switch selectedIntent {
        case .playNamed:           return !favoriteName.isEmpty
        case .playFavoriteByNumber: return favoriteIndex >= 1 && favoriteIndex <= 9
        case .setVolume:           return true
        case .joinSpeaker:         return !targetSpeakerName.isEmpty
        default:                   return false
        }
    }

    private var selectedSpeakerName: String {
        discoveredSpeakers.first(where: { $0.stableId == selectedSpeakerId })?.name ?? selectedSpeakerId
    }

    private var otherSpeakers: [Speaker] {
        discoveredSpeakers.filter { $0.stableId != selectedSpeakerId }
    }

    private var previewResolvedLine: String {
        guard let intent = selectedIntent else { return "Pick a command below" }
        switch intent {
        case .playNamed:
            return favoriteName.isEmpty ? "→ (choose favourite)" : "→ \(favoriteName)"
        case .playFavoriteByNumber:
            return "→ Favourite \(favoriteIndex)"
        case .setVolume:
            return "→ Volume \(volumeValue)"
        case .joinSpeaker:
            return targetSpeakerName.isEmpty ? "→ Join (choose speaker)" : "→ Join \(targetSpeakerName)"
        default:
            return "→ \(intent.rawValue)"
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            BeoColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHeader
                Divider().background(BeoColor.separator)

                if currentStep == 1 {
                    step1Content
                        .transition(reduceMotion
                            ? .opacity.animation(.easeInOut(duration: 0.2))
                            : .asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal:   .move(edge: .trailing).combined(with: .opacity)
                              ).animation(BeoAnimation.cardExpand)
                        )
                } else {
                    step2Content
                        .transition(reduceMotion
                            ? .opacity.animation(.easeInOut(duration: 0.2))
                            : .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal:   .move(edge: .leading).combined(with: .opacity)
                              ).animation(BeoAnimation.cardExpand)
                        )
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isDirty)
        .alert("Discard changes?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { isPresented = false }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Your alias will not be saved.")
        }
        .alert("Delete alias?", isPresented: $showDeleteAlert, presenting: editingAlias) { alias in
            Button("Delete", role: .destructive) {
                try? store.deleteAlias(alias.id)
                isPresented = false
            }
            Button("Cancel", role: .cancel) {}
        } message: { alias in
            Text("This will permanently remove \"\(alias.phrase)\".")
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: onAppear)
        .onDisappear(perform: stopMic)
    }

    // MARK: - Sheet header

    private var sheetHeader: some View {
        VStack(spacing: Spacing.s8) {
            ZStack {
                Text(isEditMode ? "Edit alias" : "Add alias")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(BeoColor.text)
                    .frame(maxWidth: .infinity)

                HStack {
                    Button {
                        handleCancel()
                    } label: {
                        Text("Cancel")
                            .font(BeoType.body)
                            .foregroundStyle(BeoColor.accent)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .padding(.leading, Spacing.s4)

                    Spacer()

                    if isEditMode {
                        Button {
                            showDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 22))
                                .foregroundStyle(.red)
                                .frame(width: 44, height: 44)
                        }
                        .padding(.trailing, Spacing.s4)
                        .accessibilityLabel("Delete alias for \(initialPhrase). Destructive.")
                    }
                }
            }

            stepIndicator
                .padding(.bottom, Spacing.s4)
        }
        .frame(minHeight: 56)
        .padding(.top, Spacing.s8)
    }

    private var stepIndicator: some View {
        HStack(spacing: Spacing.s8) {
            ForEach(1...2, id: \.self) { step in
                Circle()
                    .fill(step == currentStep ? BeoColor.accent : BeoColor.muted.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .clipShape(Capsule())
            }
            Text(currentStep == 1 ? "1 of 2" : "2 of 2")
                .font(BeoType.caption)
                .foregroundStyle(BeoColor.muted)
                .padding(.leading, Spacing.s4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep) of 2")
    }

    // MARK: - Step 1

    private var step1Content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("What do you want to say?")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(BeoColor.text)
                    .padding(.top, Spacing.s24)
                    .padding(.horizontal, Spacing.s16)

                Text("Say exactly what you want Voxio to hear, e.g. \"morning music\".")
                    .font(BeoType.body)
                    .foregroundStyle(BeoColor.muted)
                    .padding(.top, Spacing.s8)
                    .padding(.horizontal, Spacing.s16)

                // Phrase input row
                HStack(spacing: Spacing.s8) {
                    phraseField
                    micButton
                }
                .padding(.top, Spacing.s20)
                .padding(.horizontal, Spacing.s16)

                // Inline validation
                if let msg = validationMessage {
                    HStack(spacing: Spacing.s4) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                        Text(msg)
                            .font(BeoType.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(.top, Spacing.s8)
                    .padding(.horizontal, Spacing.s16)
                    .transition(.opacity.animation(BeoAnimation.toast))
                }

                if micDenied {
                    Text("Speech recognition not available — type the phrase instead.")
                        .font(BeoType.caption)
                        .foregroundStyle(.red)
                        .padding(.top, Spacing.s8)
                        .padding(.horizontal, Spacing.s16)
                        .transition(.opacity.animation(BeoAnimation.toast))
                }

                Spacer(minLength: Spacing.s24 + 44 + Spacing.s24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            continueButton
                .padding(.bottom, Spacing.s24)
                .background(BeoColor.bg)
        }
    }

    private var phraseField: some View {
        TextField("Type or dictate a phrase", text: $phrase)
            .font(BeoType.nowPlaying)
            .foregroundStyle(BeoColor.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(false)
            .focused($phraseFieldFocused)
            .padding(.horizontal, Spacing.s16)
            .padding(.vertical, 14)
            .background(BeoColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(
                        validationMessage != nil ? Color.red :
                            (phraseFieldFocused ? BeoColor.accent : BeoColor.cardBorder),
                        lineWidth: phraseFieldFocused || validationMessage != nil ? 1 : 0.5
                    )
            )
            .onChange(of: phrase) { _, _ in
                // Clear validation on edit so the user gets real-time feedback relief.
                if validationMessage != nil { validationMessage = nil }
            }
    }

    private var micButton: some View {
        Button {
            toggleMic()
        } label: {
            ZStack {
                Circle()
                    .fill(isListening ? BeoColor.accent : BeoColor.cardBg)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle().strokeBorder(
                            isListening ? BeoColor.accent : BeoColor.cardBorder,
                            lineWidth: 0.5
                        )
                    )

                if isListening {
                    WaveformMicIndicator()
                } else {
                    Image(systemName: "mic")
                        .font(.system(size: 22))
                        .foregroundStyle(BeoColor.text)
                }
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityLabel(isListening ? "Stop dictation" : "Dictate phrase")
        .accessibilityHint("Double-tap to begin or end dictation")
    }

    private var continueButton: some View {
        addAliasButton("Continue") {
            handleContinue()
        }
        .disabled(phrase.isEmpty)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Step 2

    private var step2Content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Back button
                Button {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : BeoAnimation.cardExpand) {
                        currentStep = 1
                    }
                } label: {
                    HStack(spacing: Spacing.s4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(BeoType.body)
                    }
                    .foregroundStyle(BeoColor.accent)
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, Spacing.s16)
                .padding(.top, Spacing.s8)

                Text("What should it do?")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(BeoColor.text)
                    .padding(.horizontal, Spacing.s16)
                    .padding(.top, Spacing.s8)

                // Live preview panel
                livePreviewPanel
                    .padding(.top, Spacing.s16)
                    .padding(.horizontal, Spacing.s16)

                // Speaker selector
                Text("ON SPEAKER")
                    .font(BeoType.caption)
                    .foregroundStyle(BeoColor.muted)
                    .padding(.leading, Spacing.s16)
                    .padding(.top, Spacing.s20)

                speakerSelector
                    .padding(.horizontal, Spacing.s16)
                    .padding(.top, Spacing.s8)

                // Speaker-change annotation in edit mode
                if isEditMode,
                   let original = editingAlias,
                   selectedSpeakerId != original.speakerId {
                    let originalName = discoveredSpeakers.first(where: { $0.stableId == original.speakerId })?.name ?? original.speakerId
                    Text("This will move the alias from \(originalName).")
                        .font(BeoType.caption)
                        .foregroundStyle(BeoColor.muted)
                        .padding(.horizontal, Spacing.s16)
                        .padding(.top, Spacing.s4)
                }

                // Command type picker
                Text("COMMAND")
                    .font(BeoType.caption)
                    .foregroundStyle(BeoColor.muted)
                    .padding(.leading, Spacing.s16)
                    .padding(.top, Spacing.s20)

                commandTypePicker
                    .padding(.horizontal, Spacing.s16)
                    .padding(.top, Spacing.s8)

                // Detail control (expands below the command picker card)
                if let intent = selectedIntent {
                    detailControl(for: intent)
                        .padding(.horizontal, Spacing.s16)
                        .padding(.top, Spacing.s12)
                        .transition(.opacity.combined(with: .move(edge: .top)).animation(BeoAnimation.cardExpand))
                }

                Spacer(minLength: Spacing.s24 + 44 + Spacing.s24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            saveButton
                .padding(.bottom, Spacing.s24)
                .background(BeoColor.bg)
        }
    }

    private var livePreviewPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text("\"\(phrase)\"")
                .font(BeoType.confirmation)
                .foregroundStyle(BeoColor.text)
            Text(selectedIntent == nil ? "Pick a command below" : "\(previewResolvedLine) on \(selectedSpeakerName)")
                .font(BeoType.body)
                .foregroundStyle(BeoColor.muted)
                .italic(selectedIntent == nil)
                .animation(BeoAnimation.toast, value: previewResolvedLine)
        }
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BeoColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(BeoColor.accent, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(selectedIntent == nil
            ? "Preview: \(phrase). Pick a command below."
            : "Preview: \(phrase) to \(previewResolvedLine) on \(selectedSpeakerName)"
        )
    }

    @ViewBuilder
    private var speakerSelector: some View {
        if discoveredSpeakers.count <= 3 {
            Picker("Speaker", selection: $selectedSpeakerId) {
                ForEach(discoveredSpeakers) { speaker in
                    Text(speaker.name).tag(speaker.stableId)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedSpeakerId) { _, _ in
                onSpeakerChanged()
            }
        } else {
            Menu {
                ForEach(discoveredSpeakers) { speaker in
                    Button(speaker.name) {
                        selectedSpeakerId = speaker.stableId
                        onSpeakerChanged()
                    }
                }
            } label: {
                HStack {
                    Text(selectedSpeakerName)
                        .font(BeoType.body)
                        .foregroundStyle(BeoColor.text)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 14))
                        .foregroundStyle(BeoColor.muted)
                }
                .padding(.horizontal, Spacing.s16)
                .padding(.vertical, 14)
                .background(BeoColor.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(BeoColor.cardBorder, lineWidth: 0.5)
                )
            }
        }
    }

    private var commandTypePicker: some View {
        VStack(spacing: 0) {
            commandTypeRow(
                icon: "music.note",
                label: "Play a favourite",
                intent: .playNamed
            )
            Divider().background(BeoColor.separator).padding(.leading, Spacing.s16)
            commandTypeRow(
                icon: "number",
                label: "Play favourite by number",
                intent: .playFavoriteByNumber
            )
            Divider().background(BeoColor.separator).padding(.leading, Spacing.s16)
            commandTypeRow(
                icon: "speaker.wave.2.fill",
                label: "Set volume",
                intent: .setVolume
            )
            Divider().background(BeoColor.separator).padding(.leading, Spacing.s16)
            commandTypeRow(
                icon: "link",
                label: "Join another speaker",
                intent: .joinSpeaker
            )
        }
        .background(BeoColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(BeoColor.cardBorder, lineWidth: 0.5)
        )
    }

    private func commandTypeRow(icon: String, label: String, intent: CommandIntent) -> some View {
        let isSelected = selectedIntent == intent
        return Button {
            withAnimation(BeoAnimation.cardExpand) {
                selectedIntent = intent
            }
        } label: {
            HStack(spacing: Spacing.s12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(BeoColor.accent)
                    .frame(width: 24, height: 24)

                Text(label)
                    .font(BeoType.body)
                    .foregroundStyle(BeoColor.text)

                Spacer()

                Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(BeoColor.muted)
            }
            .padding(.horizontal, Spacing.s16)
            .padding(.vertical, 0)
            .frame(minHeight: 56)
            .background(isSelected ? BeoColor.accent.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func detailControl(for intent: CommandIntent) -> some View {
        switch intent {
        case .playNamed:
            favouriteByNameControl
        case .playFavoriteByNumber:
            favouriteByNumberControl
        case .setVolume:
            setVolumeControl
        case .joinSpeaker:
            joinSpeakerControl
        default:
            EmptyView()
        }
    }

    // MARK: Detail control A — Play favourite by name

    private var favouriteByNameControl: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("Choose favourite")
                .font(BeoType.caption)
                .foregroundStyle(BeoColor.muted)

            if isFetchingFavorites {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.s12)
            } else if speakerFavorites.isEmpty {
                Text("No favourites available for this speaker.")
                    .font(BeoType.body)
                    .foregroundStyle(BeoColor.muted)
                    .padding(.vertical, Spacing.s8)
            } else {
                VStack(spacing: 0) {
                    ForEach(speakerFavorites) { fav in
                        let isSelected = favoriteName == fav.displayName
                        Button {
                            favoriteName = fav.displayName
                        } label: {
                            HStack {
                                Text(fav.displayName)
                                    .font(BeoType.body)
                                    .foregroundStyle(BeoColor.text)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16))
                                        .foregroundStyle(BeoColor.accent)
                                }
                            }
                            .padding(.horizontal, Spacing.s16)
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if fav.id != speakerFavorites.last?.id {
                            Divider().background(BeoColor.separator).padding(.leading, Spacing.s16)
                        }
                    }
                }
            }
        }
        .padding(Spacing.s16)
        .background(BeoColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(BeoColor.cardBorder, lineWidth: 0.5)
        )
        .task(id: selectedSpeakerId) {
            await fetchFavoritesForSelectedSpeaker()
        }
    }

    // MARK: Detail control B — Play favourite by number

    private var favouriteByNumberControl: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("Favourite number")
                .font(BeoType.caption)
                .foregroundStyle(BeoColor.muted)

            HStack(spacing: Spacing.s20) {
                Button {
                    if favoriteIndex > 1 { favoriteIndex -= 1 }
                } label: {
                    ZStack {
                        Circle()
                            .fill(BeoColor.cardBg)
                            .frame(width: 44, height: 44)
                        Image(systemName: "minus")
                            .font(.system(size: 22))
                            .foregroundStyle(BeoColor.accent)
                    }
                }
                .disabled(favoriteIndex <= 1)

                Text("\(favoriteIndex)")
                    .font(BeoType.speakerName)
                    .foregroundStyle(BeoColor.text)
                    .frame(minWidth: 48, minHeight: 48)
                    .multilineTextAlignment(.center)

                Button {
                    if favoriteIndex < 9 { favoriteIndex += 1 }
                } label: {
                    ZStack {
                        Circle()
                            .fill(BeoColor.cardBg)
                            .frame(width: 44, height: 44)
                        Image(systemName: "plus")
                            .font(.system(size: 22))
                            .foregroundStyle(BeoColor.accent)
                    }
                }
                .disabled(favoriteIndex >= 9)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Spacing.s16)
        .background(BeoColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(BeoColor.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: Detail control C — Set volume

    private var setVolumeControl: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            HStack {
                Text("Volume level")
                    .font(BeoType.caption)
                    .foregroundStyle(BeoColor.muted)
                Spacer()
                Text("\(volumeValue)%")
                    .font(BeoType.confirmation)
                    .foregroundStyle(BeoColor.text)
            }

            Slider(value: Binding(
                get: { Double(volumeValue) },
                set: { volumeValue = Int(($0 / 5).rounded()) * 5 }
            ), in: 0...100, step: 5)
            .tint(BeoColor.accent)
        }
        .padding(Spacing.s16)
        .background(BeoColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(BeoColor.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: Detail control D — Join another speaker

    private var joinSpeakerControl: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("Speaker to join")
                .font(BeoType.caption)
                .foregroundStyle(BeoColor.muted)

            if otherSpeakers.isEmpty {
                Text("No other speakers discovered.")
                    .font(BeoType.body)
                    .foregroundStyle(BeoColor.muted)
                    .padding(.vertical, Spacing.s8)
            } else {
                VStack(spacing: 0) {
                    ForEach(otherSpeakers) { speaker in
                        let isSelected = targetSpeakerName == speaker.name
                        Button {
                            targetSpeakerName = speaker.name
                        } label: {
                            HStack {
                                Text(speaker.name)
                                    .font(BeoType.body)
                                    .foregroundStyle(BeoColor.text)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16))
                                        .foregroundStyle(BeoColor.accent)
                                }
                            }
                            .padding(.horizontal, Spacing.s16)
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if speaker.id != otherSpeakers.last?.id {
                            Divider().background(BeoColor.separator).padding(.leading, Spacing.s16)
                        }
                    }
                }
            }
        }
        .padding(Spacing.s16)
        .background(BeoColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(BeoColor.cardBorder, lineWidth: 0.5)
        )
    }

    private var saveButton: some View {
        addAliasButton(isEditMode ? "Save changes" : "Add alias") {
            handleSave()
        }
        .disabled(!isSaveEnabled || (isEditMode && !isDirty))
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Actions

    private func onAppear() {
        phrase = initialPhrase
        selectedSpeakerId = initialSpeakerId

        if case .edit(let record) = mode {
            selectedIntent = record.intent
            switch record.intent {
            case .playNamed:
                favoriteName = record.slots["favoriteName"] ?? ""
            case .playFavoriteByNumber:
                favoriteIndex = Int(record.slots["favoriteIndex"] ?? "1") ?? 1
            case .setVolume:
                volumeValue = Int(record.slots["volumeValue"] ?? "40") ?? 40
            case .joinSpeaker:
                targetSpeakerName = record.slots["targetSpeakerName"] ?? ""
            default:
                break
            }
        }

        if !isEditMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                phraseFieldFocused = true
            }
        }
    }

    private func handleCancel() {
        if isDirty {
            showDiscardAlert = true
        } else {
            isPresented = false
        }
    }

    private func handleContinue() {
        let trimmed = phrase.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            withAnimation(BeoAnimation.toast) { validationMessage = "Enter a phrase first." }
            return
        }
        if trimmed.lowercased().contains("voxio") {
            withAnimation(BeoAnimation.toast) {
                validationMessage = "Phrases cannot contain \"Voxio\" — it's the app's wake word."
            }
            return
        }
        // Check for duplicate on the same speaker (skip check for the current alias in edit mode)
        let existingAliases = store.aliases(for: selectedSpeakerId)
        let isDuplicate = existingAliases.contains(where: { record in
            record.phrase == trimmed.lowercased() && record.id != editingAlias?.id
        })
        if isDuplicate {
            withAnimation(BeoAnimation.toast) {
                validationMessage = "A phrase already exists for this action. Delete the existing alias first."
            }
            return
        }

        phrase = trimmed
        validationMessage = nil
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : BeoAnimation.cardExpand) {
            currentStep = 2
        }
    }

    private func handleSave() {
        guard let intent = selectedIntent else { return }
        do {
            if isEditMode, let original = editingAlias {
                try store.updateAlias(
                    id: original.id,
                    speakerId: selectedSpeakerId,
                    phrase: phrase,
                    intent: intent,
                    slots: currentSlots
                )
            } else {
                try store.saveAlias(
                    speakerId: selectedSpeakerId,
                    phrase: phrase,
                    intent: intent,
                    slots: currentSlots
                )
            }
            isPresented = false
        } catch PersonalisationStore.SaveAliasError.reservedWord {
            withAnimation(BeoAnimation.toast) {
                validationMessage = "Phrases cannot contain \"Voxio\" — it's the app's wake word."
                currentStep = 1
            }
        } catch PersonalisationStore.SaveAliasError.duplicatePhrase {
            withAnimation(BeoAnimation.toast) {
                validationMessage = "A phrase already exists for this action. Delete the existing alias first."
                currentStep = 1
            }
        } catch {
            Log.error("[AliasEditSheet] save failed: \(error)")
        }
    }

    private func onSpeakerChanged() {
        // When the speaker changes in edit mode, if a play-by-name favourite was selected,
        // reset it because the new speaker may not have the same favourite list.
        if selectedIntent == .playNamed { favoriteName = "" }
        // Reset join target if it's no longer valid.
        if selectedIntent == .joinSpeaker {
            if !otherSpeakers.contains(where: { $0.name == targetSpeakerName }) {
                targetSpeakerName = otherSpeakers.first?.name ?? ""
            }
        }
    }

    // MARK: - Favourites fetch

    private func fetchFavoritesForSelectedSpeaker() async {
        guard let speaker = discoveredSpeakers.first(where: { $0.stableId == selectedSpeakerId }) else {
            speakerFavorites = []
            return
        }
        isFetchingFavorites = true
        do {
            let favs = try await speaker.getFavorites()
            speakerFavorites = favs
        } catch {
            Log.error("[AliasEditSheet] getFavorites failed: \(error)")
            speakerFavorites = []
        }
        isFetchingFavorites = false
    }

    // MARK: - Mic (fresh SFSpeechRecognizer instance, NOT VoiceToText)

    private func toggleMic() {
        if isListening {
            stopMic()
        } else {
            startMic()
        }
    }

    private func startMic() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    micDenied = true
                    return
                }
                micDenied = false
                beginRecognition()
            }
        }
    }

    private func beginRecognition() {
        let locale = Locale.current
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            micDenied = true
            return
        }
        speechRecognizer = recognizer

        let engine = AVAudioEngine()
        audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        // Dismiss keyboard before starting audio session
        phraseFieldFocused = false

        do {
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            try engine.start()
        } catch {
            Log.error("[AliasEditSheet] audio engine start failed: \(error)")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            DispatchQueue.main.async {
                if let result {
                    phrase = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal == true) {
                    stopMic()
                }
            }
        }

        isListening = true
    }

    private func stopMic() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        speechRecognizer = nil
        isListening = false
    }
}

// MARK: - Waveform mic indicator (3-bar animation)

private struct WaveformMicIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animating = false

    var body: some View {
        HStack(spacing: 2) {
            bar(phase: 0.0)
            bar(phase: 0.3)
            bar(phase: 0.6)
        }
        .frame(width: 22, height: 22)
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }

    private func bar(phase: Double) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(BeoColor.text)
            .frame(width: 3)
            .frame(height: animating && !reduceMotion ? 18 : 8)
            .animation(
                reduceMotion ? nil :
                    .easeInOut(duration: 0.7)
                    .repeatForever(autoreverses: true)
                    .delay(phase),
                value: animating
            )
    }
}

// MARK: - Previews

#Preview("AliasEditSheet — add") {
    AliasEditSheet(
        mode: .add,
        store: PersonalisationStore(context: PersistenceController.preview.viewContext),
        discoveredSpeakers: [],
        isPresented: .constant(true)
    )
}
