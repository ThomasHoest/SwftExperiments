import Foundation

enum ToastKind: Equatable {
    case error(message: String, list: [String])
    case volumeLimit(message: String, isMax: Bool)
    case success(message: String)
}

struct Toast: Identifiable, Equatable {
    let id: UUID
    let kind: ToastKind

    var dismissDelay: TimeInterval {
        if case .success = kind { return 2 }
        return 4
    }

    init(kind: ToastKind) {
        self.id   = UUID()
        self.kind = kind
    }
}
