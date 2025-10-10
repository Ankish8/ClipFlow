import Foundation
import GRDB
import ClipFlowCore
import ClipFlowAPI

// MARK: - ClipboardItemRecord

struct ClipboardItemRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var contentType: String
    var contentData: Data?
    var contentText: String?
    var metadata: String
    var source: String
    var timestamps: String
    var security: String
    var collectionIds: String?
    var tagIds: String?
    var isFavorite: Bool
    var isPinned: Bool
    var isDeleted: Bool
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval?
    var accessedAt: TimeInterval?
    var expiresAt: TimeInterval?
    var hash: String

    static let databaseTableName = "clipboard_items"
    
    // Custom row decoding to handle snake_case to camelCase conversion
    init(row: Row) throws {
        id = try row["id"]
        contentType = try row["content_type"]
        contentData = row["content_data"]
        contentText = row["content_text"]
        metadata = try row["metadata"]
        source = try row["source"]
        timestamps = try row["timestamps"]
        security = try row["security"]
        collectionIds = row["collection_ids"]
        tagIds = row["tag_ids"]
        isFavorite = try row["is_favorite"]
        isPinned = try row["is_pinned"]
        isDeleted = try row["is_deleted"]
        createdAt = try row["created_at"]
        modifiedAt = row["modified_at"]
        accessedAt = row["accessed_at"]
        expiresAt = row["expires_at"]
        hash = try row["hash"]
    }
    
    // Custom persistence for snake_case column names
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["content_type"] = contentType
        container["content_data"] = contentData
        container["content_text"] = contentText
        container["metadata"] = metadata
        container["source"] = source
        container["timestamps"] = timestamps
        container["security"] = security
        container["collection_ids"] = collectionIds
        container["tag_ids"] = tagIds
        container["is_favorite"] = isFavorite
        container["is_pinned"] = isPinned
        container["is_deleted"] = isDeleted
        container["created_at"] = createdAt
        container["modified_at"] = modifiedAt
        container["accessed_at"] = accessedAt
        container["expires_at"] = expiresAt
        container["hash"] = hash
    }

    init(from item: ClipboardItem) {
        self.id = item.id.uuidString
        self.contentType = item.content.contentType
        self.contentData = try? JSONEncoder().encode(item.content)
        self.contentText = item.content.displayText
        self.metadata = (try? JSONEncoder().encode(item.metadata).base64EncodedString()) ?? ""
        self.source = (try? JSONEncoder().encode(item.source).base64EncodedString()) ?? ""
        self.timestamps = (try? JSONEncoder().encode(item.timestamps).base64EncodedString()) ?? ""
        self.security = (try? JSONEncoder().encode(item.security).base64EncodedString()) ?? ""
        self.collectionIds = item.collectionIds.isEmpty ? nil : (try? JSONEncoder().encode(Array(item.collectionIds)).base64EncodedString())
        self.tagIds = item.tagIds.isEmpty ? nil : (try? JSONEncoder().encode(Array(item.tagIds)).base64EncodedString())
        self.isFavorite = item.isFavorite
        self.isPinned = item.isPinned
        self.isDeleted = item.isDeleted
        self.createdAt = item.timestamps.createdAt.timeIntervalSince1970
        self.modifiedAt = item.timestamps.modifiedAt?.timeIntervalSince1970
        self.accessedAt = item.timestamps.lastAccessedAt?.timeIntervalSince1970
        self.expiresAt = item.timestamps.expiresAt?.timeIntervalSince1970
        self.hash = item.metadata.hash
    }

    func toClipboardItem() throws -> ClipboardItem {
        let decoder = JSONDecoder()

        guard let contentData = contentData,
              let content = try? decoder.decode(ClipboardContent.self, from: contentData) else {
            throw DatabaseError.corruptedData("Failed to decode content")
        }

        guard let metadataData = Data(base64Encoded: metadata),
              let itemMetadata = try? decoder.decode(ItemMetadata.self, from: metadataData) else {
            throw DatabaseError.corruptedData("Failed to decode metadata")
        }

        guard let sourceData = Data(base64Encoded: source),
              let itemSource = try? decoder.decode(ItemSource.self, from: sourceData) else {
            throw DatabaseError.corruptedData("Failed to decode source")
        }

        guard let timestampsData = Data(base64Encoded: timestamps),
              let itemTimestamps = try? decoder.decode(ItemTimestamps.self, from: timestampsData) else {
            throw DatabaseError.corruptedData("Failed to decode timestamps")
        }

        guard let securityData = Data(base64Encoded: security),
              let itemSecurity = try? decoder.decode(SecurityMetadata.self, from: securityData) else {
            throw DatabaseError.corruptedData("Failed to decode security")
        }


        let itemCollectionIds: Set<UUID>
        if let collectionIdsString = collectionIds,
           let collectionIdsData = Data(base64Encoded: collectionIdsString),
           let decodedCollectionIds = try? decoder.decode([UUID].self, from: collectionIdsData) {
            itemCollectionIds = Set(decodedCollectionIds)
        } else {
            itemCollectionIds = []
        }

        let itemTagIds: Set<UUID>
        if let tagIdsString = tagIds,
           let tagIdsData = Data(base64Encoded: tagIdsString),
           let decodedTagIds = try? decoder.decode([UUID].self, from: tagIdsData) {
            itemTagIds = Set(decodedTagIds)
        } else {
            itemTagIds = []
        }

        guard let uuid = UUID(uuidString: id) else {
            throw DatabaseError.corruptedData("Invalid UUID")
        }

        return ClipboardItem(
            id: uuid,
            content: content,
            metadata: itemMetadata,
            source: itemSource,
            timestamps: itemTimestamps,
            security: itemSecurity,
            collectionIds: itemCollectionIds,
            tagIds: itemTagIds,
            isFavorite: isFavorite,
            isPinned: isPinned,
            isDeleted: isDeleted
        )
    }
}

// MARK: - CollectionRecord

struct CollectionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var name: String
    var description: String?
    var icon: String
    var color: String
    var isShared: Bool
    var shareSettings: String?
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval

    static let databaseTableName = "collections"

    init(from collection: Collection) {
        self.id = collection.id.uuidString
        self.name = collection.name
        self.description = collection.description
        self.icon = collection.icon
        self.color = collection.color
        self.isShared = collection.isShared
        self.shareSettings = collection.shareSettings.flatMap { settings in
            try? JSONEncoder().encode(settings).base64EncodedString()
        }
        self.createdAt = collection.createdAt.timeIntervalSince1970
        self.modifiedAt = collection.modifiedAt.timeIntervalSince1970
    }

    func toCollection() throws -> Collection {
        let decoder = JSONDecoder()

        let settings: ShareSettings?
        if let shareSettingsString = shareSettings,
           let shareSettingsData = Data(base64Encoded: shareSettingsString) {
            settings = try? decoder.decode(ShareSettings.self, from: shareSettingsData)
        } else {
            settings = nil
        }

        guard let uuid = UUID(uuidString: id) else {
            throw DatabaseError.corruptedData("Invalid UUID")
        }

        return Collection(
            id: uuid,
            name: name,
            description: description,
            icon: icon,
            color: color,
            itemIds: [], // Will be populated separately
            isShared: isShared,
            shareSettings: settings,
            createdAt: Date(timeIntervalSince1970: createdAt),
            modifiedAt: Date(timeIntervalSince1970: modifiedAt)
        )
    }
}

// MARK: - SnippetRecord

struct SnippetRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var title: String
    var content: String
    var placeholders: String?
    var keyword: String?
    var category: String
    var usageCount: Int
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval

    static let databaseTableName = "snippets"

    init(from snippet: SnippetContent) {
        self.id = snippet.id.uuidString
        self.title = snippet.title
        self.content = snippet.content
        self.placeholders = snippet.placeholders.isEmpty ? nil :
            (try? JSONEncoder().encode(snippet.placeholders).base64EncodedString())
        self.keyword = snippet.keyword
        self.category = snippet.category
        self.usageCount = snippet.usageCount
        self.createdAt = Date().timeIntervalSince1970
        self.modifiedAt = Date().timeIntervalSince1970
    }

    func toSnippet() throws -> SnippetContent {
        let decoder = JSONDecoder()

        let snippetPlaceholders: [Placeholder]
        if let placeholdersString = placeholders,
           let placeholdersData = Data(base64Encoded: placeholdersString) {
            snippetPlaceholders = (try? decoder.decode([Placeholder].self, from: placeholdersData)) ?? []
        } else {
            snippetPlaceholders = []
        }

        guard let uuid = UUID(uuidString: id) else {
            throw DatabaseError.corruptedData("Invalid UUID")
        }

        return SnippetContent(
            id: uuid,
            title: title,
            content: content,
            placeholders: snippetPlaceholders,
            keyword: keyword,
            category: category,
            usageCount: usageCount
        )
    }
}

// MARK: - AutomationRuleRecord

struct AutomationRuleRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var name: String
    var triggerData: String
    var conditions: String?
    var actions: String
    var isEnabled: Bool
    var executionCount: Int
    var lastExecuted: TimeInterval?
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval

    static let databaseTableName = "automation_rules"

    func toAutomationRule() throws -> AutomationRule {
        guard let uuid = UUID(uuidString: id) else {
            throw DatabaseError.corruptedData("Invalid UUID")
        }

        // For now, return a placeholder AutomationRule
        // Full implementation would decode the JSON data
        return AutomationRule(
            id: uuid,
            name: name,
            trigger: .clipboardChange,
            conditions: [],
            actions: [],
            isEnabled: isEnabled
        )
    }
}

// MARK: - TagRecord

struct TagRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var name: String
    var color: String
    var icon: String  // Required by existing schema
    var description: String?  // Optional in existing schema
    var usageCount: Int  // Required by existing schema
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval

    static let databaseTableName = "tags"

    init(row: Row) throws {
        id = try row["id"]
        name = try row["name"]
        color = try row["color"]
        icon = try row["icon"]
        description = row["description"]
        usageCount = try row["usage_count"]
        createdAt = try row["created_at"]
        modifiedAt = try row["modified_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["name"] = name
        container["color"] = color
        container["icon"] = icon
        container["description"] = description
        container["usage_count"] = usageCount
        container["created_at"] = createdAt
        container["modified_at"] = modifiedAt
    }

    init(from tag: Tag) {
        self.id = tag.id.uuidString
        self.name = tag.name
        self.color = tag.color.rawValue
        self.icon = "tag"  // Default icon value
        self.description = nil
        self.usageCount = 0
        self.createdAt = tag.createdAt.timeIntervalSince1970
        self.modifiedAt = tag.modifiedAt.timeIntervalSince1970
    }

    func toTag() throws -> Tag {
        guard let uuid = UUID(uuidString: id) else {
            throw DatabaseError.corruptedData("Invalid UUID for tag")
        }

        guard let tagColor = TagColor(rawValue: color) else {
            throw DatabaseError.corruptedData("Invalid tag color: \(color)")
        }

        return Tag(
            id: uuid,
            name: name,
            color: tagColor,
            createdAt: Date(timeIntervalSince1970: createdAt),
            modifiedAt: Date(timeIntervalSince1970: modifiedAt)
        )
    }
}

// MARK: - Database Errors

enum DatabaseError: Error {
    case corruptedData(String)
    case migrationFailed(String)
    case connectionFailed
    case queryFailed(String)
}

// MARK: - AutomationRule Placeholder

public struct AutomationRule: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let trigger: AutomationTrigger
    public let conditions: [AutomationCondition]
    public let actions: [AutomationAction]
    public let isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        trigger: AutomationTrigger,
        conditions: [AutomationCondition] = [],
        actions: [AutomationAction] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
        self.isEnabled = isEnabled
    }
}

public enum AutomationTrigger: Codable {
    case clipboardChange
    case applicationLaunch(bundleID: String)
    case timeInterval(seconds: Int)
    case hotkey(combination: String)
}

public struct AutomationCondition: Codable {
    public let type: ConditionType
    public let value: String
    public let comparisonOperator: ComparisonOperator

    public init(type: ConditionType, value: String, operator: ComparisonOperator) {
        self.type = type
        self.value = value
        self.comparisonOperator = `operator`
    }
}

public enum ConditionType: String, Codable {
    case contentType, application, textContains, size, age
}

public enum ComparisonOperator: String, Codable {
    case equals, contains, startsWith, endsWith, regex, greater, less
}

public enum AutomationAction: Codable {
    case transform(TransformAction)
    case notify(message: String)
    case copyToCollection(id: UUID)
    case delete
    case export(format: ExportFormat)
}


public enum ExportFormat: String, Codable {
    case json, csv, txt, rtf, html
}