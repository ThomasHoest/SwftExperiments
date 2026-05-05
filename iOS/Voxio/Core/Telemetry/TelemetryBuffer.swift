import CoreData
import CryptoKit
import Foundation

@MainActor
final class TelemetryBuffer {

    static let maxEventCount = 1_000
    static let maxEventsPerDay = 200

    private let context: NSManagedObjectContext

    private var misparseCandidates: [String: (objectID: NSManagedObjectID, timestamp: Date)] = [:]

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - record

    func record(
        transcription: String,
        speakerName: String,
        speakerId: String,
        intent: String,
        slots: [String: String],
        parserPath: String,
        outcome: TelemetryOutcome,
        locale: String,
        flags: TelemetryFlags = []
    ) throws {
        guard try todayCount() < Self.maxEventsPerDay else { return }

        let anonymisedTranscription = stripSpeakerName(from: transcription, speakerName: speakerName)
        let anonymisedSlots = hashFavoriteNames(in: slots)
        let slotsJSON = encodeSlotsJSON(anonymisedSlots)

        let event = TelemetryEventEntity(context: context)
        event.id = UUID()
        event.transcriptionAnonymised = anonymisedTranscription
        event.intent = intent
        event.slotsAnonymised = slotsJSON
        event.parserPath = parserPath
        event.outcome = outcome.rawValue
        event.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        event.modelVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        event.locale = locale
        event.timestamp = Date()
        event.flagsJSON = encodeFlagsJSON(flags)
        event.speakerId = speakerId
        event.uploaded = false

        try saveContext()

        let objectID = event.objectID

        switch outcome {
        case .cancelled:
            misparseCandidates[speakerId] = (objectID: objectID, timestamp: Date())

        case .confirmed:
            let now = Date()
            if let candidate = misparseCandidates[speakerId],
               now.timeIntervalSince(candidate.timestamp) <= 30 {
                try flagAsMisparse(objectID: candidate.objectID)
                misparseCandidates.removeValue(forKey: speakerId)
            }

        default:
            break
        }

        try enforceCap()
    }

    // MARK: - pendingBatch

    func pendingBatch(limit: Int) throws -> [TelemetryEvent] {
        let request: NSFetchRequest<TelemetryEventEntity> = TelemetryEventEntity.fetchRequest()
        request.predicate = NSPredicate(format: "uploaded == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        request.fetchLimit = limit

        let results = try context.fetch(request)
        return results.compactMap { entity in
            guard let id = entity.id,
                  let transcription = entity.transcriptionAnonymised,
                  let intent = entity.intent,
                  let slots = entity.slotsAnonymised,
                  let parserPath = entity.parserPath,
                  let outcomeRaw = entity.outcome,
                  let outcome = TelemetryOutcome(rawValue: outcomeRaw),
                  let appVersion = entity.appVersion,
                  let modelVersion = entity.modelVersion,
                  let locale = entity.locale,
                  let timestamp = entity.timestamp,
                  let speakerId = entity.speakerId else { return nil }
            let flags = decodeFlagsJSON(entity.flagsJSON)
            return TelemetryEvent(
                id: id,
                transcriptionAnonymised: transcription,
                intent: intent,
                slotsAnonymised: slots,
                parserPath: parserPath,
                outcome: outcome,
                appVersion: appVersion,
                modelVersion: modelVersion,
                locale: locale,
                timestamp: timestamp,
                flags: flags,
                speakerId: speakerId
            )
        }
    }

    // MARK: - markUploaded

    func markUploaded(_ ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let request: NSFetchRequest<TelemetryEventEntity> = TelemetryEventEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", ids as NSArray)
        let results = try context.fetch(request)
        results.forEach { $0.uploaded = true }
        try saveContext()
    }

    // MARK: - flagAsMisparse

    func flagAsMisparse(eventId: UUID) throws {
        let request: NSFetchRequest<TelemetryEventEntity> = TelemetryEventEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", eventId as NSUUID)
        request.fetchLimit = 1
        guard let entity = try context.fetch(request).first else { return }
        var flags = decodeFlagsJSON(entity.flagsJSON)
        flags.insert(.likelyMisparse)
        entity.flagsJSON = encodeFlagsJSON(flags)
        try saveContext()
    }

    // MARK: - deleteAll

    func deleteAll() throws {
        let request: NSFetchRequest<NSFetchRequestResult> = TelemetryEventEntity.fetchRequest()
        let batchDelete = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(batchDelete)
        context.refreshAllObjects()
        misparseCandidates.removeAll()
    }

    // MARK: - uploadedCount

    func uploadedCount(since date: Date) throws -> Int {
        let request: NSFetchRequest<TelemetryEventEntity> = TelemetryEventEntity.fetchRequest()
        request.predicate = NSPredicate(format: "uploaded == YES AND timestamp >= %@", date as NSDate)
        return try context.count(for: request)
    }

    // MARK: - Private helpers

    private func todayCount() throws -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let request: NSFetchRequest<TelemetryEventEntity> = TelemetryEventEntity.fetchRequest()
        request.predicate = NSPredicate(format: "timestamp >= %@", startOfDay as NSDate)
        return try context.count(for: request)
    }

    private func enforceCap() throws {
        let countRequest: NSFetchRequest<TelemetryEventEntity> = TelemetryEventEntity.fetchRequest()
        let total = try context.count(for: countRequest)
        guard total > Self.maxEventCount else { return }

        let excess = total - Self.maxEventCount
        let evictRequest: NSFetchRequest<TelemetryEventEntity> = TelemetryEventEntity.fetchRequest()
        evictRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        evictRequest.fetchLimit = excess
        let toEvict = try context.fetch(evictRequest)
        toEvict.forEach { context.delete($0) }
        try saveContext()
    }

    private func flagAsMisparse(objectID: NSManagedObjectID) throws {
        guard let entity = try context.existingObject(with: objectID) as? TelemetryEventEntity else { return }
        var flags = decodeFlagsJSON(entity.flagsJSON)
        flags.insert(.likelyMisparse)
        entity.flagsJSON = encodeFlagsJSON(flags)
        try saveContext()
    }

    private func saveContext() throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            Log.error("[TelemetryBuffer] save failed: \(error)")
            throw error
        }
    }

    private func stripSpeakerName(from text: String, speakerName: String) -> String {
        guard !speakerName.isEmpty else { return text }
        let pattern = NSRegularExpression.escapedPattern(for: speakerName)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "[speaker]")
    }

    private func hashFavoriteNames(in slots: [String: String]) -> [String: String] {
        var result = slots
        if let name = result["favoriteName"] {
            result["favoriteName"] = sha256Prefix(name)
        }
        return result
    }

    private func sha256Prefix(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(8))
    }

    private func encodeSlotsJSON(_ slots: [String: String]) -> String {
        guard !slots.isEmpty,
              let data = try? JSONEncoder().encode(slots),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func encodeFlagsJSON(_ flags: TelemetryFlags) -> String {
        guard let data = try? JSONEncoder().encode(flags),
              let str = String(data: data, encoding: .utf8) else { return "0" }
        return str
    }

    private func decodeFlagsJSON(_ json: String?) -> TelemetryFlags {
        guard let json,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(TelemetryFlags.self, from: data) else { return [] }
        return decoded
    }
}
