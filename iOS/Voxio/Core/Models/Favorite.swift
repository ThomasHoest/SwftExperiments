import Foundation

struct Favorite: Identifiable {
    let id: String           // scene UUID (dictionary key from GET /scenes)
    let displayName: String  // scene label, falls back to id
    let presetIndex: Int     // 0-based position in sorted list → used in /playback/preset/{index}/trigger
}
