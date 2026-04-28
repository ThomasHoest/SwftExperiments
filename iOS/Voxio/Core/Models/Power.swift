import Foundation

enum PowerValue: String, Decodable {
    case networkStandby = "networkStandby"
    case on             = "on"
    case standby        = "standby"
    case shutdown       = "shutdown"
    case storage        = "storage"
    case unknown        = "unknown"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PowerValue(rawValue: raw) ?? .unknown
    }
}

struct PowerState: Decodable {
    let state: PowerValue
}
