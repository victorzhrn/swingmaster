import SwiftUI

/// A reusable glass-morphism container that applies iOS material backgrounds,
/// border strokes for edge definition, and light-mode shadow polish.
///
/// Styles:
/// - `.subtle` – Overlays on video
/// - `.medium` – Standard cards
/// - `.heavy` – Modals and focused surfaces
///
/// Usage example:
/// ```swift
/// GlassContainer(style: .medium, cornerRadius: 16) {
///     VStack { /* content */ }
///         .padding(Spacing.cardPadding)
/// }
/// ```
struct GlassContainer<Content: View>: View {
    enum Style {
        case subtle   // Video overlays
        case medium   // Cards
        case heavy    // Modals

        var material: Material {
            switch self {
            case .subtle: return .ultraThinMaterial
            case .medium: return .thinMaterial
            case .heavy: return .regularMaterial
            }
        }

        var borderOpacity: Double {
            switch self {
            case .subtle: return 0.1
            case .medium: return 0.15
            case .heavy: return 0.2
            }
        }
    }

    let style: Style
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content()
            .background(style.material)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(style.borderOpacity), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: colorScheme == .light ? .black.opacity(0.08) : .clear,
                radius: 8,
                y: 4
            )
    }
}


