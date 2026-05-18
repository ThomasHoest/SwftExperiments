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

/// Maps the Mozart `PowerStateEnum` schema (`{ "value": "on" | "standby" | ... }`).
/// Both `GET /state/power` and the `WebSocketEventPowerState.eventData` envelope
/// use this shape — the field is `value`, NOT `state` (the latter was a misnomer
/// in earlier code and caused WS decode failures on every speaker boot).
struct PowerState: Decodable {
    let value: PowerValue
}
