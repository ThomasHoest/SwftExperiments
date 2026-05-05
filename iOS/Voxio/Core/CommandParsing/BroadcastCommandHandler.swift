import Foundation

/// The result of a broadcast command fan-out.
struct BroadcastResult {
    let successCount: Int
    let totalCount: Int
    let intent: VoiceCommand
}

/// Executes broadcast `VoiceCommand` values across all discovered speakers in parallel.
///
/// Speaker scope filtering:
/// - `.stopAll` / `.pauseAll`  → speakers where `playbackState == .playing`
/// - `.resumeAll`              → speakers where `playbackState == .paused`
/// - `.adjustVolumeAll` / `.muteAll` / `.unmuteAll` → all discovered speakers
@MainActor
struct BroadcastCommandHandler {
    let discovery: SpeakerDiscoveryService

    /// Executes `command` across the applicable speaker subset.
    /// Returns a `BroadcastResult` describing how many calls succeeded.
    func handle(_ command: VoiceCommand) async -> BroadcastResult {
        let allSpeakers = discovery.groups.flatMap(\.members)

        let scopedSpeakers: [Speaker]
        switch command {
        case .stopAll, .pauseAll:
            scopedSpeakers = allSpeakers.filter { $0.playbackState == .playing }
        case .resumeAll:
            scopedSpeakers = allSpeakers.filter { $0.playbackState == .paused }
        case .adjustVolumeAll, .muteAll, .unmuteAll:
            scopedSpeakers = allSpeakers
        default:
            return BroadcastResult(successCount: 0, totalCount: 0, intent: command)
        }

        var successes = 0
        await withTaskGroup(of: Bool.self) { group in
            for speaker in scopedSpeakers {
                // Capture name on MainActor before entering the child task,
                // where MainActor-isolated sync properties are inaccessible.
                let name = speaker.name
                group.addTask {
                    do {
                        switch command {
                        case .stopAll:
                            try await speaker.stop()
                        case .pauseAll:
                            try await speaker.pause()
                        case .resumeAll:
                            try await speaker.play()
                        case .adjustVolumeAll(let delta):
                            try await speaker.adjustVolume(delta)
                        case .muteAll:
                            try await speaker.mute()
                        case .unmuteAll:
                            try await speaker.unmute()
                        default:
                            break
                        }
                        return true
                    } catch {
                        print("[BroadcastCommandHandler] speaker \(name) failed: \(error)")
                        return false
                    }
                }
            }
            for await success in group {
                if success { successes += 1 }
            }
        }

        return BroadcastResult(successCount: successes, totalCount: scopedSpeakers.count, intent: command)
    }
}
