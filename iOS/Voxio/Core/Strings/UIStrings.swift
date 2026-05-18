import Foundation

/// Language-keyed strings for static UI labels and microphone status messages.
struct UIStrings {
    // ── Confirmation sheet ────────────────────────────────────────────────────
    var confirmationAboutTo:   String   // header label above the action read-back
    var confirmationVoiceHint: String   // mic indicator pill
    var confirmYes:            String   // affirmative button label
    var confirmNo:             String   // negative button label

    // ── Countdown confirmation surface (E-25) ─────────────────────────────────
    var cancelLabel: String             // cancel button label
    private var _countdownTemplate: String  // e.g. "Cancelling in %d…"

    /// Returns the localised countdown label with the remaining seconds substituted.
    func countdownLabel(n: Int) -> String {
        String(format: _countdownTemplate, n)
    }

    // ── Microphone / recognition status ──────────────────────────────────────
    var initialisingMic:  String
    var listening:        String
    var micUnavailable:   String
    var micAccessDenied:  String
    var backgroundPaused: String

    // ── Home screen ───────────────────────────────────────────────────────────
    var lookingForSpeakers: String

    // ── Transport controls (E-56 T-5607) ─────────────────────────────────────
    var play:  String   // accessibility label for the play button
    var pause: String   // accessibility label for the pause button

    // ── Favorites row (E-58 T-5803) ──────────────────────────────────────────
    var couldNotStartFavorite: String   // error toast when playFavorite throws

    static let english = UIStrings(
        confirmationAboutTo:   "About to:",
        confirmationVoiceHint: "or say Yes / No",
        confirmYes:            "Yes",
        confirmNo:             "No",
        cancelLabel:           "Cancel",
        _countdownTemplate:    "Cancelling in %d\u{2026}",
        initialisingMic:       "Initialising microphone…",
        listening:             "Listening…",
        micUnavailable:        "Microphone unavailable",
        micAccessDenied:       "Microphone access denied",
        backgroundPaused:      "Paused",
        lookingForSpeakers:    "Looking for speakers…",
        play:                  "Play",
        pause:                 "Pause",
        couldNotStartFavorite: "Could not start favorite"
    )

    static let danish = UIStrings(
        confirmationAboutTo:   "Er ved at:",
        confirmationVoiceHint: "eller sig Ja / Nej",
        confirmYes:            "Ja",
        confirmNo:             "Nej",
        cancelLabel:           "Annuller",
        _countdownTemplate:    "Annullerer om %d\u{2026}",
        initialisingMic:       "Initialiserer mikrofon…",
        listening:             "Lytter…",
        micUnavailable:        "Mikrofon utilgængelig",
        micAccessDenied:       "Mikrofonadgang nægtet",
        backgroundPaused:      "Sat på pause",
        lookingForSpeakers:    "Leder efter højttalere…",
        play:                  "Afspil",
        pause:                 "Pause",
        couldNotStartFavorite: "Kunne ikke starte favorit"
    )

    static func forLanguage(_ language: Language) -> UIStrings {
        language == .danish ? .danish : .english
    }
}
