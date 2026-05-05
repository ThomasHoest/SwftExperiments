import SwiftUI

struct SettingsView: View {
    let store: PersonalisationStore
    let discoveredSpeakers: [Speaker]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Voice control") {
                    Toggle("Personalisation", isOn: Binding(
                        get: { store.isEnabled },
                        set: { store.isEnabled = $0 }
                    ))

                    NavigationLink {
                        AliasListView(store: store, discoveredSpeakers: discoveredSpeakers)
                    } label: {
                        Label("Aliases", systemImage: "text.badge.plus")
                    }

                    NavigationLink {
                        LearnedPhrasesView(store: store)
                    } label: {
                        Label("Learned phrases", systemImage: "brain")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
