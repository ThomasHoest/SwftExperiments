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
    func tryFoundationModel(_ transcript: String) async -> VoiceCommand? {
        guard let fp = foundationParser as? FoundationModelParser else { return nil }
        Log.info("[CommandParserRouter] path: FoundationModelParser")
        guard let result = try? await fp.parse(transcript) else {
            Log.info("[CommandParserRouter] FoundationModel failed — falling back to TwoStageFallbackParser")
            return nil
        }
        Log.info("[CommandParserRouter] result: \(toVoiceCommand(result)) (FoundationModel)")
        return toVoiceCommand(result)
    }

    @available(iOS 26, *)
    func warmUpFoundationModel() async {
        guard let fp = foundationParser as? FoundationModelParser else { return }
        await fp.warmUp()
    }
}
#endif
