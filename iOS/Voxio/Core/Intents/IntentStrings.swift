import Foundation

enum IntentStrings {
    static func appNotRunning(_ lang: Language) -> String {
        switch lang {
        case .english: return "To control your speaker, open Voxio first."
        case .danish:  return "Åbn Voxio for at styre din højttaler."
        }
    }

    static func speakerUnreachable(_ name: String, _ lang: Language) -> String {
        switch lang {
        case .english: return "I couldn't reach \(name). Make sure Voxio is running and the speaker is on the network."
        case .danish:  return "Jeg kunne ikke nå \(name). Sørg for, at Voxio kører og højttaleren er på netværket."
        }
    }

    static func speakerNotFound(_ name: String, _ lang: Language) -> String {
        switch lang {
        case .english: return "I couldn't find a speaker called \(name) in Voxio. Make sure it's on the network."
        case .danish:  return "Jeg kunne ikke finde en højttaler ved navn \(name) i Voxio. Sørg for, at den er på netværket."
        }
    }

    static func joined(_ source: String, _ target: String, _ lang: Language) -> String {
        switch lang {
        case .english: return "Joined \(source) to \(target)."
        case .danish:  return "Tilsluttede \(source) til \(target)."
        }
    }

    static func left(_ name: String, _ lang: Language) -> String {
        switch lang {
        case .english: return "\(name) is now playing alone."
        case .danish:  return "\(name) spiller nu alene."
        }
    }
}
