import SwiftUI

enum BeoColor {
    // Adaptive — resolved from named assets in Assets.xcassets
    static let bg          = Color("BgPrimary")
    static let text        = Color("LabelPrimary")
    static let muted       = Color("LabelSecondary")
    static let accent      = Color("Accent")
    static let cardBg      = Color("CardSurface")
    static let cardBorder  = Color("CardBorder")
    static let separator   = Color("Separator")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
