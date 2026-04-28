import SwiftUI

struct ConnectionStatusChip: View {
    var speakerCount: Int

    private var isOnline: Bool { speakerCount > 0 }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isOnline ? "wifi" : "wifi.slash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOnline ? Color.green : Color.secondary)

            Text(isOnline ? "\(speakerCount)" : "Offline")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOnline ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(in: Capsule())
    }
}
