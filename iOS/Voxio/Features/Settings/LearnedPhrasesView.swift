import SwiftUI

struct LearnedPhrasesView: View {
    let store: PersonalisationStore

    // Speaker IDs to group by; discovered speakers are not required here —
    // we group by whatever speakerIds exist in the learned-commands store.
    @State private var speakerGroups: [(speakerId: String, records: [ConfirmedCommandRecord])] = []
    @State private var showClearAllAlert = false
    @State private var deleteTarget: ConfirmedCommandRecord?
    @State private var showDeleteAlert = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEmpty: Bool { speakerGroups.isEmpty }

    var body: some View {
        ZStack {
            BeoColor.bg.ignoresSafeArea()

            if isEmpty {
                emptyState
            } else {
                phraseList
            }
        }
        .navigationTitle("Learned Phrases")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(BeoColor.bg, for: .navigationBar)
        .toolbar {
            if !isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear all") {
                        showClearAllAlert = true
                    }
                    .font(BeoType.body)
                    .foregroundStyle(.red)
                }
            }
        }
        .alert("Clear all learned phrases?", isPresented: $showClearAllAlert) {
            Button("Clear All", role: .destructive) {
                performClearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all learned phrases. This cannot be undone.")
        }
        .alert("Delete phrase?", isPresented: $showDeleteAlert, presenting: deleteTarget) { target in
            Button("Delete", role: .destructive) {
                performDelete(target)
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("This will permanently remove \"\(target.transcription)\".")
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.s24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(BeoColor.cardBg)
                    .frame(width: 96, height: 96)
                Image(systemName: "text.bubble")
                    .font(.system(size: 40))
                    .foregroundStyle(BeoColor.accent.opacity(0.8))
            }
            .accessibilityHidden(true)

            VStack(spacing: Spacing.s12) {
                Text("No learned phrases yet")
                    .font(BeoType.speakerName)
                    .foregroundStyle(BeoColor.text)
                    .multilineTextAlignment(.center)

                Text("Voxio remembers commands you confirm. They'll appear here after you use voice control.")
                    .font(BeoType.body)
                    .foregroundStyle(BeoColor.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.s16)
    }

    // MARK: - Phrase List

    private var phraseList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(speakerGroups, id: \.speakerId) { group in
                    speakerSection(group)
                }
            }
            .padding(.vertical, Spacing.s20)
        }
    }

    private func speakerSection(
        _ group: (speakerId: String, records: [ConfirmedCommandRecord])
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.speakerId.uppercased())
                .font(BeoType.caption)
                .foregroundStyle(BeoColor.muted)
                .padding(.leading, Spacing.s16)
                .padding(.bottom, Spacing.s8)
                .padding(.top, Spacing.s20)

            VStack(spacing: 0) {
                ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        Divider()
                            .background(BeoColor.separator)
                            .padding(.leading, Spacing.s16)
                    }
                    learnedPhraseRow(record)
                }
            }
            .background(BeoColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(BeoColor.cardBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.s16)
        }
    }

    private func learnedPhraseRow(_ record: ConfirmedCommandRecord) -> some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text(record.transcription)
                    .font(BeoType.nowPlaying)
                    .foregroundStyle(BeoColor.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: Spacing.s8) {
                    Text(intentLabel(record.intent))
                        .font(BeoType.body)
                        .foregroundStyle(BeoColor.muted)

                    Text("·")
                        .font(BeoType.body)
                        .foregroundStyle(BeoColor.muted)

                    Text(usageLabel(record))
                        .font(BeoType.caption)
                        .foregroundStyle(BeoColor.muted)
                }
            }
            .padding(.vertical, Spacing.s12)
            .padding(.leading, Spacing.s16)

            Spacer()

            Text(relativeDateLabel(record.lastUsedAt))
                .font(BeoType.caption)
                .foregroundStyle(BeoColor.muted)
                .padding(.trailing, Spacing.s16)
        }
        .frame(minHeight: 64)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteTarget = record
                showDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(record.transcription). \(intentLabel(record.intent)). \(usageLabel(record)). Last used \(relativeDateLabel(record.lastUsedAt)).")
    }

    // MARK: - Actions

    private func reload() {
        // Collect all speaker IDs that have confirmed commands.
        // We don't have direct access to a distinct list of speakerIds, so we
        // load progressively: fetch per speaker using whatever IDs we know,
        // plus a broad fetch to surface any speaker ID present in the store.
        let allRecords = fetchAllConfirmedCommands()
        let ids = Set(allRecords.map(\.speakerId))
        speakerGroups = ids
            .map { sid in (sid, allRecords.filter { $0.speakerId == sid }) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private func fetchAllConfirmedCommands() -> [ConfirmedCommandRecord] {
        store.allConfirmedCommandRecords()
    }

    private func performDelete(_ record: ConfirmedCommandRecord) {
        withAnimation(reduceMotion ? nil : BeoAnimation.spring) {
            try? store.deleteConfirmedCommand(transcription: record.transcription, speakerId: record.speakerId)
            reload()
        }
    }

    private func performClearAll() {
        withAnimation(reduceMotion ? nil : BeoAnimation.spring) {
            try? store.clearAllConfirmedCommands()
            reload()
        }
    }

    // MARK: - Formatters

    private func intentLabel(_ intent: CommandIntent) -> String {
        switch intent {
        case .playNamed:            return "Play favourite"
        case .playFavoriteByNumber: return "Play by number"
        case .playDefault:          return "Play"
        case .setVolume:            return "Set volume"
        case .volumeUp:             return "Volume up"
        case .volumeDown:           return "Volume down"
        case .mute:                 return "Mute"
        case .unmute:               return "Unmute"
        case .stop:                 return "Stop"
        case .pause:                return "Pause"
        case .resume:               return "Resume"
        case .joinSpeaker:          return "Join speaker"
        case .leaveSpeaker:         return "Leave group"
        case .listFavorites:        return "List favourites"
        case .confirm:              return "Confirm"
        case .cancel:               return "Cancel"
        case .stopAll:              return "Stop all"
        case .pauseAll:             return "Pause all"
        case .resumeAll:            return "Resume all"
        case .volumeUpAll:          return "Volume up all"
        case .volumeDownAll:        return "Volume down all"
        case .muteAll:              return "Mute all"
        case .unmuteAll:            return "Unmute all"
        case .unknown:              return "Unknown"
        }
    }

    private func usageLabel(_ record: ConfirmedCommandRecord) -> String {
        record.useCount == 1 ? "Used once" : "Used \(record.useCount) times"
    }

    private func relativeDateLabel(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Previews

#Preview("LearnedPhrasesView — empty") {
    NavigationStack {
        LearnedPhrasesView(
            store: PersonalisationStore(context: PersistenceController.preview.viewContext)
        )
    }
}
