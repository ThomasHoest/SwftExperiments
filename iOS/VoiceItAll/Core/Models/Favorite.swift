import Foundation

struct Favorite: Decodable, Identifiable {
    let id: String
    let title: String?
    let providerName: String?

    var displayName: String { title ?? providerName ?? id }

    enum CodingKeys: String, CodingKey {
        case id, title, providerName
    }
}
