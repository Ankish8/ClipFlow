import Foundation

// MARK: - Tag Model

/// Lightweight tag for categorizing clipboard items
public struct Tag: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var color: TagColor
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        color: TagColor,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public mutating func update(name: String? = nil, color: TagColor? = nil) {
        if let name = name { self.name = name }
        if let color = color { self.color = color }
        self.modifiedAt = Date()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Tag, rhs: Tag) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Tag Color

/// Predefined colors for tags with consistent branding
public enum TagColor: String, Codable, CaseIterable, Sendable {
    case red = "#FF3B30"
    case orange = "#FF9500"
    case yellow = "#FFCC00"
    case green = "#34C759"
    case blue = "#007AFF"
    case indigo = "#5856D6"
    case purple = "#AF52DE"
    case pink = "#FF2D55"
    case gray = "#8E8E93"
    case teal = "#5AC8FA"

    /// Display name for the color
    public var displayName: String {
        switch self {
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .gray: return "Gray"
        case .teal: return "Teal"
        }
    }

    /// Hex color value (without #)
    public var hexValue: String {
        return rawValue
    }

    /// Get a random tag color
    public static func random() -> TagColor {
        return TagColor.allCases.randomElement() ?? .blue
    }

    /// RGB components for SwiftUI Color
    public var rgbComponents: (red: Double, green: Double, blue: Double) {
        let hex = String(rawValue.dropFirst()) // Remove #
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return (r, g, b)
    }
}

// MARK: - Predefined Tags

public extension Tag {
    /// Create a set of default tags for initial setup
    static var defaults: [Tag] {
        return [
            Tag(name: "Important", color: .red),
            Tag(name: "Work", color: .blue),
            Tag(name: "Personal", color: .green),
            Tag(name: "Ideas", color: .yellow),
            Tag(name: "Archive", color: .gray)
        ]
    }
}
