import SwiftUI

// T-2201 — Sheet content roots (dark-mode enforcement audit):
//   1. LanguagePickerSheet — .preferredColorScheme(.dark) on body root (T-2202) ✓
//   2. CountdownConfirmationSurface — .preferredColorScheme(.dark) on body root (T-2203, wired in E-25) ○
// T-2209 — Dark-mode-only constraint: every new .sheet, .popover, or .fullScreenCover
//           content view MUST include .preferredColorScheme(.dark) on its body root.

@main
struct VoxioApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var splashVisible = true

    /// How long the splash stays on screen before cross-fading to HomeView.
    private static let splashDuration: Duration = .milliseconds(1200)

    init() {
        Log.addListener(ConsoleLogListener())
        Log.addListener(FileLogListener.shared)
        Log.addListener(IncidentReporter.shared)
        WiFiPathMonitor.shared.start()
        FileLogListener.shared.pruneOldLogs()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView()
                if splashVisible {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                try? await Task.sleep(for: Self.splashDuration)
                withAnimation(.easeInOut(duration: 0.35)) {
                    splashVisible = false
                }
            }
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
