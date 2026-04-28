import Foundation

struct VolumeLevel: Decodable {
    let level: Int
    let maximum: Int?
    let muted: Bool?
}

struct VolumeResponse: Decodable {
    let volume: VolumeLevel
}
