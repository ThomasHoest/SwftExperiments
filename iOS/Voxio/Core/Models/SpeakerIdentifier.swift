import Foundation

struct SpeakerIdentifier: Hashable, Codable {
    let host: String
    let jid: String?
    let platform: SpeakerPlatform
}

enum SpeakerPlatform: String, Codable {
    case mozart, bnr
}
