import Foundation

/// Language-keyed strings for confirmation read-backs, completion feedback,
/// and the action-cancelled timeout message.
/// Strings match functional-spec-bo-voice-control v1.3.
struct CommandStrings {
    // ── Confirmation read-backs (spoken before execution) ─────────────────────
    var playFavorite:       (_ index: Int, _ speaker: String) -> String
    var playFavoriteByName: (_ name: String, _ speaker: String) -> String
    var playDefault:        (_ speaker: String) -> String
    var stop:             (_ speaker: String) -> String
    var pause:            (_ speaker: String) -> String
    var resume:           (_ speaker: String) -> String
    var setVolume:        (_ speaker: String, _ level: Int) -> String
    var adjustVolumeUp:   (_ speaker: String, _ amount: Int) -> String
    var adjustVolumeDown: (_ speaker: String, _ amount: Int) -> String
    var mute:             (_ speaker: String, _ volume: Int?) -> String
    var unmute:           (_ speaker: String) -> String

    // ── Completion feedback (spoken after successful execution) ────────────────
    var stopped:          (_ speaker: String) -> String
    var paused:           (_ speaker: String) -> String
    var resumed:          (_ speaker: String) -> String
    var volumeSet:        (_ speaker: String, _ level: Int) -> String
    var volumeAdjusted:   (_ speaker: String) -> String
    var muted:            (_ speaker: String) -> String
    var unmuted:          (_ speaker: String) -> String

    // ── Grouping ──────────────────────────────────────────────────────────────
    var joinSpeakers:  (_ source: String, _ target: String) -> String
    var leaveSpeaker:  (_ speaker: String) -> String
    var joined:        (_ source: String, _ target: String) -> String
    var leftGroup:     (_ speaker: String) -> String

    // ── Favorites listing ─────────────────────────────────────────────────────
    var listFavoritesResult: (_ speaker: String, _ list: String) -> String

    // ── Timeout ───────────────────────────────────────────────────────────────
    var actionCancelled: String

    static let english = CommandStrings(
        playFavorite:       { i, s in "Playing favorite \(i) on \(s)" },
        playFavoriteByName: { n, s in "Playing \(n) on \(s)" },
        playDefault:        { s in "Playing on \(s)" },
        stop:             { s in "Stopping playback on \(s)" },
        pause:            { s in "Pausing \(s)" },
        resume:           { s in "Resuming \(s)" },
        setVolume:        { s, l in "Setting \(s) volume to \(l)" },
        adjustVolumeUp:   { s, a in "Turning \(s) volume up by \(a)" },
        adjustVolumeDown: { s, a in "Turning \(s) volume down by \(a)" },
        mute:             { s, v in "Muting \(s)\(v.map { " (currently at volume \($0))" } ?? "")" },
        unmute:           { s in "Unmuting \(s)" },
        stopped:          { s in "\(s) stopped" },
        paused:           { s in "\(s) paused" },
        resumed:          { s in "\(s) resumed" },
        volumeSet:        { s, l in "\(s) volume is now \(l)" },
        volumeAdjusted:   { s in "\(s) volume adjusted" },
        muted:            { s in "\(s) muted" },
        unmuted:          { s in "\(s) unmuted" },
        joinSpeakers:     { src, tgt in "Joining \(src) to \(tgt)" },
        leaveSpeaker:     { s in "Disconnecting \(s) from its group" },
        joined:           { src, tgt in "\(src) joined \(tgt)" },
        leftGroup:        { s in "\(s) is now playing alone" },
        listFavoritesResult: { s, list in "Favorites on \(s): \(list)" },
        actionCancelled:  "Action cancelled"
    )

    static let danish = CommandStrings(
        playFavorite:       { i, s in "Afspiller favorit \(i) på \(s)" },
        playFavoriteByName: { n, s in "Afspiller \(n) på \(s)" },
        playDefault:        { s in "Afspiller på \(s)" },
        stop:             { s in "Stopper afspilning på \(s)" },
        pause:            { s in "Pauser \(s)" },
        resume:           { s in "Genoptager \(s)" },
        setVolume:        { s, l in "Sætter \(s) lydstyrke til \(l)" },
        adjustVolumeUp:   { s, a in "Skruer \(s) lydstyrke op med \(a)" },
        adjustVolumeDown: { s, a in "Skruer \(s) lydstyrke ned med \(a)" },
        mute:             { s, v in "Slår \(s) fra\(v.map { " (lydstyrke \($0))" } ?? "")" },
        unmute:           { s in "Slår \(s) til" },
        stopped:          { s in "\(s) stoppet" },
        paused:           { s in "\(s) sat på pause" },
        resumed:          { s in "\(s) genoptaget" },
        volumeSet:        { s, l in "\(s) lydstyrke er nu \(l)" },
        volumeAdjusted:   { s in "\(s) lydstyrke justeret" },
        muted:            { s in "\(s) slået fra" },
        unmuted:          { s in "\(s) slået til" },
        joinSpeakers:     { src, tgt in "Tilslutter \(src) til \(tgt)" },
        leaveSpeaker:     { s in "Afkobler \(s) fra gruppen" },
        joined:           { src, tgt in "\(src) tilsluttet \(tgt)" },
        leftGroup:        { s in "\(s) spiller nu alene" },
        listFavoritesResult: { s, list in "Favoritter på \(s): \(list)" },
        actionCancelled:  "Handling annulleret"
    )

    static func forLanguage(_ language: Language) -> CommandStrings {
        language == .danish ? .danish : .english
    }
}
