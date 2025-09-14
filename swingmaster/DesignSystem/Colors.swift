import SwiftUI
import UIKit

/// Tennis design system color tokens and semantic colors.
///
/// Provides:
/// - Base palette via `TennisColors` (stable color tokens)
/// - Semantic/dynamic colors via `Color` extensions (dark-mode aware)
/// - Hex initializers for `Color` and `UIColor`
///
/// Usage examples:
/// ```swift
/// let primary = TennisColors.tennisGreen
/// let record = Color.recordButton
/// let glass = Color.glassBackground
/// ```

// MARK: - Base Color Palette (Design Tokens)
enum TennisColors {
    // Primary Tennis Colors
    static let tennisGreen = Color(hex: "#4A9B4E")
    static let courtGreen = Color(hex: "#3B7F3C")
    static let aceGreen = Color(hex: "#5CB85C")

    // Accent Colors
    static let tennisYellow = Color(hex: "#F7DC6F")
    static let brightYellow = Color(hex: "#FFE135")
    static let clayOrange = Color(hex: "#E67E22")
    static let clayTerracotta = Color(hex: "#D35400")

    // Neutral Colors
    static let courtWhite = Color(hex: "#FAFAFA")
    static let tennisNet = Color(hex: "#2C3E50")
}

// MARK: - Semantic Colors with Dark Mode Support
extension Color {
    /// Recording button color (adaptive). Brighter in dark mode.
    static var recordButton: Color {
        Color(UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(hex: "#E67E22") ?? .systemOrange
            } else {
                return UIColor(hex: "#D35400") ?? .systemOrange
            }
        })
    }

    /// Technique quality excellent state (adaptive greens).
    static var excellentForm: Color {
        Color(UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(hex: "#5CB85C") ?? .systemGreen
            } else {
                return UIColor(hex: "#4A9B4E") ?? .systemGreen
            }
        })
    }

    /// Glass morphism background color (adaptive alpha over white/black).
    static var glassBackground: Color {
        Color(UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor.black.withAlphaComponent(0.3)
            } else {
                return UIColor.white.withAlphaComponent(0.3)
            }
        })
    }

    /// Semantic color for excellent shot quality.
    static var shotExcellent: Color {
        Color(UIColor { traits in
            // Use aceGreen in both modes to maintain consistency
            return UIColor(hex: "#5CB85C") ?? .systemGreen
        })
    }

    /// Semantic color for good/acceptable shot quality.
    static var shotGood: Color {
        Color(UIColor { traits in
            // courtGreen token
            return UIColor(hex: "#3B7F3C") ?? .systemGreen
        })
    }

    /// Semantic color for shots needing work. Yellow in dark, clay orange in light.
    static var shotNeedsWork: Color {
        Color(UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(hex: "#F7DC6F") ?? .systemYellow
            } else {
                return UIColor(hex: "#E67E22") ?? .systemOrange
            }
        })
    }
}

// MARK: - Hex Helpers
extension Color {
    /// Initialize a SwiftUI `Color` from a hex string like `#RRGGBB` or `RRGGBB`.
    /// Supports `#RGB`, `#RRGGBB`, and `#AARRGGBB` formats.
    /// Falls back to clear if parsing fails.
    ///
    /// - Parameter hex: Hex string (with or without leading `#`).
    init(hex: String) {
        if let uiColor = UIColor(hex: hex) {
            self = Color(uiColor)
        } else {
            self = Color.clear
        }
    }
}

extension UIColor {
    /// Initialize a `UIColor` from hex strings: `#RGB`, `#RRGGBB`, or `#AARRGGBB`.
    /// - Parameters:
    ///   - hex: Hex string representing the color (with/without `#`).
    ///   - alpha: Optional alpha override (0...1). If provided, it overrides any alpha from the hex string.
    convenience init?(hex: String, alpha: CGFloat? = nil) {
        let r, g, b, a: CGFloat

        let sanitized = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()

        func component(from start: Int, length: Int) -> CGFloat? {
            let startIndex = sanitized.index(sanitized.startIndex, offsetBy: start)
            let endIndex = sanitized.index(startIndex, offsetBy: length)
            let substring = String(sanitized[startIndex..<endIndex])
            var value: UInt64 = 0
            guard Scanner(string: substring).scanHexInt64(&value) else { return nil }
            switch length {
            case 1: // 4-bit
                return CGFloat(value) / 15.0
            case 2: // 8-bit
                return CGFloat(value) / 255.0
            default:
                return nil
            }
        }

        switch sanitized.count {
        case 3: // RGB (12-bit, e.g., F0A)
            guard
                let rr = component(from: 0, length: 1),
                let gg = component(from: 1, length: 1),
                let bb = component(from: 2, length: 1)
            else { return nil }
            r = rr
            g = gg
            b = bb
            a = 1.0
        case 6: // RRGGBB (24-bit)
            guard
                let rr = component(from: 0, length: 2),
                let gg = component(from: 2, length: 2),
                let bb = component(from: 4, length: 2)
            else { return nil }
            r = rr
            g = gg
            b = bb
            a = 1.0
        case 8: // AARRGGBB (32-bit)
            guard
                let aa = component(from: 0, length: 2),
                let rr = component(from: 2, length: 2),
                let gg = component(from: 4, length: 2),
                let bb = component(from: 6, length: 2)
            else { return nil }
            a = aa
            r = rr
            g = gg
            b = bb
        default:
            return nil
        }

        let resolvedAlpha = alpha ?? a
        self.init(red: r, green: g, blue: b, alpha: resolvedAlpha)
    }
}


