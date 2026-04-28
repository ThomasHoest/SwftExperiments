import SwiftUI

struct WaveformView: View {
    var audioLevel: Float
    var isListening: Bool

    @State private var breathPhase = false
    @State private var breathTask: Task<Void, Never>?

    private static let baseHeights: [CGFloat] = [0.35, 0.60, 0.85, 0.60, 0.35]
    private static let maxHeight:  CGFloat     = 44

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(0..<5, id: \.self) { i in bar(at: i) }
        }
        .onAppear {
            breathTask = Task { @MainActor in
                while !Task.isCancelled {
                    breathPhase.toggle()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        .onDisappear {
            breathTask?.cancel()
            breathTask = nil
        }
    }

    @ViewBuilder
    private func bar(at index: Int) -> some View {
        let h = height(at: index)
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(hex: "#C8A97E"))
            .frame(width: 4, height: h)
            .animation(
                isListening
                    ? .linear(duration: 0.06)
                    : .easeInOut(duration: 1.0).delay(Double(index) * 0.10),
                value: h
            )
    }

    private func height(at index: Int) -> CGFloat {
        let base = Self.baseHeights[index]
        if isListening && audioLevel > 0.01 {
            let boost = min(CGFloat(audioLevel) * 4.0, 1.0)
            return Self.maxHeight * (base * 0.5 + boost * 0.5)
        }
        return Self.maxHeight * base * (breathPhase ? 1.2 : 0.55)
    }
}
