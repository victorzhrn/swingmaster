import SwiftUI

/// Tennis design system typography helpers and modifiers.
///
/// Provides a simple API for common text styles following iOS HIG.
/// Prefer the system font for platform consistency.
///
/// Usage examples:
/// ```swift
/// TennisTypography.largeTitle("Tennis Coach")
/// TennisTypography.headline("Recent Sessions")
/// TennisTypography.metric("7.5")
/// Text("7.5").modifier(TennisTypography.MetricStyle())
/// ```
struct TennisTypography {
    /// Large screen titles – 34pt regular.
    /// - Parameter text: The string to render.
    /// - Returns: A configured `Text` view.
    static func largeTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .regular))
    }

    /// Headline for card titles – 17pt semibold.
    /// - Parameter text: The string to render.
    /// - Returns: A configured `Text` view.
    static func headline(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
    }

    /// Monospaced metric text – 24pt bold, stable width.
    /// - Parameter value: The metric string to render.
    /// - Returns: A configured `Text` view.
    static func metric(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 24, weight: .bold, design: .monospaced))
    }

    /// ViewModifier for applying the standard metric style to any `Text`.
    struct MetricStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.system(size: 24, weight: .bold, design: .monospaced))
        }
    }
}

extension View {
    /// Convenience for applying metric style to any view producing text.
    /// - Returns: A view with `MetricStyle` applied.
    func tennisMetricStyle() -> some View {
        modifier(TennisTypography.MetricStyle())
    }
}


