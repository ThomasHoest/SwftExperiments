import Foundation

extension CommandParserRouter {
    func parseFallback(_ transcript: String) -> VoiceCommand {
        Log.info("[CommandParserRouter] path: TwoStageFallbackParser")
        let result = fallback.parse(transcript)
        Log.info("[CommandParserRouter] result: \(result) (Fallback)")
        return toVoiceCommand(result)
    }
}
