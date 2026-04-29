import Foundation
import Combine

private let kLanguageKey = "com.voxio.activeLanguage"

/// Single source of truth for the active UI and recognition language.
/// Defaults to the device's primary language on first launch; persists user
/// overrides to `UserDefaults`.
class LanguageService: ObservableObject {
    static let shared = LanguageService()

    @Published private(set) var activeLanguage: Language

    private init() {
        let saved = UserDefaults.standard.string(forKey: kLanguageKey)
        activeLanguage = saved.flatMap(Language.init(rawValue:)) ?? .fromLocale()
        Log.info("[Language] active language: \(activeLanguage.localeIdentifier)")
    }

    @MainActor
    func setLanguage(_ language: Language) {
        guard language != activeLanguage else { return }
        activeLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: kLanguageKey)
        Log.info("[Language] switched to \(language.localeIdentifier)")
    }
}
