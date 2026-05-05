import Foundation

enum TelemetryOutcome: String, Codable {
    case confirmed, cancelled, timedOut, unknown
}

struct TelemetryFlags: OptionSet, Codable {
    let rawValue: Int
    static let likelyMisparse     = TelemetryFlags(rawValue: 1 << 0)
    static let recoverableUnknown = TelemetryFlags(rawValue: 1 << 1)
    static let broadcast          = TelemetryFlags(rawValue: 1 << 2)
}

struct TelemetryEvent: Identifiable {
    let id: UUID
    let transcriptionAnonymised: String
    let intent: String
    let slotsAnonymised: String
    let parserPath: String
    let outcome: TelemetryOutcome
    let appVersion: String
    let modelVersion: String
    let locale: String
    let timestamp: Date
    var flags: TelemetryFlags
    let speakerId: String
}
