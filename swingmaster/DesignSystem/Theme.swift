import SwiftUI

/// Theme environment object for app-wide design system preferences.
///
/// Holds runtime flags like reduced transparency/motion and the active color scheme,
/// enabling views/components to adapt consistently.
final class Theme: ObservableObject {
    /// Active color scheme (updated by views as needed).
    @Published var colorScheme: ColorScheme = .light

    /// Whether reduced transparency is enabled (affects glass effects).
    @Published var useReducedTransparency: Bool = UIAccessibility.isReduceTransparencyEnabled

    /// Whether reduce motion is enabled (affects animations).
    @Published var useReduceMotion: Bool = UIAccessibility.isReduceMotionEnabled

    /// Refresh theme from current environment.
    /// - Parameter scheme: The environment color scheme.
    func refresh(from scheme: ColorScheme) {
        colorScheme = scheme
        useReducedTransparency = UIAccessibility.isReduceTransparencyEnabled
        useReduceMotion = UIAccessibility.isReduceMotionEnabled
    }
}

// MARK: - EnvironmentKey for Theme
private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = Theme()
}

extension EnvironmentValues {
    /// Access the shared `Theme` via environment.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    /// Inject a `Theme` into the environment and as an `EnvironmentObject` for observers.
    /// - Parameter theme: The theme instance to provide.
    /// - Returns: A view with theme in the environment.
    func theme(_ theme: Theme) -> some View {
        self
            .environment(\.theme, theme)
            .environmentObject(theme)
    }
}


