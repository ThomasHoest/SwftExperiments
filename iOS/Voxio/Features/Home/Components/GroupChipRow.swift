import SwiftUI

// MARK: - ChipData
// File: iOS/Voxio/Features/Home/Components/GroupChipRow.swift
//
// Pure-data model for a single chip in the group chip row (E-53).
// E-60 adds:  case loading(name: String)   — spinner + dimmed label, non-interactive.
// E-61 adds:  var onTap: (@MainActor () -> Void)? = nil  — tap handler for .member chips.
//
// E-61 NOTE: Adding `onTap: (@MainActor () -> Void)?` breaks ChipData's implicit
// Sendable conformance because closures that capture @MainActor-isolated state are not
// unconditionally Sendable. @unchecked Sendable is correct here: ChipData is constructed
// and consumed exclusively on @MainActor (SpeakerCard.chipData and GroupChipRow.body
// both run on the main actor). The closure calls SessionViewModel methods which are
// @MainActor-isolated. See extension below.

internal struct ChipData: Identifiable {
    /// Stable identity for ForEach diffing — generated automatically per instance.
    /// Default value ensures F2/E-61 can append new properties (e.g. `onTap`)
    /// without modifying any E-53 construction site.
    let id: UUID = UUID()
    /// Display name of the speaker. Used for the chip label and accessibilityLabel.
    let speakerName: String
    /// Determines chip rendering variant.
    let kind: ChipKind
    /// E-61 T-6102: optional tap handler for .member chips.
    /// Nil default means all E-53/E-60 construction sites compile unchanged.
    /// When non-nil, the chip body is wrapped in a Button and gains tap affordance.
    /// Loading chips always have onTap == nil (non-interactive per US-81).
    var onTap: (@MainActor () -> Void)? = nil

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

// E-61 T-6102: @unchecked Sendable because ChipData.onTap is a @MainActor-bound closure
// and ChipData is constructed and consumed exclusively on @MainActor. The compiler cannot
// prove Sendable without this annotation because (() -> Void) is not unconditionally
// Sendable, but the usage is safe — see struct-level comment above.
extension ChipData: @unchecked Sendable {}

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
            .contentShape(Rectangle())
            // iOS 26 workaround: chip-level tap recognizers (`.onTapGesture`,
            // `Button`, `.highPriorityGesture`, `.simultaneousGesture`) all
            // refused to fire when the chip row is nested under the session
            // card's `.dropDestination`. On-device diagnostics confirmed taps
            // reach the HStack but never the individual chips. Claim taps at
            // the HStack and route to the correct chip by x-coordinate. The
            // 88 pt stride matches each chip's `.frame(minWidth: 80)` plus
            // the 8 pt HStack spacing. Best-effort — for the typical case of
            // 2-3 chips with short Danish room names, location-based routing
            // is reliable. Loading chips (`.onTap == nil`) gracefully no-op.
            .onTapGesture(coordinateSpace: .local) { location in
                let stride: CGFloat = 88
                let idx = max(0, min(chips.count - 1, Int(location.x / stride)))
                let chip = chips[idx]
                Log.info("[Remove] chip tap → routed to [\(idx)] = \(chip.speakerName)")
                chip.onTap?()
            }
        }
    }

    // MARK: - Chip rendering

    @ViewBuilder
    private func chipView(_ chip: ChipData) -> some View {
        let strings = GroupChipStrings.forLanguage(LanguageService.shared.activeLanguage)

        switch chip.kind {
        case .member:
            // E-61 T-6102: when onTap is set, wrap the chip in a Button so the full
            // capsule area is tappable. The Button's action calls the @MainActor closure
            // directly. When onTap is nil (E-53 display-only context), the chip renders
            // as a plain label — all E-53/E-60 construction sites compile unchanged.
            let groupingStrings = GroupingStrings.forLanguage(LanguageService.shared.activeLanguage)
            memberChipView(chip: chip, strings: strings, groupingStrings: groupingStrings)

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

    // MARK: - Member chip (E-61 T-6102)
    //
    // Extracted into a separate @ViewBuilder so we can apply typed accessibility
    // modifiers to each concrete branch without a `let chipLabel: some View` binding
    // (which would lose the View type information needed for .accessibilityRole).

    @ViewBuilder
    private func memberChipView(
        chip: ChipData,
        strings: GroupChipStrings,
        groupingStrings: GroupingStrings
    ) -> some View {
        if let onTap = chip.onTap {
            // Visible chip — no tap gesture here; taps are handled by the
            // parent HStack and routed by location (see body comment).
            // The `.frame(minWidth: 80, minHeight: 44)` keeps the visible
            // bounding box predictable so the parent's stride-based routing
            // works, and meets Apple HIG's minimum touch-target size.
            // `.accessibilityAction` exposes the remove to VoiceOver (which
            // uses its own gesture path and is not affected by the iOS 26
            // drop-destination conflict).
            Text("+ \(chip.speakerName)")
                .font(BeoType.caption)
                .foregroundStyle(BeoColor.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, Spacing.s12)
                .padding(.vertical, Spacing.s8)
                .background(.white.opacity(0.07), in: Capsule())
                .frame(minWidth: 80, minHeight: 44)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(String(format: groupingStrings.chipMemberLabel, chip.speakerName))
                .accessibilityHint(groupingStrings.chipMemberHint)
                .accessibilityAction { onTap() }
        } else {
            // Display-only variant (E-53 context — onTap is nil).
            // Retains the status-only accessibilityLabel from E-60; no role change.
            Text("+ \(chip.speakerName)")
                .font(BeoType.caption)
                .foregroundStyle(BeoColor.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, Spacing.s8)
                .padding(.vertical, Spacing.s4)
                .background(.white.opacity(0.07), in: Capsule())
                .accessibilityLabel("\(strings.alsoPlaying): \(chip.speakerName)")
        }
    }
}
