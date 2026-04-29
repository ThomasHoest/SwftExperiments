#if canImport(FoundationModels)
import FoundationModels
import Foundation

extension CommandParserRouter {

    @available(iOS 26, *)
    func makeFoundationParser() -> Any? {
        let model = SystemLanguageModel.default
        if model.availability == .available {
            Log.info("[CommandParserRouter] Apple Intelligence available — FoundationModelParser active")
            return FoundationModelParser()
        }
        Log.info("[CommandParserRouter] Apple Intelligence unavailable — using TwoStageFallbackParser")
        return nil
    }

    @available(iOS 26, *)
    func tryFoundationModel(
        _ remainder: String,
        speaker: Speaker,
        allSpeakers: [String],
        favoriteNames: [String]
    ) async -> ParsedCommand? {
        guard let fp = foundationParser as? FoundationModelParser else { return nil }
        fp.updateContext(speakers: allSpeakers, activeSpeaker: speaker.name, favorites: favoriteNames)
        Log.info("[CommandParserRouter] path: FoundationModelParser")
        guard let result = try? await fp.parse(remainder, speaker: speaker) else {
            Log.info("[CommandParserRouter] FoundationModel failed — falling back to TwoStageFallbackParser")
            return nil
        }
        Log.info("[CommandParserRouter] result: \(result) (FoundationModel)")
        return result
    }

    @available(iOS 26, *)
    func warmUpFoundationModel() async {
        guard let fp = foundationParser as? FoundationModelParser else { return }
        await fp.warmUp()
    }
}
#endif
