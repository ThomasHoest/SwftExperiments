import SwiftUI

// E-40 T-4001–T-4005 — Redesigned help screen.
// Presented as a .sheet from:
//   • HomeView questionmark.circle toolbar button (T-4006)
//   • SettingsView "Help" row (E-39 T-3906)
//
// HelpView is side-effect-free: speaker names are passed as value-type
// arguments resolved at sheet-open time (ADR §Rationale / design spec §3.7.1).

struct HelpView: View {
    let speakerA: String?
    let speakerB: String?
    let activeLanguage: Language
    @Binding var isPresented: Bool

    @State private var displayLanguage: Language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(speakerA: String?, speakerB: String?, activeLanguage: Language, isPresented: Binding<Bool>) {
        self.speakerA = speakerA
        self.speakerB = speakerB
        self.activeLanguage = activeLanguage
        self._isPresented = isPresented
        self._displayLanguage = State(initialValue: activeLanguage)
    }

    // MARK: — Computed helpers

    private var sections: [HelpSection] {
        HelpSection.all(speakerA: speakerA, speakerB: speakerB)
    }

    private var isEnglishActive: Bool { displayLanguage == .english }

    private var closeLabel: String {
        displayLanguage == .danish ? "Luk hjælp" : "Close help"
    }

    private var titleText: String {
        displayLanguage == .danish ? "Hjælp" : "Help"
    }

    // ADR E-40 §Conflicts 3 — display-only toggle; does not change recognition language.
    // Remove this caption if product owner decides toggle should change the app language.
    private var languageCaption: String {
        displayLanguage == .danish
            ? "Kun visning. Skift sprog i indstillinger."
            : "Display only. Change app language in Settings."
    }

    // MARK: — Body

    var body: some View {
        ZStack(alignment: .top) {
            BeoColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHeader
                Divider()
                    .background(BeoColor.separator)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Spacing.s24) {
                        ForEach(sections.indices, id: \.self) { index in
                            sectionCard(sections[index])
                        }
                    }
                    .padding(.horizontal, Spacing.s16)
                    .padding(.top, Spacing.s24)
                    .padding(.bottom, Spacing.s24)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: — Sheet header (spec §3.4)

    private var sheetHeader: some View {
        ZStack {
            // Centred title
            Text(titleText)
                .font(BeoType.nowPlaying)
                .foregroundStyle(BeoColor.text)
                .frame(maxWidth: .infinity)

            HStack {
                // Leading: close button
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(BeoColor.accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(closeLabel)

                Spacer()

                // Trailing: language toggle (spec §3.5)
                languageToggle
                    .padding(.trailing, Spacing.s16)
            }
        }
        .frame(height: 56)
        .padding(.leading, Spacing.s4)
    }

    // MARK: — Language toggle (spec §3.5)

    private var languageToggle: some View {
        VStack(alignment: .trailing, spacing: Spacing.s4) {
            Picker(
                displayLanguage == .danish ? "Hjælpesprog" : "Help language",
                selection: $displayLanguage
            ) {
                Text("EN").tag(Language.english)
                Text("DA").tag(Language.danish)
            }
            .pickerStyle(.segmented)
            .frame(width: 88)
            .tint(BeoColor.accent)
            .animation(reduceMotion ? nil : BeoAnimation.toast, value: displayLanguage)
            .accessibilityLabel(displayLanguage == .danish ? "Hjælpesprog" : "Help language")
            .accessibilityHint(
                displayLanguage == .english
                    ? "Danish. Double-tap to switch."
                    : "English. Double-tap to switch."
            )

            Text(languageCaption)
                .font(BeoType.caption)
                .foregroundStyle(BeoColor.muted)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
        }
    }

    // MARK: — Section card (spec §3.6)

    private func sectionCard(_ section: HelpSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section title
            Text(isEnglishActive ? section.titleEN : section.titleDA)
                .font(BeoType.nowPlaying)
                .foregroundStyle(BeoColor.text)
                .padding(.horizontal, Spacing.s16)
                .padding(.top, Spacing.s16)
                .padding(.bottom, Spacing.s12)

            // Rows
            ForEach(section.rows.indices, id: \.self) { rowIndex in
                if rowIndex > 0 {
                    Divider()
                        .background(BeoColor.separator)
                        .padding(.horizontal, 0)
                }
                phraseRow(section.rows[rowIndex])
            }

            // Bottom padding inside card
            Color.clear.frame(height: Spacing.s12)
        }
        .background(BeoColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(BeoColor.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: — Phrase row (spec §3.7)

    @ViewBuilder
    private func phraseRow(_ row: HelpRow) -> some View {
        let activePhrase   = isEnglishActive ? row.phraseEN : row.phraseDA
        let inactivePhrase = isEnglishActive ? row.phraseDA : row.phraseEN
        let actionLabel    = isEnglishActive ? row.actionEN : row.actionDA
        // ADR E-40 §Conflicts 4 — stacked layout at accessibility4+ to prevent action-label truncation.
        let isLargeType = dynamicTypeSize >= .accessibility4

        Group {
            if isLargeType {
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    Text(actionLabel)
                        .font(BeoType.caption)
                        .foregroundStyle(BeoColor.muted)
                    phraseTexts(activePhrase: activePhrase, inactivePhrase: inactivePhrase)
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.s12) {
                    // Action label column — fixed width (spec §3.7: 110 pt)
                    Text(actionLabel)
                        .font(BeoType.caption)
                        .foregroundStyle(BeoColor.muted)
                        .frame(width: 110, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    phraseTexts(activePhrase: activePhrase, inactivePhrase: inactivePhrase)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, Spacing.s16)
        .padding(.vertical, Spacing.s12)
        .frame(minHeight: 56)
        // VoiceOver: combine action + both phrases into a single element (spec §4.2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(actionLabel). \(isEnglishActive ? "Active phrase:" : "Aktiv sætning:") \(activePhrase). \(isEnglishActive ? "Other language:" : "Andet sprog:") \(inactivePhrase).")
    }

    @ViewBuilder
    private func phraseTexts(activePhrase: String, inactivePhrase: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(activePhrase)
                .font(BeoType.confirmation)
                .foregroundStyle(BeoColor.text)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
                .animation(reduceMotion ? nil : BeoAnimation.toast, value: displayLanguage)

            Text(inactivePhrase)
                .font(BeoType.body)
                .foregroundStyle(BeoColor.muted)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
                .animation(reduceMotion ? nil : BeoAnimation.toast, value: displayLanguage)
        }
    }
}

// MARK: — Previews

#Preview("HelpView — EN active, no speakers") {
    HelpView(
        speakerA: nil,
        speakerB: nil,
        activeLanguage: .english,
        isPresented: .constant(true)
    )
}

#Preview("HelpView — EN active, real speaker names") {
    HelpView(
        speakerA: "Beolab",
        speakerB: "Beosound",
        activeLanguage: .english,
        isPresented: .constant(true)
    )
}

#Preview("HelpView — DA active") {
    HelpView(
        speakerA: "Beolab",
        speakerB: "Beosound",
        activeLanguage: .danish,
        isPresented: .constant(true)
    )
}
