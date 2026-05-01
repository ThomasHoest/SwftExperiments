import Foundation

func makeSpeakerClientPair(host: String, platform: SpeakerPlatform) -> (any SpeakerClient, any SpeakerEventSource) {
    switch platform {
    case .mozart: return (MozartClient(host: host), MozartEvents(host: host))
    case .bnr:    return (BNRClient(host: host),    BNREvents(host: host))
    }
}
