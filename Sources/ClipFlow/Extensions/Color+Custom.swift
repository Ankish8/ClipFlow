import SwiftUI
import AppKit
import ClipFlowCore

// MARK: - Custom Colors
extension Color {
    /// System accent color — respects user's macOS accent color preference
    static let customAccent = Color.accentColor
    
    /// Adaptive color for selected text/icons - ensures visibility in both modes
    static let adaptiveAccent = Color.primary
    
    /// High contrast color for selected states
    static let highContrastAccent = Color.white
}

// MARK: - TagColor SwiftUI Convenience
extension TagColor {
    /// SwiftUI Color from this tag color — avoids the (r,g,b) destructure pattern at call sites
    public var swiftUIColor: Color {
        let (r, g, b) = rgbComponents
        return Color(red: r, green: g, blue: b)
    }

    /// Rendered tag color mapped to the platform's semantic system colors so each
    /// predefined tag color gets a tuned light-mode and dark-mode variant.
    public func adaptiveSwiftUIColor(for _: ColorScheme) -> Color {
        Color(nsColor: adaptiveNSColor)
    }

    public func indicatorBorderColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .light {
            return Color.black.opacity(needsStrongerLightBorder ? 0.18 : 0.14)
        }
        return Color.white.opacity(needsStrongerDarkBorder ? 0.16 : 0.10)
    }

    private var adaptiveNSColor: NSColor {
        switch self {
        case .red:
            return .systemRed
        case .orange:
            return .systemOrange
        case .yellow:
            return .systemYellow
        case .green:
            return .systemGreen
        case .blue:
            return .systemBlue
        case .indigo:
            return .systemIndigo
        case .purple:
            return .systemPurple
        case .pink:
            return .systemPink
        case .gray:
            return .systemGray
        case .teal:
            return .systemTeal
        }
    }

    private var needsStrongerLightBorder: Bool {
        switch self {
        case .yellow, .teal, .gray:
            return true
        default:
            return false
        }
    }

    private var needsStrongerDarkBorder: Bool {
        switch self {
        case .gray, .indigo, .purple:
            return true
        default:
            return false
        }
    }
}