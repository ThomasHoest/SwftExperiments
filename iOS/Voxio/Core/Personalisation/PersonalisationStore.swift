import CoreData
import Foundation

// MARK: - AliasRecord

struct AliasRecord: Identifiable {
    let id: UUID
    let speakerId: String
    let phrase: String
    let intent: CommandIntent
    let slots: [String: String]
    let createdAt: Date
}

// MARK: - ConfirmedCommandRecord

struct ConfirmedCommandRecord: Identifiable {
    let id: UUID
    let speakerId: String
    let transcription: String
    let intent: CommandIntent
    let lastUsedAt: Date
    let useCount: Int64
}

// MARK: - PersonalisationStore

@MainActor
final class PersonalisationStore {

    // MARK: isEnabled

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "personalisationEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "personalisationEnabled") }
    }

    // MARK: Init

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Alias CRUD

    enum SaveAliasError: Error {
        case reservedWord   // phrase contains "voxio"
        case duplicatePhrase
    }

    func saveAlias(speakerId: String, phrase: String, intent: CommandIntent, slots: [String: String]) throws {
        let normalised = phrase.lowercased()
        guard !normalised.contains("voxio") else {
            throw SaveAliasError.reservedWord
        }

        // Check for duplicate phrase on the same speaker — block, do not overwrite.
        let duplicateRequest: NSFetchRequest<Alias> = Alias.fetchRequest()
        duplicateRequest.predicate = NSPredicate(format: "phrase == %@ AND speakerId == %@", normalised, speakerId)
        duplicateRequest.fetchLimit = 1
        let existing = try context.fetch(duplicateRequest)
        guard existing.isEmpty else {
            throw SaveAliasError.duplicatePhrase
        }

        let alias = Alias(context: context)
        alias.id = UUID()
        alias.speakerId = speakerId
        alias.phrase = normalised
        alias.intentRaw = intent.rawValue
        alias.slotsJSON = encodeSlotsJSON(slots)
        alias.createdAt = Date()
        try saveContext()
    }

    func updateAlias(id: UUID, speakerId: String, phrase: String, intent: CommandIntent, slots: [String: String]) throws {
        let normalised = phrase.lowercased()
        guard !normalised.contains("voxio") else {
            throw SaveAliasError.reservedWord
        }

        let request: NSFetchRequest<Alias> = Alias.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        let results = try context.fetch(request)
        guard let alias = results.first else { return }

        // Check for duplicate phrase on the target speaker, excluding this alias itself.
        let duplicateRequest: NSFetchRequest<Alias> = Alias.fetchRequest()
        duplicateRequest.predicate = NSPredicate(
            format: "phrase == %@ AND speakerId == %@ AND id != %@",
            normalised, speakerId, id as CVarArg
        )
        duplicateRequest.fetchLimit = 1
        let existing = try context.fetch(duplicateRequest)
        guard existing.isEmpty else {
            throw SaveAliasError.duplicatePhrase
        }

        alias.speakerId  = speakerId
        alias.phrase     = normalised
        alias.intentRaw  = intent.rawValue
        alias.slotsJSON  = encodeSlotsJSON(slots)
        try saveContext()
    }

    func aliases(for speakerId: String) -> [AliasRecord] {
        let request: NSFetchRequest<Alias> = Alias.fetchRequest()
        request.predicate = NSPredicate(format: "speakerId == %@", speakerId)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        do {
            let results = try context.fetch(request)
            return results.compactMap { aliasRecord(from: $0) }
        } catch {
            Log.error("[PersonalisationStore] aliases(for:) fetch failed: \(error)")
            return []
        }
    }

    func deleteAlias(_ id: UUID) throws {
        let request: NSFetchRequest<Alias> = Alias.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        let results = try context.fetch(request)
        if let alias = results.first {
            context.delete(alias)
            try saveContext()
        }
    }

    func deleteAllAliases(for speakerId: String) throws {
        let request: NSFetchRequest<Alias> = Alias.fetchRequest()
        request.predicate = NSPredicate(format: "speakerId == %@", speakerId)
        let results = try context.fetch(request)
        results.forEach { context.delete($0) }
        try saveContext()
    }

    // MARK: - ConfirmedCommand CRUD

    func recordConfirmedCommand(speakerId: String, transcription: String, intent: CommandIntent, slots: [String: String]) throws {
        let normalised = transcription.lowercased()
        let request: NSFetchRequest<ConfirmedCommand> = ConfirmedCommand.fetchRequest()
        request.predicate = NSPredicate(format: "transcription == %@ AND speakerId == %@", normalised, speakerId)
        request.fetchLimit = 1

        let existing = try context.fetch(request)
        if let entry = existing.first {
            // Upsert — update existing entry
            entry.lastUsedAt = Date()
            entry.useCount += 1
            entry.intentRaw = intent.rawValue
            entry.slotsJSON = encodeSlotsJSON(slots)
        } else {
            // Insert new entry
            let entry = ConfirmedCommand(context: context)
            entry.id = UUID()
            entry.speakerId = speakerId
            entry.transcription = normalised
            entry.intentRaw = intent.rawValue
            entry.slotsJSON = encodeSlotsJSON(slots)
            entry.lastUsedAt = Date()
            entry.useCount = 1
        }

        try saveContext()
        try evictOldestConfirmedCommands(for: speakerId)
    }

    func deleteConfirmedCommand(transcription: String, speakerId: String) throws {
        let normalised = transcription.lowercased()
        let request: NSFetchRequest<ConfirmedCommand> = ConfirmedCommand.fetchRequest()
        request.predicate = NSPredicate(format: "transcription == %@ AND speakerId == %@", normalised, speakerId)
        let results = try context.fetch(request)
        results.forEach { context.delete($0) }
        try saveContext()
    }

    func confirmedCommands(for speakerId: String) -> [ConfirmedCommandRecord] {
        let request: NSFetchRequest<ConfirmedCommand> = ConfirmedCommand.fetchRequest()
        request.predicate = NSPredicate(format: "speakerId == %@", speakerId)
        request.sortDescriptors = [NSSortDescriptor(key: "lastUsedAt", ascending: false)]
        do {
            let results = try context.fetch(request)
            return results.compactMap { confirmedCommandRecord(from: $0) }
        } catch {
            Log.error("[PersonalisationStore] confirmedCommands(for:) fetch failed: \(error)")
            return []
        }
    }

    func allConfirmedCommandRecords() -> [ConfirmedCommandRecord] {
        let request: NSFetchRequest<ConfirmedCommand> = ConfirmedCommand.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "lastUsedAt", ascending: false)]
        do {
            let results = try context.fetch(request)
            return results.compactMap { confirmedCommandRecord(from: $0) }
        } catch {
            Log.error("[PersonalisationStore] allConfirmedCommandRecords fetch failed: \(error)")
            return []
        }
    }

    func clearAllConfirmedCommands() throws {
        let request: NSFetchRequest<NSFetchRequestResult> = ConfirmedCommand.fetchRequest()
        let batchDelete = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(batchDelete)
        // NSBatchDeleteRequest bypasses context change-tracking; refreshAllObjects ensures
        // in-memory objects reflect the cleared state immediately (ADR E-34).
        context.refreshAllObjects()
        try saveContext()
    }

    // MARK: - Match (Tier 0 lookups)

    func matchAlias(phrase: String, speakerId: String) -> ParsedCommand? {
        let normalised = phrase.lowercased()
        let request: NSFetchRequest<Alias> = Alias.fetchRequest()
        request.predicate = NSPredicate(format: "phrase == %@ AND speakerId == %@", normalised, speakerId)
        request.fetchLimit = 1
        do {
            let results = try context.fetch(request)
            guard let alias = results.first,
                  let intentRaw = alias.intentRaw,
                  let intent = CommandIntent(rawValue: intentRaw) else { return nil }
            let slots = decodeSlotsJSON(alias.slotsJSON)
            return buildParsedCommand(intent: intent, slots: slots)
        } catch {
            Log.error("[PersonalisationStore] matchAlias fetch failed: \(error)")
            return nil
        }
    }

    func matchConfirmedCommand(transcription: String, speakerId: String) -> ParsedCommand? {
        let normalised = transcription.lowercased()
        let request: NSFetchRequest<ConfirmedCommand> = ConfirmedCommand.fetchRequest()
        request.predicate = NSPredicate(format: "transcription == %@ AND speakerId == %@", normalised, speakerId)
        request.fetchLimit = 1
        do {
            let results = try context.fetch(request)
            guard let entry = results.first,
                  let intentRaw = entry.intentRaw,
                  let intent = CommandIntent(rawValue: intentRaw) else { return nil }

            // Update last-used metadata
            entry.lastUsedAt = Date()
            entry.useCount += 1
            try? saveContext()

            let slots = decodeSlotsJSON(entry.slotsJSON)
            return buildParsedCommand(intent: intent, slots: slots)
        } catch {
            Log.error("[PersonalisationStore] matchConfirmedCommand fetch failed: \(error)")
            return nil
        }
    }

    // MARK: - Private helpers

    private func evictOldestConfirmedCommands(for speakerId: String) throws {
        let countRequest: NSFetchRequest<ConfirmedCommand> = ConfirmedCommand.fetchRequest()
        countRequest.predicate = NSPredicate(format: "speakerId == %@", speakerId)
        let count = try context.count(for: countRequest)

        guard count > 200 else { return }

        let evictCount = count - 200
        let evictRequest: NSFetchRequest<ConfirmedCommand> = ConfirmedCommand.fetchRequest()
        evictRequest.predicate = NSPredicate(format: "speakerId == %@", speakerId)
        evictRequest.sortDescriptors = [NSSortDescriptor(key: "lastUsedAt", ascending: true)]
        evictRequest.fetchLimit = evictCount
        let toEvict = try context.fetch(evictRequest)
        toEvict.forEach { context.delete($0) }
        try saveContext()
        Log.info("[PersonalisationStore] evicted \(evictCount) confirmed command(s) for speakerId \(speakerId)")
    }

    private func saveContext() throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            Log.error("[PersonalisationStore] save failed: \(error)")
            throw error
        }
    }

    private func encodeSlotsJSON(_ slots: [String: String]) -> String {
        guard !slots.isEmpty,
              let data = try? JSONEncoder().encode(slots),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func decodeSlotsJSON(_ json: String?) -> [String: String] {
        guard let json, let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return decoded
    }

    private func buildParsedCommand(intent: CommandIntent, slots: [String: String]) -> ParsedCommand {
        let favoriteIndex = slots["favoriteIndex"].flatMap { Int($0) }
        let volumeValue   = slots["volumeValue"].flatMap   { Int($0) }
        let volumeDelta   = slots["volumeDelta"].flatMap   { Int($0) }
        return ParsedCommand(
            intent:            intent,
            favoriteName:      slots["favoriteName"],
            favoriteIndex:     favoriteIndex,
            volumeValue:       volumeValue,
            volumeDelta:       volumeDelta,
            targetSpeakerName: slots["targetSpeakerName"]
        )
    }

    private func aliasRecord(from alias: Alias) -> AliasRecord? {
        guard let id        = alias.id,
              let speakerId = alias.speakerId,
              let phrase    = alias.phrase,
              let intentRaw = alias.intentRaw,
              let intent    = CommandIntent(rawValue: intentRaw),
              let createdAt = alias.createdAt else { return nil }
        let slots = decodeSlotsJSON(alias.slotsJSON)
        return AliasRecord(id: id, speakerId: speakerId, phrase: phrase, intent: intent, slots: slots, createdAt: createdAt)
    }

    private func confirmedCommandRecord(from entry: ConfirmedCommand) -> ConfirmedCommandRecord? {
        guard let id           = entry.id,
              let speakerId    = entry.speakerId,
              let transcription = entry.transcription,
              let intentRaw    = entry.intentRaw,
              let intent       = CommandIntent(rawValue: intentRaw),
              let lastUsedAt   = entry.lastUsedAt else { return nil }
        return ConfirmedCommandRecord(
            id: id,
            speakerId: speakerId,
            transcription: transcription,
            intent: intent,
            lastUsedAt: lastUsedAt,
            useCount: Int64(entry.useCount)
        )
    }
}
