import SwiftUI

struct SpeakerCardView: View {
    let speaker: Speaker

    var body: some View {
        HStack(spacing: Spacing.s12) {
            Image(systemName: "speaker.wave.2")
                .foregroundColor(BeoColor.accent)
                .opacity(speaker.isPlaying ? 1.0 : 0.3)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(speaker.name)
                    .font(BeoType.body)
                    .foregroundColor(BeoColor.text)

                Text(speaker.stateDisplay)
                    .font(BeoType.caption)
                    .foregroundColor(speaker.isPlaying ? BeoColor.accent : BeoColor.muted)

                if !speaker.trackDisplay.isEmpty {
                    Text(speaker.trackDisplay)
                        .font(BeoType.caption.italic())
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
                    .font(BeoType.caption)
                    .foregroundColor(BeoColor.muted)
            }
        }
        .padding(14)
        .background(BeoColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .stroke(
                    speaker.isPlaying
                        ? BeoColor.accent.opacity(0.35)
                        : BeoColor.cardBorder,
                    lineWidth: 1
                )
        )
    }
}
