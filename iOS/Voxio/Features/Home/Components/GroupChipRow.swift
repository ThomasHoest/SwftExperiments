import SwiftUI

// MARK: - ChipData
// File: iOS/Voxio/Features/Home/Components/GroupChipRow.swift
//
// Pure-data model for a single chip in the group chip row (E-53).
// E-60 adds:  case loading(name: String)   — spinner + dimmed label, non-interactive.
// F2 / E-61 will add:  var onTap: (@MainActor () -> Void)? = nil  (new ChipData property).
//
// E-61 NOTE: Adding `onTap: (@MainActor () -> Void)?` to ChipData breaks its implicit
// Sendable conformance. E-61 implementer must add @unchecked Sendable or @MainActor
// isolation at that time.

internal struct ChipData: Identifiable {
    /// Stable identity for ForEach diffing — generated automatically per instance.
    /// Default value ensures F2/E-61 can append new properties (e.g. `onTap`)
    /// without modifying any E-53 construction site.
    let id: UUID = UUID()
    /// Display name of the speaker. Used for the chip label and accessibilityLabel.
    let speakerName: String
    /// Determines chip rendering variant.
    let kind: ChipKind

    internal enum ChipKind: Equatable {
        /// Renders "+ <speakerName>"
        case member
        /// Renders "+<N> more" / "+<N> flere"; associated Int = remaining count.
        case overflow(Int)
        /// E-60 T-6002. Renders inline ProgressView + dimmed label. Non-interactive (US-81).
        /// `name` is the speaker display name shown alongside the spinner.
        /// Accessibility label: GroupingStrings.connectingFormat ("Connecting %@…").
        /// No tap gesture — loading chips cannot be removed mid-flight or re-dragged.
        // Do NOT add @unknown default to GroupChipRow.body's switch — any new case
        // must compile-break so the renderer is always updated explicitly (ADR-E53 CF-3).
        case loading(name: String)
    }
}

// MARK: - GroupChipRow

/// Display-only chip row shown at the bottom of a session card.
/// Renders one chip per element in `chips`; returns `EmptyView()` when the array is empty.
///
/// Caller is responsible for computing the overflow chip — `GroupChipRow` renders
/// chips exactly as provided, in order. Padding is applied at the `SpeakerCard` call site.
///
/// Behavioural contracts:
/// 1. `chips.isEmpty` → `EmptyView()` — no horizontal stack, no blank space.
/// 2. Each chip is a `Capsule()` with `.white.opacity(0.07)` background.
/// 3. Text style: `BeoType.caption`, `BeoColor.muted` foreground, `.lineLimit(1)`, `.truncationMode(.tail)`.
/// 4. Chip padding: `Spacing.s8` horizontal, `Spacing.s4` vertical.
/// 5. No `Button` wrapper and no `.onTapGesture` — chips are display-only in E-53.
///    (F2 / E-61 will add optional tap handling via `ChipData.onTap`.)
/// 6. The row does NOT reflow vertically at large Dynamic Type sizes — truncation is correct.
internal struct GroupChipRow: View {
    /// Fully-resolved chip data including overflow chip when applicable.
    let chips: [ChipData]

    var body: some View {
        if chips.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: Spacing.s8) {
                ForEach(chips) { chip in
                    chipView(chip)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Chip rendering

    @ViewBuilder
    private func chipView(_ chip: ChipData) -> some View {
        let strings = GroupChipStrings.forLanguage(LanguageService.shared.activeLanguage)

        switch chip.kind {
        case .member:
            Text("+ \(chip.speakerName)")
                .font(BeoType.caption)
                .foregroundStyle(BeoColor.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, Spacing.s8)
                .padding(.vertical, Spacing.s4)
                .background(.white.opacity(0.07), in: Capsule())
                .accessibilityLabel("\(strings.alsoPlaying): \(chip.speakerName)")

        case .overflow(let count):
            let label = String(format: strings.overflowFormat, count)
            let a11yLabel = String(format: strings.overflowAccessibilityFormat, count)
            Text(label)
                .font(BeoType.caption)
                .foregroundStyle(BeoColor.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, Spacing.s8)
                .padding(.vertical, Spacing.s4)
                .background(.white.opacity(0.07), in: Capsule())
                .accessibilityLabel(a11yLabel)

        // E-60 T-6002 — Loading chip: spinner + dimmed label, non-interactive (US-81).
        // Behavioural contracts:
        //   1. 10 pt circular ProgressView on the leading edge of the chip label.
        //   2. Entire chip at 0.6 opacity (design-spec §4.2).
        //   3. accessibilityLabel uses GroupingStrings.connectingFormat = "Connecting %@…".
        //   4. No tap gesture, no .contentShape — non-interactive chip.
        //   5. ProgressView respects @Environment(\.accessibilityReduceMotion) natively.
        case .loading(let name):
            let groupingStrings = GroupingStrings.forLanguage(LanguageService.shared.activeLanguage)
            HStack(spacing: Spacing.s4) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(width: 10, height: 10)
                    .tint(BeoColor.muted)
                Text(name)
                    .font(BeoType.caption)
                    .foregroundStyle(BeoColor.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .opacity(0.6)
            .padding(.horizontal, Spacing.s8)
            .padding(.vertical, Spacing.s4)
            .background(.white.opacity(0.07), in: Capsule())
            .accessibilityLabel(String(format: groupingStrings.connectingFormat, name))
            // No .onTapGesture — loading chips are non-interactive (US-81)
        }
    }
}
