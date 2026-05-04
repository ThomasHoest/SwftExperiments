import AppIntents
import SwiftUI
import WidgetKit

struct VoxioWidgetMediumView: View {
    let entry: VoxioWidgetEntry

    var body: some View {
        if entry.isEmpty {
            emptyContent
        } else {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                speakerHeader
                contentArea
            }
            .opacity(entry.appRunning ? 1.0 : 0.5)
        }
    }

    // MARK: - Speaker header (full width)

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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Two-column content area

    private var contentArea: some View {
        HStack(alignment: .center, spacing: 0) {
            leftColumn
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(55)

            Rectangle()
                .frame(width: 0.5)
                .foregroundStyle(BeoColor.separator.opacity(0.15))
                .padding(.horizontal, Spacing.s4)

            rightColumn
                .frame(maxWidth: .infinity)
                .layoutPriority(45)
        }
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            if entry.appRunning {
                trackRow
                Text("\(entry.sourceBadge ?? "—") · \(entry.volume)")
                    .font(BeoType.widgetCaption)
                    .foregroundStyle(BeoColor.labelSecondary)
                    .lineLimit(1)
            } else {
                trackRow
                Text("\(entry.sourceBadge ?? "—") · \(entry.volume)")
                    .font(BeoType.widgetCaption)
                    .foregroundStyle(BeoColor.labelSecondary)
                    .lineLimit(1)
                Spacer()
                Text("Open to control")
                    .font(BeoType.widgetCaption)
                    .foregroundStyle(BeoColor.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private var trackRow: some View {
        if entry.playbackState == "playing" {
            HStack(spacing: Spacing.s4) {
                Image(systemName: "waveform")
                    .font(.system(size: 12))
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

    // MARK: - Right column

    @ViewBuilder
    private var rightColumn: some View {
        if entry.appRunning {
            VStack(spacing: Spacing.s8) {
                playPauseButton
                volumeRow
            }
        } else {
            Link(destination: URL(string: "voxio://open")!) {
                openVoxioLabel
            }
            .accessibilityLabel("Open Voxio")
        }
    }

    // MARK: - Play/pause button

    @ViewBuilder
    private var playPauseButton: some View {
        if entry.playbackState == "loading" {
            Button(intent: makePlaybackToggle(host: entry.host)) {
                HStack(spacing: WidgetButtonToken.iconGap) {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(BeoColor.labelSecondary)
                    Text("—")
                        .font(BeoType.widgetCaption)
                        .foregroundStyle(BeoColor.labelPrimary)
                }
                .padding(.vertical, WidgetButtonToken.paddingV)
                .padding(.horizontal, WidgetButtonToken.paddingH)
                .frame(maxWidth: .infinity)
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
                HStack(spacing: WidgetButtonToken.iconGap) {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                    Text(label)
                        .font(BeoType.widgetCaption)
                        .foregroundStyle(BeoColor.labelPrimary)
                }
                .padding(.vertical, WidgetButtonToken.paddingV)
                .padding(.horizontal, WidgetButtonToken.paddingH)
                .frame(maxWidth: .infinity)
            }
            .glassButtonStyle()
            .accessibilityLabel(aLabel)
        }
    }

    // MARK: - Volume row

    private func makeAdjustVolume(delta: Int) -> AdjustVolumeIntent {
        let intent = AdjustVolumeIntent()
        intent.delta = delta
        intent.targetHost = entry.host
        return intent
    }

    private func makePlaybackToggle(host: String?) -> PlaybackToggleIntent {
        let intent = PlaybackToggleIntent()
        intent.targetHost = host
        return intent
    }

    private var volumeRow: some View {
        HStack(spacing: Spacing.s8) {
            Button(intent: makeAdjustVolume(delta: -10)) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: WidgetButtonToken.iconOnlySize / 2))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BeoColor.labelPrimary)
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(entry.volume <= 0)
            .opacity(entry.volume <= 0 ? 0.4 : 1.0)
            .accessibilityLabel("Volume down")

            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 16))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BeoColor.labelSecondary)

            Button(intent: makeAdjustVolume(delta: 10)) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: WidgetButtonToken.iconOnlySize / 2))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BeoColor.labelPrimary)
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(entry.volume >= 100)
            .opacity(entry.volume >= 100 ? 0.4 : 1.0)
            .accessibilityLabel("Volume up")
        }
    }

    // MARK: - Open Voxio label (app not running right column)

    private var openVoxioLabel: some View {
        HStack(spacing: WidgetButtonToken.iconGap) {
            Image(systemName: "arrow.up.forward.app.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BeoColor.labelSecondary)
            Text("Open Voxio")
                .font(BeoType.widgetCaption)
                .foregroundStyle(BeoColor.labelSecondary)
        }
        .padding(.vertical, WidgetButtonToken.paddingV)
        .padding(.horizontal, WidgetButtonToken.paddingH)
        .frame(maxWidth: .infinity)
        .glassButtonBackground()
    }

    // MARK: - Empty state

    private var emptyContent: some View {
        HStack(spacing: Spacing.s12) {
            VStack(spacing: Spacing.s8) {
                Image(systemName: "hifispeaker.slash")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BeoColor.labelSecondary)
                Text("No speaker found")
                    .font(BeoType.widgetCaption)
                    .foregroundStyle(BeoColor.labelSecondary)
            }
            .frame(maxWidth: .infinity)
            Link(destination: URL(string: "voxio://open")!) {
                Text("Open Voxio")
                    .font(BeoType.widgetCaption)
                    .foregroundStyle(BeoColor.labelSecondary)
                    .padding(.vertical, WidgetButtonToken.paddingV)
                    .padding(.horizontal, WidgetButtonToken.paddingH)
                    .glassButtonBackground()
            }
            .accessibilityLabel("Open Voxio")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
