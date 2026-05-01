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
        return .source(name: src?.friendlyName, id: src?.id)

    case "PROGRESS_INFORMATION":
        let state = mapPlaybackState(data.state ?? "")
        return .playbackState(state)

    case "NOW_PLAYING_NET_RADIO":
        return .metadata(title: data.name, artist: data.liveDescription, album: nil)

    case "NOW_PLAYING_STORED_MUSIC":
        return .metadata(title: data.name, artist: data.artist, album: data.album)

    case "SOFTWARE_UPDATE_STATE":
        return nil

    default:
        Log.verbose("[BNR] unknown notification type: \(envelope.type)")
        return nil
    }
}

private func mapPlaybackState(_ raw: String) -> BNRPlaybackState {
    switch raw {
    case "play":      return .playing
    case "pause":     return .paused
    case "stop":      return .stopped
    case "buffering": return .buffering
    case "completed": return .stopped
    default:          return .stopped
    }
}
