import Foundation

// MARK: - Playback state

enum BNRPlaybackState: String {
    case playing, paused, stopped, buffering
}

// MARK: - Notification wire types

struct BNRNotification: Decodable {
    let notification: BNRNotificationEnvelope
}

struct BNRNotificationEnvelope: Decodable {
    let type: String
    let data: BNRNotificationData
}

struct BNRNotificationData: Decodable {
    // VOLUME
    let speaker: BNRSpeakerVolume?
    // SOURCE
    let primaryExperience: BNRPrimaryExperience?
    // PROGRESS_INFORMATION
    let state: String?
    // NOW_PLAYING_NET_RADIO
    let name: String?
    let liveDescription: String?
    let image: [BNRImage]?
    // NOW_PLAYING_STORED_MUSIC: name is reused; artist / album below
    let artist: String?
    let album: String?
}

struct BNRSpeakerVolume: Decodable {
    let level: Int
    let muted: Bool
    let range: BNRVolumeRange
}

struct BNRVolumeRange: Decodable {
    let minimum: Int
    let maximum: Int
}

struct BNRPrimaryExperience: Decodable {
    let source: BNRSourceRef?
    let state: String?      // per spec, SOURCE notifications include state here
}

struct BNRSourceRef: Decodable {
    let id: String?
    let friendlyName: String?
    let category: String?
}

struct BNRImage: Decodable {
    let url: String
    let size: String
}

// MARK: - Typed event

enum BNREvent {
    case volume(level: Int, muted: Bool)
    case source(name: String?, id: String?)
    case playbackState(BNRPlaybackState)
    case metadata(title: String?, artist: String?, album: String?)
    case unknown(String)
}

// MARK: - Normalisation

func normalise(_ notification: BNRNotification) -> BNREvent? {
    let envelope = notification.notification
    let data = envelope.data

    switch envelope.type {
    case "VOLUME":
        guard let spk = data.speaker else { return nil }
        let max = max(spk.range.maximum, 1)
        let pct = spk.level * 100 / max
        return .volume(level: pct, muted: spk.muted)

    case "SOURCE":
        let src = data.primaryExperience?.source
        let embeddedState = data.primaryExperience?.state
        Log.info("[BNR-norm] SOURCE → name:\(src?.friendlyName ?? "nil") id:\(src?.id ?? "nil") embeddedState:\(embeddedState ?? "nil")")
        return .source(name: src?.friendlyName, id: src?.id)

    case "PROGRESS_INFORMATION":
        let raw = data.state ?? ""
        let state = mapPlaybackState(raw)
        Log.info("[BNR-norm] PROGRESS_INFORMATION → raw:\"\(raw)\" → \(state)")
        return .playbackState(state)

    case "NOW_PLAYING_NET_RADIO":
        Log.info("[BNR-norm] NOW_PLAYING_NET_RADIO → title:\(data.name ?? "nil") artist:\(data.liveDescription ?? "nil")")
        return .metadata(title: data.name, artist: data.liveDescription, album: nil)

    case "NOW_PLAYING_STORED_MUSIC":
        Log.info("[BNR-norm] NOW_PLAYING_STORED_MUSIC → title:\(data.name ?? "nil") artist:\(data.artist ?? "nil") album:\(data.album ?? "nil")")
        return .metadata(title: data.name, artist: data.artist, album: data.album)

    case "NOW_PLAYING_ENDED":
        Log.info("[BNR-norm] NOW_PLAYING_ENDED (state mapping not currently emitted)")
        return nil

    case "STREAMING_STATUS":
        Log.info("[BNR-norm] STREAMING_STATUS data.state:\(data.state ?? "nil") — not currently mapped")
        return nil

    case "SOURCE_EXPERIENCE_CHANGED":
        Log.info("[BNR-norm] SOURCE_EXPERIENCE_CHANGED data.state:\(data.state ?? "nil") primary.state:\(data.primaryExperience?.state ?? "nil") — not currently mapped")
        return nil

    case "SOFTWARE_UPDATE_STATE":
        return nil

    default:
        Log.info("[BNR-norm] unhandled notification type: \(envelope.type)")
        return nil
    }
}

private func mapPlaybackState(_ raw: String) -> BNRPlaybackState {
    switch raw {
    case "play", "playing", "started": return .playing
    case "pause", "paused":             return .paused
    case "stop", "stopped":             return .stopped
    case "buffering":                   return .buffering
    case "completed", "ended":          return .stopped
    default:
        Log.info("[BNR-norm] mapPlaybackState: unknown raw state \"\(raw)\" → defaulting to .stopped")
        return .stopped
    }
}
