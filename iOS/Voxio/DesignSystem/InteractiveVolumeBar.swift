import SwiftUI

// MARK: - InteractiveVolumeBar
//
// E-57 changes applied in this file:
//   T-5701 — GeometryReader + two Capsule views + DragGesture(minimumDistance: 0).
//            Value binding: Int 0–100, snapped to nearest 5.
//            onEditingChanged(true) fires on first onChanged per gesture.
//            onEditingChanged(false) fires on onEnded.
//   T-5706 — .accessibilityLabel / .accessibilityValue / .accessibilityAdjustableAction

struct InteractiveVolumeBar: View {
    /// Volume level 0–100, snapped to multiples of 5.
    @Binding var value: Int
    /// Called with `true` when drag starts, `false` when drag ends.
    let onEditingChanged: (Bool) -> Void

    /// Tracks whether we've already fired onEditingChanged(true) for the current gesture.
    @State private var isEditing: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track — frosted underlay
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 4)

                    // Gold fill — proportional to value
                    Capsule()
                        .fill(Color(hex: "#C8A97E"))
                        .frame(width: geo.size.width * CGFloat(value) / 100, height: 4)
                        // Animate only external (non-drag) value changes
                        .animation(.easeOut(duration: 0.3), value: value)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                // Transparent full-area overlay carrying the drag gesture
                .overlay(
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let snapped = snappedValue(from: drag.location.x,
                                                               width: geo.size.width)
                                    value = snapped
                                    if !isEditing {
                                        isEditing = true
                                        onEditingChanged(true)
                                    }
                                }
                                .onEnded { drag in
                                    let snapped = snappedValue(from: drag.location.x,
                                                               width: geo.size.width)
                                    value = snapped
                                    onEditingChanged(false)
                                    isEditing = false
                                }
                        )
                )
            }
            .frame(height: 4)

            // Trailing volume number — 12 pt medium, secondary colour, 28 pt fixed width
            Text("\(value)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        // T-5706: Accessibility
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(value) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(100, value + 5)
                onEditingChanged(true)
                onEditingChanged(false)
            case .decrement:
                value = max(0, value - 5)
                onEditingChanged(true)
                onEditingChanged(false)
            default:
                break
            }
        }
    }

    // MARK: - Helpers

    /// Maps an x position within the track to a clamped 0–100 value snapped to the nearest 5.
    private func snappedValue(from x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return value }
        let fraction = Double(max(0, min(x, width)) / width)
        let raw = fraction * 100
        let snapped = Int((raw / 5).rounded()) * 5
        return max(0, min(100, snapped))
    }
}
