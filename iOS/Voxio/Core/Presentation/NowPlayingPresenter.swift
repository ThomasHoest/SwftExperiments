import Foundation

/// Pure, free function that resolves a `NowPlayingPresentation` from raw
/// speaker state. Lives outside `Speaker` so it's unit-testable without a
/// speaker instance and reusable from the widget extension's writer.
enum NowPlayingPresenter {

    static func make(
        state: SpeakerPlaybackState,
        metadata: PlaybackMetadata?,
        sourceID: String?,
        sourceName: String?,
        typeHint: String? = nil
    ) -> NowPlayingPresentation {
        let category    = resolveCategory(sourceID: sourceID, typeHint: typeHint)
        let badge       = sourceName ?? fallbackName(for: category)
        let (p, s)      = lines(for: category, metadata: metadata)
        let playingLike = state == .playing || state == .buffering

        return NowPlayingPresentation(
            primaryLine:   p,
            secondaryLine: s,
            sourceBadge:   badge,
            isPlaying:     playingLike,
            category:      category
        )
    }

    // MARK: - Category resolution

    /// Looks at the prefix before the first ":" of the source ID. For TV apps
    /// (id like `TV|netflix:jid`) the prefix is `TV` so we still hit `.tv`.
    /// `typeHint` is consulted only when the id-based lookup yields `.unknown`.
    private static func resolveCategory(sourceID: String?, typeHint: String?) -> SourceCategory {
        if let id = sourceID, let prefix = id.split(separator: ":", maxSplits: 1).first {
            let key = prefix.lowercased()
            if let cat = byPrefix[key] { return cat }
        }
        if let hint = typeHint?.lowercased(), let cat = byHint[hint] {
            return cat
        }
        return .unknown
    }

    private static let byPrefix: [String: SourceCategory] = [
        "beoradio":     .beoRadio,
        "radio":        .netRadio,
        "spotify":      .spotify,
        "tidal":        .tidal,
        "tidalconnect": .tidal,
        "deezer":       .deezer,
        "music":        .appleMusic,
        "applemusic":   .appleMusic,
        "airplay":      .airplay,
        "googlecast":   .googleCast,
        "dlna":         .dlna,
        "qplay":        .qplay,
        "usb":          .usb,
        "bluetooth":    .bluetooth,
        "linein":       .lineIn,
        "toslink":      .toslink,
        "hdmi_a":       .hdmi,
        "hdmi_b":       .hdmi,
        "hdmi_c":       .hdmi,
        "hdmi":         .hdmi,
        "tv":           .tv,
        "alarm":        .alarm,
        "encore":       .encore,
    ]

    /// `typeHint` values from BNR (`sourceType.type`) and Mozart sources.
    /// Lower-cased; spaces collapsed away when matching.
    private static let byHint: [String: SourceCategory] = [
        "beo radio":   .beoRadio,
        "beoradio":    .beoRadio,
        "radio":       .netRadio,
        "tunein":      .netRadio,
        "spotify":     .spotify,
        "tidal":       .tidal,
        "deezer":      .deezer,
        "applemusic":  .appleMusic,
        "airplay":     .airplay,
        "googlecast":  .googleCast,
        "dlna":        .dlna,
        "usb":         .usb,
        "usb playback": .usb,
        "bluetooth":   .bluetooth,
        "line in":     .lineIn,
        "linein":      .lineIn,
        "toslink":     .toslink,
        "hdmi":        .hdmi,
        "tv":          .tv,
        "alarm":       .alarm,
    ]

    // MARK: - Line resolution

    private static func lines(
        for category: SourceCategory,
        metadata: PlaybackMetadata?
    ) -> (primary: String?, secondary: String?) {
        switch category {
        // Radio — title is station name; artist field carries free-form
        // live description (never labelled "Artist" in the UI).
        case .beoRadio, .netRadio:
            return (nonEmpty(metadata?.title), nonEmpty(metadata?.artist))

        // Track-aware sources.
        case .spotify, .tidal, .deezer, .appleMusic,
             .airplay, .googleCast, .dlna, .qplay,
             .usb, .storedMusic, .encore:
            return (nonEmpty(metadata?.title), nonEmpty(metadata?.artist))

        // Passthrough — no track-level metadata; source badge alone is enough.
        case .bluetooth, .lineIn, .toslink, .hdmi, .tv, .alarm:
            return (nil, nil)

        // Best-effort fallback for unrecognised sources.
        case .unknown:
            let primary = nonEmpty(metadata?.title)
                ?? nonEmpty(metadata?.genre)
                ?? nonEmpty(metadata?.album)
            return (primary, nonEmpty(metadata?.artist))
        }
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    // MARK: - Source badge fallback

    private static func fallbackName(for category: SourceCategory) -> String? {
        switch category {
        case .beoRadio:    return "B&O Radio"
        case .netRadio:    return "Radio"
        case .spotify:     return "Spotify"
        case .tidal:       return "Tidal"
        case .deezer:      return "Deezer"
        case .appleMusic:  return "Apple Music"
        case .airplay:     return "AirPlay"
        case .googleCast:  return "Cast"
        case .dlna:        return "DLNA"
        case .qplay:       return "QPlay"
        case .usb:         return "USB"
        case .storedMusic: return "Music"
        case .bluetooth:   return "Bluetooth"
        case .lineIn:      return "Line In"
        case .toslink:     return "Optical"
        case .hdmi:        return "HDMI"
        case .tv:          return "TV"
        case .alarm:       return "Alarm"
        case .encore:      return "Encore"
        case .unknown:     return nil
        }
    }
}
