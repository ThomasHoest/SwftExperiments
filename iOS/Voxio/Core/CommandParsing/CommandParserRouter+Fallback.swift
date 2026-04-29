import Foundation

extension CommandParserRouter {
    func parseFallback(_ remainder: String) -> ParsedCommand {
        Log.info("[CommandParserRouter] path: TwoStageFallbackParser")
        let result = fallback.parse(remainder)
        Log.info("[CommandParserRouter] result: \(result) (Fallback)")
        return result
    }
}
