import AppIntents
import Foundation

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
        guard let speaker = await SpeakerStore.shared.activeSpeaker else {
            let msg = IntentStrings.appNotRunning(LanguageService.shared.activeLanguage)
            return .result(dialog: IntentDialog(stringLiteral: msg))
        }
        do {
            if await speaker.isPlaying {
                try await speaker.client.pause()
            } else {
                try await speaker.client.play()
            }
            return .result()
        } catch _ as SpeakerError {
            let name = await speaker.name
            let msg = IntentStrings.speakerUnreachable(name, LanguageService.shared.activeLanguage)
            return .result(dialog: IntentDialog(stringLiteral: msg))
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
        guard let speaker = await SpeakerStore.shared.activeSpeaker else {
            let msg = IntentStrings.appNotRunning(LanguageService.shared.activeLanguage)
            return .result(dialog: IntentDialog(stringLiteral: msg))
        }
        do {
            let fetched = try? await speaker.client.getVolume()
            let fallback = await speaker.volume ?? 50
            let current = fetched ?? fallback
            let clamped = max(0, min(100, current + delta))
            try await speaker.client.setVolume(clamped)
            return .result()
        } catch _ as SpeakerError {
            let name = await speaker.name
            let msg = IntentStrings.speakerUnreachable(name, LanguageService.shared.activeLanguage)
            return .result(dialog: IntentDialog(stringLiteral: msg))
        }
    }
}

// MARK: - MuteIntent

struct MuteIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Mute Voxio"
    static var description = IntentDescription("Toggles mute on your active B&O speaker.")

    func perform() async throws -> some IntentResult {
        guard let speaker = await SpeakerStore.shared.activeSpeaker else {
            let msg = IntentStrings.appNotRunning(LanguageService.shared.activeLanguage)
            return .result(dialog: IntentDialog(stringLiteral: msg))
        }
        do {
            let muted = await speaker.isMuted
            try await speaker.client.mute(!muted)
            return .result()
        } catch _ as SpeakerError {
            let name = await speaker.name
            let msg = IntentStrings.speakerUnreachable(name, LanguageService.shared.activeLanguage)
            return .result(dialog: IntentDialog(stringLiteral: msg))
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

    func perform() async throws -> some IntentResult {
        let lang = LanguageService.shared.activeLanguage
        let (sourceSpeaker, targetSpeaker) = await MainActor.run {
            let all = SpeakerStore.shared.allSpeakers
            return (
                all.first(where: { $0.host == source.id }),
                all.first(where: { $0.host == target.id })
            )
        }
        guard let sourceSpeaker else {
            return .result(dialog: IntentDialog(stringLiteral: IntentStrings.speakerNotFound(source.name, lang)))
        }
        guard let targetSpeaker else {
            return .result(dialog: IntentDialog(stringLiteral: IntentStrings.speakerNotFound(target.name, lang)))
        }
        do {
            // Mozart→any: expand from target; BNR→any: join from source
            if await targetSpeaker.identifier.platform == .mozart {
                try await targetSpeaker.client.join(peer: await sourceSpeaker.identifier)
            } else {
                try await sourceSpeaker.client.join(peer: await targetSpeaker.identifier)
            }
            let sourceName = await sourceSpeaker.name
            let targetName = await targetSpeaker.name
            let msg = IntentStrings.joined(sourceName, targetName, lang)
            return .result(dialog: IntentDialog(stringLiteral: msg))
        } catch _ as SpeakerError {
            let name = await sourceSpeaker.name
            let msg = IntentStrings.speakerUnreachable(name, lang)
            return .result(dialog: IntentDialog(stringLiteral: msg))
        }
    }
}

// MARK: - LeaveSpeakerIntent

struct LeaveSpeakerIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Leave Group in Voxio"
    static var description = IntentDescription("Causes a B&O speaker to leave its group.")

    @Parameter(title: "Speaker")
    var speaker: SpeakerEntity

    func perform() async throws -> some IntentResult {
        let lang = LanguageService.shared.activeLanguage
        let resolved = await MainActor.run {
            SpeakerStore.shared.allSpeakers.first(where: { $0.host == speaker.id })
        }
        guard let resolved else {
            return .result(dialog: IntentDialog(stringLiteral: IntentStrings.speakerNotFound(speaker.name, lang)))
        }
        do {
            try await resolved.client.leave()
            let name = await resolved.name
            let msg = IntentStrings.left(name, lang)
            return .result(dialog: IntentDialog(stringLiteral: msg))
        } catch _ as SpeakerError {
            let name = await resolved.name
            let msg = IntentStrings.speakerUnreachable(name, lang)
            return .result(dialog: IntentDialog(stringLiteral: msg))
        }
    }
}
