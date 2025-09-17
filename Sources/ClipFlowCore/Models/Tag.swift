import Foundation
import SwiftUI

// MARK: - Tag Model

public struct Tag: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var color: String
    public var icon: String?
    public var description: String?
    public var usageCount: Int
    public var itemIds: Set<UUID>
    public let createdAt: Date
    public var modifiedAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        color: String = "#007AFF",
        icon: String? = nil,
        description: String? = nil,
        usageCount: Int = 0,
        itemIds: Set<UUID> = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.description = description
        self.usageCount = usageCount
        self.itemIds = itemIds
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
    
    public mutating func addItem(_ itemId: UUID) {
        itemIds.insert(itemId)
        usageCount = itemIds.count
        modifiedAt = Date()
    }
    
    public mutating func removeItem(_ itemId: UUID) {
        itemIds.remove(itemId)
        usageCount = itemIds.count
        modifiedAt = Date()
    }
    
    public mutating func updateMetadata(
        name: String? = nil,
        color: String? = nil,
        icon: String? = nil,
        description: String? = nil
    ) {
        if let name = name { self.name = name }
        if let color = color { self.color = color }
        if let icon = icon { self.icon = icon }
        if let description = description { self.description = description }
        modifiedAt = Date()
    }
    
    public var itemCount: Int {
        itemIds.count
    }
    
    public var colorValue: Color {
        Color(hex: color) ?? Color.blue
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: Tag, rhs: Tag) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Tag Management

public extension Tag {
    static var defaultTags: [Tag] {
        [
            Tag(
                name: "Work",
                color: "#007AFF",
                icon: "briefcase.fill",
                description: "Work-related items"
            ),
            Tag(
                name: "Personal",
                color: "#34C759",
                icon: "person.fill",
                description: "Personal items"
            ),
            Tag(
                name: "Important",
                color: "#FF3B30",
                icon: "exclamationmark.triangle.fill",
                description: "Important items"
            ),
            Tag(
                name: "Code",
                color: "#FF9500",
                icon: "curlybraces",
                description: "Code snippets"
            ),
            Tag(
                name: "Design",
                color: "#AF52DE",
                icon: "paintbrush.fill",
                description: "Design assets"
            ),
            Tag(
                name: "Research",
                color: "#5AC8FA",
                icon: "magnifyingglass",
                description: "Research materials"
            )
        ]
    }
    
    static func createTag(name: String, color: String = "#007AFF") -> Tag {
        Tag(
            name: name,
            color: color,
            icon: nil,
            description: nil
        )
    }
}

// MARK: - Tag Statistics

public struct TagStatistics: Codable, Sendable {
    public let totalTags: Int
    public let totalTaggedItems: Int
    public let mostUsedTags: [Tag]
    public let recentlyCreatedTags: [Tag]
    public let tagsByColor: [String: Int]
    
    public init(
        totalTags: Int,
        totalTaggedItems: Int,
        mostUsedTags: [Tag] = [],
        recentlyCreatedTags: [Tag] = [],
        tagsByColor: [String: Int] = [:]
    ) {
        self.totalTags = totalTags
        self.totalTaggedItems = totalTaggedItems
        self.mostUsedTags = mostUsedTags
        self.recentlyCreatedTags = recentlyCreatedTags
        self.tagsByColor = tagsByColor
    }
}

// MARK: - Tag Color Helper

extension Color {
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        
        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue)
    }
    
    func toHex() -> String {
        let components = self.cgColor?.components
        let r: CGFloat = components?[0] ?? 0
        let g: CGFloat = components?[1] ?? 0
        let b: CGFloat = components?[2] ?? 0
        
        let hexString = String(format: "#%02lX%02lX%02lX", lround(r * 255), lround(g * 255), lround(b * 255))
        return hexString
    }
}