import Foundation

// MARK: - Tag Model

public struct Tag: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var color: String
    public var icon: String
    public var description: String?
    public var usageCount: Int
    public let createdAt: Date
    public var modifiedAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        color: String = "#007AFF",
        icon: String = "tag.fill",
        description: String? = nil,
        usageCount: Int = 0,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.description = description
        self.usageCount = usageCount
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
    
    public mutating func incrementUsage() {
        usageCount += 1
        modifiedAt = Date()
    }
    
    public mutating func decrementUsage() {
        if usageCount > 0 {
            usageCount -= 1
            modifiedAt = Date()
        }
    }
    
    public mutating func updateMetadata(name: String? = nil,
                                      color: String? = nil,
                                      icon: String? = nil,
                                      description: String? = nil) {
        if let name = name { self.name = name }
        if let color = color { self.color = color }
        if let icon = icon { self.icon = icon }
        if let description = description { self.description = description }
        self.modifiedAt = Date()
    }
    
    public var displayColor: TagColor {
        TagColor(hex: color) ?? TagColor(red: 0, green: 0, blue: 1)
    }
}

// MARK: - Tag Assignment Model

public struct TagAssignment: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let tagId: UUID
    public let itemId: UUID
    public let assignedAt: Date
    public let assignedBy: String? // User identifier
    
    public init(
        id: UUID = UUID(),
        tagId: UUID,
        itemId: UUID,
        assignedAt: Date = Date(),
        assignedBy: String? = nil
    ) {
        self.id = id
        self.tagId = tagId
        self.itemId = itemId
        self.assignedAt = assignedAt
        self.assignedBy = assignedBy
    }
}

// MARK: - Tag Statistics Model

public struct TagStatistics: Codable, Sendable {
    public let totalTags: Int
    public let totalAssignments: Int
    public let averageUsagePerTag: Double
    public let mostUsedTags: [Tag]
    public let recentlyUsedTags: [Tag]
    public let tagsByColor: [String: Int]
    public let usageTrend: [Date: Int] // Date -> usage count
    
    public init(
        totalTags: Int,
        totalAssignments: Int,
        averageUsagePerTag: Double,
        mostUsedTags: [Tag] = [],
        recentlyUsedTags: [Tag] = [],
        tagsByColor: [String: Int] = [:],
        usageTrend: [Date: Int] = [:]
    ) {
        self.totalTags = totalTags
        self.totalAssignments = totalAssignments
        self.averageUsagePerTag = averageUsagePerTag
        self.mostUsedTags = mostUsedTags
        self.recentlyUsedTags = recentlyUsedTags
        self.tagsByColor = tagsByColor
        self.usageTrend = usageTrend
    }
}

// MARK: - Tag Color Helper

public struct TagColor: Codable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = max(0, min(1, red))
        self.green = max(0, min(1, green))
        self.blue = max(0, min(1, blue))
        self.alpha = max(0, min(1, alpha))
    }
    
    public init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
    
    public var hexString: String {
        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Predefined Tags

public extension Tag {
    static var important: Tag {
        Tag(name: "Important", color: "#FF3B30", icon: "exclamationmark.triangle.fill")
    }
    
    static var work: Tag {
        Tag(name: "Work", color: "#007AFF", icon: "briefcase.fill")
    }
    
    static var personal: Tag {
        Tag(name: "Personal", color: "#34C759", icon: "person.fill")
    }
    
    static var todo: Tag {
        Tag(name: "To-Do", color: "#FF9500", icon: "checkmark.circle.fill")
    }
    
    static var reference: Tag {
        Tag(name: "Reference", color: "#5856D6", icon: "book.fill")
    }
    
    static var code: Tag {
        Tag(name: "Code", color: "#AF52DE", icon: "chevron.left.forwardslash.chevron.right")
    }
    
    static var idea: Tag {
        Tag(name: "Idea", color: "#FF2D92", icon: "lightbulb.fill")
    }
    
    static var temporary: Tag {
        Tag(name: "Temporary", color: "#8E8E93", icon: "clock.arrow.circlepath")
    }
    
    static var defaultTags: [Tag] {
        [.important, .work, .personal, .todo, .reference, .code, .idea, .temporary]
    }
}