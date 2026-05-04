import AppIntents
import SwiftUI
import WidgetKit

struct VoxioWidgetSmallView: View {
    let entry: VoxioWidgetEntry

    var body: some View {
        if entry.isEmpty {
            emptyContent
        } else if !entry.appRunning {
            appNotRunningContent
        } else {
            liveContent
        }
    }

    // MARK: - Live content

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            speakerHeader
            trackRow
            Text(entry.sourceBadge ?? "—")
                .font(BeoType.widgetCaption)
                .foregroundStyle(BeoColor.labelSecondary)
                .lineLimit(1)
            Spacer()
            primaryButton
        }
    }

    // MARK: - Speaker header

    private var speakerHeader: some View {
        HStack(spacing: Spacing.s4) {
            Image(systemName: "hifispeaker.fill")
                .font(.system(size: 12))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BeoColor.labelSecondary)
            Text(entry.speakerName)
                .font(BeoType.widgetSpeakerName)
                .foregroundStyle(BeoColor.labelPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Track row

    @ViewBuilder
    private var trackRow: some View {
        if entry.playbackState == "playing" {
            HStack(spacing: Spacing.s4) {
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BeoColor.accent)
                Text(entry.primaryLine ?? "—")
                    .font(BeoType.widgetTrack)
                    .foregroundStyle(BeoColor.labelPrimary)
                    .lineLimit(2)
            }
        } else {
            Text(entry.primaryLine ?? "—")
                .font(BeoType.widgetTrack)
                .foregroundStyle(BeoColor.labelPrimary)
                .lineLimit(2)
        }
    }

    // MARK: - Primary action button

    @ViewBuilder
    private var primaryButton: some View {
        if entry.playbackState == "loading" {
            Button(intent: makePlaybackToggle(host: entry.host)) {
                buttonLabel(icon: "ellipsis", label: "—", iconTint: BeoColor.labelSecondary)
            }
            .disabled(true)
            .glassButtonStyle()
            .accessibilityLabel("Loading")
        } else {
            let isPlaying = entry.playbackState == "playing"
            let icon  = isPlaying ? "pause.fill" : "play.fill"
            let label = isPlaying ? "Pause" : "Play"
            let tint  = isPlaying ? BeoColor.accent : BeoColor.labelSecondary
            let aLabel = isPlaying
                ? "Pause \(entry.speakerName)"
                : "Play \(entry.speakerName)"

            Button(intent: makePlaybackToggle(host: entry.host)) {
                buttonLabel(icon: icon, label: label, iconTint: tint)
            }
            .glassButtonStyle()
            .accessibilityLabel(aLabel)
        }
    }

    // MARK: - App not running

    private var appNotRunningContent: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            speakerHeader
            trackRow
            Text(entry.sourceBadge ?? "—")
                .font(BeoType.widgetCaption)
                .foregroundStyle(BeoColor.labelSecondary)
                .lineLimit(1)
            Spacer()
            Link(destination: URL(string: "voxio://open")!) {
                buttonLabel(icon: "arrow.up.forward.app.fill",
                            label: "Open Voxio",
                            iconTint: BeoColor.labelSecondary)
                    .glassButtonBackground()
            }
            .accessibilityLabel("Open Voxio")
        }
        .opacity(0.5)
    }

    // MARK: - Empty state

    private var emptyContent: some View {
        VStack(spacing: Spacing.s8) {
            Image(systemName: "hifispeaker.slash")
                .font(.system(size: 24))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BeoColor.labelSecondary)
            Text("No speaker found")
                .font(BeoType.widgetCaption)
                .foregroundStyle(BeoColor.labelSecondary)
            Link(destination: URL(string: "voxio://open")!) {
                Text("Open Voxio")
                    .font(BeoType.widgetCaption)
                    .foregroundStyle(BeoColor.labelSecondary)
            }
            .accessibilityLabel("Open Voxio")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func makePlaybackToggle(host: String?) -> PlaybackToggleIntent {
        let intent = PlaybackToggleIntent()
        intent.targetHost = host
        return intent
    }

    private func buttonLabel(icon: String, label: String, iconTint: Color) -> some View {
        HStack(spacing: WidgetButtonToken.iconGap) {
            Image(systemName: icon)
                .foregroundStyle(iconTint)
            Text(label)
                .font(BeoType.widgetCaption)
                .foregroundStyle(BeoColor.labelPrimary)
        }
        .padding(.vertical, WidgetButtonToken.paddingV)
        .padding(.horizontal, WidgetButtonToken.paddingH)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Glass button modifiers

private extension View {
    func glassButtonStyle() -> some View {
        self.glassButtonBackground()
    }

    func glassButtonBackground() -> some View {
        self
            .background(
                Capsule().fill(Color.black.opacity(0.45))
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
    }
}
