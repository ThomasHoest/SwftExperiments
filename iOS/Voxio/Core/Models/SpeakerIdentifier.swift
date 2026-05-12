import Foundation

// Sendable + nonisolated Codable conformance is required so the type can be used
// as a Transferable payload (E-59 T-5901). Without explicit nonisolated declaration,
// the default-isolation setting in this target makes the synthesised Codable
// conformance @MainActor-isolated, which breaks CodableRepresentation's
// `Sendable` requirement at compile time.
struct SpeakerIdentifier: Hashable, Sendable {
    let host: String
    let jid: String?
    let platform: SpeakerPlatform
}

nonisolated extension SpeakerIdentifier: Codable {}

enum SpeakerPlatform: String, Codable, Sendable {
    case mozart, bnr
}
