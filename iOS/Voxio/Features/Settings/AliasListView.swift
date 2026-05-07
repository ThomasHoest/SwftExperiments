import SwiftUI

struct AliasListView: View {
    let store: PersonalisationStore
    let discoveredSpeakers: [Speaker]

    @State private var allAliases: [AliasRecord] = []
    @State private var showAddSheet = false
    @State private var editingAlias: AliasRecord?
    @State private var deleteTarget: AliasRecord?
    @State private var bulkDeleteSpeakerId: String?
    @State private var showDeleteSingleAlert = false
    @State private var showBulkDeleteAlert = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Aliases grouped by speaker, sorted alphabetically by speaker name.
    private var grouped: [(speakerId: String, speakerName: String, aliases: [AliasRecord])] {
        let speakerIds = Set(allAliases.map(\.speakerId))
        return speakerIds
            .map { sid -> (String, String, [AliasRecord]) in
                let name = discoveredSpeakers.first(where: { $0.stableId == sid })?.name ?? sid
                let records = allAliases.filter { $0.speakerId == sid }
                return (sid, name, records)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            BeoColor.bg.ignoresSafeArea()

            if allAliases.isEmpty {
                emptyState
            } else {
                aliasList
            }
        }
        .navigationTitle("Aliases")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(BeoColor.bg, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(BeoColor.accent)
                }
                .accessibilityLabel("Add alias")
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: reloadAliases) {
            AliasEditSheet(
                mode: .add,
                store: store,
                discoveredSpeakers: discoveredSpeakers,
                isPresented: $showAddSheet
            )
        }
        .sheet(item: $editingAlias, onDismiss: reloadAliases) { alias in
            AliasEditSheet(
                mode: .edit(alias),
                store: store,
                discoveredSpeakers: discoveredSpeakers,
                isPresented: Binding(
                    get: { editingAlias != nil },
                    set: { if !$0 { editingAlias = nil } }
                )
            )
        }
        .alert("Delete alias?", isPresented: $showDeleteSingleAlert, presenting: deleteTarget) { target in
            Button("Delete", role: .destructive) {
                performDeleteSingle(target)
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("This will permanently remove \"\(target.phrase)\".")
        }
        .alert(
            bulkDeleteAlertTitle,
            isPresented: $showBulkDeleteAlert
        ) {
            Button("Delete All", role: .destructive) {
                if let sid = bulkDeleteSpeakerId {
                    performBulkDelete(speakerId: sid)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(bulkDeleteAlertMessage)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: reloadAliases)
        .onAppear { BreadcrumbTracker.shared.push("Settings.Aliases") }
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
                Text("No aliases yet")
                    .font(BeoType.speakerName)
                    .foregroundStyle(BeoColor.text)
                    .multilineTextAlignment(.center)

                Text("Teach Voxio your own phrases. Say \"morning music\" and have it play your favourite breakfast playlist.")
                    .font(BeoType.body)
                    .foregroundStyle(BeoColor.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            addAliasButton("Add alias") {
                showAddSheet = true
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.s16)
    }

    // MARK: - Alias List

    private var aliasList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                ForEach(grouped, id: \.speakerId) { group in
                    speakerSection(group)
                }
            }
            .padding(.vertical, Spacing.s20)
        }
    }

    private func speakerSection(
        _ group: (speakerId: String, speakerName: String, aliases: [AliasRecord])
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text(group.speakerName.uppercased())
                .font(BeoType.caption)
                .foregroundStyle(BeoColor.muted)
                .padding(.leading, Spacing.s16)
                .padding(.bottom, Spacing.s8)
                .padding(.top, Spacing.s20)

            // Card containing rows
            VStack(spacing: 0) {
                ForEach(Array(group.aliases.enumerated()), id: \.element.id) { index, alias in
                    if index > 0 {
                        Divider()
                            .background(BeoColor.separator)
                            .padding(.leading, Spacing.s16)
                    }
                    aliasRow(alias)
                }
            }
            .background(BeoColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(BeoColor.cardBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.s16)

            // Per-speaker bulk delete
            Button {
                bulkDeleteSpeakerId = group.speakerId
                showBulkDeleteAlert = true
            } label: {
                Text("Delete all aliases for \(group.speakerName)")
                    .font(BeoType.body)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .padding(.top, Spacing.s12)
            .padding(.horizontal, Spacing.s16)
            .accessibilityLabel("Delete all \(group.aliases.count) aliases for \(group.speakerName). Destructive.")
        }
    }

    private func aliasRow(_ alias: AliasRecord) -> some View {
        Button {
            editingAlias = alias
        } label: {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text(alias.phrase)
                        .font(BeoType.nowPlaying)
                        .foregroundStyle(BeoColor.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(resolvedCommandLabel(for: alias))
                        .font(BeoType.body)
                        .foregroundStyle(BeoColor.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.vertical, Spacing.s12)
                .padding(.leading, Spacing.s16)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(BeoColor.muted)
                    .accessibilityHidden(true)
                    .padding(.trailing, Spacing.s16)
            }
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteTarget = alias
                showDeleteSingleAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(alias.phrase), \(resolvedCommandLabel(for: alias)). Double-tap to edit.")
    }

    // MARK: - Alert helpers

    private var bulkDeleteAlertTitle: String {
        guard let sid = bulkDeleteSpeakerId,
              let group = grouped.first(where: { $0.speakerId == sid }) else {
            return "Delete all aliases?"
        }
        return "Delete all aliases for \(group.speakerName)?"
    }

    private var bulkDeleteAlertMessage: String {
        guard let sid = bulkDeleteSpeakerId,
              let group = grouped.first(where: { $0.speakerId == sid }) else {
            return "This cannot be undone."
        }
        let n = group.aliases.count
        return "This will permanently remove all \(n) aliases for \(group.speakerName). This cannot be undone."
    }

    // MARK: - Actions

    private func reloadAliases() {
        let speakerIds = Set(discoveredSpeakers.map { $0.stableId })
        allAliases = speakerIds.flatMap { store.aliases(for: $0) }
    }

    private func performDeleteSingle(_ alias: AliasRecord) {
        withAnimation(reduceMotion ? nil : BeoAnimation.spring) {
            try? store.deleteAlias(alias.id)
            reloadAliases()
        }
    }

    private func performBulkDelete(speakerId: String) {
        withAnimation(reduceMotion ? nil : BeoAnimation.spring) {
            try? store.deleteAllAliases(for: speakerId)
            reloadAliases()
        }
    }

    // MARK: - Resolved command label

    private func resolvedCommandLabel(for alias: AliasRecord) -> String {
        switch alias.intent {
        case .playNamed:
            let name = alias.slots["favoriteName"] ?? ""
            return "→ \(name)"
        case .playFavoriteByNumber:
            let n = alias.slots["favoriteIndex"] ?? "?"
            return "→ Favourite \(n)"
        case .setVolume:
            let vol = alias.slots["volumeValue"] ?? "?"
            return "→ Volume \(vol)"
        case .joinSpeaker:
            let target = alias.slots["targetSpeakerName"] ?? ""
            return "→ Join \(target)"
        default:
            return "→ \(alias.intent.rawValue)"
        }
    }
}

// MARK: - Gold CTA button (shared across Settings screens)

struct addAliasButton<Label: View>: View {
    let action: () -> Void
    let label: Label

    @State private var isPressed = false

    init(action: @escaping () -> Void, @ViewBuilder labelBuilder: () -> Label) {
        self.action = action
        self.label = labelBuilder()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BeoColor.text)
                .padding(.vertical, 14)
                .padding(.horizontal, Spacing.s24)
                .frame(minWidth: 220, minHeight: 44)
                .background(BeoColor.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(GoldCTAButtonStyle())
    }
}

extension addAliasButton where Label == Text {
    init(_ title: String, action: @escaping () -> Void) {
        self.action = action
        self.label = Text(title)
    }
}

struct GoldCTAButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? DarkGlassButtonTokens.pressedScale : 1)
            .animation(
                .spring(
                    response: DarkGlassButtonTokens.pressSpringResponse,
                    dampingFraction: DarkGlassButtonTokens.pressSpringDamping
                ),
                value: configuration.isPressed
            )
    }
}

// MARK: - Previews

#Preview("AliasListView — empty") {
    NavigationStack {
        AliasListView(
            store: PersonalisationStore(context: PersistenceController.preview.viewContext),
            discoveredSpeakers: []
        )
    }
}
