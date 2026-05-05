import SwiftUI

struct SettingsView: View {
    let store: PersonalisationStore
    let discoveredSpeakers: [Speaker]
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var langService = LanguageService.shared
    @AppStorage("telemetryEnabled") private var telemetryEnabled = false

    private var str: SettingsStrings { .forLanguage(langService.activeLanguage) }

    var body: some View {
        NavigationStack {
            List {
                Section(str.sectionVoiceControl) {
                    Toggle(str.personalisation, isOn: Binding(
                        get: { store.isEnabled },
                        set: { store.isEnabled = $0 }
                    ))

                    NavigationLink {
                        AliasListView(store: store, discoveredSpeakers: discoveredSpeakers)
                    } label: {
                        Label(str.aliases, systemImage: "text.badge.plus")
                    }

                    NavigationLink {
                        LearnedPhrasesView(store: store, discoveredSpeakers: discoveredSpeakers)
                    } label: {
                        Label(str.learnedPhrases, systemImage: "brain")
                    }
                }

                Section(str.sectionLanguage) {
                    Picker(str.sectionLanguage, selection: Binding(
                        get: { langService.activeLanguage },
                        set: { langService.setLanguage($0) }
                    )) {
                        Text(str.languageEnglish).tag(Language.english)
                        Text(str.languageDanish).tag(Language.danish)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section(footer: Text(str.telemetryFooter)) {
                    Toggle(str.telemetryToggle, isOn: $telemetryEnabled)
                }
            }
            .navigationTitle(str.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(str.done) { dismiss() }
                }
            }
        }
    }
}
