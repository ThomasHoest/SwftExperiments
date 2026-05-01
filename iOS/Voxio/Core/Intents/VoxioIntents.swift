import AppIntents
import Foundation

// MARK: - Error

private struct VoxioIntentError: LocalizedError {
    let errorDescription: String?
}

// MARK: - SpeakerEntity

struct SpeakerEntity: AppEntity, Sendable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Speaker"
    static var defaultQuery = SpeakerEntityQuery()

    var id: String   // host IP
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SpeakerEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [SpeakerEntity] {
        SpeakerStore.shared.allSpeakers
            .filter { identifiers.contains($0.host) }
            .map { SpeakerEntity(id: $0.host, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SpeakerEntity] {
        SpeakerStore.shared.allSpeakers
            .map { SpeakerEntity(id: $0.host, name: $0.name) }
    }
}

// MARK: - PlaybackToggleIntent

struct PlaybackToggleIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play/Pause Voxio"
    static var description = IntentDescription("Toggles play/pause on your active B&O speaker.")

    func perform() async throws -> some IntentResult {
        let lang = LanguageService.shared.activeLanguage
        guard let speaker = await SpeakerStore.shared.activeSpeaker else {
            throw VoxioIntentError(errorDescription: IntentStrings.appNotRunning(lang))
        }
        do {
            if await speaker.isPlaying {
                try await speaker.client.pause()
            } else {
                try await speaker.client.play()
            }
            return .result()
        } catch _ as SpeakerError {
            throw VoxioIntentError(errorDescription: IntentStrings.speakerUnreachable(await speaker.name, lang))
        }
    }
}

// MARK: - AdjustVolumeIntent

struct AdjustVolumeIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Adjust Volume in Voxio"
    static var description = IntentDescription("Adjusts the volume of your active B&O speaker.")

    @Parameter(title: "Delta", default: 10)
    var delta: Int

    func perform() async throws -> some IntentResult {
        let lang = LanguageService.shared.activeLanguage
        guard let speaker = await SpeakerStore.shared.activeSpeaker else {
            throw VoxioIntentError(errorDescription: IntentStrings.appNotRunning(lang))
        }
        do {
            let fetched  = try? await speaker.client.getVolume()
            let fallback = await speaker.volume ?? 50
            let clamped  = max(0, min(100, (fetched ?? fallback) + delta))
            try await speaker.client.setVolume(clamped)
            return .result()
        } catch _ as SpeakerError {
            throw VoxioIntentError(errorDescription: IntentStrings.speakerUnreachable(await speaker.name, lang))
        }
    }
}

// MARK: - MuteIntent

struct MuteIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Mute Voxio"
    static var description = IntentDescription("Toggles mute on your active B&O speaker.")

    func perform() async throws -> some IntentResult {
        let lang = LanguageService.shared.activeLanguage
        guard let speaker = await SpeakerStore.shared.activeSpeaker else {
            throw VoxioIntentError(errorDescription: IntentStrings.appNotRunning(lang))
        }
        do {
            try await speaker.client.mute(!(await speaker.isMuted))
            return .result()
        } catch _ as SpeakerError {
            throw VoxioIntentError(errorDescription: IntentStrings.speakerUnreachable(await speaker.name, lang))
        }
    }
}

// MARK: - JoinSpeakerIntent

struct JoinSpeakerIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Join Speakers in Voxio"
    static var description = IntentDescription("Joins one B&O speaker to another's audio session.")

    @Parameter(title: "Source Speaker")
    var source: SpeakerEntity

    @Parameter(title: "Target Speaker")
    var target: SpeakerEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let lang = LanguageService.shared.activeLanguage
        let (sourceSpeaker, targetSpeaker) = await MainActor.run {
            let all = SpeakerStore.shared.allSpeakers
            return (all.first { $0.host == source.id }, all.first { $0.host == target.id })
        }
        guard let sourceSpeaker else {
            throw VoxioIntentError(errorDescription: IntentStrings.speakerNotFound(source.name, lang))
        }
        guard let targetSpeaker else {
            throw VoxioIntentError(errorDescription: IntentStrings.speakerNotFound(target.name, lang))
        }
        do {
            if await targetSpeaker.identifier.platform == .mozart {
                try await targetSpeaker.client.join(peer: await sourceSpeaker.identifier)
            } else {
                try await sourceSpeaker.client.join(peer: await targetSpeaker.identifier)
            }
            let msg = IntentStrings.joined(await sourceSpeaker.name, await targetSpeaker.name, lang)
            return .result(dialog: IntentDialog(stringLiteral: msg))
        } catch _ as SpeakerError {
            throw VoxioIntentError(errorDescription: IntentStrings.speakerUnreachable(await sourceSpeaker.name, lang))
        }
    }
}

// MARK: - LeaveSpeakerIntent

struct LeaveSpeakerIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Leave Group in Voxio"
    static var description = IntentDescription("Causes a B&O speaker to leave its group.")

    @Parameter(title: "Speaker")
    var speaker: SpeakerEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let lang = LanguageService.shared.activeLanguage
        let resolved = await MainActor.run {
            SpeakerStore.shared.allSpeakers.first { $0.host == speaker.id }
        }
        guard let resolved else {
            throw VoxioIntentError(errorDescription: IntentStrings.speakerNotFound(speaker.name, lang))
        }
        do {
            try await resolved.client.leave()
            let msg = IntentStrings.left(await resolved.name, lang)
            return .result(dialog: IntentDialog(stringLiteral: msg))
        } catch _ as SpeakerError {
            throw VoxioIntentError(errorDescription: IntentStrings.speakerUnreachable(await resolved.name, lang))
        }
    }
}
