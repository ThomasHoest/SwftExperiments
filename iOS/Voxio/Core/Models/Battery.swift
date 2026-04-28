import Foundation

struct Battery: Decodable {
    let batteryLevel: Int
    let isCharging: Bool
    let remainingPlayingTime: Int?
}
