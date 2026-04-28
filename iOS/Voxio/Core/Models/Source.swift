import Foundation

struct Source: Decodable {
    let id: String?
    let friendlyName: String?
    let sourceType: String?

    var displayName: String? { friendlyName ?? id }
}
