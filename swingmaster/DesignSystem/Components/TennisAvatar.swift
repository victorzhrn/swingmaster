import SwiftUI

/// Solid color avatar with initial, consistent with tennis design tokens.
/// Avoid gradients on small elements per design principles.
struct TennisAvatar: View {
    let initial: String
    let size: CGFloat

    init(initial: String, size: CGFloat = 56) {
        self.initial = String(initial.prefix(1)).uppercased()
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(TennisColors.tennisGreen)
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.43, weight: .bold))
                    .foregroundColor(.white)
            )
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


