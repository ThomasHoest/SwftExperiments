import SwiftUI

// Design tokens from design-spec-bo-voice-control v1.0

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

enum BeoType {
    static let speakerName    = Font.system(size: 34, weight: .semibold, design: .default)
    static let nowPlaying     = Font.system(size: 22, weight: .regular,  design: .default)
    static let confirmation   = Font.system(size: 17, weight: .regular,  design: .default)
    static let body           = Font.system(size: 15, weight: .regular,  design: .default)
    static let caption        = Font.system(size: 12, weight: .medium,   design: .default)
}
