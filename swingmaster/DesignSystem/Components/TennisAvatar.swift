import SwiftUI

/// Ring-style avatar with initial, aligned with tennis design tokens.
/// Uses a 2pt Tennis Green border and a transparent center.
struct TennisAvatar: View {
    let initial: String
    let size: CGFloat

    init(initial: String, size: CGFloat = 48) {
        self.initial = String(initial.prefix(1)).uppercased()
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.tennisPrimary, lineWidth: 2)
            Text(initial)
                .font(.system(size: size * 0.43, weight: .bold))
                .foregroundColor(.tennisPrimary)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .accessibilityLabel("Avatar for \(initial)")
        .accessibilityHidden(false)
    }
}

#Preview {
    HStack(spacing: 16) {
        TennisAvatar(initial: "V")
        TennisAvatar(initial: "A", size: 40)
    }
    .padding()
}


