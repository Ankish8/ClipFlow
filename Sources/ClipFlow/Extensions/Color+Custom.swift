import SwiftUI
import ClipFlowCore

// MARK: - Custom Colors
extension Color {
    /// Custom accent color with better visibility in both light and dark modes
    /// Using a bright blue that has good contrast in both modes
    static let customAccent = Color(red: 0.0, green: 0.48, blue: 1.0)
    
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