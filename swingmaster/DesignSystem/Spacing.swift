import SwiftUI

/// Tennis design system spacing tokens based on a 4pt grid.
///
/// Use these constants instead of raw numbers to maintain visual rhythm.
///
/// Example:
/// ```swift
/// VStack(spacing: Spacing.large) { ... }
/// .padding(.horizontal, Spacing.screenMargin)
/// ```
enum Spacing {
    static let micro: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xlarge: CGFloat = 32
    static let xxlarge: CGFloat = 48

    // Convenience for common patterns
    static let cardPadding: CGFloat = 16
    static let screenMargin: CGFloat = 16
    static let sectionGap: CGFloat = 24
}


