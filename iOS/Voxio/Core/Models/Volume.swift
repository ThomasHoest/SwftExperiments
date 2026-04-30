import Foundation

struct VolumeLevel: Decodable {
    let level: Int
    let muted: Bool?
}

// Real API shape: {"level":{"level":40},"muted":{"muted":false},"maximum":{"level":100},...}
// Custom decoder unwraps the nested boxes so callers use vol.volume.level / vol.volume.muted.
struct VolumeResponse: Decodable {
    let volume: VolumeLevel

    private enum CodingKeys: String, CodingKey { case level, muted }
    private struct LevelBox: Decodable { let level: Int }
    private struct MutedBox: Decodable { let muted: Bool }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let levelBox = try c.decode(LevelBox.self, forKey: .level)
        let mutedBox = try? c.decode(MutedBox.self, forKey: .muted)
        volume = VolumeLevel(level: levelBox.level, muted: mutedBox?.muted)
    }
}
