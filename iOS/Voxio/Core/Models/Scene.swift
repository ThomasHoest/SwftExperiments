import Foundation

/// Decodable representation of a single scene from `GET /api/v1/scenes`.
/// The response is a `[String: SceneResponse]` dictionary keyed by UUID.
struct SceneResponse: Decodable {
    let label: String?
    let actionList: [SceneAction]?
    let tags: [String]?
    let classification: String?

    struct SceneAction: Decodable {
        let type: String
        let buttonName: String?
    }
}
