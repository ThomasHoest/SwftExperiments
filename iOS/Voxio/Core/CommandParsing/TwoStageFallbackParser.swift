import Foundation
import NaturalLanguage

private let defaultVolumeStep = 10

/// Two-stage deterministic + probabilistic fallback parser.
///
/// Stage 1: Swift `Regex` patterns — O(1) per intent, exact and fast.
/// Stage 2: `NLModel` text classifier — probabilistic, handles phrasing variation.
/// If both stages fail or confidence is below 0.65, returns `.unknown`.
struct TwoStageFallbackParser {

    // ── NLModel (Stage 2) ─────────────────────────────────────────────────────

    private static let nlModel: NLModel? = {
        guard let url = Bundle.main.url(forResource: "VoxioCommandModel", withExtension: "mlmodelc") else {
            Log.info("[TwoStageFallbackParser] NLModel not found — Stage 2 disabled")
            return nil
        }
        return try? NLModel(contentsOf: url)
    }()

    // ── Public API ────────────────────────────────────────────────────────────

    func parse(_ remainder: String) -> ParsedCommand {
        let text = remainder.trimmingCharacters(in: .whitespaces).lowercased()
        Log.verbose("[TwoStageFallbackParser] input: \"\(text)\"")
        guard !text.isEmpty else {
            Log.info("[TwoStageFallbackParser] empty input → unknown")
            return .unknown(remainder)
        }

        if let stage1 = parseStage1(text, raw: remainder) {
            Log.info("[TwoStageFallbackParser] Stage 1 match → \(stage1)")
            return stage1
        }
        Log.verbose("[TwoStageFallbackParser] Stage 1 no match — trying Stage 2")

        if let stage2 = parseStage2(text, raw: remainder) {
            Log.info("[TwoStageFallbackParser] Stage 2 match → \(stage2)")
            return stage2
        }

        Log.info("[TwoStageFallbackParser] Stage 1 + Stage 2 no match → unknown(\"\(text)\")")
        return .unknown(remainder)
    }

    // ── Stage 1: Deterministic Regex ─────────────────────────────────────────

    private func parseStage1(_ text: String, raw: String) -> ParsedCommand? {
        // confirm / cancel  (anchored — must be the whole utterance)
        if text.matches(of: /^(yes|yeah|correct|do it|confirm|ja|jo)$/).count > 0 {
            return ParsedCommand(intent: .confirm)
        }
        if text.matches(of: /^(no|cancel|stop that|never mind|nope|nej|annuller)$/).count > 0 {
            return ParsedCommand(intent: .cancel)
        }

        // stop
        if text.contains(/\b(stop|stop music|stop playing)\b/) {
            return ParsedCommand(intent: .stop)
        }
        // pause
        if text.contains(/\bpause\b/) {
            return ParsedCommand(intent: .pause)
        }
        // resume
        if text.contains(/\b(resume|continue playing|unpause|fortsæt|genoptag)\b/) {
            return ParsedCommand(intent: .resume)
        }
        // unmute (before mute so "unmute" doesn't match \bmute\b)
        if text.contains(/\b(unmute|slå lyden til)\b/) {
            return ParsedCommand(intent: .unmute)
        }
        // mute
        if text.contains(/\b(mute|slå lyden fra|tavs)\b/) {
            return ParsedCommand(intent: .mute)
        }

        // list favorites
        if text.contains(/\b(what are my favou?rites?|list favou?rites?|show favou?rites?|list favoritter|vis favoritter|hvad er mine favoritter)\b/) {
            return ParsedCommand(intent: .listFavorites)
        }

        // set volume (absolute) — "set volume to 42" / "volume 42" / "lydstyrke 42"
        if let match = text.firstMatch(of: /\b(?:set volume to|volume|lydstyrke)\s+(\d{1,3})\b/) {
            let value = max(0, min(100, Int(match.1) ?? 0))
            return ParsedCommand(intent: .setVolume, volumeValue: value)
        }

        // volume up with amount — "volume up 20" / "louder by 20" / "skru op 20"
        if let match = text.firstMatch(of: /\b(?:volume up|louder by|skru op|højere med)\s+(\d{1,3})\b/) {
            let delta = Int(match.1) ?? defaultVolumeStep
            return ParsedCommand(intent: .volumeUp, volumeDelta: delta)
        }
        // volume down with amount — "volume down 20" / "quieter by 20" / "skru ned 20"
        if let match = text.firstMatch(of: /\b(?:volume down|quieter by|skru ned|lavere med)\s+(\d{1,3})\b/) {
            let delta = Int(match.1) ?? defaultVolumeStep
            return ParsedCommand(intent: .volumeDown, volumeDelta: delta)
        }
        // volume up (default step)
        if text.contains(/\b(volume up|louder|higher|increase|skru op|højere)\b/) {
            return ParsedCommand(intent: .volumeUp)
        }
        // volume down (default step)
        if text.contains(/\b(volume down|quieter|softer|lower|decrease|skru ned|lavere)\b/) {
            return ParsedCommand(intent: .volumeDown)
        }

        // play favorite by number — "play favorite one" / "afspil favorit en" / "start favorit et"
        let playTriggers      = Set(["play", "afspil", "spil", "start"])
        let favoriteTriggers  = Set(["favorite", "favourite", "favorit", "favorites", "favourites"])
        let numberWordMap: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4,
            "en": 1,  "et": 1,  "to": 2,    "tre": 3,  "fire": 4
        ]
        let words = text.split(separator: " ").map(String.init)
        Log.verbose("[TwoStageFallbackParser] words: \(words)")
        if words.count >= 3,
           playTriggers.contains(words[0]),
           favoriteTriggers.contains(words[1]),
           let index = numberWordMap[words[2]] {
            return ParsedCommand(intent: .playFavoriteByNumber, favoriteIndex: index)
        }

        // play default (bare "play" / "afspil" / "spil" / "start")
        if text.matches(of: /^(play|afspil|spil|start)(?: music| noget)?$/).count > 0 {
            return ParsedCommand(intent: .playDefault)
        }

        return nil
    }

    // ── Stage 2: NLModel Classifier ───────────────────────────────────────────

    private static let confidenceThreshold: Double = 0.65

    private func parseStage2(_ text: String, raw: String) -> ParsedCommand? {
        guard let model = TwoStageFallbackParser.nlModel else { return nil }

        let hypotheses = model.predictedLabelHypotheses(for: text, maximumCount: 1)
        guard let (label, confidence) = hypotheses.first else {
            Log.info("[TwoStageFallbackParser] Stage 2 produced no hypotheses")
            return nil
        }
        Log.verbose("[TwoStageFallbackParser] Stage 2 top: \"\(label)\" confidence=\(String(format: "%.2f", confidence)) (threshold=\(TwoStageFallbackParser.confidenceThreshold))")
        guard confidence >= TwoStageFallbackParser.confidenceThreshold,
              let intent = CommandIntent(rawValue: label)
        else {
            Log.info("[TwoStageFallbackParser] Stage 2 rejected: \"\(label)\" confidence=\(String(format: "%.2f", confidence)) below threshold")
            return nil
        }

        // Extract slots for play-named and volume intents
        var favoriteName: String?
        var volumeDelta: Int?

        if intent == .playNamed {
            // Trailing phrase after "play" / "afspil" / "spil"
            if let match = text.firstMatch(of: /(?:play|afspil|spil)\s+(.+)$/) {
                favoriteName = String(match.1)
            }
        }
        if intent == .volumeUp || intent == .volumeDown {
            if let match = text.firstMatch(of: /(\d{1,3})/) {
                volumeDelta = Int(match.1)
            }
        }

        return ParsedCommand(
            intent:       intent,
            favoriteName: favoriteName,
            volumeDelta:  volumeDelta,
            rawText:      raw
        )
    }
}
