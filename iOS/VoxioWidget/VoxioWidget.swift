import WidgetKit
import SwiftUI

struct VoxioPlayerWidget: Widget {
    let kind: String = "VoxioPlayerWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: VoxioWidgetIntent.self,
            provider: VoxioWidgetProvider()
        ) { entry in
            VoxioWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.black.opacity(0.45)
                }
                .environment(\.colorScheme, .dark)
        }
        .configurationDisplayName("Voxio Player")
        .description("Control your B&O speaker from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct VoxioWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VoxioWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            VoxioWidgetSmallView(entry: entry)
                .padding(Spacing.s12)
        case .systemMedium:
            VoxioWidgetMediumView(entry: entry)
                .padding(Spacing.s12)
        default:
            VoxioWidgetSmallView(entry: entry)
                .padding(Spacing.s12)
        }
    }
}
