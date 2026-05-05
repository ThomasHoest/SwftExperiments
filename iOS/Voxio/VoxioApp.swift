import SwiftUI

// T-2201 — Sheet content roots (dark-mode enforcement audit):
//   1. LanguagePickerSheet — .preferredColorScheme(.dark) on body root (T-2202) ✓
//   2. CountdownConfirmationSurface — .preferredColorScheme(.dark) on body root (T-2203, wired in E-25) ○
// T-2209 — Dark-mode-only constraint: every new .sheet, .popover, or .fullScreenCover
//           content view MUST include .preferredColorScheme(.dark) on its body root.

@main
struct VoxioApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Log.addListener(ConsoleLogListener())
        Log.addListener(FileLogListener.shared)
        FileLogListener.shared.pruneOldLogs()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                Task { @MainActor in WidgetStateWriter.markAppRunning(false) }
                FileLogListener.shared.flushSync()
            case .active:
                Task { @MainActor in WidgetStateWriter.markAppRunning(true) }
            @unknown default:
                break
            }
        }
    }
}
