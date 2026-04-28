import Foundation

/// Language-keyed strings for static UI labels and microphone status messages.
struct UIStrings {
    // ── Confirmation sheet ────────────────────────────────────────────────────
    var confirmationAboutTo:   String   // header label above the action read-back
    var confirmationVoiceHint: String   // mic indicator pill
    var confirmYes:            String   // affirmative button label
    var confirmNo:             String   // negative button label

    // ── Microphone / recognition status ──────────────────────────────────────
    var initialisingMic:  String
    var listening:        String
    var micUnavailable:   String
    var micAccessDenied:  String
    var backgroundPaused: String

    // ── Home screen ───────────────────────────────────────────────────────────
    var lookingForSpeakers: String

    static let english = UIStrings(
        confirmationAboutTo:   "About to:",
        confirmationVoiceHint: "or say Yes / No",
        confirmYes:            "Yes",
        confirmNo:             "No",
        initialisingMic:       "Initialising microphone…",
        listening:             "Listening…",
        micUnavailable:        "Microphone unavailable",
        micAccessDenied:       "Microphone access denied",
        backgroundPaused:      "Paused",
        lookingForSpeakers:    "Looking for speakers…"
    )

    static let danish = UIStrings(
        confirmationAboutTo:   "Er ved at:",
        confirmationVoiceHint: "eller sig Ja / Nej",
        confirmYes:            "Ja",
        confirmNo:             "Nej",
        initialisingMic:       "Initialiserer mikrofon…",
        listening:             "Lytter…",
        micUnavailable:        "Mikrofon utilgængelig",
        micAccessDenied:       "Mikrofonadgang nægtet",
        backgroundPaused:      "Sat på pause",
        lookingForSpeakers:    "Leder efter højttalere…"
    )

    static func forLanguage(_ language: Language) -> UIStrings {
        language == .danish ? .danish : .english
    }
}
