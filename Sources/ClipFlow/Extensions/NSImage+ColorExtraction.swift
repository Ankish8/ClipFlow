import AppKit
import CoreImage
import SwiftUI

extension NSImage {
    /// Extracts the dominant color from an image using Core Image
    /// Returns nil if extraction fails
    func extractDominantColor() -> Color? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)

        // Use CIAreaAverage filter to get average color
        let extentVector = CIVector(
            x: ciImage.extent.origin.x,
            y: ciImage.extent.origin.y,
            z: ciImage.extent.size.width,
            w: ciImage.extent.size.height
        )

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: extentVector
        ]) else {
            return nil
        }

        guard let outputImage = filter.outputImage else {
            return nil
        }

        // The output is a 1x1 pixel image containing the average color
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        // Convert to Color
        let red = Double(bitmap[0]) / 255.0
        let green = Double(bitmap[1]) / 255.0
        let blue = Double(bitmap[2]) / 255.0
        let alpha = Double(bitmap[3]) / 255.0

        // Apply brightness adjustment if color is too dark or too light
        let adjustedColor = adjustColorForVisibility(red: red, green: green, blue: blue, alpha: alpha)

        return adjustedColor
    }

    /// Adjusts color brightness to ensure it's visible as a border accent
    private func adjustColorForVisibility(red: Double, green: Double, blue: Double, alpha: Double) -> Color {
        // Calculate perceived brightness (luminance)
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue

        var adjustedRed = red
        var adjustedGreen = green
        var adjustedBlue = blue

        // If too dark, brighten it
        if luminance < 0.3 {
            let factor = 0.3 / (luminance + 0.001) // Avoid division by zero
            adjustedRed = min(red * factor, 1.0)
            adjustedGreen = min(green * factor, 1.0)
            adjustedBlue = min(blue * factor, 1.0)
        }
        // If too light, darken it
        else if luminance > 0.85 {
            let factor = 0.85 / luminance
            adjustedRed = red * factor
            adjustedGreen = green * factor
            adjustedBlue = blue * factor
        }

        return Color(.sRGB, red: adjustedRed, green: adjustedGreen, blue: adjustedBlue, opacity: alpha)
    }
}

/// Cache for extracted colors to avoid redundant processing
actor ColorCache {
    private var cache: [String: Color] = [:]

    func get(forKey key: String) -> Color? {
        return cache[key]
    }

    func set(_ color: Color, forKey key: String) {
        cache[key] = color
    }

    func clear() {
        cache.removeAll()
    }
}

/// Global color cache instance
@MainActor
class AppIconColorCache {
    static let shared = AppIconColorCache()
    private let cache = ColorCache()

    private init() {}

    func getColor(for bundleID: String) async -> Color? {
        return await cache.get(forKey: bundleID)
    }

    func setColor(_ color: Color, for bundleID: String) async {
        await cache.set(color, forKey: bundleID)
    }

    func clearCache() async {
        await cache.clear()
    }
}
