import Foundation

// MARK: - Collection Model

public struct Collection: Codable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var description: String?
    public var icon: String
    public var color: String
    public var itemIds: Set<UUID>
    public var isShared: Bool
    public var shareSettings: ShareSettings?
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        icon: String = "folder.fill",
        color: String = "#007AFF",
        itemIds: Set<UUID> = [],
        isShared: Bool = false,
        shareSettings: ShareSettings? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.itemIds = itemIds
        self.isShared = isShared
        self.shareSettings = shareSettings
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public mutating func addItem(_ itemId: UUID) {
        itemIds.insert(itemId)
        modifiedAt = Date()
    }

    public mutating func removeItem(_ itemId: UUID) {
        itemIds.remove(itemId)
        modifiedAt = Date()
    }

    public mutating func updateMetadata(name: String? = nil,
                                       description: String? = nil,
                                       icon: String? = nil,
                                       color: String? = nil) {
        if let name = name { self.name = name }
        if let description = description { self.description = description }
        if let icon = icon { self.icon = icon }
        if let color = color { self.color = color }
        self.modifiedAt = Date()
    }

    public var itemCount: Int {
        itemIds.count
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Collection, rhs: Collection) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Share Settings

public struct ShareSettings: Codable, Hashable {
    public let shareID: String
    public var permissions: Set<Permission>
    public var expiresAt: Date?
    public var password: String?
    public var allowedUsers: [String] // Apple IDs or emails
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        shareID: String = UUID().uuidString,
        permissions: Set<Permission> = [.read],
        expiresAt: Date? = nil,
        password: String? = nil,
        allowedUsers: [String] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.shareID = shareID
        self.permissions = permissions
        self.expiresAt = expiresAt
        self.password = password
        self.allowedUsers = allowedUsers
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }

    public var hasPasswordProtection: Bool {
        password != nil && !password!.isEmpty
    }

    public var isPublic: Bool {
        allowedUsers.isEmpty && !hasPasswordProtection
    }

    public mutating func addUser(_ userIdentifier: String) {
        if !allowedUsers.contains(userIdentifier) {
            allowedUsers.append(userIdentifier)
            modifiedAt = Date()
        }
    }

    public mutating func removeUser(_ userIdentifier: String) {
        if let index = allowedUsers.firstIndex(of: userIdentifier) {
            allowedUsers.remove(at: index)
            modifiedAt = Date()
        }
    }

    public mutating func updatePermissions(_ newPermissions: Set<Permission>) {
        permissions = newPermissions
        modifiedAt = Date()
    }

    public func canAccess(user: String?) -> Bool {
        // If expired, deny access
        if isExpired { return false }

        // If public, allow access
        if isPublic { return true }

        // If user is in allowed list, allow access
        if let user = user, allowedUsers.contains(user) {
            return true
        }

        return false
    }
}

public enum Permission: String, Codable, CaseIterable {
    case read = "read"
    case write = "write"
    case delete = "delete"
    case share = "share"
    case admin = "admin"

    public var displayName: String {
        switch self {
        case .read: return "View"
        case .write: return "Edit"
        case .delete: return "Delete"
        case .share: return "Share"
        case .admin: return "Admin"
        }
    }

    public var description: String {
        switch self {
        case .read: return "Can view collection items"
        case .write: return "Can add and modify items"
        case .delete: return "Can delete items"
        case .share: return "Can share with others"
        case .admin: return "Full administrative access"
        }
    }

    public static var defaultPermissions: Set<Permission> {
        [.read]
    }

    public static var fullPermissions: Set<Permission> {
        Set(Permission.allCases)
    }
}

// MARK: - Collection Statistics

public struct CollectionStatistics: Codable {
    public let totalCollections: Int
    public let totalItems: Int
    public let totalSharedCollections: Int
    public let averageItemsPerCollection: Double
    public let mostPopularCollection: UUID?
    public let recentlyModifiedCollections: [UUID]
    public let collectionsByType: [String: Int]

    public init(
        totalCollections: Int,
        totalItems: Int,
        totalSharedCollections: Int,
        averageItemsPerCollection: Double,
        mostPopularCollection: UUID? = nil,
        recentlyModifiedCollections: [UUID] = [],
        collectionsByType: [String: Int] = [:]
    ) {
        self.totalCollections = totalCollections
        self.totalItems = totalItems
        self.totalSharedCollections = totalSharedCollections
        self.averageItemsPerCollection = averageItemsPerCollection
        self.mostPopularCollection = mostPopularCollection
        self.recentlyModifiedCollections = recentlyModifiedCollections
        self.collectionsByType = collectionsByType
    }
}

// MARK: - Predefined Collections

public extension Collection {
    static var favorites: Collection {
        Collection(
            name: "Favorites",
            description: "Your favorite clipboard items",
            icon: "heart.fill",
            color: "#FF3B30"
        )
    }

    static var recent: Collection {
        Collection(
            name: "Recent",
            description: "Recently copied items",
            icon: "clock.fill",
            color: "#007AFF"
        )
    }

    static var images: Collection {
        Collection(
            name: "Images",
            description: "All copied images",
            icon: "photo.fill",
            color: "#34C759"
        )
    }

    static var text: Collection {
        Collection(
            name: "Text",
            description: "Text and rich text content",
            icon: "text.alignleft",
            color: "#5856D6"
        )
    }

    static var code: Collection {
        Collection(
            name: "Code",
            description: "Code snippets and programming content",
            icon: "curlybraces",
            color: "#FF9500"
        )
    }

    static var files: Collection {
        Collection(
            name: "Files",
            description: "File paths and documents",
            icon: "doc.fill",
            color: "#8E8E93"
        )
    }

    static var links: Collection {
        Collection(
            name: "Links",
            description: "URLs and web links",
            icon: "link",
            color: "#00C7BE"
        )
    }

    static var defaultCollections: [Collection] {
        [.favorites, .recent, .images, .text, .code, .files, .links]
    }
}