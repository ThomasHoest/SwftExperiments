import SwiftUI

// Design tokens from design-spec-bo-voice-control v1.1

enum BeoAsset {
    static let appBackground = "AppBackground"
}

enum Spacing {
    static let s4:  CGFloat = 4
    static let s8:  CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
}

enum Radius {
    static let card:  CGFloat = 20
    static let pill:  CGFloat = 100
    static let sheet: CGFloat = 16
}

enum BeoAnimation {
    static let springDamping:  CGFloat = 0.75
    static let springResponse: CGFloat = 0.45

    static var spring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }

    static var cardExpand: Animation {
        .spring(response: 0.4, dampingFraction: 0.7)
    }

    static var toast: Animation {
        .spring(response: 0.4, dampingFraction: 0.8)
    }
}

// v1.1 dark Liquid Glass button tokens — design-spec-bo-voice-control §Design Tokens Reference
enum DarkGlassButtonTokens {
    static let overlayColor:       Color   = .black.opacity(0.45)
    static let borderColor:        Color   = .white.opacity(0.15)
    static let borderWidth:        CGFloat = 0.5
    static let paddingV:           CGFloat = 10
    static let paddingH:           CGFloat = 16
    static let iconGap:            CGFloat = 6
    static let iconOnlySize:       CGFloat = 36
    static let pressedScale:       CGFloat = 0.95
    static let pressSpringResponse: Double = 0.3
    static let pressSpringDamping:  Double = 0.7
}

enum BeoType {
    static let speakerName    = Font.system(size: 34, weight: .semibold, design: .default)
    static let nowPlaying     = Font.system(size: 22, weight: .regular,  design: .default)
    static let confirmation   = Font.system(size: 17, weight: .regular,  design: .default)
    // body: SF Pro Text 15 pt — UI labels. Distinct from widgetTrack (SF Pro Display/rounded at 15 pt).
    static let body           = Font.system(size: 15, weight: .regular,  design: .default)
    static let caption        = Font.system(size: 12, weight: .medium,   design: .default)
}

extension BeoType {
    // Widget extension only — not used in the main app target.
    static let widgetSpeakerName = Font.system(size: 12, weight: .semibold, design: .default)
    // Widget extension only — not used in the main app target.
    // Uses .rounded design for SF Pro Display warmth at small sizes; distinct from BeoType.body (.default).
    static let widgetTrack       = Font.system(size: 15, weight: .regular,  design: .rounded)
    // Widget extension only — not used in the main app target.
    static let widgetCaption     = Font.system(size: 11, weight: .regular,  design: .default)
}

// Widget canvas-sized button padding — do not use in main app. See DarkGlassButtonTokens for main app values.
enum WidgetButtonToken {
    static let paddingV:     CGFloat = 8
    static let paddingH:     CGFloat = 12
    static let iconGap:      CGFloat = 6   // same as DarkGlassButtonTokens.iconGap
    static let iconOnlySize: CGFloat = 36  // same as DarkGlassButtonTokens.iconOnlySize
}
