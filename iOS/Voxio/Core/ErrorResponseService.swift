import Foundation

/// Maps every `AppError` to the exact spoken and display strings from the functional spec v1.2.
struct ErrorResponseService {

    func spoken(_ error: AppError) -> String {
        switch error {

        case .noSpeakerSpoken(let available):
            let list = available.isEmpty ? "none found" : available.joined(separator: ", ")
            return "Please start your command with a speaker name. Available speakers are: \(list)"

        case .speakerNotFound(let spoken, let available):
            let list = available.joined(separator: ", ")
            return "\(spoken) was not found. Available speakers are: \(list)"

        case .favoriteNotFound(let name, let speaker, let available):
            let list = available.isEmpty ? "none" : available.joined(separator: ", ")
            return "\(name) was not found on \(speaker). Available favorites are: \(list)"

        case .speakerUnreachable(let speaker):
            return "\(speaker) could not be reached. Please check the speaker is powered on and connected to the network"

        case .nothingPlaying(let speaker):
            return "\(speaker) is not currently playing anything"

        case .volumeAtLimit(let speaker, let atMax):
            return "\(speaker) is already at \(atMax ? "maximum" : "minimum") volume"

        case .pauseNotSupported(let speaker):
            return "\(speaker) does not support pause for this source. Say \(speaker), stop to stop instead"

        case .alreadyMuted(let speaker):
            return "\(speaker) is already muted"

        case .voiceNotRecognised:
            return "Sorry, I didn't catch that. Please repeat your command"

        case .apiTimeout:
            return "Could not reach the Bang & Olufsen service. Please try again"
        }
    }

    /// Display string — identical to spoken for v1; E-12 can diverge these.
    func display(_ error: AppError) -> String { spoken(error) }
}
