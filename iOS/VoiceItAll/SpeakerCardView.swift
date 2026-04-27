import SwiftUI

struct SpeakerCardView: View {
    let speaker: Speaker

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2")
                .foregroundColor(BeoColor.accent)
                .opacity(speaker.isPlaying ? 1.0 : 0.3)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(speaker.name)
                    .font(.system(size: 13))
                    .foregroundColor(BeoColor.text)

                Text(speaker.stateDisplay)
                    .font(.system(size: 11))
                    .foregroundColor(speaker.isPlaying ? BeoColor.accent : BeoColor.muted)

                if !speaker.trackDisplay.isEmpty {
                    Text(speaker.trackDisplay)
                        .font(.system(size: 11).italic())
                        .foregroundColor(BeoColor.muted)
                        .lineLimit(1)
                }

                if speaker.batteryLevel != nil {
                    Text(speaker.batteryDisplay)
                        .font(.system(size: 10))
                        .foregroundColor(BeoColor.muted)
                }
            }

            Spacer()

            if !speaker.volumeDisplay.isEmpty {
                Text(speaker.volumeDisplay)
                    .font(.system(size: 11))
                    .foregroundColor(BeoColor.muted)
            }
        }
        .padding(14)
        .background(BeoColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    speaker.isPlaying
                        ? BeoColor.accent.opacity(0.35)
                        : BeoColor.cardBorder,
                    lineWidth: 1
                )
        )
    }
}

enum BeoColor {
    static let bg          = Color(hex: "#080808")
    static let text        = Color(hex: "#E8E3DA")
    static let muted       = Color(hex: "#888888")
    static let accent      = Color(hex: "#C4A07A")
    static let cardBg      = Color(hex: "#0D0D0D")
    static let cardBorder  = Color(hex: "#2A2A2A")
    static let separator   = Color(hex: "#1E1E1E")
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
