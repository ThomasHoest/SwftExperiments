import Foundation

enum Language: String, CaseIterable {
    case english = "en"
    case danish  = "da"

    /// Infers the language from the device's ordered preferred-language list.
    /// Returns `.danish` if any entry starts with "da", otherwise `.english`.
    static func fromLocale() -> Language {
        Locale.preferredLanguages.contains(where: { $0.hasPrefix("da") }) ? .danish : .english
    }

    var localeIdentifier: String {
        switch self {
        case .english: return "en-US"
        case .danish:  return "da-DK"
        }
    }

    var locale: Locale { Locale(identifier: localeIdentifier) }
}
