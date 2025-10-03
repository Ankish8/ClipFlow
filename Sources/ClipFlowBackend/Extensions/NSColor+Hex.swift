import Foundation
import AppKit

// MARK: - NSColor Extensions for Hex Color Support

public extension NSColor {
    /// Initialize NSColor from hex string (e.g., "#FF5733", "#000000")
    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove # if present
        let cleanHex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex

        // Validate hex format (6 or 8 characters for RGB or RGBA)
        guard cleanHex.count == 6 || cleanHex.count == 8 else {
            return nil
        }

        // Parse hex components
        var rgbValue: UInt64 = 0
        guard Scanner(string: cleanHex).scanHexInt64(&rgbValue) else {
            return nil
        }

        let r, g, b, a: CGFloat

        if cleanHex.count == 6 {
            // RGB format (#RRGGBB)
            r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgbValue & 0x0000FF) / 255.0
            a = 1.0
        } else {
            // RGBA format (#RRGGBBAA)
            r = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgbValue & 0x000000FF) / 255.0
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }

    /// Convert NSColor to hex string (e.g., "#FF5733")
    var hexString: String? {
        guard let rgbColor = self.usingColorSpace(.sRGB) else {
            return nil
        }

        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
