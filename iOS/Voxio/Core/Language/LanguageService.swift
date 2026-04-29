import Foundation
import Combine

private let kLanguageKey    = "com.voxio.activeLanguage"
private let kLanguageChosenKey = "com.voxio.activeLanguage.hasExplicitlyChosen"

/// Single source of truth for the active UI and recognition language.
/// Defaults to the device's primary language on first launch; persists user
/// overrides to `UserDefaults`.
class LanguageService: ObservableObject {
    static let shared = LanguageService()

    @Published private(set) var activeLanguage: Language
    /// `true` once the user has explicitly picked a language via `setLanguage(_:)`.
    /// Persisted under `com.voxio.activeLanguage.hasExplicitlyChosen`.
    @Published private(set) var hasExplicitlyChosen: Bool

    private init() {
        let saved = UserDefaults.standard.string(forKey: kLanguageKey)
        activeLanguage = saved.flatMap(Language.init(rawValue:)) ?? .fromLocale()
        hasExplicitlyChosen = UserDefaults.standard.bool(forKey: kLanguageChosenKey)
        Log.info("[Language] active language: \(activeLanguage.localeIdentifier), hasExplicitlyChosen: \(hasExplicitlyChosen)")
    }

    @MainActor
    func setLanguage(_ language: Language) {
        activeLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: kLanguageKey)
        hasExplicitlyChosen = true
        UserDefaults.standard.set(true, forKey: kLanguageChosenKey)
        Log.info("[Language] switched to \(language.localeIdentifier)")
    }
}
