import SwiftUI

struct LearnedPhrasesView: View {
    let store: PersonalisationStore
    var discoveredSpeakers: [Speaker] = []
    @ObservedObject private var langService = LanguageService.shared

    @State private var speakerGroups: [(speakerId: String, records: [ConfirmedCommandRecord])] = []
    @State private var showClearAllAlert = false
    @State private var deleteTarget: ConfirmedCommandRecord?
    @State private var showDeleteAlert = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var str: SettingsStrings { .forLanguage(langService.activeLanguage) }
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
        .navigationTitle(str.learnedPhrasesTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(BeoColor.bg, for: .navigationBar)
        .toolbar {
            if !isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(str.clearAll) {
                        showClearAllAlert = true
                    }
                    .font(BeoType.body)
                    .foregroundStyle(.red)
                }
            }
        }
        .alert(str.clearAllAlertTitle, isPresented: $showClearAllAlert) {
            Button(str.clearAll, role: .destructive) {
                performClearAll()
            }
            Button(str.cancel, role: .cancel) {}
        } message: {
            Text(str.clearAllAlertMessage)
        }
        .alert(str.deleteAlertTitle, isPresented: $showDeleteAlert, presenting: deleteTarget) { target in
            Button(str.delete, role: .destructive) {
                performDelete(target)
            }
            Button(str.cancel, role: .cancel) {}
        } message: { target in
            Text(str.deleteAlertMessage(phrase: target.transcription))
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
        .onAppear { BreadcrumbTracker.shared.push("Settings.LearnedPhrases") }
        .onDisappear { BreadcrumbTracker.shared.pop() }
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
                Text(str.emptyTitle)
                    .font(BeoType.speakerName)
                    .foregroundStyle(BeoColor.text)
                    .multilineTextAlignment(.center)

                Text(str.emptySubtitle)
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
                Text(str.learnedPhrasesIntro)
                    .font(BeoType.body)
                    .foregroundStyle(BeoColor.muted)
                    .padding(.horizontal, Spacing.s16)
                    .padding(.top, Spacing.s20)
                    .padding(.bottom, Spacing.s8)

                ForEach(speakerGroups, id: \.speakerId) { group in
                    speakerSection(group)
                }
            }
            .padding(.bottom, Spacing.s20)
        }
    }

    private func displayName(for speakerId: String) -> String {
        if let speaker = discoveredSpeakers.first(where: { $0.stableId == speakerId }) {
            return speaker.name
        }
        return speakerId
    }

    private func speakerSection(
        _ group: (speakerId: String, records: [ConfirmedCommandRecord])
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(displayName(for: group.speakerId).uppercased())
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
                    Text(str.intentLabel(for: record.intent))
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
                Label(str.delete, systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(record.transcription). \(str.intentLabel(for: record.intent)). \(usageLabel(record)). Last used \(relativeDateLabel(record.lastUsedAt)).")
    }

    // MARK: - Actions

    private func reload() {
        let allRecords = store.allConfirmedCommandRecords()
        let ids = Set(allRecords.map(\.speakerId))
        speakerGroups = ids
            .map { sid in (sid, allRecords.filter { $0.speakerId == sid }) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
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

    private func usageLabel(_ record: ConfirmedCommandRecord) -> String {
        record.useCount == 1 ? str.usedOnce : str.usedTimes(count: record.useCount)
    }

    private func relativeDateLabel(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = langService.activeLanguage.locale
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Previews

#Preview("LearnedPhrasesView — empty") {
    NavigationStack {
        LearnedPhrasesView(
            store: PersonalisationStore(context: PersistenceController.preview.viewContext),
            discoveredSpeakers: []
        )
    }
}
