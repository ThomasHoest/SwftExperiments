import SwiftUI

enum BeoColor {
    // Adaptive — resolved from named assets in Assets.xcassets
    static let bg          = Color("BgPrimary")
    static let text        = Color("LabelPrimary")
    static let muted       = Color("LabelSecondary")
    static let accent      = Color("Accent")
    static let cardBg      = Color("CardSurface")
    static let cardBorder  = Color("CardBorder")
    static let separator   = Color("BeoSeparator")

    // v1.1 aliases — same assets as above; v1.0 names remain to avoid breaking call sites
    // UIAccessibility.isContrastEnabled audit: zero hits in codebase — SwiftUI-first, using
    // @Environment(\.colorSchemeContrast) throughout. No replacements needed. (T-2204)
    static let labelPrimary   = BeoColor.text   // T-2100
    static let labelSecondary = BeoColor.muted  // T-2100
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
