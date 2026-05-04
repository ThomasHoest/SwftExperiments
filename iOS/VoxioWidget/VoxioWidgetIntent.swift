import AppIntents
import Foundation

// MARK: - WidgetSpeakerEntity
// Minimal AppEntity for widget speaker selection. Duplicated from the main app's SpeakerEntity
// because the widget process cannot access SpeakerStore.shared. Entity query reads from the
// App Group shared container written by WidgetStateWriter.

struct WidgetSpeakerEntity: AppEntity, Sendable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Speaker"
    static var defaultQuery = WidgetSpeakerEntityQuery()

    var id: String   // host IP, or "auto" for Automatic
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WidgetSpeakerEntityQuery: EntityQuery {
    private static let suiteName = "group.T-Creative.Voxio"

    func entities(for identifiers: [String]) async throws -> [WidgetSpeakerEntity] {
        allEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetSpeakerEntity] {
        allEntities()
    }

    private func allEntities() -> [WidgetSpeakerEntity] {
        var result: [WidgetSpeakerEntity] = [
            WidgetSpeakerEntity(id: "auto", name: "Automatic (most recent)")
        ]
        guard let defaults = UserDefaults(suiteName: Self.suiteName),
              let data = defaults.data(forKey: "widget_discovered_speakers"),
              let records = try? JSONDecoder().decode([WidgetSpeakerRecord].self, from: data)
        else { return result }

        result += records.map { WidgetSpeakerEntity(id: $0.host, name: $0.name) }
        return result
    }
}

// Codable mirror of SpeakerRecord — widget extension cannot import WidgetStateWriter directly
private struct WidgetSpeakerRecord: Codable {
    let host: String
    let name: String
    let platform: String
}

// MARK: - VoxioWidgetIntent

struct VoxioWidgetIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configure Voxio Widget"
    static var description = IntentDescription("Select which B&O speaker to display.")

    @Parameter(title: "Speaker", default: WidgetSpeakerEntity(id: "auto", name: "Automatic (most recent)"))
    var speakerPicker: WidgetSpeakerEntity?
}
