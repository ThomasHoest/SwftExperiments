import Foundation

extension CommandParserRouter {
    func parseFallback(_ transcript: String) -> VoiceCommand {
        let result = fallback.parse(transcript)
        Log.info("[CommandParserRouter] result: \(result) (NLModel)")
        return toVoiceCommand(result)
    }
}
