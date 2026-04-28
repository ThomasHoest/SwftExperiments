import Foundation

/// Maps every `AppError` to a spoken and display string in the active language.
/// Strings are looked up from `ErrorStrings` at call time so language switches
/// take effect immediately without reinitialising this service.
struct ErrorResponseService {

    func spoken(_ error: AppError) -> String {
        let s = ErrorStrings.forLanguage(LanguageService.shared.activeLanguage)
        switch error {
        case .noSpeakerSpoken(let available):               return s.noSpeakerSpoken(available)
        case .speakerNotFound(let spoken, let available):   return s.speakerNotFound(spoken, available)
        case .favoriteNotFound(let n, let sp, let avail):   return s.favoriteNotFound(n, sp, avail)
        case .speakerUnreachable(let speaker):              return s.speakerUnreachable(speaker)
        case .nothingPlaying(let speaker):                  return s.nothingPlaying(speaker)
        case .volumeAtLimit(let speaker, let atMax):        return s.volumeAtLimit(speaker, atMax)
        case .pauseNotSupported(let speaker):               return s.pauseNotSupported(speaker)
        case .alreadyMuted(let speaker):                    return s.alreadyMuted(speaker)
        case .voiceNotRecognised:                           return s.voiceNotRecognised
        case .apiTimeout:                                   return s.apiTimeout
        }
    }

    /// Display string — identical to spoken for v1.
    func display(_ error: AppError) -> String { spoken(error) }
}
