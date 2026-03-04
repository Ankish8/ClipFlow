import SwiftUI
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
}